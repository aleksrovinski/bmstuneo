import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:bmstu_neo/models/discipline_progress.dart';
import 'package:bmstu_neo/models/session_result.dart';
import 'package:bmstu_neo/models/user_profile.dart';
import 'package:bmstu_neo/providers/auth_provider.dart';
import 'package:bmstu_neo/providers/progress_provider.dart';
import 'package:bmstu_neo/services/auth_storage.dart';
import 'package:bmstu_neo/services/bmstu_api_service.dart';
import 'package:bmstu_neo/widgets/grades/discipline_card.dart';
import 'package:bmstu_neo/widgets/home_hero_card.dart';
import 'package:bmstu_neo/widgets/profile_session_card.dart';

ControlEvent _event(String type, {String? stage, int index = 1, String? id}) => ControlEvent(
      type: type,
      title: '$type-$index',
      week: 4,
      stage: stage,
      disciplineTitle: 'Сопротивление материалов',
      controlIndex: index,
      controlId: id,
    );

DisciplineProgress _discipline(List<ControlEvent> controls) =>
    DisciplineProgress(title: 'Сопротивление материалов', points: const {}, controls: controls);

// Logs in without network and serves fixed session results
class FakeSessionApi extends BmstuApiService {
  final List<SemesterSession> sessions;
  FakeSessionApi(this.sessions);

  @override
  Future<UserProfile?> login(String username, String password) async => UserProfile(
        lastName: 'Тестов',
        firstName: 'Иван',
        middleName: 'Петрович',
        groupTitle: 'РК5-32Б',
        groupUuid: 'group-1',
        stageUuid: 'stage-1',
      );

  @override
  Future<List<SemesterSession>> getSessionResults({String? stageUuid, bool forceRefresh = false}) async =>
      sessions;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Manual marks', () {
    test('Each mark maps to the matching status for the event type', () {
      final hw = _event('ДЗ', stage: '1');
      expect(hw.isIssued, isTrue);

      final done = hw.withManualMark(ManualMark.submitted);
      expect(done.isSubmitted, isTrue);
      expect(done.manualMark, ManualMark.submitted);
      expect(done.lksOriginal, same(hw));

      expect(hw.withManualMark(ManualMark.missed).isMissed, isTrue);
      expect(_event('РК').withManualMark(ManualMark.issued).shortBadgeText, 'Назначен');
      expect(hw.withManualMark(ManualMark.notIssued).isNotIssued, isTrue);
      expect(_event('СЗ').withManualMark(ManualMark.submitted).shortBadgeText, 'Посещено');

      // Re-marking keeps the original LKS event, not the previous mark
      expect(done.withManualMark(ManualMark.missed).lksOriginal, same(hw));
    });

    test('Modules are graded by points and cannot be marked by hand', () {
      expect(_event('М').canMarkManually, isFalse);
      expect(_event('ЛР').canMarkManually, isTrue);
    });

    test('Marks overlay LKS data, persist, survive a refresh and can be reset', () async {
      SharedPreferences.setMockInitialValues({});
      final lab = _event('ЛР', stage: '1', id: 'lab-uuid');
      final prog = ProgressProvider(apiService: BmstuApiService());
      prog.setDisciplinesForTest([_discipline([lab, _event('РК', index: 2)])]);

      await prog.setManualMark(lab, ManualMark.submitted);
      expect(prog.disciplines.first.controls.first.isSubmitted, isTrue);
      expect(prog.disciplines.first.controls.first.manualMark, ManualMark.submitted);
      expect(prog.disciplines.first.controls[1].manualMark, isNull);
      expect(prog.manualMarkFor(lab), ManualMark.submitted);

      // Fresh LKS data (still "issued") does not wipe the mark
      prog.setDisciplinesForTest([_discipline([_event('ЛР', stage: '1', id: 'lab-uuid')])]);
      expect(prog.disciplines.first.controls.first.isSubmitted, isTrue);

      // Another app launch reads the mark back
      final restarted = ProgressProvider(apiService: BmstuApiService());
      await Future<void>.delayed(Duration.zero);
      restarted.setDisciplinesForTest([_discipline([lab])]);
      expect(restarted.disciplines.first.controls.first.manualMark, ManualMark.submitted);

      await prog.setManualMark(lab, null);
      expect(prog.disciplines.first.controls.first.isIssued, isTrue);
      expect(prog.disciplines.first.controls.first.manualMark, isNull);
    });

