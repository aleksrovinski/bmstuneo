import 'dart:convert';
import 'dart:ui';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';
import '../models/discipline_progress.dart';
import '../models/user_profile.dart';
import '../providers/auth_provider.dart';
import '../providers/progress_provider.dart';
import '../providers/schedule_provider.dart';
import 'app_notifications.dart';
import 'auth_storage.dart';
import 'bmstu_api_service.dart';
import 'progress_alerts.dart';
import 'push_channel.dart';
import 'secure_cookie_storage.dart';
import 'widget_sync_service.dart';

/// Entry point the OS calls in the background (Android WorkManager, iOS Background
/// App Refresh). A silent push will call [BackgroundSync.run] the same way.
@pragma('vm:entry-point')
void backgroundSyncDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    WidgetsFlutterBinding.ensureInitialized();
    DartPluginRegistrant.ensureInitialized();
    try {
      await BackgroundSync.run();
      return true;
    } catch (e) {
      debugPrint('[BackgroundSync] Failed: $e');
      // Let the OS retry later instead of reporting success
      return false;
    }
  });
}

/// Refreshes the student's progress without the UI and notifies about changes.
class BackgroundSync {
  static const taskId = 'ru.bmstu.neo.sync';
  static const enabledKey = 'notifications_progress_enabled_v1';
  static const _notifiedKey = 'notified_progress_alerts_v1';
  static const _maxRemembered = 300;
  static const _runningSinceKey = 'background_sync_running_since_v1';
  // A sync that started longer ago than this crashed or was killed: don't wait for it
  static const _staleRun = Duration(minutes: 2);
  // Same-isolate guard; the prefs flag above covers the WorkManager isolate
  static bool _running = false;

  static Future<bool> isEnabled() async =>
      (await SharedPreferences.getInstance()).getBool(enabledKey) ?? false;

