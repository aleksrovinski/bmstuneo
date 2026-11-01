import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../constants/app_mode.dart';
import '../constants/app_version.dart';

/// A newer APK published on the website (`version.json` next to the landing page).
class AppUpdateInfo {
  final int versionCode;
  final String versionName;
  final Uri apkUrl;
  final int size;
  final String sha256;
  final String notes;

  const AppUpdateInfo({
    required this.versionCode,
    required this.versionName,
    required this.apkUrl,
    required this.size,
    required this.sha256,
    this.notes = '',
  });

  /// `apk` may be relative to the manifest URL. Returns null for a malformed manifest.
  static AppUpdateInfo? fromJson(Map<String, dynamic> json, Uri manifestUrl) {
    final code = json['versionCode'];
    final name = json['versionName'];
    final apk = json['apk'];
    final sha = json['sha256'];
    if (code is! int || name is! String || apk is! String || sha is! String) return null;
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(sha)) return null;
    final url = manifestUrl.resolve(apk);
    // Only ever install over HTTPS, whatever the manifest says
    if (url.scheme != 'https') return null;
    return AppUpdateInfo(
      versionCode: code,
      versionName: name,
      apkUrl: url,
      size: json['size'] is int ? json['size'] as int : 0,
      sha256: sha,
      notes: json['notes'] is String ? json['notes'] as String : '',
    );
  }
}

enum InstallOutcome { started, needsPermission, corrupted, failed }

/// Self-updates for the Android APK distributed from the website (there is no store
/// to do it). iOS builds come from TestFlight, which updates them itself.
class AppUpdater {
  static const manifestUrl =
      String.fromEnvironment('UPDATE_MANIFEST_URL', defaultValue: 'https://bmstuneo.xyz/version.json');
  static const _channel = MethodChannel('ru.bmstu.neo/update');
  static const lastCheckKey = 'app_update_last_check_v1';
  static const skippedKey = 'app_update_skipped_v1';
  static const checkInterval = Duration(hours: 12);

  final Uri _manifest;
  final int _currentBuild;
  final Dio _dio;

  AppUpdater({String? manifest, int? currentBuild, Dio? dio})
      : _manifest = Uri.parse(manifest ?? manifestUrl),
        _currentBuild = currentBuild ?? int.tryParse(AppVersion.buildNumber) ?? 0,
        _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 30),
            ));

  static bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android && !AppMode.isDemo && kReleaseMode;

  /// Returns a newer version, or null when up to date, offline or the manifest is broken.
  /// Without [force] it asks the website at most every [checkInterval] and ignores a
  /// version the student chose to skip.
  Future<AppUpdateInfo?> check({bool force = false}) async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now().millisecondsSinceEpoch;
    if (!force) {
      final last = prefs.getInt(lastCheckKey) ?? 0;
      if (now - last < checkInterval.inMilliseconds) return null;
    }
    try {
      final response = await _dio.getUri<Map<String, dynamic>>(
        _manifest.replace(queryParameters: {'t': '$now'}), // past any caching proxy
      );
      await prefs.setInt(lastCheckKey, now);
      final data = response.data;
      final info = data == null ? null : AppUpdateInfo.fromJson(data, _manifest);
      if (info == null || info.versionCode <= _currentBuild) return null;
      if (!force && prefs.getInt(skippedKey) == info.versionCode) return null;
      return info;
    } catch (e) {
      debugPrint('[AppUpdater] Check failed: $e');
      return null;
    }
  }

  Future<void> skip(AppUpdateInfo info) async =>
      (await SharedPreferences.getInstance()).setInt(skippedKey, info.versionCode);

  /// Downloads the APK into the app cache; [onProgress] gets 0..1.
  Future<String> download(AppUpdateInfo info, {void Function(double)? onProgress, CancelToken? cancel}) async {
    final path = await _channel.invokeMethod<String>('downloadPath');
    if (path == null) throw StateError('No download path');
    await _dio.downloadUri(
      info.apkUrl,
      path,
      cancelToken: cancel,
      options: Options(receiveTimeout: const Duration(minutes: 5)),
      onReceiveProgress: (received, total) {
        final expected = total > 0 ? total : info.size;
        if (expected > 0) onProgress?.call((received / expected).clamp(0, 1).toDouble());
      },
    );
    return path;
  }

  /// Checks the checksum natively and opens the system installer.
  Future<InstallOutcome> install(String path, AppUpdateInfo info) async {
    try {
      final result = await _channel.invokeMethod<String>('install', {'path': path, 'sha256': info.sha256});
      return switch (result) {
        'started' => InstallOutcome.started,
        'needsPermission' => InstallOutcome.needsPermission,
        'corrupted' => InstallOutcome.corrupted,
        _ => InstallOutcome.failed,
      };
    } catch (e) {
      debugPrint('[AppUpdater] Install failed: $e');
      return InstallOutcome.failed;
    }
  }
}
