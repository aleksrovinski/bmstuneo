import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bmstu_neo/models/current_week.dart';
import 'package:bmstu_neo/models/schedule_lesson.dart';
import 'package:bmstu_neo/providers/auth_provider.dart';
import 'package:bmstu_neo/providers/fv_provider.dart';
import 'package:bmstu_neo/providers/homework_provider.dart';
import 'package:bmstu_neo/providers/progress_provider.dart';
import 'package:bmstu_neo/providers/schedule_provider.dart';
import 'package:bmstu_neo/providers/theme_provider.dart';
import 'package:bmstu_neo/screens/home_screen.dart';
import 'package:bmstu_neo/screens/schedule_screen.dart';
import 'package:bmstu_neo/screens/settings_screen.dart';
import 'package:bmstu_neo/services/auth_storage.dart';
import 'package:bmstu_neo/services/bmstu_api_service.dart';
import 'package:bmstu_neo/services/lks_parsers.dart';
import 'package:bmstu_neo/widgets/pair_card.dart';

class _FakeHttpAdapter implements HttpClientAdapter {
  final FutureOr<ResponseBody> Function(RequestOptions options) handler;
  _FakeHttpAdapter(this.handler);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async =>
      handler(options);

  @override
  void close({bool force = false}) {}
}

class _FakeScheduleApi extends BmstuApiService {
  final Map<String, List<ScheduleLesson>> schedulesByGroup;
  final Set<String> failingGroups;

  _FakeScheduleApi({
    this.schedulesByGroup = const {},
    this.failingGroups = const {},
  });

  @override
  Future<CurrentWeek?> getCurrentWeek({bool fallbackToDefault = true}) async => CurrentWeek(
        weekNumber: 12,
        weekName: 'знаменатель',
        weekShortName: 'зн',
        term: 1,
        semesterStarts: '2026-09-01',
        semesterEnds: '2026-12-31',
      );

  @override
  Future<List<ScheduleLesson>> getGroupSchedule(String groupUuid) async {
    if (failingGroups.contains(groupUuid)) {
      throw Exception('offline');
    }
    return schedulesByGroup[groupUuid] ?? const [];
  }
}

ScheduleLesson _makeLesson({
  required int day,
  required int time,
  String startTime = '08:30',
  String endTime = '10:05',
  String week = 'all',
  required String title,
  String actType = 'seminar',
  List<int> subgroups = const [],
  int subgroupCount = 0,
  String teacherLast = 'Иванов',
}) =>
    ScheduleLesson(
      day: day,
      time: time,
      startTime: startTime,
      endTime: endTime,
      week: week,
      disciplineTitle: title,
      actType: actType,
      audiences: [ScheduleAudience(name: '3.308', building: 'КФ-УАК3')],
      teachers: [ScheduleTeacher(firstName: 'Иван', lastName: teacherLast, middleName: 'Иванович')],
      subgroups: subgroups,
      subgroupCount: subgroupCount,
    );

Map<String, dynamic> _rawLksLesson({
  int day = 4,
  int time = 3,
  String week = 'ch',
  String title = 'Инженерная и компьютерная графика',
  String actType = 'seminar',
  required String streamName,
  required List<Map<String, dynamic>> streamGroups,
}) =>
    {
      'day': day,
      'time': time,
      'startTime': '12:10',
      'endTime': '13:45',
      'week': week,
      'discipline': {'fullName': title, 'actType': actType},
      'audiences': [
        {'name': '1.250', 'building': 'КФ-УАК1'},
      ],
      'teachers': [
        {'firstName': 'Андрей', 'lastName': 'Вяткин', 'middleName': 'Алексеевич'},
      ],
      'stream': {
        'name': streamName,
        'groups': streamGroups,
      },
    };

