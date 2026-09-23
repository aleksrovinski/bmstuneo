import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../providers/schedule_provider.dart';

class WidgetSyncService {
  static const MethodChannel _channel = MethodChannel('ru.bmstu.neo/widget');

  /// Updates the Android Home Screen Widget with the latest schedule data.
  /// Automatically switches between today's pairs and tomorrow's pairs
  /// depending on whether today's classes are finished or absent.
  static Future<void> updateScheduleWidget({
    required ScheduleProvider scheduleProvider,
  }) async {
    // Only Android supports this native AppWidget
    if (defaultTargetPlatform != TargetPlatform.android) return;

    try {
      final group = scheduleProvider.currentGroupTitle.isNotEmpty
          ? scheduleProvider.currentGroupTitle
          : 'МГТУ';

      final liveStatus = scheduleProvider.getLivePairStatus();
      final todayLessons = scheduleProvider.lessonsForToday;

      // Switch to tomorrow if pairs today are finished or there are no pairs today
      final isTomorrow = (liveStatus.type == LivePairType.finishedForToday || todayLessons.isEmpty);

      final now = DateTime.now();
      final targetDayTitle = isTomorrow
          ? 'Завтра (${scheduleProvider.tomorrowDayTitle})'
          : 'Сегодня (${_getWeekdayName(now.weekday)})';

      final currentLessons = isTomorrow
          ? scheduleProvider.lessonsForTomorrow
          : todayLessons;

      final isNumerator = isTomorrow
          ? scheduleProvider.isTomorrowNumerator
          : (scheduleProvider.currentWeek?.isNumerator ?? true);

      final weekParity = isNumerator ? 'Числитель' : 'Знаменатель';

      String shortType(String full) {
        if (full.startsWith('Лек')) return 'Лек';
        if (full.startsWith('Сем')) return 'Сем';
        if (full.startsWith('Лаб')) return 'Лаб';
        return full.length > 4 ? full.substring(0, 3) : full;
      }

      final payload = {
        'groupTitle': group,
        'dayTitle': targetDayTitle,
        'isTomorrow': isTomorrow,
        'weekParity': weekParity,
        'statusHeadline': liveStatus.headline,
        'statusSubline': liveStatus.subline,
        'lessons': currentLessons.map((l) => {
          'time': '${l.startTime} - ${l.endTime}',
          'startTime': l.startTime,
          'endTime': l.endTime,
          'disciplineTitle': l.disciplineTitle,
          'type': shortType(l.actTypeTitle),
          'actTypeTitle': l.actTypeTitle,
          'room': l.displayAudiences,
          'audiencesFormatted': l.displayAudiences,
          'teacher': l.displayTeachers,
          'teachersFormatted': l.displayTeachers,
        }).toList(),
      };

      final jsonString = jsonEncode(payload);
      await _channel.invokeMethod('updateWidget', {'scheduleJson': jsonString});
      
      // Also sync Live Activity Notification
      final notifEnabled = await isLiveNotificationEnabled();
      await _channel.invokeMethod('updateLiveNotification', {
        'scheduleJson': jsonString,
        'enabled': notifEnabled,
      });

      debugPrint('[WidgetSyncService] Android schedule widget and Live Activity updated successfully (${currentLessons.length} lessons, isTomorrow: $isTomorrow)');
    } catch (e) {
      debugPrint('[WidgetSyncService] Error updating widget: $e');
    }
  }

  /// Checks if the Live Activity notification is enabled by user
  static Future<bool> isLiveNotificationEnabled() async {
    if (defaultTargetPlatform != TargetPlatform.android) return false;
    try {
      final enabled = await _channel.invokeMethod<bool>('isLiveNotificationEnabled');
      return enabled ?? true;
    } catch (e) {
      return true;
    }
  }

  /// Checks whether Android has granted notification permission
  static Future<bool> hasNotificationPermission() async {
    if (defaultTargetPlatform != TargetPlatform.android) return true;
    try {
      final granted = await _channel.invokeMethod<bool>('hasNotificationPermission');
      return granted ?? true;
    } catch (e) {
      return true;
    }
  }

  /// Requests the system notification permission on Android 13+
  static Future<bool> requestNotificationPermission() async {
    if (defaultTargetPlatform != TargetPlatform.android) return true;
    try {
      final granted = await _channel.invokeMethod<bool>('requestNotificationPermission');
      return granted ?? true;
    } catch (e) {
      return true;
    }
  }

  /// Sets whether the Live Activity notification is enabled
  static Future<void> setLiveNotificationEnabled(bool enabled, {ScheduleProvider? scheduleProvider}) async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    try {
      if (enabled) {
        // Request runtime permission if not yet granted
        final hasPermission = await hasNotificationPermission();
        if (!hasPermission) {
          await requestNotificationPermission();
        }
      }
      await _channel.invokeMethod('setLiveNotificationEnabled', {'enabled': enabled});
      if (enabled && scheduleProvider != null) {
        await updateScheduleWidget(scheduleProvider: scheduleProvider);
      } else if (!enabled) {
        await _channel.invokeMethod('cancelLiveNotification');
      }
    } catch (e) {
      debugPrint('[WidgetSyncService] Error setting live notification state: $e');
    }
  }

  /// Checks if the launcher supports pinning widgets directly to the home screen
  static Future<bool> isPinningSupported() async {
    if (defaultTargetPlatform != TargetPlatform.android) return false;
    try {
      final supported = await _channel.invokeMethod<bool>('isPinningSupported');
      return supported ?? false;
    } catch (e) {
      return false;
    }
  }

  /// Requests the Android launcher to pin the schedule widget to the home screen
  static Future<bool> pinWidget() async {
    if (defaultTargetPlatform != TargetPlatform.android) return false;
    try {
      final success = await _channel.invokeMethod<bool>('pinWidget');
      return success ?? false;
    } catch (e) {
      debugPrint('[WidgetSyncService] Error requesting pin widget: $e');
      return false;
    }
  }

  static String _getWeekdayName(int weekday) {
    switch (weekday) {
      case 1:
        return 'Пн';
      case 2:
        return 'Вт';
      case 3:
        return 'Ср';
      case 4:
        return 'Чт';
      case 5:
        return 'Пт';
      case 6:
        return 'Сб';
      case 7:
        return 'Вс';
      default:
        return '';
    }
  }
}
