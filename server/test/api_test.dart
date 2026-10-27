import 'dart:convert';
import 'package:bmstu_neo_push/bmstu_neo_push.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

const _id = '3f2b8c1e-4d5a-4b6c-8d7e-9f0a1b2c3d4e';
const _secret = 'Zq3x-8vLmN2pQr5sT7uW9yA1bC4dE6fG8hJ0kL2mN4p';
const _apnsToken = '42685e92ab12cd34ef5678901234567890abcdef1234567890abcdef12345678';
const _group = '08e4210a-47ca-11ee-814c-005056961205';

void main() {
  late InMemoryDeviceStore store;
  late Handler handler;
  final now = DateTime.utc(2026, 10, 23, 12);

  setUp(() {
    store = InMemoryDeviceStore();
    handler = buildHandler(
      store: store,
      scheduler: SyncScheduler(store: store, senders: {}),
      adminToken: 'admin-secret',
      now: () => now,
    );
  });

  Future<Response> register(Map<String, dynamic> body, {String ip = '10.0.0.1'}) async => await handler(Request(
        'POST',
        Uri.parse('http://localhost/v1/devices'),
        body: jsonEncode(body),
        headers: {'x-forwarded-for': ip},
      ));

  Map<String, dynamic> device({String secret = _secret, String token = _apnsToken, String? group = _group}) => {
        'installationId': _id,
        'secret': secret,
        'platform': 'apns',
        'token': token,
        'groupUuid': ?group,
      };

  test('Registers a device and stores only a hash of its secret', () async {
    expect((await register(device())).statusCode, 201);
    final saved = (await store.get(_id))!;
    expect(saved.token, _apnsToken);
    expect(saved.groupUuid, _group);
    expect(saved.secretHash, isNot(contains(_secret)));
    expect(saved.secretMatches(_secret), isTrue);
  });

  test('Only the owner can update a registration; a new token forgets the APNs environment', () async {
    await register(device());
    await store.put((await store.get(_id))!.copyWith(apnsEnvironment: 'sandbox'));

    final hijack = await register(device(secret: 'x' * 40, token: 'ab' * 32));
    expect(hijack.statusCode, 403);
    expect((await store.get(_id))!.token, _apnsToken);

    expect((await register(device(token: 'cd' * 32))).statusCode, 204);
    final updated = (await store.get(_id))!;
    expect(updated.token, 'cd' * 32);
    expect(updated.apnsEnvironment, isNull);
  });

  test('Rejects malformed input', () async {
    expect((await register({...device(), 'installationId': 'not-a-uuid'})).statusCode, 400);
    expect((await register(device(secret: 'short'))).statusCode, 400);
    expect((await register({...device(), 'platform': 'sms'})).statusCode, 400);
    expect((await register(device(token: 'not hex!'))).statusCode, 400);
    expect((await register({...device(), 'groupUuid': 42})).statusCode, 400);
    final notJson = await handler(Request('POST', Uri.parse('http://localhost/v1/devices'), body: '{oops'));
    expect(notJson.statusCode, 400);
    expect(await store.all(), isEmpty);
  });

  test('Unsubscribing needs the installation secret and is idempotent', () async {
    await register(device());
    Future<Response> delete(String? secret) async => await handler(Request(
          'DELETE',
          Uri.parse('http://localhost/v1/devices/$_id'),
          headers: {'x-installation-secret': ?secret},
        ));

    expect((await delete('wrong-secret')).statusCode, 403);
    expect(await store.get(_id), isNotNull);
    expect((await delete(_secret)).statusCode, 204);
    expect(await store.get(_id), isNull);
    expect((await delete(_secret)).statusCode, 204);
  });

  test('Oversized bodies and floods are refused', () async {
    final big = await handler(Request('POST', Uri.parse('http://localhost/v1/devices'),
        body: 'x' * 9000, headers: {'content-length': '9000'}));
    expect(big.statusCode, 413);

    final statuses = [for (var i = 0; i < 61; i++) (await register(device(), ip: '10.0.0.9')).statusCode];
    expect(statuses.last, 429);
    expect((await register(device(), ip: '10.0.0.10')).statusCode, isNot(429), reason: 'other clients unaffected');
  });

  test('Health check and the admin-only manual tick', () async {
    await register(device());
    final health = await handler(Request('GET', Uri.parse('http://localhost/healthz')));
    expect(jsonDecode(await health.readAsString()), {'ok': true, 'devices': 1});

    final anonymous = await handler(Request('POST', Uri.parse('http://localhost/internal/tick')));
    expect(anonymous.statusCode, 401);
    final admin = await handler(Request('POST', Uri.parse('http://localhost/internal/tick'),
        headers: {'authorization': 'Bearer admin-secret'}));
    expect(admin.statusCode, 200);
  });
}