Future<void> _loadAppFont() async {
  final loader = FontLoader(appFontFamily);
  for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold', 'Black']) {
    loader.addFont(rootBundle.load('assets/fonts/Onest-$w.ttf'));
  }
  await loader.load();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const targetGroupUuid = '3109b2f6-2cfc-11f1-9e62-005056aae53e';
  const otherGroupUuid = '821f8752-2cfb-11f1-b208-005056aae53e';

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  group('LksParsers.schedule subgroup parsing', () {
    test('parses 1/2, 2/2, whole-group 0/0, and case-insensitive groupUuid', () {
      final raw = [
        _rawLksLesson(
          streamName: 'ИУК3-11/5(2/2)',
          streamGroups: [
            {'sub1': 2, 'sub2': 2, 'groupUuid': targetGroupUuid.toUpperCase()},
          ],
        ),
        _rawLksLesson(
          streamName: 'ИУК3-11/5(1/2)',
          streamGroups: [
            {'sub1': 1, 'sub2': 2, 'groupUuid': targetGroupUuid},
          ],
        ),
        _rawLksLesson(
          week: 'zn',
          actType: 'lab',
          streamName: 'ИУК3-11/5',
          streamGroups: [
            {'sub1': 0, 'sub2': 0, 'groupUuid': targetGroupUuid},
          ],
        ),
      ];

      final lessons = LksParsers.schedule(raw, groupUuid: targetGroupUuid);
      expect(lessons, hasLength(3));

      expect(lessons[0].subgroups, [2]);
      expect(lessons[0].subgroupCount, 2);
      expect(lessons[0].hasSubgroup, isTrue);

      expect(lessons[1].subgroups, [1]);
      expect(lessons[1].subgroupCount, 2);

      expect(lessons[2].subgroups, isEmpty);
      expect(lessons[2].subgroupCount, 0);
      expect(lessons[2].hasSubgroup, isFalse);
    });

    test('filters stream.groups strictly by target groupUuid in multi-group streams', () {
      final raw = [
        _rawLksLesson(
          streamName: 'ИУК1-11/6(1/2); ИУК3-11/5',
          streamGroups: [
            {'sub1': 1, 'sub2': 2, 'groupUuid': otherGroupUuid},
            {'sub1': 0, 'sub2': 0, 'groupUuid': targetGroupUuid},
          ],
        ),
      ];

      final lessons = LksParsers.schedule(raw, groupUuid: targetGroupUuid);
      expect(lessons.single.subgroups, isEmpty);
      expect(lessons.single.subgroupCount, 0);
      expect(lessons.single.isStream, isTrue);
    });

    test('handles multiple entries for the same group (1/3+2/3 and whole-group override)', () {
      final raw = [
        _rawLksLesson(
          streamName: 'ИУК3-11/5(1/3, 2/3)',
          streamGroups: [
            {'sub1': 2, 'sub2': 3, 'groupUuid': targetGroupUuid},
            {'sub1': 1, 'sub2': 3, 'groupUuid': targetGroupUuid},
          ],
        ),
        _rawLksLesson(
          streamName: 'ИУК3-11/5',
          streamGroups: [
            {'sub1': 1, 'sub2': 2, 'groupUuid': targetGroupUuid},
            {'sub1': 0, 'sub2': 2, 'groupUuid': targetGroupUuid},
          ],
        ),
      ];

      final lessons = LksParsers.schedule(raw, groupUuid: targetGroupUuid);
      expect(lessons[0].subgroups, [1, 2]);
      expect(lessons[0].subgroupCount, 3);
      expect(lessons[0].subgroupLabel, '1, 2 подгр.');

      // sub1 == 0 means the lesson applies to the whole group
      expect(lessons[1].subgroups, isEmpty);
      expect(lessons[1].subgroupCount, 2);
    });

    test('teacher schedule without groupUuid leaves subgroups empty and keeps streamName', () {
      final raw = [
        _rawLksLesson(
          streamName: 'ИУК3-11/5(1/2)',
          streamGroups: [
            {'sub1': 1, 'sub2': 2, 'groupUuid': targetGroupUuid},
          ],
        ),
      ];

      final lessons = LksParsers.schedule(raw);
      expect(lessons.single.subgroups, isEmpty);
      expect(lessons.single.subgroupCount, 0);
      expect(lessons.single.streamName, 'ИУК3-11/5(1/2)');
    });

    test('BmstuApiService.getGroupSchedule passes groupUuid to LksParsers.schedule', () async {
      final api = BmstuApiService();
      api.httpClientAdapter = _FakeHttpAdapter((options) {
        return ResponseBody.fromString(
          jsonEncode({
            'data': {
              'uuid': targetGroupUuid,
              'schedule': [
                _rawLksLesson(
                  streamName: 'ИУК3-11/5(2/2)',
                  streamGroups: [
                    {'sub1': 2, 'sub2': 2, 'groupUuid': targetGroupUuid},
                  ],
                ),
              ],
            },
          }),
          200,
          headers: {
            Headers.contentTypeHeader: ['application/json'],
          },
        );
      });

      final lessons = await api.getGroupSchedule(targetGroupUuid);
      expect(lessons, hasLength(1));
      expect(lessons.single.subgroups, [2]);
      expect(lessons.single.subgroupCount, 2);
    });
  });

  group('ScheduleLesson subgroup methods & JSON', () {
    test('toJson / fromJson round-trip preserves subgroups and subgroupCount', () {
      final lesson = _makeLesson(
        day: 5,
        time: 2,
        title: 'Химия',
        actType: 'lab',
        subgroups: const [1, 2],
        subgroupCount: 3,
      );

      final restored = ScheduleLesson.fromJson(lesson.toJson());
      expect(restored.subgroups, [1, 2]);
      expect(restored.subgroupCount, 3);
      expect(restored.hasSubgroup, isTrue);
      expect(restored.subgroupLabel, '1, 2 подгр.');
    });

    test('legacy JSON without subgroup fields deserializes cleanly', () {
      final legacy = ScheduleLesson.fromJson({
        'day': 1,
        'time': 1,
        'startTime': '08:30',
        'endTime': '10:05',
        'week': 'all',
        'disciplineTitle': 'Математика',
        'actType': 'lecture',
        'audiences': const [],
        'teachers': const [],
      });

      expect(legacy.subgroups, isEmpty);
      expect(legacy.subgroupCount, 0);
      expect(legacy.hasSubgroup, isFalse);
      expect(legacy.subgroupLabel, isNull);
    });

    test('matchesSubgroup and subgroupLabel behave as expected', () {
      final whole = _makeLesson(day: 1, time: 1, title: 'Лекция');
      final sub1 = _makeLesson(day: 4, time: 3, title: 'Графика', subgroups: const [1], subgroupCount: 2);
      final sub12 = _makeLesson(day: 4, time: 3, title: 'Практика', subgroups: const [1, 2], subgroupCount: 3);

      expect(whole.subgroupLabel, isNull);
      expect(whole.matchesSubgroup(null), isTrue);
      expect(whole.matchesSubgroup(0), isTrue);
      expect(whole.matchesSubgroup(1), isTrue);
      expect(whole.matchesSubgroup(2), isTrue);

      expect(sub1.subgroupLabel, '1 подгр.');
      expect(sub1.matchesSubgroup(null), isTrue);
      expect(sub1.matchesSubgroup(0), isTrue);
      expect(sub1.matchesSubgroup(1), isTrue);
      expect(sub1.matchesSubgroup(2), isFalse);

      expect(sub12.subgroupLabel, '1, 2 подгр.');
      expect(sub12.matchesSubgroup(1), isTrue);
      expect(sub12.matchesSubgroup(2), isTrue);
      expect(sub12.matchesSubgroup(3), isFalse);
    });
  });

  group('ScheduleProvider subgroup filtering, sorting & persistence', () {
    test('detects subgroups, filters allLessons/getLessonsForDay/lessonsForTomorrow, and sorts by subgroup', () async {
      final sched = ScheduleProvider(apiService: BmstuApiService());
      final tomorrowDay = sched.tomorrowWeekday <= 6 ? sched.tomorrowWeekday : 1;

      sched.lessonsForTest = [
        _makeLesson(
          day: 4,
          time: 3,
          startTime: '12:10',
          endTime: '13:45',
          title: 'Графика (2)',
          subgroups: const [2],
          subgroupCount: 2,
          teacherLast: 'Сахаров',
        ),
        _makeLesson(
          day: 4,
          time: 3,
          startTime: '12:10',
          endTime: '13:45',
          title: 'Графика (1)',
          subgroups: const [1],
          subgroupCount: 2,
          teacherLast: 'Вяткин',
        ),
        _makeLesson(
          day: 4,
          time: 2,
          startTime: '10:20',
          endTime: '11:55',
          title: 'История России',
        ),
        if (sched.tomorrowWeekday <= 6) ...[
          _makeLesson(
            day: tomorrowDay,
            time: 2,
            startTime: '10:20',
            endTime: '11:55',
            title: 'Завтра 2 подгр.',
            subgroups: const [2],
            subgroupCount: 2,
          ),
          _makeLesson(
            day: tomorrowDay,
            time: 2,
            startTime: '10:20',
            endTime: '11:55',
            title: 'Завтра 1 подгр.',
            subgroups: const [1],
            subgroupCount: 2,
          ),
        ],
      ];

      expect(sched.hasSubgroups, isTrue);
      expect(sched.subgroupCount, 2);
      expect(sched.effectiveSubgroup, isNull);

      // In 'Все' mode, 1 подгр. sorts before 2 подгр. even though raw list had 2 first
      final allDay4 = sched.getLessonsForDay(4, 'all');
      expect(allDay4.map((l) => l.disciplineTitle), ['История России', 'Графика (1)', 'Графика (2)']);

      await sched.setSelectedSubgroup(1);
      expect(sched.effectiveSubgroup, 1);
      expect(
        sched.getLessonsForDay(4, 'all').map((l) => l.disciplineTitle),
        ['История России', 'Графика (1)'],
      );
      if (sched.tomorrowWeekday <= 6) {
        expect(sched.lessonsForTomorrow.map((l) => l.disciplineTitle), ['Завтра 1 подгр.']);
      }

      await sched.setSelectedSubgroup(2);
      expect(
        sched.getLessonsForDay(4, 'all').map((l) => l.disciplineTitle),
        ['История России', 'Графика (2)'],
      );

      // Out-of-range subgroup falls back cleanly to effectiveSubgroup == null
      await sched.setSelectedSubgroup(5);
      expect(sched.selectedSubgroup, 5);
      expect(sched.effectiveSubgroup, isNull);
      expect(sched.getLessonsForDay(4, 'all'), hasLength(3));
    });

    test('persists subgroup per groupUuid for primary, isolates secondary, and clears stale lessons on switch', () async {
      final api = _FakeScheduleApi(
        schedulesByGroup: {
          'group-a': [
            _makeLesson(day: 1, time: 1, title: 'Группа А (1)', subgroups: const [1], subgroupCount: 2),
            _makeLesson(day: 1, time: 1, title: 'Группа А (2)', subgroups: const [2], subgroupCount: 2),
          ],
          'group-b': [
            _makeLesson(day: 1, time: 1, title: 'Группа Б (общ.)'),
          ],
        },
        failingGroups: {'group-offline-empty'},
      );

      final primary = ScheduleProvider(apiService: api, isPrimary: true);
      await primary.loadSchedule(groupUuid: 'group-a', groupTitle: 'A');
      await primary.setSelectedSubgroup(2);

      final prefs = await SharedPreferences.getInstance();
      expect(jsonDecode(prefs.getString(ScheduleProvider.subgroupPrefsKey)!), {'group-a': 2});

      // Secondary browse provider does not overwrite primary prefs
      final secondary = ScheduleProvider(apiService: api, isPrimary: false);
      await secondary.loadSchedule(groupUuid: 'group-a', groupTitle: 'A');
      expect(secondary.effectiveSubgroup, isNull);
      await secondary.setSelectedSubgroup(1);
      expect(jsonDecode(prefs.getString(ScheduleProvider.subgroupPrefsKey)!), {'group-a': 2});

      // Refresh on same groupUuid preserves in-memory subgroup
      await primary.refresh();
      expect(primary.effectiveSubgroup, 2);

      // Switching to group-b restores group-b (null) and replaces group-a lessons
      await primary.loadSchedule(groupUuid: 'group-b', groupTitle: 'B');
      expect(primary.hasSubgroups, isFalse);
      expect(primary.effectiveSubgroup, isNull);
      expect(primary.allLessons.map((l) => l.disciplineTitle), ['Группа Б (общ.)']);

      // Switching to an uncached offline group clears stale group-b lessons
      await primary.loadSchedule(groupUuid: 'group-offline-empty', groupTitle: 'Offline');
      expect(primary.allLessons, isEmpty);

      // Switching back to group-a restores saved subgroup 2 after restart
      final restarted = ScheduleProvider(apiService: api, isPrimary: true);
      await restarted.loadSchedule(groupUuid: 'group-a', groupTitle: 'A');
      expect(restarted.effectiveSubgroup, 2);
      expect(restarted.allLessons.map((l) => l.disciplineTitle), ['Группа А (2)']);

      // Setting back to null removes group entry from prefs
      await restarted.setSelectedSubgroup(null);
      expect(prefs.getString(ScheduleProvider.subgroupPrefsKey), isNull);
    });

    test('AuthProvider.logout clears subgroup preferences', () async {
      await ScheduleProvider.saveSubgroupForGroup('group-a', 2);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(ScheduleProvider.subgroupPrefsKey), isNotNull);

      final auth = AuthProvider(apiService: BmstuApiService(), authStorage: AuthStorage());
      await auth.logout();

      expect(prefs.getString(ScheduleProvider.subgroupPrefsKey), isNull);
    });
  });

  group('Subgroup UI widget tests', () {
    testWidgets('PairCard shows subgroup label only for subgroup lessons', (tester) async {
      final subLesson = _makeLesson(
        day: 4,
        time: 3,
        title: 'Инженерная графика',
        subgroups: const [1],
        subgroupCount: 2,
      );
      final wholeLesson = _makeLesson(day: 4, time: 2, title: 'История России');

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                PairCard(lesson: subLesson),
                PairCard(lesson: wholeLesson),
              ],
            ),
          ),
        ),
      );

      expect(find.textContaining('1 подгр.'), findsOneWidget);
      expect(find.textContaining('История России'), findsOneWidget);
    });

    testWidgets('ScheduleScreen hides bar when no subgroups and filters cards when subgroups exist', (tester) async {
      final api = BmstuApiService();
      final auth = AuthProvider(apiService: api, authStorage: AuthStorage());
      final sched = ScheduleProvider(apiService: api);
      final day = sched.selectedDay;

      sched.lessonsForTest = [
        _makeLesson(day: day, time: 1, title: 'Общая лекция'),
      ];

      Widget wrap(Widget child) => MultiProvider(
            providers: [
              ChangeNotifierProvider.value(value: auth),
              ChangeNotifierProvider.value(value: sched),
              ChangeNotifierProvider(create: (_) => ProgressProvider(apiService: api)),
              ChangeNotifierProvider(create: (_) => FvProvider(apiService: api)),
              ChangeNotifierProvider(create: (_) => HomeworkProvider()),
            ],
            child: MaterialApp(home: child),
          );

      await tester.pumpWidget(wrap(const ScheduleScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Подгруппа 1'), findsNothing);
      expect(find.text('Общая лекция'), findsOneWidget);

      // Now simulate a group with 2 subgroups
      sched.lessonsForTest = [
        _makeLesson(day: day, time: 1, title: 'Общая лекция'),
        _makeLesson(
          day: day,
          time: 2,
          startTime: '10:20',
          endTime: '11:55',
          title: 'Химия 1',
          subgroups: const [1],
          subgroupCount: 2,
        ),
        _makeLesson(
          day: day,
          time: 2,
          startTime: '10:20',
          endTime: '11:55',
          title: 'Химия 2',
          subgroups: const [2],
          subgroupCount: 2,
        ),
      ];

      await tester.pumpWidget(wrap(const ScheduleScreen()));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(ChoiceChip, 'Все'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, 'Подгруппа 1'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, 'Подгруппа 2'), findsOneWidget);
      expect(find.text('Химия 1'), findsOneWidget);
      expect(find.text('Химия 2'), findsOneWidget);

      await tester.tap(find.widgetWithText(ChoiceChip, 'Подгруппа 1'));
      await tester.pumpAndSettle();
      expect(find.text('Общая лекция'), findsOneWidget);
      expect(find.text('Химия 1'), findsOneWidget);
      expect(find.text('Химия 2'), findsNothing);

      await tester.tap(find.widgetWithText(ChoiceChip, 'Подгруппа 2'));
      await tester.pumpAndSettle();
      expect(find.text('Общая лекция'), findsOneWidget);
      expect(find.text('Химия 1'), findsNothing);
      expect(find.text('Химия 2'), findsOneWidget);
    });

    testWidgets('SettingsScreen displays subgroup selector when hasSubgroups and updates ScheduleProvider',
        (tester) async {
      final api = BmstuApiService();
      final auth = AuthProvider(apiService: api, authStorage: AuthStorage());
      final sched = ScheduleProvider(apiService: api);
      sched.lessonsForTest = [
        _makeLesson(day: 1, time: 1, title: 'Лаба 1', subgroups: const [1], subgroupCount: 2),
        _makeLesson(day: 1, time: 1, title: 'Лаба 2', subgroups: const [2], subgroupCount: 2),
      ];

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: auth),
            ChangeNotifierProvider.value(value: sched),
            ChangeNotifierProvider(create: (_) => ProgressProvider(apiService: api)),
            ChangeNotifierProvider(create: (_) => ThemeProvider()),
          ],
          child: const MaterialApp(home: SettingsScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Подгруппа'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, 'Подгруппа 2'), findsOneWidget);

      await tester.tap(find.widgetWithText(ChoiceChip, 'Подгруппа 2'));
      await tester.pumpAndSettle();

      expect(sched.effectiveSubgroup, 2);
    });

    testWidgets('HomeScreen AppBar shows selected subgroup indicator when active', (tester) async {
      final api = BmstuApiService();
      final auth = AuthProvider(apiService: api, authStorage: AuthStorage());
      await auth.enterGuestMode(groupTitle: 'ИУК3-11/5', groupUuid: targetGroupUuid);
      final sched = ScheduleProvider(apiService: api);
      sched.lessonsForTest = [
        _makeLesson(day: 1, time: 1, title: 'Лаба', subgroups: const [2], subgroupCount: 2),
      ];

      Widget buildHome() => MultiProvider(
            providers: [
              ChangeNotifierProvider.value(value: auth),
              ChangeNotifierProvider.value(value: sched),
              ChangeNotifierProvider(create: (_) => ProgressProvider(apiService: api)),
              ChangeNotifierProvider(
                create: (_) => FvProvider(apiService: api)..loadGuestSample(),
              ),
              ChangeNotifierProvider(create: (_) => HomeworkProvider()),
            ],
            child: MaterialApp(
              home: HomeScreen(
                onOpenSchedule: () {},
                onOpenGrades: () {},
                onOpenFv: () {},
              ),
            ),
          );

      await tester.pumpWidget(buildHome());
      await tester.pumpAndSettle();
      expect(find.text('Гостевой режим'), findsOneWidget);

      await sched.setSelectedSubgroup(2);
      await tester.pumpAndSettle();
      expect(find.text('Гостевой режим · 2 подгр.'), findsOneWidget);
    });

    testWidgets('ScheduleScreen renders with 3 subgroups at 2.0x text scale on 360px screen without overflow',
        (tester) async {
      await _loadAppFont();
      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final api = BmstuApiService();
      final auth = AuthProvider(apiService: api, authStorage: AuthStorage());
      final sched = ScheduleProvider(apiService: api);
      final day = sched.selectedDay;
      sched.lessonsForTest = [
        _makeLesson(day: day, time: 1, title: 'Предмет А', subgroups: const [1], subgroupCount: 3),
        _makeLesson(day: day, time: 1, title: 'Предмет Б', subgroups: const [2], subgroupCount: 3),
        _makeLesson(day: day, time: 1, title: 'Предмет В', subgroups: const [3], subgroupCount: 3),
      ];

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: auth),
            ChangeNotifierProvider.value(value: sched),
            ChangeNotifierProvider(create: (_) => ProgressProvider(apiService: api)),
            ChangeNotifierProvider(create: (_) => FvProvider(apiService: api)),
            ChangeNotifierProvider(create: (_) => HomeworkProvider()),
          ],
          child: MaterialApp(
            theme: ThemeData(useMaterial3: true, fontFamily: appFontFamily),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(2.0)),
              child: child!,
            ),
            home: const ScheduleScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.widgetWithText(ChoiceChip, 'Подгруппа 1'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, 'Подгруппа 3'), findsOneWidget);
    });

    testWidgets('SettingsScreen renders 3 subgroups at 2.0x text scale on 360px screen without overflow',
        (tester) async {
      await _loadAppFont();
      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final api = BmstuApiService();
      final auth = AuthProvider(apiService: api, authStorage: AuthStorage());
      final sched = ScheduleProvider(apiService: api);
      sched.lessonsForTest = [
        _makeLesson(day: 1, time: 1, title: 'Предмет А', subgroups: const [1], subgroupCount: 3),
        _makeLesson(day: 1, time: 1, title: 'Предмет Б', subgroups: const [2], subgroupCount: 3),
        _makeLesson(day: 1, time: 1, title: 'Предмет В', subgroups: const [3], subgroupCount: 3),
      ];

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: auth),
            ChangeNotifierProvider.value(value: sched),
            ChangeNotifierProvider(create: (_) => ProgressProvider(apiService: api)),
            ChangeNotifierProvider(create: (_) => ThemeProvider()),
          ],
          child: MaterialApp(
            theme: ThemeData(useMaterial3: true, fontFamily: appFontFamily),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(2.0)),
              child: child!,
            ),
            home: const SettingsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Подгруппа'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, 'Подгруппа 3'), findsOneWidget);
    });
  });
}
