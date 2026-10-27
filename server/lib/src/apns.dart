import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:http2/http2.dart';
import 'device.dart';
import 'push_sender.dart';

class HttpResponseData {
  final int status;
  final String body;
  const HttpResponseData(this.status, this.body);
}

/// One HTTP/2 POST to APNs; replaceable in tests.
abstract class ApnsTransport {
  Future<HttpResponseData> post(String host, String path, Map<String, String> headers, String body);
  Future<void> close();
}

/// Keeps one HTTP/2 connection per APNs host, as Apple recommends.
class Http2ApnsTransport implements ApnsTransport {
  final Map<String, ClientTransportConnection> _connections = {};

  Future<ClientTransportConnection> _connection(String host) async {
    final existing = _connections[host];
    if (existing != null && existing.isOpen) return existing;
    final socket = await SecureSocket.connect(host, 443, supportedProtocols: ['h2']);
    return _connections[host] = ClientTransportConnection.viaSocket(socket);
  }

  @override
  Future<HttpResponseData> post(String host, String path, Map<String, String> headers, String body) async {
    final connection = await _connection(host);
    final stream = connection.makeRequest([
      Header.ascii(':method', 'POST'),
      Header.ascii(':scheme', 'https'),
      Header.ascii(':path', path),
      Header.ascii(':authority', host),
      for (final e in headers.entries) Header.ascii(e.key, e.value),
    ]);
    stream.sendData(utf8.encode(body), endStream: true);

    var status = 0;
    final data = <int>[];
    await for (final message in stream.incomingMessages.timeout(const Duration(seconds: 20))) {
      if (message is HeadersStreamMessage) {
        for (final header in message.headers) {
          if (utf8.decode(header.name) == ':status') status = int.parse(utf8.decode(header.value));
        }
      } else if (message is DataStreamMessage) {
        data.addAll(message.bytes);
      }
    }
    return HttpResponseData(status, utf8.decode(data, allowMalformed: true));
  }

  @override
  Future<void> close() async {
    for (final c in _connections.values) {
      await c.finish();
    }
    _connections.clear();
  }
}

/// Silent pushes through APNs with token-based (.p8) authentication.
///
/// Xcode builds get sandbox tokens, TestFlight/App Store builds production ones,
/// and the app can't tell which. An unknown device is tried on production first;
/// "BadDeviceToken" there means it is a sandbox token, which is then remembered.
class ApnsClient implements PushSender {
  static const productionHost = 'api.push.apple.com';
  static const sandboxHost = 'api.sandbox.push.apple.com';

  final String keyId;
  final String teamId;
  final String bundleId;
  final String _privateKeyPem;
  final ApnsTransport _transport;
  final DateTime Function() _now;

  String? _jwt;
  DateTime? _jwtIssuedAt;

  ApnsClient({
    required this.keyId,
    required this.teamId,
    required this.bundleId,
    required this._privateKeyPem,
    ApnsTransport? transport,
    DateTime Function()? now,
  })  : _transport = transport ?? Http2ApnsTransport(),
        _now = now ?? DateTime.now;

  /// Apple accepts a provider token for an hour and rejects refreshing it more
  /// often than every 20 minutes; reuse it for 50.
  String get providerToken {
    final issued = _jwtIssuedAt;
    if (_jwt == null || issued == null || _now().difference(issued) > const Duration(minutes: 50)) {
      final issuedAt = _now();
      _jwt = JWT(
        {'iss': teamId, 'iat': issuedAt.millisecondsSinceEpoch ~/ 1000},
        header: {'kid': keyId},
      ).sign(ECPrivateKey(_privateKeyPem), algorithm: JWTAlgorithm.ES256, noIssueAt: true);
      _jwtIssuedAt = issuedAt;
    }
    return _jwt!;
  }

  @override
  Future<PushResult> sendSync(Device device) async {
    final known = device.apnsEnvironment;
    final first = await _send(device.token, known ?? 'production');
    if (known == null && first.outcome == PushOutcome.invalidToken && first.detail == 'BadDeviceToken') {
      return _send(device.token, 'sandbox');
    }
    return first;
  }

  Future<PushResult> _send(String token, String environment) async {
    final host = environment == 'sandbox' ? sandboxHost : productionHost;
    final HttpResponseData response;
    try {
      response = await _transport.post(
        host,
        '/3/device/$token',
        {
          'authorization': 'bearer $providerToken',
          'apns-topic': bundleId,
          'apns-push-type': 'background',
          // Background pushes must use priority 5
          'apns-priority': '5',
          'content-type': 'application/json',
        },
        '{"aps":{"content-available":1},"type":"sync"}',
      );
    } catch (e) {
      return PushResult(PushOutcome.retryLater, detail: 'network: $e');
    }

    if (response.status == 200) {
      return PushResult(PushOutcome.delivered, apnsEnvironment: environment);
    }
    final reason = _reason(response.body);
    if (response.status == 410 || reason == 'Unregistered' || reason == 'BadDeviceToken' || reason == 'DeviceTokenNotForTopic') {
      return PushResult(PushOutcome.invalidToken, detail: reason ?? 'HTTP ${response.status}');
    }
    if (response.status == 403 && (reason == 'ExpiredProviderToken' || reason == 'InvalidProviderToken')) {
      _jwt = null; // sign a fresh token next time
    }
    return PushResult(PushOutcome.retryLater, detail: reason ?? 'HTTP ${response.status}');
  }

  static String? _reason(String body) {
    try {
      return (jsonDecode(body) as Map<String, dynamic>)['reason'] as String?;
    } catch (_) {
      return null;
    }
  }

  Future<void> close() => _transport.close();
}