    test('Events without an LKS id are keyed by discipline, type and index', () {
      expect(_event('ДЗ', index: 3).markKey, 'Сопротивление материалов|ДЗ|3');
      expect(_event('ДЗ', id: 'abc').markKey, 'abc');
    });
  });

  group('Week timeline', () {
    // 17 weeks × 70 px + 2 × 12 px padding = 1214 px of content
    const viewport = 360.0;
    const maxExtent = 1214.0 - viewport;

    test('Current week is centered', () {
      // Week 8 center: 12 + 7 × 70 + 35 = 537
      expect(WeekTimeline.centerOffset(8, viewport, maxExtent), 537 - viewport / 2);
    });

    test('Edge weeks stay within the scroll range', () {
      expect(WeekTimeline.centerOffset(1, viewport, maxExtent), 0);
      expect(WeekTimeline.centerOffset(17, viewport, maxExtent), maxExtent);
    });
  });

  group('Home greetings', () {
    test('Stays the same within a part of the day and uses the name', () {
      final a = HomeGreetings.forTime(DateTime(2026, 10, 22, 9, 0), 'Александр');
      final b = HomeGreetings.forTime(DateTime(2026, 10, 22, 11, 59, 59), 'Александр');
      expect(a, b);
      expect(a, contains(', Александр!'));
    });

    test('Changes with the part of the day and has no name placeholder when unknown', () {
      final morning = HomeGreetings.forTime(DateTime(2026, 10, 22, 8), '');
      final night = HomeGreetings.forTime(DateTime(2026, 10, 22, 23, 30), '');
      expect(morning, isNot(night));
      expect(morning, isNot(contains(', !')));
    });

    test('Weekend daytime uses the weekend set', () {
      final weekday = {for (var d = 19; d <= 23; d++) HomeGreetings.forTime(DateTime(2026, 10, d, 14), '')};
      final saturday = HomeGreetings.forTime(DateTime(2026, 10, 24, 14), '');
      expect(weekday.contains(saturday), isFalse);
    });
  });

  test('Semester session counts passed, debts and the exam average', () {
    const session = SemesterSession(
      semesterTitle: 'Семестр 2',
      semesterNumber: 2,
      disciplines: [
        SessionDiscipline(title: 'Физика', department: 'ФН4', controlType: 'Экз', hours: 144, grade: 'Отлично'),
        SessionDiscipline(title: 'Химия', department: 'ФН5', controlType: 'Экз', hours: 108, grade: 'Хорошо'),
        SessionDiscipline(title: 'Английский', department: 'Л3', controlType: 'Зач', hours: 72, grade: 'Зачтено'),
        SessionDiscipline(title: 'Матанализ', department: 'ФН1', controlType: 'Экз', hours: 144, grade: 'Не аттестован'),
      ],
    );
    expect(session.passedCount, 3);
    expect(session.debtCount, 1);
    expect(session.averageGrade, 4.5);
  });

  testWidgets('Profile session card is a compact summary of the latest semester', (tester) async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    final api = FakeSessionApi(const [
      SemesterSession(
        semesterTitle: 'Семестр 2',
        semesterNumber: 2,
        disciplines: [
          SessionDiscipline(title: 'Физика', department: 'ФН4', controlType: 'Экз', hours: 144, grade: 'Отлично'),
          SessionDiscipline(title: 'Матанализ', department: 'ФН1', controlType: 'Экз', hours: 144, grade: 'Не аттестован'),
        ],
      ),
      SemesterSession(
        semesterTitle: 'Семестр 1',
        semesterNumber: 1,
        disciplines: [
          SessionDiscipline(title: 'Химия', department: 'ФН5', controlType: 'Экз', hours: 108, grade: 'Хорошо'),
        ],
      ),
    ]);
    final auth = AuthProvider(apiService: api, authStorage: AuthStorage());
    await tester.runAsync(() => auth.login('student', 'secret', rememberMe: false));

    await tester.pumpWidget(ChangeNotifierProvider<AuthProvider>.value(
      value: auth,
      child: const MaterialApp(home: Scaffold(body: SingleChildScrollView(child: ProfileSessionCard()))),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Результаты сессий'), findsOneWidget);
    expect(find.text('Семестр 2 • 2 дисциплины'), findsOneWidget);
    expect(find.text('Сдано 1/2'), findsOneWidget);
    expect(find.text('Долги: 1'), findsOneWidget);
    expect(find.text('Ср. балл 5.00'), findsOneWidget);
    // Compact: only the debt is listed, passed disciplines stay in the Session section
    expect(find.text('Не аттестован'), findsOneWidget);
    expect(find.text('Отлично'), findsNothing);
    expect(find.text('Хорошо'), findsNothing, reason: 'only the latest semester is summarized');
    expect(find.text('Все семестры (2)'), findsOneWidget);
  });
}
