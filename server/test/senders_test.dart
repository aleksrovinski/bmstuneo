import 'dart:convert';
import 'dart:io';
import 'package:bmstu_neo_push/bmstu_neo_push.dart';
import 'package:test/test.dart';

final _apnsKey = File('test/fixtures/apns_throwaway.testkey').readAsStringSync();
final _fcmKey = File('test/fixtures/fcm_throwaway.testkey').readAsStringSync();

Device _device(String platform, {String? env}) => Device(
      installationId: '3f2b8c1e-4d5a-4b6c-8d7e-9f0a1b2c3d4e',
      secretHash: Device.hashSecret('s'),
      platform: platform,
      token: platform == 'apns' ? 'ab' * 32 : 'fcm-token-1234567890',
      apnsEnvironment: env,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    );

class FakeApns implements ApnsTransport {
  final List<String> hosts = [];
  final List<Map<String, String>> headers = [];
  final HttpResponseData Function(String host) answer;
  FakeApns(this.answer);

  @override
  Future<HttpResponseData> post(String host, String path, Map<String, String> h, String body) async {
    hosts.add(host);
    headers.add(h);
    expect(jsonDecode(body), {'aps': {'content-available': 1}, 'type': 'sync'});
    return answer(host);
  }

  @override
  Future<void> close() async {}
}

Map<String, dynamic> _jwtPart(String jwt, int i) =>
    jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(jwt.split('.')[i])))) as Map<String, dynamic>;

void main() {
  group('ApnsClient', () {
    ApnsClient client(FakeApns transport) => ApnsClient(
        keyId: 'A78SGLKGT5', teamId: 'F72A8BN5CB', bundleId: 'ru.bmstu.neo', privateKeyPem: _apnsKey, transport: transport);

    test('Sends a background push with an ES256 provider token', () async {
      final transport = FakeApns((_) => const HttpResponseData(200, ''));
      final result = await client(transport).sendSync(_device('apns', env: 'production'));

      expect(result.outcome, PushOutcome.delivered);
      final h = transport.headers.single;
      expect(h['apns-push-type'], 'background');
      expect(h['apns-priority'], '5');
      expect(h['apns-topic'], 'ru.bmstu.neo');
      final jwt = h['authorization']!.substring('bearer '.length);
      expect(_jwtPart(jwt, 0), {'alg': 'ES256', 'typ': 'JWT', 'kid': 'A78SGLKGT5'});
      expect(_jwtPart(jwt, 1)['iss'], 'F72A8BN5CB');
      expect(_jwtPart(jwt, 1)['iat'], isA<int>());
    });

    test('Unknown environment: a sandbox token is found after production says BadDeviceToken', () async {
      final transport = FakeApns((host) => host == ApnsClient.productionHost
          ? const HttpResponseData(400, '{"reason":"BadDeviceToken"}')
          : const HttpResponseData(200, ''));
      final result = await client(transport).sendSync(_device('apns'));

      expect(transport.hosts, [ApnsClient.productionHost, ApnsClient.sandboxHost]);
      expect(result.outcome, PushOutcome.delivered);
      expect(result.apnsEnvironment, 'sandbox');
    });

    test('Unregistered tokens are dead; throttling is temporary', () async {
      final gone = await client(FakeApns((_) => const HttpResponseData(410, '{"reason":"Unregistered"}')))
          .sendSync(_device('apns', env: 'production'));
      expect(gone.outcome, PushOutcome.invalidToken);

      final busy = await client(FakeApns((_) => const HttpResponseData(429, '{"reason":"TooManyRequests"}')))
          .sendSync(_device('apns', env: 'production'));
      expect(busy.outcome, PushOutcome.retryLater);
    });

    test('The provider token is reused instead of re-signed for every push', () async {
      var now = DateTime.utc(2026, 10, 23, 12);
      final transport = FakeApns((_) => const HttpResponseData(200, ''));
      final apns = ApnsClient(
          keyId: 'K', teamId: 'T', bundleId: 'ru.bmstu.neo', privateKeyPem: _apnsKey, transport: transport, now: () => now);
      await apns.sendSync(_device('apns', env: 'sandbox'));
      await apns.sendSync(_device('apns', env: 'sandbox'));
      now = now.add(const Duration(minutes: 55));
      await apns.sendSync(_device('apns', env: 'sandbox'));

      final tokens = transport.headers.map((h) => h['authorization']).toList();
      expect(tokens[0], tokens[1]);
      expect(tokens[2], isNot(tokens[0]));
    });
  });

  group('FcmClient', () {
    final account = jsonEncode({
      'project_id': 'bmstuneo',
      'client_email': 'push@bmstuneo.iam.gserviceaccount.com',
      'private_key': _fcmKey,
      'token_uri': 'https://oauth2.googleapis.com/token',
    });

    test('Exchanges a signed JWT for an access token once, then sends data-only high-priority pushes', () async {
      final calls = <(Uri, Map<String, String>, String)>[];
      Future<HttpResponseData> post(Uri url, Map<String, String> headers, String body) async {
        calls.add((url, headers, body));
        if (url.host == 'oauth2.googleapis.com') {
          return const HttpResponseData(200, '{"access_token":"ya29.test","expires_in":3599}');
        }
        return const HttpResponseData(200, '{"name":"projects/bmstuneo/messages/1"}');
      }

      final fcm = FcmClient.fromServiceAccount(account, post: post);
      expect((await fcm.sendSync(_device('fcm'))).outcome, PushOutcome.delivered);
      expect((await fcm.sendSync(_device('fcm'))).outcome, PushOutcome.delivered);

      expect(calls.where((c) => c.$1.host == 'oauth2.googleapis.com'), hasLength(1));
      final assertion = Uri.splitQueryString(calls.first.$3)['assertion']!;
      expect(_jwtPart(assertion, 0)['alg'], 'RS256');
      expect(_jwtPart(assertion, 1)['scope'], 'https://www.googleapis.com/auth/firebase.messaging');

      final send = calls[1];
      expect(send.$1.path, '/v1/projects/bmstuneo/messages:send');
      expect(send.$2['authorization'], 'Bearer ya29.test');
      expect(jsonDecode(send.$3), {
        'message': {
          'token': 'fcm-token-1234567890',
          'data': {'type': 'sync'},
          'android': {'priority': 'high'},
        },
      });
    });

    test('UNREGISTERED tokens are dead; server errors are temporary', () async {
      HttpPost answering(int status, String body) => (url, headers, _) async => url.host == 'oauth2.googleapis.com'
          ? const HttpResponseData(200, '{"access_token":"t","expires_in":3599}')
          : HttpResponseData(status, body);

      final gone = await FcmClient.fromServiceAccount(account,
              post: answering(404, '{"error":{"status":"NOT_FOUND","details":[{"errorCode":"UNREGISTERED"}]}}'))
          .sendSync(_device('fcm'));
      expect(gone.outcome, PushOutcome.invalidToken);

      final busy = await FcmClient.fromServiceAccount(account, post: answering(503, '{"error":{"status":"UNAVAILABLE"}}'))
          .sendSync(_device('fcm'));
      expect(busy.outcome, PushOutcome.retryLater);
    });
  });
}
