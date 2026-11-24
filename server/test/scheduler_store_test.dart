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

// Changes the stored device while its push is "in flight", like the API would;
// a change returning null unsubscribes the device
class _MidFlightSender extends FakeSender {
  final DeviceStore store;
  final Map<String, Device? Function(Device)> changes;
  _MidFlightSender(this.store, this.changes, {super.dead});

  @override
  Future<PushResult> sendSync(Device device) async {
    final change = changes[device.installationId];
    if (change != null) {
      final next = change(device);
      if (next == null) {
        await store.delete(device.installationId);
      } else {
        await store.put(next);
      }
    }
    return super.sendSync(device);
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

    test('A re-registration during the push is not overwritten by the tick', () async {
      final store = InMemoryDeviceStore();
      await store.put(_device('moved'));
      await store.put(_device('regrouped'));
      final apns = _MidFlightSender(store, {
        // The app got a new token while the push to the old one was in flight
        'moved': (d) => d.copyWith(token: 'token-moved-2', clearApnsEnvironment: true),
        // Same token, the student picked another group
        'regrouped': (d) => d.copyWith(groupUuid: 'group-2'),
      });

      final stats = await SyncScheduler(store: store, senders: {'apns': apns}, now: () => noon).tick();

      final moved = (await store.get('moved'))!;
      expect(moved.token, 'token-moved-2');
      expect(moved.lastPushAt, isNull, reason: 'the new token got no push yet: due next tick');
      expect(moved.apnsEnvironment, isNull, reason: 'the old token\'s environment says nothing about the new one');

      final regrouped = (await store.get('regrouped'))!;
      expect(regrouped.groupUuid, 'group-2');
      expect(regrouped.lastPushAt, noon);
      expect(stats.delivered, 2);
    });

    test('A dead old token doesn\'t delete a device that re-registered meanwhile', () async {
      final store = InMemoryDeviceStore();
      await store.put(_device('moved'));
      final apns = _MidFlightSender(store, {'moved': (d) => d.copyWith(token: 'token-moved-2')}, dead: {'moved'});

      final stats = await SyncScheduler(store: store, senders: {'apns': apns}, now: () => noon).tick();

      expect((await store.get('moved'))?.token, 'token-moved-2');
      expect(stats.removed, 0);
    });

    test('An unsubscribe during the push is not undone by the tick', () async {
      final store = InMemoryDeviceStore();
      await store.put(_device('gone'));
      final apns = _MidFlightSender(store, {'gone': (_) => null});

      await SyncScheduler(store: store, senders: {'apns': apns}, now: () => noon).tick();

      expect(await store.get('gone'), isNull);
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

  test('FileDeviceStore saves a burst of changes together and recovers from a failed write', () async {
    final dir = await Directory.systemTemp.createTemp('push_store_test');
    addTearDown(() => dir.delete(recursive: true));
    final path = '${dir.path}/devices.json';

    final store = await FileDeviceStore.open(path);
    await Future.wait([for (var i = 0; i < 50; i++) store.put(_device('d$i'))]);
    expect(await (await FileDeviceStore.open(path)).all(), hasLength(50));

    // The data directory disappears (volume hiccup): that write fails, the next one works
    await dir.delete(recursive: true);
    await expectLater(store.put(_device('lost')), throwsA(isA<FileSystemException>()));
    await dir.create();
    await store.put(_device('back'));
    expect(await (await FileDeviceStore.open(path)).all(), hasLength(52));
  });
}