  /// Turns periodic background checks on or off. Returns false if the OS denied
  /// the notification permission (nothing is scheduled then).
  static Future<bool> setEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    if (!enabled) {
      await prefs.setBool(enabledKey, false);
      await Workmanager().cancelByUniqueName(taskId);
      await PushChannel.disable();
      return true;
    }
    if (!await AppNotifications.requestPermission()) return false;
    await prefs.setBool(enabledKey, true);
    await Workmanager().registerPeriodicTask(
      taskId,
      taskId,
      // Android's minimum is 15 min; iOS treats it as a hint and picks its own time
      frequency: const Duration(hours: 1),
      // Android runs a new periodic task right away; enabling already did the first sync
      initialDelay: const Duration(hours: 1),
      constraints: Constraints(networkType: NetworkType.connected),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
    );
    // Silent pushes on top of the periodic checks; failing here doesn't block them
    await PushChannel.enable();
    return true;
  }

  /// One sync pass. Returns the alerts that were delivered. Never asks the user
  /// anything: without a cached profile or saved credentials it just stops.
  static Future<List<ProgressAlert>> run({
    BmstuApiService? api,
    AuthStorage? authStorage,
    Future<void> Function(List<ProgressAlert>)? deliver,
  }) async {
    if (_running) return const [];
    _running = true;
    try {
      return await _runExclusive(api: api, authStorage: authStorage, deliver: deliver);
    } finally {
      _running = false;
    }
  }

  static Future<List<ProgressAlert>> _runExclusive({
    BmstuApiService? api,
    AuthStorage? authStorage,
    Future<void> Function(List<ProgressAlert>)? deliver,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    // Background tasks run in their own isolate with their own prefs cache: re-read what
    // the app (or another task) wrote, so two syncs don't both notify about the same thing
    await prefs.reload();
    if (!(prefs.getBool(enabledKey) ?? false)) return const [];

    final now = DateTime.now().millisecondsSinceEpoch;
    final runningSince = prefs.getInt(_runningSinceKey);
    if (runningSince != null && now - runningSince < _staleRun.inMilliseconds) {
      debugPrint('[BackgroundSync] Another sync is in progress, skipping');
      return const [];
    }
    await prefs.setInt(_runningSinceKey, now);
    final storage = authStorage ?? AuthStorage();
    final service = api ?? BmstuApiService(cookieJar: PersistCookieJar(storage: SecureCookieStorage()));
    // The saved LKS session usually works; if it expired, sign in with the saved password
    service.onSilentRelogin = () => _login(service, storage);
    try {
      final alerts = await _run(prefs, service, storage, deliver: deliver);
      // Whatever happened with progress, keep the home-screen widget current
      await _refreshScheduleWidget(prefs, service);
      return alerts;
    } finally {
      await prefs.remove(_runningSinceKey);
    }
  }

  static Future<List<ProgressAlert>> _run(
    SharedPreferences prefs,
    BmstuApiService service,
    AuthStorage storage, {
    Future<void> Function(List<ProgressAlert>)? deliver,
  }) async {
    final stageUuid = _cachedProfile(prefs)?.stageUuid;
    if (stageUuid == null || stageUuid.isEmpty) return const [];

    List<DisciplineProgress> fresh;
    try {
      fresh = await service.getProgress(stageUuid);
    } on BmstuAuthException {
      if (!await _login(service, storage)) return const [];
      fresh = await service.getProgress(stageUuid);
    }
    if (fresh.isEmpty) return const [];

    final week = (await service.getCurrentWeek())?.weekNumber ?? 1;
    final cacheKey = '${ProgressProvider.cacheProgressPrefix}$stageUuid';
    final previous = _decodeProgress(prefs.getString(cacheKey));
    final marks = ManualMark.decodeAll(prefs.getString(ProgressProvider.manualMarksKey));
    final notified = (prefs.getStringList(_notifiedKey) ?? const <String>[]).toSet();

    final alerts = computeProgressAlerts(
      previous: previous,
      current: [for (final d in fresh) d.withManualMarks(marks)],
      currentWeek: week,
      alreadyNotified: notified,
    );

    // The app shows the same fresh data next time it opens
    await prefs.setString(cacheKey, jsonEncode(fresh.map((d) => d.toJson()).toList()));
    await prefs.setString('${ProgressProvider.cacheProgressTimePrefix}$stageUuid', DateTime.now().toIso8601String());

    if (alerts.isNotEmpty) {
      final remembered = [...prefs.getStringList(_notifiedKey) ?? const <String>[], ...alerts.map((a) => a.key)];
      await prefs.setStringList(
        _notifiedKey,
        remembered.length > _maxRemembered ? remembered.sublist(remembered.length - _maxRemembered) : remembered,
      );
      await (deliver ?? AppNotifications.show)(alerts);
    }
    debugPrint('[BackgroundSync] Done: ${alerts.length} alert(s)');
    return alerts;
  }

  /// Reloads the group's schedule (public, no session needed) and stores a fresh widget
  /// snapshot; on Android the push's follow-up WidgetRefreshWorker redraws the widget from it.
  static Future<void> _refreshScheduleWidget(SharedPreferences prefs, BmstuApiService service) async {
    final profile = _cachedProfile(prefs);
    if (profile == null || profile.groupUuid.isEmpty) return;
    try {
      final schedule = ScheduleProvider(apiService: service);
      await schedule.loadCustomLessons();
      await schedule.loadSchedule(groupUuid: profile.groupUuid, groupTitle: profile.groupTitle);
      if (schedule.allLessons.isEmpty) return;
      await WidgetSyncService.updateScheduleWidget(scheduleProvider: schedule);
    } catch (e) {
      debugPrint('[BackgroundSync] Widget refresh failed: $e');
    }
  }

  static UserProfile? _cachedProfile(SharedPreferences prefs) {
    final raw = prefs.getString(AuthProvider.cachedProfileKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      return UserProfile.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  static List<DisciplineProgress>? _decodeProgress(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      return (jsonDecode(raw) as List)
          .whereType<Map<String, dynamic>>()
          .map(DisciplineProgress.fromJson)
          .toList();
    } catch (_) {
      return null;
    }
  }

  static Future<bool> _login(BmstuApiService service, AuthStorage storage) async {
    final creds = await storage.getCredentials();
    final user = creds['username'];
    final pass = creds['password'];
    if (user == null || user.isEmpty || pass == null || pass.isEmpty) return false;
    try {
      return await service.login(user.trim(), pass) != null;
    } catch (e) {
      debugPrint('[BackgroundSync] Login failed: $e');
      return false;
    }
  }
}
