import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/current_week.dart';
import '../models/schedule_lesson.dart';
import '../models/sync_status.dart';
import '../services/bmstu_api_service.dart';
import '../services/bmstu_groups_catalog.dart';
import '../services/widget_sync_service.dart';

class ScheduleProvider with ChangeNotifier {
  static const _cachePrefix = 'cached_sched_v1_';
  static const _cacheTimePrefix = 'cached_sched_time_v1_';
  final BmstuApiService apiService;

  static const _customLessonsKey = 'bmstu_custom_lessons_v1';
  CurrentWeek? _currentWeek;
  List<ScheduleLesson> _lessons = [];
  List<ScheduleLesson> _customLessons = [];
  String _currentGroupUuid = '';
  String _currentGroupTitle = '';

  int _selectedDay = 1; // 1 = ПН, 6 = СБ
  String _selectedWeekFilter = 'current'; // 'current', 'numerator', 'denominator', 'all'
  bool _isLoading = false;
  String? _errorMessage;
  SyncStatus? _syncStatus;

  ScheduleProvider({required this.apiService}) {
    // Set default day based on today's weekday (1 = Mon ... 7 = Sun)
    final now = DateTime.now();
    if (now.weekday >= 1 && now.weekday <= 6) {
      _selectedDay = now.weekday;
    } else {
      _selectedDay = 1; // Mon if Sunday
    }
    loadCustomLessons();
  }

  CurrentWeek? get currentWeek => _currentWeek;
  List<ScheduleLesson> get allLessons => [..._lessons, ..._customLessons];
  List<ScheduleLesson> get customLessons => _customLessons;
  String get currentGroupUuid => _currentGroupUuid;
  String get currentGroupTitle => _currentGroupTitle;
  int get selectedDay => _selectedDay;
  String get selectedWeekFilter => _selectedWeekFilter;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  SyncStatus? get syncStatus => _syncStatus;

  void setSelectedDay(int day) {
    if (day >= 1 && day <= 6) {
      _selectedDay = day;
      notifyListeners();
    }
  }

  void setSelectedWeekFilter(String filter) {
    _selectedWeekFilter = filter;
    notifyListeners();
  }

