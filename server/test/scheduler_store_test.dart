import 'dart:io';
import 'package:bmstu_neo_push/bmstu_neo_push.dart';
import 'package:test/test.dart';

Device _device(String id, {String platform = 'apns', DateTime? lastPushAt, String? env}) => Device(
      installationId: id,
      secretHash: Device.hashSecret('secret-$id'),
      platform: platform,
      token: 'token-$id',
      createdAt: DateTime.utc(2026, 10, 1),
      updatedAt: DateTime.utc(2026, 10, 1),
      lastPushAt: lastPushAt,
      apnsEnvironment: env,
    );

// Answers per token: 'dead' tokens are invalid, 'busy' ones need a retry
class FakeSender implements PushSender {
  final List<String> sent = [];
  final Set<String> dead;
  final Set<String> busy;
  FakeSender({this.dead = const {}, this.busy = const {}});

  @override
  Future<PushResult> sendSync(Device device) async {
    sent.add(device.installationId);
    if (dead.contains(device.installationId)) return const PushResult(PushOutcome.invalidToken);
    if (busy.contains(device.installationId)) return const PushResult(PushOutcome.retryLater);
    return const PushResult(PushOutcome.delivered, apnsEnvironment: 'sandbox');
  }
}

void main() {
  // 12:00 in Moscow
  final noon = DateTime.utc(2026, 10, 23, 9);

  group('SyncScheduler', () {
    test('Pushes due devices, forgets dead tokens, keeps temporary failures for later', () async {
      final store = InMemoryDeviceStore();
      for (final d in [
        _device('new'),
        _device('stale', lastPushAt: noon.subtract(const Duration(hours: 3))),
        _device('fresh', lastPushAt: noon.subtract(const Duration(minutes: 30))),
        _device('dead'),
        _device('busy'),
      ]) {
        await store.put(d);
      }
      final apns = FakeSender(dead: {'dead'}, busy: {'busy'});
      final scheduler = SyncScheduler(store: store, senders: {'apns': apns}, now: () => noon);

      final stats = await scheduler.tick();

      expect(apns.sent, unorderedEquals(['new', 'stale', 'dead', 'busy']), reason: '"fresh" is not due yet');
      expect([stats.delivered, stats.removed, stats.deferred], [2, 1, 1]);
      expect(await store.get('dead'), isNull);
      expect((await store.get('new'))!.lastPushAt, noon);
      expect((await store.get('new'))!.apnsEnvironment, 'sandbox');
      expect((await store.get('busy'))!.lastPushAt, isNull, reason: 'retried next tick');
    });

    test('Nothing is sent at night in Moscow', () async {
      final store = InMemoryDeviceStore()..put(_device('a'));
      final apns = FakeSender();
      // 23:30 Moscow = 20:30 UTC; 07:59 Moscow = 04:59 UTC
      for (final utc in [DateTime.utc(2026, 10, 23, 20, 30), DateTime.utc(2026, 10, 24, 4, 59)]) {
        final stats = await SyncScheduler(store: store, senders: {'apns': apns}, now: () => utc).tick();
        expect(stats.quietHours, isTrue);
      }
      expect(apns.sent, isEmpty);
      expect((await SyncScheduler(store: store, senders: {'apns': apns}, now: () => DateTime.utc(2026, 10, 24, 5)).tick()).delivered, 1);
    });

    test('Spreads load: the longest-waiting devices go first, up to maxPerTick', () async {
      final store = InMemoryDeviceStore();
      for (var i = 0; i < 10; i++) {
        await store.put(_device('d$i', lastPushAt: noon.subtract(Duration(hours: 3 + i))));
      }
      final apns = FakeSender();
      await SyncScheduler(store: store, senders: {'apns': apns}, now: () => noon, maxPerTick: 3).tick();
      expect(apns.sent, unorderedEquals(['d9', 'd8', 'd7']));
    });

    test('Devices of a platform without credentials are skipped, not deleted', () async {
      final store = InMemoryDeviceStore()..put(_device('android', platform: 'fcm'));
      final stats = await SyncScheduler(store: store, senders: {'apns': FakeSender()}, now: () => noon).tick();
      expect(stats.delivered + stats.removed + stats.deferred, 0);
      expect(await store.get('android'), isNotNull);
    });
  });

  test('FileDeviceStore survives a restart and writes atomically', () async {
    final dir = await Directory.systemTemp.createTemp('push_store_test');
    addTearDown(() => dir.delete(recursive: true));
    final path = '${dir.path}/devices.json';

    final store = await FileDeviceStore.open(path);
    await store.put(_device('a', env: 'production'));
    await store.put(_device('b'));
    await store.delete('b');

    final reopened = await FileDeviceStore.open(path);
    expect((await reopened.all()).map((d) => d.installationId), ['a']);
    expect((await reopened.get('a'))!.apnsEnvironment, 'production');
    expect(File('$path.tmp').existsSync(), isFalse);
  });
}
