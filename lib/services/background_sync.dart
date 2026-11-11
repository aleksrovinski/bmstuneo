import 'dart:convert';
import 'dart:ui';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';
import '../models/discipline_progress.dart';
import '../models/mail_message.dart';
import '../models/user_profile.dart';
import '../providers/auth_provider.dart';
import '../providers/progress_provider.dart';
import '../providers/schedule_provider.dart';
import 'app_notifications.dart';
import 'auth_storage.dart';
import 'bmstu_api_service.dart';
import 'mail_alerts.dart';
import 'mail_credentials_storage.dart';
import 'mail_service.dart';
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

/// Refreshes the student's progress and checks the mail without the UI, and notifies
/// about changes. Progress and mail notifications are switched on separately; the
/// periodic task runs while at least one of them is on.
class BackgroundSync {
  static const taskId = 'ru.bmstu.neo.sync';
  static const enabledKey = 'notifications_progress_enabled_v1';
  static const mailEnabledKey = 'notifications_mail_enabled_v1';
  /// UID of the newest inbox letter seen by the last mail check
  static const mailLastUidKey = 'notified_mail_last_uid_v1';
  // Newest inbox letters looked at by one mail check
  static const _mailCheckDepth = 10;
  static const _notifiedKey = 'notified_progress_alerts_v1';
  static const _maxRemembered = 300;
  static const _runningSinceKey = 'background_sync_running_since_v1';
  // A sync that started longer ago than this crashed or was killed: don't wait for it
  static const _staleRun = Duration(minutes: 2);
  // Same-isolate guard; the prefs flag above covers the WorkManager isolate
  static bool _running = false;

  /// Progress notifications are on.
  static Future<bool> isEnabled() async =>
      (await SharedPreferences.getInstance()).getBool(enabledKey) ?? false;

  static Future<bool> isMailEnabled() async =>
      (await SharedPreferences.getInstance()).getBool(mailEnabledKey) ?? false;

  /// Progress or mail notifications are on, so background checks are scheduled.
  static Future<bool> isAnyEnabled() async => await isEnabled() || await isMailEnabled();

  /// Turns progress notifications on or off. Returns false if the OS denied
  /// the notification permission (nothing is scheduled then).
  static Future<bool> setEnabled(bool enabled) => _setFlag(enabledKey, enabled);

  /// Turns new-mail notifications on or off; like [setEnabled].
  static Future<bool> setMailEnabled(bool enabled) async {
    // The next check starts from the current inbox, not from an old mailbox's UID
    await (await SharedPreferences.getInstance()).remove(mailLastUidKey);
    return _setFlag(mailEnabledKey, enabled);
  }

  static Future<bool> _setFlag(String key, bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    if (!enabled) {
      await prefs.setBool(key, false);
      // Nothing left to check: stop waking the app
      if (!(prefs.getBool(enabledKey) ?? false) && !(prefs.getBool(mailEnabledKey) ?? false)) {
        await Workmanager().cancelByUniqueName(taskId);
        await PushChannel.disable();
      }
      return true;
    }
    if (!await AppNotifications.requestPermission()) return false;
    await prefs.setBool(key, true);
    await _schedule();
    return true;
  }

  /// Call at startup. While notifications are on, makes sure the periodic check is
  /// still scheduled and the push server has the current token: push tokens change,
  /// and settings restored from a backup arrive on a device where nothing is scheduled.
  static Future<void> resume() async {
    if (await isAnyEnabled()) await _schedule();
  }

  static Future<void> _schedule() async {
    await Workmanager().registerPeriodicTask(
      taskId,
      taskId,
      // Android's minimum is 15 min; iOS treats it as a hint and picks its own time
      frequency: const Duration(hours: 1),
      // Android runs a new periodic task right away; enabling already did the first sync
      initialDelay: const Duration(hours: 1),
      constraints: Constraints(networkType: NetworkType.connected),
      // An already scheduled task keeps its timing
      existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
    );
    // Silent pushes on top of the periodic checks; failing here doesn't block them
    await PushChannel.enable();
  }