  Future<void> _saveScheduleToCache(String groupUuid, List<ScheduleLesson> lessons) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonList = lessons.map((l) => l.toJson()).toList();
      await prefs.setString('$_cachePrefix$groupUuid', jsonEncode(jsonList));
      await prefs.setString('$_cacheTimePrefix$groupUuid', DateTime.now().toIso8601String());
    } catch (_) {}
  }

  Future<List<ScheduleLesson>?> _loadScheduleFromCache(String groupUuid) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('$_cachePrefix$groupUuid');
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw) as List;
      return decoded.map((e) => ScheduleLesson.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return null;
    }
  }

  Future<DateTime?> _loadCacheTimestamp(String groupUuid) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('$_cacheTimePrefix$groupUuid');
      if (raw != null) return DateTime.tryParse(raw);
    } catch (_) {}
    return null;
  }

  Future<void> loadCustomLessons() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_customLessonsKey);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw) as List;
        _customLessons = decoded
            .map((e) => ScheduleLesson.fromJson(e as Map<String, dynamic>))
            .toList();
        notifyListeners();
      }
    } catch (_) {}
  }

  Future<void> addCustomLesson(ScheduleLesson lesson) async {
    _customLessons.add(lesson);
    await _saveCustomLessons();
    notifyListeners();
    WidgetSyncService.updateScheduleWidget(scheduleProvider: this);
  }

  Future<void> deleteCustomLesson(String id) async {
    _customLessons.removeWhere((l) => l.id == id);
    await _saveCustomLessons();
    notifyListeners();
    WidgetSyncService.updateScheduleWidget(scheduleProvider: this);
  }

  Future<void> _saveCustomLessons() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final listJson = _customLessons.map((l) => l.toJson()).toList();
      await prefs.setString(_customLessonsKey, jsonEncode(listJson));
    } catch (_) {}
  }

  // Load schedule for group with offline cache support
  Future<void> loadSchedule({required String groupUuid, required String groupTitle}) async {
    _currentGroupUuid = groupUuid;
    _currentGroupTitle = groupTitle;
    _errorMessage = null;

    // Fast offline preview if lessons are not loaded yet
    if (_lessons.isEmpty) {
      final cached = await _loadScheduleFromCache(groupUuid);
      if (cached != null && cached.isNotEmpty) {
        _lessons = cached;
        final cachedTime = await _loadCacheTimestamp(groupUuid);
        _syncStatus = SyncStatus(
          lastUpdated: cachedTime ?? DateTime.now(),
          isLive: false,
          itemCount: _lessons.length,
          message: 'Офлайн-копия расписания',
        );
        notifyListeners();
      }
    }

    _isLoading = true;
    notifyListeners();

    try {
      // 1. Fetch current week
      _currentWeek = await apiService.getCurrentWeek();

      // 2. Fetch fresh lessons from network
      final freshLessons = await apiService.getGroupSchedule(groupUuid);
      if (freshLessons.isNotEmpty) {
        _lessons = freshLessons;
        await _saveScheduleToCache(groupUuid, freshLessons);
      } else if (_lessons.isEmpty) {
        final cached = await _loadScheduleFromCache(groupUuid);
        if (cached != null && cached.isNotEmpty) {
          _lessons = cached;
        }
      }

      _syncStatus = SyncStatus(
        lastUpdated: DateTime.now(),
        isLive: true,
        itemCount: _lessons.length,
      );
      _isLoading = false;
      notifyListeners();
      WidgetSyncService.updateScheduleWidget(scheduleProvider: this);
    } catch (e) {
      _errorMessage = e.toString().replaceAll('Exception: ', '');

      // Offline fallback: restore from cache if not already restored
      if (_lessons.isEmpty) {
        final cached = await _loadScheduleFromCache(groupUuid);
        if (cached != null && cached.isNotEmpty) {
          _lessons = cached;
        }
      }

      final cachedTime = await _loadCacheTimestamp(groupUuid);
      _syncStatus = SyncStatus(
        lastUpdated: cachedTime ?? DateTime.now(),
        isLive: false,
        itemCount: _lessons.length,
        message: _lessons.isNotEmpty
            ? 'Офлайн-режим (показана сохраненная копия)'
            : 'Ошибка обновления: $_errorMessage',
      );
      _isLoading = false;
      notifyListeners();
      if (_lessons.isNotEmpty) {
        WidgetSyncService.updateScheduleWidget(scheduleProvider: this);
      }
    }
  }

  Future<void> refresh() async {
    if (_currentGroupUuid.isNotEmpty) {
      await loadSchedule(groupUuid: _currentGroupUuid, groupTitle: _currentGroupTitle);
    }
  }

  // Switch group
  Future<void> switchGroup(BmstuGroup group) async {
    await loadSchedule(groupUuid: group.uuid, groupTitle: group.title);
  }

  // Filter lessons for selected day
  List<ScheduleLesson> get lessonsForSelectedDay {
    return getLessonsForDay(_selectedDay, _selectedWeekFilter);
  }

  // Filter lessons for today
  List<ScheduleLesson> get lessonsForToday {
    final now = DateTime.now();
    if (now.weekday < 1 || now.weekday > 6) return [];
    return getLessonsForDay(now.weekday, 'current');
  }

  // Tomorrow's date and weekday calculations
  DateTime get tomorrowDate => DateTime.now().add(const Duration(days: 1));
  int get tomorrowWeekday => tomorrowDate.weekday; // 1 = Mon ... 7 = Sun

  bool get isTomorrowNumerator {
    final curNum = _currentWeek?.isNumerator ?? true;
    // If tomorrow is Monday, week changes parity
    return tomorrowWeekday == 1 ? !curNum : curNum;
  }

  String get tomorrowDayTitle => getWeekdayFullName(tomorrowWeekday);

  // Filter lessons for tomorrow
  List<ScheduleLesson> get lessonsForTomorrow {
    if (tomorrowWeekday < 1 || tomorrowWeekday > 6) return [];
    final dayLessons = allLessons.where((l) => l.day == tomorrowWeekday).toList();
    final isNum = isTomorrowNumerator;
    final filtered = dayLessons.where((l) => l.matchesWeek(isNumeratorWeek: isNum)).toList();
    filtered.sort((a, b) => a.time.compareTo(b.time));
    return filtered;
  }

  List<ScheduleLesson> getLessonsForDay(int day, String weekFilter) {
    final dayLessons = allLessons.where((l) => l.day == day).toList();

    List<ScheduleLesson> filtered;
    if (weekFilter == 'all') {
      filtered = dayLessons;
    } else if (weekFilter == 'numerator') {
      filtered = dayLessons.where((l) => l.isEveryWeek || l.isNumerator).toList();
    } else if (weekFilter == 'denominator') {
      filtered = dayLessons.where((l) => l.isEveryWeek || l.isDenominator).toList();
    } else {
      // 'current'
      final isNum = _currentWeek?.isNumerator ?? true;
      filtered = dayLessons.where((l) => l.matchesWeek(isNumeratorWeek: isNum)).toList();
    }

    filtered.sort((a, b) => a.time.compareTo(b.time));
    return filtered;
  }

  bool isDateNumerator(DateTime date) {
    final currentNum = _currentWeek?.isNumerator ?? true;
    final now = DateTime.now();
    final nowMonday = DateTime(now.year, now.month, now.day).subtract(Duration(days: now.weekday - 1));
    final targetMonday = DateTime(date.year, date.month, date.day).subtract(Duration(days: date.weekday - 1));
    final weekDiff = (targetMonday.difference(nowMonday).inDays / 7).round();
    return weekDiff % 2 == 0 ? currentNum : !currentNum;
  }

  String formatCountdownDuration(Duration diff) {
    if (diff.isNegative) return '0 с';
    final days = diff.inDays;
    final hours = diff.inHours % 24;
    final minutes = diff.inMinutes % 60;
    final seconds = diff.inSeconds % 60;

    final parts = <String>[];
    if (days > 0) parts.add('$days д');
    if (hours > 0 || days > 0) parts.add('$hours ч');
    if (minutes > 0 || hours > 0 || days > 0) parts.add('$minutes мин');
    parts.add('$seconds с');

    return parts.join(' ');
  }

  static const _weekdayNames = [
    '',
    'Понедельник',
    'Вторник',
    'Среда',
    'Четверг',
    'Пятница',
    'Суббота',
    'Воскресенье',
  ];

  static String getWeekdayFullName(int weekday) {
    if (weekday >= 1 && weekday <= 7) return _weekdayNames[weekday];
    return '';
  }

  // Live pair analysis with real-time countdown (days, hours, minutes, seconds)
  LivePairStatus getLivePairStatus() {
    final now = DateTime.now();
    final todayLessons = lessonsForToday;

    // 1. Check if a pair is currently active
    for (final lesson in todayLessons) {
      final startParts = lesson.startTime.split(':');
      final endParts = lesson.endTime.split(':');
      if (startParts.length == 2 && endParts.length == 2) {
        final startDt = DateTime(
          now.year,
          now.month,
          now.day,
          int.tryParse(startParts[0]) ?? 0,
          int.tryParse(startParts[1]) ?? 0,
          0,
        );
        final endDt = DateTime(
          now.year,
          now.month,
          now.day,
          int.tryParse(endParts[0]) ?? 0,
          int.tryParse(endParts[1]) ?? 0,
          0,
        );

        if (now.isAfter(startDt) && now.isBefore(endDt)) {
          final diff = endDt.difference(now);
          final formatted = formatCountdownDuration(diff);
          return LivePairStatus(
            type: LivePairType.inProgress,
            currentLesson: lesson,
            timeRemaining: diff,
            timeRemainingFormatted: formatted,
            targetDateTime: endDt,
            headline: 'Идёт пара • ещё $formatted',
            subline: '${lesson.disciplineTitle} (${lesson.displayAudiences}) • до ${lesson.endTime}',
          );
        }
      }
    }

    // 2. Check for next upcoming pair today
    for (final lesson in todayLessons) {
      final startParts = lesson.startTime.split(':');
      if (startParts.length == 2) {
        final startDt = DateTime(
          now.year,
          now.month,
          now.day,
          int.tryParse(startParts[0]) ?? 0,
          int.tryParse(startParts[1]) ?? 0,
          0,
        );
        if (now.isBefore(startDt)) {
          final diff = startDt.difference(now);
          final formatted = formatCountdownDuration(diff);
          return LivePairStatus(
            type: LivePairType.upcoming,
            nextLesson: lesson,
            timeRemaining: diff,
            timeRemainingFormatted: formatted,
            targetDateTime: startDt,
            headline: 'Следующая пара через $formatted',
            subline: '${lesson.disciplineTitle} • ${lesson.startTime} (${lesson.displayAudiences})',
          );
        }
      }
    }

    // 3. If today's pairs are over or today has no pairs, look forward for the next pair
    for (int offset = 1; offset <= 14; offset++) {
      final checkDate = now.add(Duration(days: offset));
      final checkWeekday = checkDate.weekday;
      if (checkWeekday >= 1 && checkWeekday <= 6) {
        final isCheckNumerator = isDateNumerator(checkDate);
        final dayLessons = _lessons
            .where((l) => l.day == checkWeekday && l.matchesWeek(isNumeratorWeek: isCheckNumerator))
            .toList();
        dayLessons.sort((a, b) => a.time.compareTo(b.time));

        if (dayLessons.isNotEmpty) {
          final nextLesson = dayLessons.first;
          final startParts = nextLesson.startTime.split(':');
          if (startParts.length == 2) {
            final targetDt = DateTime(
              checkDate.year,
              checkDate.month,
              checkDate.day,
              int.tryParse(startParts[0]) ?? 0,
              int.tryParse(startParts[1]) ?? 0,
              0,
            );
            final diff = targetDt.difference(now);
            final formatted = formatCountdownDuration(diff);

            final String dayLabel;
            if (offset == 1) {
              dayLabel = 'Завтра в ';
            } else {
              dayLabel = '${getWeekdayFullName(checkWeekday)} в ';
            }

            return LivePairStatus(
              type: offset == 1 && todayLessons.isNotEmpty
                  ? LivePairType.finishedForToday
                  : LivePairType.upcoming,
              nextLesson: nextLesson,
              timeRemaining: diff,
              timeRemainingFormatted: formatted,
              targetDateTime: targetDt,
              headline: 'Следующая пара через $formatted',
              subline: '${nextLesson.disciplineTitle} • $dayLabel${nextLesson.startTime} (${nextLesson.displayAudiences})',
            );
          }
        }
      }
    }

    // 4. Default fallback when no lessons exist in schedule
    if (now.weekday == 7) {
      return LivePairStatus(
        type: LivePairType.sunday,
        headline: 'Воскресенье — выходной!',
        subline: 'Заряжайте батарейки, готовьтесь к новой неделе!',
      );
    }

    return LivePairStatus(
      type: LivePairType.noPairsToday,
      headline: 'Расписание свободно',
      subline: 'Отличный день, чтобы ботать в библиотеке или отдыхать!',
    );
  }
}

enum LivePairType {
  inProgress,
  upcoming,
  noPairsToday,
  finishedForToday,
  sunday,
}

class LivePairStatus {
  final LivePairType type;
  final ScheduleLesson? currentLesson;
  final ScheduleLesson? nextLesson;
  final Duration? timeRemaining;
  final String timeRemainingFormatted;
  final DateTime? targetDateTime;
  final String headline;
  final String subline;

  LivePairStatus({
    required this.type,
    this.currentLesson,
    this.nextLesson,
    this.timeRemaining,
    this.timeRemainingFormatted = '',
    this.targetDateTime,
    required this.headline,
    required this.subline,
  });

  int get minutesRemaining => timeRemaining?.inMinutes ?? 0;
}
