import 'dart:convert';
import 'dart:math';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user_profile.dart';
import '../providers/auth_provider.dart';

/// Registers this installation with the BMSTU neo push server (server/ in the repo),
/// which then wakes the app with silent pushes on a schedule.
///
/// Only the push token, the platform and the group UUID are sent. The installation
/// proves it owns its record with a random secret kept in secure storage.
/// Without `--dart-define=PUSH_SERVER_URL=...` this does nothing.
class PushServer {
  static const configuredUrl = String.fromEnvironment('PUSH_SERVER_URL');
  static const _idKey = 'push_installation_id';
  static const _secretKey = 'push_installation_secret';

  final String baseUrl;
  final Dio _dio;
  final FlutterSecureStorage _secureStorage;

  PushServer({String? baseUrl, Dio? dio, FlutterSecureStorage? secureStorage})
      : baseUrl = baseUrl ?? configuredUrl,
        _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 10),
            )),
        _secureStorage = secureStorage ?? const FlutterSecureStorage();

  bool get isConfigured => baseUrl.isNotEmpty;

  Future<(String, String)> _identity() async {
    var id = await _secureStorage.read(key: _idKey);
    var secret = await _secureStorage.read(key: _secretKey);
    if (id == null || secret == null) {
      final random = Random.secure();
      final bytes = List<int>.generate(16, (_) => random.nextInt(256));
      bytes[6] = (bytes[6] & 0x0f) | 0x40; // UUID v4
      bytes[8] = (bytes[8] & 0x3f) | 0x80;
      final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      id = '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-'
          '${hex.substring(16, 20)}-${hex.substring(20)}';
      secret = base64Url.encode(List<int>.generate(32, (_) => random.nextInt(256))).replaceAll('=', '');
      await _secureStorage.write(key: _idKey, value: id);
      await _secureStorage.write(key: _secretKey, value: secret);
    }
    return (id, secret);
  }

  /// Sends the current push token; safe to call on every launch.
  Future<bool> register({required String token, required String platform}) async {
    if (!isConfigured) return false;
    try {
      final (id, secret) = await _identity();
      await _dio.post<void>('$baseUrl/v1/devices', data: {
        'installationId': id,
        'secret': secret,
        'platform': platform,
        'token': token,
        'groupUuid': ?await _groupUuid(),
      });
      return true;
    } catch (e) {
      debugPrint('[PushServer] Registration failed, periodic checks still work: $e');
      return false;
    }
  }

  Future<void> unregister() async {
    if (!isConfigured) return;
    try {
      final id = await _secureStorage.read(key: _idKey);
      final secret = await _secureStorage.read(key: _secretKey);
      if (id == null || secret == null) return;
      await _dio.delete<void>('$baseUrl/v1/devices/$id', options: Options(headers: {'x-installation-secret': secret}));
    } catch (e) {
      debugPrint('[PushServer] Unregistration failed: $e');
    }
  }

  // For schedule-change pushes later; the server never learns who the student is
  static Future<String?> _groupUuid() async {
    final raw = (await SharedPreferences.getInstance()).getString(AuthProvider.cachedProfileKey);
    if (raw == null) return null;
    try {
      final group = UserProfile.fromJson(jsonDecode(raw) as Map<String, dynamic>).groupUuid;
      return group.isEmpty ? null : group;
    } catch (_) {
      return null;
    }
  }
}
