import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:bmstu_neo/models/current_week.dart';
import 'package:bmstu_neo/models/discipline_progress.dart';
import 'package:bmstu_neo/models/schedule_lesson.dart';
import 'package:bmstu_neo/models/user_profile.dart';
import 'package:bmstu_neo/providers/auth_provider.dart';
import 'package:bmstu_neo/providers/progress_provider.dart';
import 'package:bmstu_neo/services/auth_storage.dart';
import 'package:bmstu_neo/services/background_sync.dart';
import 'package:bmstu_neo/services/bmstu_api_service.dart';
import 'package:bmstu_neo/services/progress_alerts.dart';
import 'package:bmstu_neo/services/widget_sync_service.dart';

Map<String, dynamic> _thresholds() => {'point_3': '19', 'point_4': '23', 'point_5': '28', 'point_all': '33'};

ControlEvent _ev(String type, int i, {String? stage, int week = 4, String? value, Map<String, dynamic>? points}) =>
    ControlEvent(
      type: type,
      title: type == 'М' ? 'Модуль $i' : '$type-$i',
      week: week,
      stage: stage,
      value: value,
      points: points,
      disciplineTitle: 'Инженерная графика',
      controlIndex: i,
    );

DisciplineProgress _disc(List<ControlEvent> controls) =>
    DisciplineProgress(title: 'Инженерная графика', points: const {}, controls: controls);

List<String> _titles(List<ProgressAlert> alerts) => alerts.map((a) => a.title).toList();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('computeProgressAlerts', () {
    test('Module score: the grade it is on, or a shortfall', () {
      final alerts = computeProgressAlerts(
        previous: [_disc([_ev('М', 1, points: _thresholds()), _ev('М', 2, points: _thresholds())])],
        current: [
          _disc([
            _ev('М', 1, value: '27', stage: '13', points: _thresholds()),
            _ev('М', 2, value: '9', stage: '13', points: _thresholds()),
          ])
        ],
        currentWeek: 8,
        alreadyNotified: {},
      );
      expect(_titles(alerts), ['Баллы за модуль 1', 'Баллы за модуль 2']);
      expect(alerts[0].body, 'Инженерная графика: 27 из 33 — на «4»');
      expect(alerts[1].body, 'Инженерная графика: 9 из 33 — недобор, порог 19');
    });

    test('New homework and a newly scheduled control', () {
      final alerts = computeProgressAlerts(
        previous: [_disc([_ev('ДЗ', 2, week: 9), _ev('РК', 2, week: 10)])],
        current: [_disc([_ev('ДЗ', 2, stage: '1', week: 9), _ev('РК', 2, stage: '1', week: 10)])],
        currentWeek: 8,
        alreadyNotified: {},
      );
      expect(_titles(alerts), ['Выдано ДЗ-2', 'Назначен РК-2']);
      expect(alerts.first.body, 'Инженерная графика • срок — 9 неделя');
    });

    test('Due this week, unless the student marked it as done', () {
      final hw = _ev('ДЗ', 1, stage: '1', week: 8);
      List<ProgressAlert> alertsFor(DisciplineProgress d) => computeProgressAlerts(
            previous: [_disc([hw])],
            current: [d],
            currentWeek: 8,
            alreadyNotified: {},
          );

      expect(_titles(alertsFor(_disc([hw]))), ['Срок на этой неделе: ДЗ-1']);
      final marked = _disc([hw]).withManualMarks({hw.markKey: ManualMark.submitted});
      expect(alertsFor(marked), isEmpty);
    });

    test('First sync only reports deadlines, not every past score', () {
      final alerts = computeProgressAlerts(
        previous: null,
        current: [
          _disc([
            _ev('М', 1, value: '27', stage: '13', points: _thresholds()),
            _ev('ДЗ', 1, stage: '1', week: 8),
          ])
        ],
        currentWeek: 8,
        alreadyNotified: {},
      );
      expect(_titles(alerts), ['Срок на этой неделе: ДЗ-1']);
    });

    test('Already sent alerts are not repeated', () {
      final args = (
        previous: [_disc([_ev('ДЗ', 1, week: 8)])],
        current: [_disc([_ev('ДЗ', 1, stage: '1', week: 8)])],
      );
      final first = computeProgressAlerts(
        previous: args.previous, current: args.current, currentWeek: 8, alreadyNotified: {});
      expect(first, hasLength(2));
      final again = computeProgressAlerts(
        previous: args.previous,
        current: args.current,
        currentWeek: 8,
        alreadyNotified: first.map((a) => a.key).toSet(),
      );
      expect(again, isEmpty);
    });
  });

  group('BackgroundSync.run', () {
    final profile = UserProfile(
      lastName: 'Тестов',
      firstName: 'Иван',
      middleName: 'Петрович',
      groupTitle: 'РК5-32Б',
      groupUuid: 'group-1',
      stageUuid: 'stage-1',
    );
    const cacheKey = '${ProgressProvider.cacheProgressPrefix}stage-1';

    void seed({required bool enabled, List<DisciplineProgress>? cached}) {
      SharedPreferences.setMockInitialValues({
        BackgroundSync.enabledKey: enabled,
        AuthProvider.cachedProfileKey: jsonEncode(profile.toJson()),
        if (cached != null) cacheKey: jsonEncode(cached.map((d) => d.toJson()).toList()),
      });
      FlutterSecureStorage.setMockInitialValues({'bmstu_username': 'student', 'bmstu_password': 'secret'});
    }

    test('Notifies about changes, updates the app cache and does not repeat itself', () async {
      seed(enabled: true, cached: [_disc([_ev('М', 1, points: _thresholds())])]);
      final api = FakeLksApi([_disc([_ev('М', 1, value: '30', stage: '13', points: _thresholds())])]);
      final delivered = <ProgressAlert>[];

      final alerts = await BackgroundSync.run(api: api, authStorage: AuthStorage(), deliver: (a) async => delivered.addAll(a));
      expect(_titles(alerts), ['Баллы за модуль 1']);
      expect(delivered, hasLength(1));
      expect(delivered.first.body, contains('на «5»'));

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(cacheKey), contains('"value":"30"'));

      expect(await BackgroundSync.run(api: api, authStorage: AuthStorage(), deliver: (a) async => delivered.addAll(a)), isEmpty);
      expect(delivered, hasLength(1));
    });

    test('Expired session: signs in with the saved password and retries', () async {
      seed(enabled: true, cached: [_disc([_ev('ДЗ', 2, week: 9)])]);
      final api = FakeLksApi([_disc([_ev('ДЗ', 2, stage: '1', week: 9)])], sessionExpired: true);

      final alerts = await BackgroundSync.run(api: api, authStorage: AuthStorage(), deliver: (_) async {});
      expect(api.loginCalls, 1);
      expect(_titles(alerts), ['Выдано ДЗ-2']);
    });

    test('A second sync started while one is running does not notify twice', () async {
      seed(enabled: true, cached: [_disc([_ev('ДЗ', 2, week: 9)])]);
      final api = FakeLksApi([_disc([_ev('ДЗ', 2, stage: '1', week: 9)])]);
      final delivered = <ProgressAlert>[];
      Future<List<ProgressAlert>> sync() =>
          BackgroundSync.run(api: api, authStorage: AuthStorage(), deliver: (a) async => delivered.addAll(a));

      final results = await Future.wait([sync(), sync()]);
      expect(results.where((r) => r.isNotEmpty), hasLength(1));
      expect(_titles(delivered), ['Выдано ДЗ-2']);

      // Once it has finished, the next sync runs normally (and finds nothing new)
      expect(await sync(), isEmpty);
      expect(api.progressCalls, 2);
    });

    test('Stores a fresh schedule snapshot for the home-screen widget', () async {
      seed(enabled: true, cached: [_disc([_ev('ДЗ', 2, week: 9)])]);
      final api = FakeLksApi([_disc([_ev('ДЗ', 2, week: 9)])]);

      await BackgroundSync.run(api: api, authStorage: AuthStorage(), deliver: (_) async {});
      expect(api.scheduleCalls, ['group-1']);
      final prefs = await SharedPreferences.getInstance();
      final snapshot = jsonDecode(prefs.getString(WidgetSyncService.backgroundSnapshotKey)!) as Map<String, dynamic>;
      expect(snapshot['groupTitle'], 'РК5-32Б');
      expect(snapshot['generatedAt'], isA<int>());
      expect((snapshot['lessons'] as List).single['disciplineTitle'], 'Сопротивление материалов');
    });

    test('Does nothing while notifications are off', () async {
      seed(enabled: false, cached: [_disc([_ev('ДЗ', 2, week: 9)])]);
      final api = FakeLksApi([_disc([_ev('ДЗ', 2, stage: '1', week: 9)])]);

      expect(await BackgroundSync.run(api: api, authStorage: AuthStorage(), deliver: (_) async {}), isEmpty);
      expect(api.progressCalls, 0);
    });
  });
}