  /// One sync pass. Returns the alerts that were delivered. Never asks the user
  /// anything: without a cached profile or saved credentials it just stops.
  static Future<List<ProgressAlert>> run({
    BmstuApiService? api,
    AuthStorage? authStorage,
    Future<void> Function(List<ProgressAlert>)? deliver,
    MailService? mailService,
    MailCredentialsStorage? mailStorage,
    Future<void> Function(List<MailSummary>)? deliverMail,
  }) async {
    if (_running) return const [];
    _running = true;
    try {
      return await _runExclusive(
        api: api,
        authStorage: authStorage,
        deliver: deliver,
        mailService: mailService,
        mailStorage: mailStorage,
        deliverMail: deliverMail,
      );
    } finally {
      _running = false;
    }
  }

  static Future<List<ProgressAlert>> _runExclusive({
    BmstuApiService? api,
    AuthStorage? authStorage,
    Future<void> Function(List<ProgressAlert>)? deliver,
    MailService? mailService,
    MailCredentialsStorage? mailStorage,
    Future<void> Function(List<MailSummary>)? deliverMail,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    // Background tasks run in their own isolate with their own prefs cache: re-read what
    // the app (or another task) wrote, so two syncs don't both notify about the same thing
    await prefs.reload();
    final progressOn = prefs.getBool(enabledKey) ?? false;
    final mailOn = prefs.getBool(mailEnabledKey) ?? false;
    if (!progressOn && !mailOn) return const [];

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
      // Mail first: a failing LKS request below must not cost the student a mail notice
      if (mailOn) {
        await _checkMail(prefs, mailService ?? MailService(), mailStorage ?? MailCredentialsStorage(), deliverMail);
      }
      final alerts = progressOn ? await _run(prefs, service, storage, deliver: deliver) : const <ProgressAlert>[];
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

  /// Signs in to the student mail with its saved login, looks at the newest inbox
  /// letters and notifies about unread ones that came since the last check.
  /// Never throws: a mail problem must not fail the whole background pass.
  static Future<List<MailSummary>> _checkMail(
    SharedPreferences prefs,
    MailService mail,
    MailCredentialsStorage storage,
    Future<void> Function(List<MailSummary>)? deliver,
  ) async {
    final creds = await storage.read();
    final user = creds.username;
    final pass = creds.password;
    if (user == null || user.isEmpty || pass == null || pass.isEmpty) return const [];
    try {
      await mail.login(user, pass);
      final page = await mail.fetchPage('INBOX', count: _mailCheckDepth);
      final result = newMailSince(page.items, prefs.getInt(mailLastUidKey));
      final lastUid = result.lastUid;
      if (lastUid != null) await prefs.setInt(mailLastUidKey, lastUid);
      if (result.fresh.isNotEmpty) await (deliver ?? AppNotifications.showMail)(result.fresh);
      debugPrint('[BackgroundSync] Mail: ${result.fresh.length} new letter(s)');
      return result.fresh;
    } catch (e) {
      debugPrint('[BackgroundSync] Mail check failed: $e');
      return const [];
    } finally {
      // The app may be sharing a downloaded attachment right now: leave the files alone
      await mail.logout(clearDownloads: false);
    }
  }

  /// Reloads the group's schedule (public, no session needed) and stores a fresh widget
  /// snapshot; on Android the push's follow-up WidgetRefreshWorker redraws the widget from it.
  static Future<void> _refreshScheduleWidget(SharedPreferences prefs, BmstuApiService service) async {
    final profile = _cachedProfile(prefs);
    if (profile == null) return;
    // The primary group chosen in settings, otherwise the student's own
    var groupUuid = profile.groupUuid;
    var groupTitle = profile.groupTitle;
    try {
      final raw = prefs.getString(AuthProvider.primaryGroupKey);
      if (raw != null && raw.isNotEmpty) {
        final primary = jsonDecode(raw) as Map<String, dynamic>;
        groupUuid = primary['uuid'] as String? ?? groupUuid;
        groupTitle = primary['title'] as String? ?? groupTitle;
      }
    } catch (_) {}
    if (groupUuid.isEmpty) return;
    try {
      final schedule = ScheduleProvider(apiService: service);
      await schedule.loadCustomLessons();
      await schedule.loadSchedule(groupUuid: groupUuid, groupTitle: groupTitle);
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
