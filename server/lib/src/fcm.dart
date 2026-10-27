import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'apns.dart' show HttpResponseData;
import 'device.dart';
import 'push_sender.dart';

/// One HTTP/1.1 POST; replaceable in tests.
typedef HttpPost = Future<HttpResponseData> Function(Uri url, Map<String, String> headers, String body);

Future<HttpResponseData> ioHttpPost(Uri url, Map<String, String> headers, String body) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
  try {
    final request = await client.postUrl(url);
    headers.forEach(request.headers.set);
    request.write(body);
    final response = await request.close().timeout(const Duration(seconds: 20));
    return HttpResponseData(response.statusCode, await response.transform(utf8.decoder).join());
  } finally {
    client.close();
  }
}

/// Silent (data-only) pushes through FCM HTTP v1, authenticated with a service account.
class FcmClient implements PushSender {
  static const _scope = 'https://www.googleapis.com/auth/firebase.messaging';

  final String projectId;
  final String _clientEmail;
  final String _privateKeyPem;
  final Uri _tokenUri;
  final HttpPost _post;
  final DateTime Function() _now;

  String? _accessToken;
  DateTime? _accessTokenExpires;

  FcmClient._(this.projectId, this._clientEmail, this._privateKeyPem, this._tokenUri, this._post, this._now);

  /// [serviceAccountJson] is the key file downloaded from Firebase → Service accounts.
  factory FcmClient.fromServiceAccount(String serviceAccountJson, {HttpPost? post, DateTime Function()? now}) {
    final json = jsonDecode(serviceAccountJson) as Map<String, dynamic>;
    return FcmClient._(
      json['project_id'] as String,
      json['client_email'] as String,
      json['private_key'] as String,
      Uri.parse(json['token_uri'] as String? ?? 'https://oauth2.googleapis.com/token'),
      post ?? ioHttpPost,
      now ?? DateTime.now,
    );
  }

  Future<String> _token() async {
    final expires = _accessTokenExpires;
    if (_accessToken != null && expires != null && _now().isBefore(expires)) return _accessToken!;

    final assertion = JWT(
      {'scope': _scope},
      issuer: _clientEmail,
      audience: Audience.one(_tokenUri.toString()),
    ).sign(RSAPrivateKey(_privateKeyPem), algorithm: JWTAlgorithm.RS256, expiresIn: const Duration(hours: 1));

    final response = await _post(
      _tokenUri,
      {'content-type': 'application/x-www-form-urlencoded'},
      'grant_type=${Uri.encodeQueryComponent('urn:ietf:params:oauth:grant-type:jwt-bearer')}'
          '&assertion=${Uri.encodeQueryComponent(assertion)}',
    );
    if (response.status != 200) {
      throw StateError('FCM OAuth failed: HTTP ${response.status}');
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    _accessToken = json['access_token'] as String;
    // Renew a minute before Google's expiry
    _accessTokenExpires = _now().add(Duration(seconds: (json['expires_in'] as num? ?? 3600).toInt() - 60));
    return _accessToken!;
  }

  @override
  Future<PushResult> sendSync(Device device) async {
    final HttpResponseData response;
    try {
      response = await _post(
        Uri.parse('https://fcm.googleapis.com/v1/projects/$projectId/messages:send'),
        {'authorization': 'Bearer ${await _token()}', 'content-type': 'application/json'},
        jsonEncode({
          'message': {
            'token': device.token,
            'data': {'type': 'sync'},
            // Data-only + high priority reaches PushMessagingService in the background
            'android': {'priority': 'high'},
          },
        }),
      );
    } catch (e) {
      return PushResult(PushOutcome.retryLater, detail: 'network: $e');
    }

    if (response.status == 200) return const PushResult(PushOutcome.delivered);
    final code = _errorCode(response.body);
    if (response.status == 404 || code == 'UNREGISTERED' || (response.status == 400 && code == 'INVALID_ARGUMENT')) {
      return PushResult(PushOutcome.invalidToken, detail: code ?? 'HTTP ${response.status}');
    }
    if (response.status == 401) _accessToken = null; // fetch a new OAuth token next time
    return PushResult(PushOutcome.retryLater, detail: code ?? 'HTTP ${response.status}');
  }

  /// FCM puts the precise reason into error.details[].errorCode, falling back to error.status.
  static String? _errorCode(String body) {
    try {
      final error = (jsonDecode(body) as Map<String, dynamic>)['error'] as Map<String, dynamic>;
      for (final detail in (error['details'] as List? ?? const []).whereType<Map<String, dynamic>>()) {
        final code = detail['errorCode'] as String?;
        if (code != null) return code;
      }
      return error['status'] as String?;
    } catch (_) {
      return null;
    }
  }
}