// LKS without network: fixed progress, week 8, optionally an expired session
class FakeLksApi extends BmstuApiService {
  final List<DisciplineProgress> progress;
  bool sessionExpired;
  int loginCalls = 0;
  int progressCalls = 0;
  final scheduleCalls = <String>[];

  FakeLksApi(this.progress, {this.sessionExpired = false});

  @override
  Future<List<DisciplineProgress>> getProgress(String stageUuid) async {
    progressCalls++;
    if (sessionExpired) throw BmstuAuthException();
    return progress;
  }

  @override
  Future<UserProfile?> login(String username, String password) async {
    loginCalls++;
    sessionExpired = false;
    return UserProfile(
      lastName: 'Тестов',
      firstName: 'Иван',
      middleName: 'Петрович',
      groupTitle: 'РК5-32Б',
      groupUuid: 'group-1',
      stageUuid: 'stage-1',
    );
  }

  // One lecture every day, so today's or tomorrow's list is never empty
  @override
  Future<List<ScheduleLesson>> getGroupSchedule(String groupUuid) async {
    scheduleCalls.add(groupUuid);
    return [
      for (var day = 1; day <= 6; day++)
        ScheduleLesson(
          day: day,
          time: 7,
          startTime: '23:58',
          endTime: '23:59',
          week: 'all',
          disciplineTitle: 'Сопротивление материалов',
          actType: 'lecture',
          audiences: const [],
          teachers: const [],
        ),
    ];
  }

  @override
  Future<CurrentWeek?> getCurrentWeek({bool fallbackToDefault = true}) async =>
      CurrentWeek.defaultWeek(DateTime(2026, 10, 22));
}
