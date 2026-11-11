import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../models/mail_message.dart';
import 'mail_alerts.dart';
import 'notification_target.dart';
import 'progress_alerts.dart';

/// System notifications about progress (scores, new work, deadlines) and new mail.
class AppNotifications {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;

  /// The notification the student tapped, until the app has opened its screen
  /// (MainNavigationScreen consumes it and sets it back to null).
  static final tapped = ValueNotifier<NotificationTarget?>(null);

  // More than this at once is collapsed into a summary, not a wall of banners
  static const _maxSeparate = 4;

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'progress',
      'Успеваемость',
      channelDescription: 'Баллы за модули, новые задания и сроки сдачи',
    ),
    iOS: DarwinNotificationDetails(threadIdentifier: 'progress'),
  );

  static const _mailDetails = NotificationDetails(
    android: AndroidNotificationDetails('mail', 'Почта', channelDescription: 'Новые письма в ящике @student.bmstu.ru'),
    iOS: DarwinNotificationDetails(threadIdentifier: 'mail'),
  );

  static Future<void> _init() async {
    if (_ready) return;
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        // Permission is asked when the student turns notifications on, not at launch
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
      onDidReceiveNotificationResponse: (response) => tapped.value = NotificationTarget.decode(response.payload),
    );
    _ready = true;
  }

  /// Call once at app start: listens for taps and picks up the notification that
  /// launched the app from scratch.
  static Future<void> listenForTaps() async {
    try {
      await _init();
      final launch = await _plugin.getNotificationAppLaunchDetails();
      if (launch?.didNotificationLaunchApp ?? false) {
        tapped.value ??= NotificationTarget.decode(launch!.notificationResponse?.payload);
      }
    } catch (e) {
      debugPrint('[AppNotifications] Failed to set up notification taps: $e');
    }
  }

  /// Asks the OS for permission to show notifications; true if granted.
  static Future<bool> requestPermission() async {
    try {
      await _init();
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        final ios = _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
        return await ios?.requestPermissions(alert: true, sound: true) ?? false;
      }
      final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      return await android?.requestNotificationsPermission() ?? true;
    } catch (e) {
      debugPrint('[AppNotifications] Permission request failed: $e');
      return false;
    }
  }

  static Future<void> show(List<ProgressAlert> alerts) async {
    if (alerts.isEmpty) return;
    try {
      await _init();
      final separate = alerts.length <= _maxSeparate ? alerts : alerts.take(_maxSeparate - 1).toList();
      for (final alert in separate) {
        await _plugin.show(
          id: alert.key.hashCode & 0x7fffffff,
          title: alert.title,
          body: alert.body,
          notificationDetails: _details,
          payload: NotificationTarget.progress(discipline: alert.discipline).encode(),
        );
      }
      final rest = alerts.length - separate.length;
      if (rest > 0) {
        await _plugin.show(
          id: 'progress-summary'.hashCode & 0x7fffffff,
          title: 'Ещё $rest обновлений успеваемости',
          body: alerts.skip(separate.length).map((a) => a.title).join(' • '),
          notificationDetails: _details,
          payload: const NotificationTarget.progress().encode(),
        );
      }
    } catch (e) {
      debugPrint('[AppNotifications] Failed to show notifications: $e');
    }
  }

  /// One banner per letter (sender, subject); a burst of letters becomes one summary.
  static Future<void> showMail(List<MailSummary> letters) async {
    if (letters.isEmpty) return;
    try {
      await _init();
      if (letters.length <= _maxSeparate) {
        for (final m in letters) {
          await _plugin.show(
            id: 'mail|${m.uid}'.hashCode & 0x7fffffff,
            title: m.from.isEmpty ? 'Новое письмо' : m.from,
            body: m.subject.isEmpty ? '(без темы)' : m.subject,
            notificationDetails: _mailDetails,
            payload: NotificationTarget.mail(uid: m.uid, from: m.from, subject: m.subject).encode(),
          );
        }
        return;
      }
      final senders = letters.map((m) => m.from).where((f) => f.isNotEmpty).toSet();
      await _plugin.show(
        id: 'mail-summary'.hashCode & 0x7fffffff,
        title: newLettersCount(letters.length),
        body: senders.isEmpty ? 'Почта @student.bmstu.ru' : 'От: ${senders.join(', ')}',
        notificationDetails: _mailDetails,
        payload: const NotificationTarget.mail().encode(),
      );
    } catch (e) {
      debugPrint('[AppNotifications] Failed to show mail notifications: $e');
    }
  }
}
