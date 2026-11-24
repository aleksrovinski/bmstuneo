import 'dart:async';
import 'device.dart';
import 'device_store.dart';
import 'push_sender.dart';

class TickStats {
  int delivered = 0;
  int removed = 0;
  int deferred = 0;
  bool quietHours = false;

  Map<String, dynamic> toJson() =>
      {'delivered': delivered, 'removed': removed, 'deferred': deferred, 'quietHours': quietHours};

  @override
  String toString() => quietHours
      ? 'quiet hours, nothing sent'
      : 'delivered $delivered, removed $removed, deferred $deferred';
}

/// Wakes every registered app every [interval] with a silent push, except at
/// night. Each tick handles the devices that waited longest, at most
/// [maxPerTick] of them, so pushes spread evenly instead of arriving at once.
class SyncScheduler {
  final DeviceStore store;
  final Map<String, PushSender> senders; // by Device.platform
  final Duration interval;
  final int quietFromHour;
  final int quietUntilHour;
  final Duration localOffset; // Moscow = +3, no DST
  final int maxPerTick;
  final int concurrency;
  final DateTime Function() _now;

  SyncScheduler({
    required this.store,
    required this.senders,
    this.interval = const Duration(hours: 2),
    this.quietFromHour = 22,
    this.quietUntilHour = 8,
    this.localOffset = const Duration(hours: 3),
    this.maxPerTick = 300,
    this.concurrency = 10,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  bool isQuietHours(DateTime utc) {
    final hour = utc.toUtc().add(localOffset).hour;
    return quietFromHour > quietUntilHour
        ? hour >= quietFromHour || hour < quietUntilHour
        : hour >= quietFromHour && hour < quietUntilHour;
  }

  Future<TickStats> tick() async {
    final stats = TickStats();
    final now = _now().toUtc();
    if (isQuietHours(now)) return stats..quietHours = true;

    final due = (await store.all())
        .where((d) => senders.containsKey(d.platform))
        .where((d) => d.lastPushAt == null || now.difference(d.lastPushAt!) >= interval)
        .toList()
      ..sort((a, b) => (a.lastPushAt ?? DateTime(2000)).compareTo(b.lastPushAt ?? DateTime(2000)));

    final queue = due.take(maxPerTick).toList();
    Future<void> worker() async {
      while (queue.isNotEmpty) {
        await _push(queue.removeLast(), now, stats);
      }
    }

    await Future.wait(List.generate(concurrency, (_) => worker()));
    return stats;
  }

  Future<void> _push(Device device, DateTime now, TickStats stats) async {
    final result = await senders[device.platform]!.sendSync(device);
    if (result.outcome == PushOutcome.retryLater) {
      stats.deferred++;
      return;
    }

    // The push went to the token from the start of the tick. While it was in flight the app
    // may have re-registered with a new token or unsubscribed: the answer says nothing about
    // that new record, so it is left as stored (a new token is simply pushed next tick).
    var applied = false;
    await store.update(device.installationId, (current) {
      if (current.token != device.token || current.platform != device.platform) return current;
      applied = true;
      return result.outcome == PushOutcome.invalidToken
          ? null
          : current.copyWith(lastPushAt: now, apnsEnvironment: result.apnsEnvironment);
    });

    if (result.outcome == PushOutcome.delivered) {
      stats.delivered++;
    } else if (applied) {
      stats.removed++;
    }
  }

  /// Runs [tick] every [every] until the returned timer is cancelled.
  Timer start({Duration every = const Duration(minutes: 5), void Function(TickStats)? onTick}) {
    var running = false;
    return Timer.periodic(every, (_) async {
      if (running) return; // a slow tick must not overlap the next one
      running = true;
      try {
        onTick?.call(await tick());
      } finally {
        running = false;
      }
    });
  }
}
