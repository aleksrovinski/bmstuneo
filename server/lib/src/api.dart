import 'dart:convert';
import 'dart:io';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'device.dart';
import 'device_store.dart';
import 'scheduler.dart';

final _uuid = RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$');
final _secret = RegExp(r'^[A-Za-z0-9_-]{32,128}$');
final _apnsToken = RegExp(r'^[0-9a-fA-F]{64,200}$');
final _fcmToken = RegExp(r'^[A-Za-z0-9_:\-]{20,4096}$');

const _maxBodyBytes = 8 * 1024;

/// HTTP API used by the app:
///
///   POST   /v1/devices                 register or update this installation
///   DELETE /v1/devices/{installationId} unsubscribe (header x-installation-secret)
///   GET    /healthz
///   POST   /internal/tick              run one scheduler pass (Bearer ADMIN_TOKEN)
Handler buildHandler({
  required DeviceStore store,
  required SyncScheduler scheduler,
  String? adminToken,
  RateLimiter? rateLimiter,
  DateTime Function()? now,
}) {
  final clock = now ?? DateTime.now;
  final router = Router();

  router.post('/v1/devices', (Request request) async {
    final Map<String, dynamic> body;
    try {
      body = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
    } catch (_) {
      return _error(400, 'invalid JSON');
    }

    final id = body['installationId'];
    final secret = body['secret'];
    final platform = body['platform'];
    final token = body['token'];
    final group = body['groupUuid'];
    if (id is! String || !_uuid.hasMatch(id)) return _error(400, 'installationId must be a UUID');
    if (secret is! String || !_secret.hasMatch(secret)) return _error(400, 'secret must be 32-128 url-safe chars');
    if (platform != 'apns' && platform != 'fcm') return _error(400, 'platform must be apns or fcm');
    final tokenPattern = platform == 'apns' ? _apnsToken : _fcmToken;
    if (token is! String || !tokenPattern.hasMatch(token)) return _error(400, 'malformed $platform token');
    if (group != null && (group is! String || !_uuid.hasMatch(group))) return _error(400, 'groupUuid must be a UUID');

    final at = clock().toUtc();
    final existing = await store.get(id);
    if (existing == null) {
      await store.put(Device(
        installationId: id,
        secretHash: Device.hashSecret(secret),
        platform: platform as String,
        token: token,
        groupUuid: group as String?,
        createdAt: at,
        updatedAt: at,
      ));
      return Response(201);
    }
    if (!existing.secretMatches(secret)) return _error(403, 'installation belongs to someone else');

    final tokenChanged = existing.token != token || existing.platform != platform;
    await store.put(existing.copyWith(
      platform: platform as String,
      token: token,
      groupUuid: group as String?,
      clearGroup: group == null,
      // A new token may live in the other APNs environment: learn it again
      clearApnsEnvironment: tokenChanged,
      updatedAt: at,
    ));
    return Response(204);
  });

  router.delete('/v1/devices/<id>', (Request request, String id) async {
    final existing = await store.get(id);
    if (existing == null) return Response(204); // already gone: unsubscribing is idempotent
    final secret = request.headers['x-installation-secret'];
    if (secret == null || !existing.secretMatches(secret)) return _error(403, 'wrong installation secret');
    await store.delete(id);
    return Response(204);
  });

  router.get('/healthz', (Request request) async {
    return Response.ok(jsonEncode({'ok': true, 'devices': (await store.all()).length}),
        headers: {'content-type': 'application/json'});
  });

  router.post('/internal/tick', (Request request) async {
    if (adminToken == null || adminToken.isEmpty) return Response.notFound(null);
    if (request.headers['authorization'] != 'Bearer $adminToken') return _error(401, 'admin token required');
    final stats = await scheduler.tick();
    return Response.ok(jsonEncode(stats.toJson()), headers: {'content-type': 'application/json'});
  });

  final limiter = rateLimiter ?? RateLimiter();
  return const Pipeline()
      .addMiddleware(_limitBody())
      .addMiddleware(limiter.middleware(clock))
      .addHandler(router.call);
}

Response _error(int status, String message) =>
    Response(status, body: jsonEncode({'error': message}), headers: {'content-type': 'application/json'});

Middleware _limitBody() => (inner) => (request) {
      final length = request.contentLength;
      if (length != null && length > _maxBodyBytes) return _error(413, 'body too large');
      return inner(request);
    };

/// Fixed-window limit per client IP; enough to stop scripted abuse of a tiny API.
class RateLimiter {
  final int maxPerMinute;
  final Map<String, (int, int)> _windows = {}; // ip -> (minute, count)

  RateLimiter({this.maxPerMinute = 60});

  bool allow(String ip, DateTime now) {
    final minute = now.millisecondsSinceEpoch ~/ 60000;
    final (seen, count) = _windows[ip] ?? (minute, 0);
    final next = seen == minute ? count + 1 : 1;
    _windows[ip] = (minute, next);
    if (_windows.length > 10000) _windows.removeWhere((_, w) => w.$1 != minute);
    return next <= maxPerMinute;
  }

  Middleware middleware(DateTime Function() clock) => (inner) => (request) {
        if (!allow(clientIp(request), clock())) return _error(429, 'too many requests');
        return inner(request);
      };

  /// Behind a reverse proxy the client is the first X-Forwarded-For entry.
  static String clientIp(Request request) {
    final forwarded = request.headers['x-forwarded-for'];
    if (forwarded != null && forwarded.isNotEmpty) return forwarded.split(',').first.trim();
    final info = request.context['shelf.io.connection_info'];
    return info is HttpConnectionInfo ? info.remoteAddress.address : 'unknown';
  }
}
