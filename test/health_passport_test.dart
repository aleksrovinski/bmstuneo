import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bmstu_neo/constants/moscow_time.dart';
import 'package:bmstu_neo/models/current_week.dart';
import 'package:bmstu_neo/models/discipline_progress.dart';
import 'package:bmstu_neo/models/physical_culture.dart';
import 'package:bmstu_neo/models/schedule_lesson.dart';
import 'package:bmstu_neo/models/user_profile.dart';
import 'package:bmstu_neo/providers/auth_provider.dart';
import 'package:bmstu_neo/providers/fv_provider.dart';
import 'package:bmstu_neo/providers/homework_provider.dart';
import 'package:bmstu_neo/providers/progress_provider.dart';
import 'package:bmstu_neo/providers/schedule_provider.dart';
import 'package:bmstu_neo/providers/theme_provider.dart';
import 'package:bmstu_neo/screens/fv_screen.dart';
import 'package:bmstu_neo/screens/home_screen.dart';
import 'package:bmstu_neo/screens/main_navigation_screen.dart';
import 'package:bmstu_neo/services/auth_storage.dart';
import 'package:bmstu_neo/services/bmstu_api_service.dart';

class _FakeApi extends BmstuApiService {
  final PhysicalCultureData? fvData;

  _FakeApi({this.fvData});

  static final _profile = UserProfile(
    lastName: 'Тестов',
    firstName: 'Иван',
    middleName: 'Петрович',
    groupTitle: 'РК5-32Б',
    groupUuid: 'group-1',
    stageUuid: 'stage-1',
  );

  @override
  Future<UserProfile?> login(String username, String password) async => _profile;

  @override
  Future<UserProfile?> fetchUserProfile() async => _profile;

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
  Future<List<ScheduleLesson>> getGroupSchedule(String groupUuid) async => const [];

  @override
  Future<List<DisciplineProgress>> getProgress(String stageUuid) async => const [];

  @override
  Future<PhysicalCultureData?> getPhysicalCulture(String stageUuid) async => fvData;
}

PhysicalCultureData _fvData({required String? medDate}) => PhysicalCultureData(
      studyPoints: 34,
      studyAttends: 14,
      medGroup: 'Основная с плаванием',
      medDate: medDate,
      medSwim: true,
      groups: const [],
      studyResults: const [],
    );

Future<AuthProvider> _signedInAuth(BmstuApiService api) async {
  final auth = AuthProvider(apiService: api, authStorage: AuthStorage());
  await auth.login('student', 'secret', rememberMe: false);
  return auth;
}

Future<void> _loadAppFont() async {
  final loader = FontLoader(appFontFamily);
  for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold', 'Black']) {
    loader.addFont(rootBundle.load('assets/fonts/Onest-$w.ttf'));
  }
  await loader.load();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final fixedNowMsk = DateTime(2026, 11, 19, 12, 0);

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    MoscowTime.clock = () => DateTime.utc(2026, 11, 19, 9, 0);
  });

  tearDown(() {
    MoscowTime.clock = DateTime.now;
  });

  group('HealthPassportInfo parsing & boundaries', () {
    test('parses ISO dates, offsets, UTC midnight, and Russian DD.MM.YYYY; rejects non-dates', () {
      expect(HealthPassportInfo.parseDate('2026-12-15'), DateTime(2026, 12, 15));
      expect(HealthPassportInfo.parseDate('2026-12-15T00:00:00+03:00'), DateTime(2026, 12, 15));
      expect(HealthPassportInfo.parseDate('2026-12-14T21:00:00Z'), DateTime(2026, 12, 15));
      expect(HealthPassportInfo.parseDate('15.12.2026'), DateTime(2026, 12, 15));
      expect(HealthPassportInfo.parseDate('5.1.2027'), DateTime(2027, 1, 5));

      expect(HealthPassportInfo.parseDate('31.02.2026'), isNull);
      expect(HealthPassportInfo.parseDate('Справка активна'), isNull);
      expect(HealthPassportInfo.parseDate('Справка до 31.08'), isNull);
      expect(HealthPassportInfo.parseDate(''), isNull);
      expect(HealthPassportInfo.parseDate(null), isNull);

      for (final bad in [null, '', 'Справка активна', 'Справка до 31.08', '31.02.2026']) {
        final info = HealthPassportInfo.fromMedDate(bad, now: fixedNowMsk);
        expect(info.state, HealthPassportState.unknown);
        expect(info.needsAttention, isFalse);
        expect(info.shortBadge, isNull);
        expect(info.warningTitle, isNull);
      }
    });

    test('boundary days: 31 valid, 30 expiringSoon, 1 tomorrow, 0 expired, -5 expired', () {
      final valid = HealthPassportInfo.fromMedDate('2026-12-20', now: fixedNowMsk);
      expect(valid.daysRemaining, 31);
      expect(valid.state, HealthPassportState.valid);
      expect(valid.needsAttention, isFalse);
      expect(valid.shortBadge, isNull);
      expect(valid.warningTitle, isNull);

      final day30 = HealthPassportInfo.fromMedDate('2026-12-19', now: fixedNowMsk);
      expect(day30.daysRemaining, 30);
      expect(day30.state, HealthPassportState.expiringSoon);
      expect(day30.isExpiringSoon, isTrue);
      expect(day30.needsAttention, isTrue);
      expect(day30.shortBadge, 'Осталось 30 дней');
      expect(day30.warningTitle, 'Паспорт здоровья истекает через 30 дней');

      final tomorrow = HealthPassportInfo.fromMedDate('2026-11-20', now: fixedNowMsk);
      expect(tomorrow.daysRemaining, 1);
      expect(tomorrow.state, HealthPassportState.expiringSoon);
      expect(tomorrow.shortBadge, 'Истекает завтра');
      expect(tomorrow.warningTitle, 'Паспорт здоровья истекает завтра');
      expect(tomorrow.warningDescription, contains('20 ноября'));

      // On the expiry date itself attendance is already disallowed
      final todayExpiry = HealthPassportInfo.fromMedDate('2026-11-19', now: fixedNowMsk);
      expect(todayExpiry.daysRemaining, 0);
      expect(todayExpiry.state, HealthPassportState.expired);
      expect(todayExpiry.isExpired, isTrue);
      expect(todayExpiry.needsAttention, isTrue);
      expect(todayExpiry.shortBadge, 'Недействителен');
      expect(todayExpiry.warningTitle, 'Нужно продлить паспорт здоровья');

      final past = HealthPassportInfo.fromMedDate('2026-11-14', now: fixedNowMsk);
      expect(past.daysRemaining, -5);
      expect(past.state, HealthPassportState.expired);
      expect(past.isExpired, isTrue);
      expect(past.shortBadge, 'Недействителен');
    });

    test('Russian pluralization of daysWord covers 1, 2-4, 5-20, 21-30', () {
      const expected = {
        1: 'день',
        2: 'дня',
        4: 'дня',
        5: 'дней',
        11: 'дней',
        14: 'дней',
        21: 'день',
        22: 'дня',
        25: 'дней',
        30: 'дней',
      };
      for (final entry in expected.entries) {
        expect(HealthPassportInfo.daysWord(entry.key), entry.value, reason: 'n=${entry.key}');
      }
    });

    test('same-year vs cross-year date formatting', () {
      final sameYear = HealthPassportInfo.fromMedDate('2026-11-29', now: fixedNowMsk);
      expect(sameYear.formattedDate, '29 ноября');
      expect(sameYear.formattedFullDate, '29 ноября 2026');

      final nextYear = HealthPassportInfo.fromMedDate(
        '2027-01-10',
        now: DateTime(2026, 12, 20, 12, 0),
      );
      expect(nextYear.daysRemaining, 21);
      expect(nextYear.formattedDate, '10 января 2027');
      expect(nextYear.formattedFullDate, '10 января 2027');
      expect(nextYear.warningTitle, 'Паспорт здоровья истекает через 21 день');
      expect(nextYear.homeSubtitle, 'Действует до 10 января 2027 · продлите в поликлинике');
    });
  });

  group('Health passport UI integration', () {
    testWidgets('FvScreen hides warning when valid or guest, shows amber when expiring and red when expired',
        (tester) async {
      final api = _FakeApi();
      final auth = await _signedInAuth(api);
      final sched = ScheduleProvider(apiService: api);
      final fv = FvProvider(apiService: api);

      Widget wrap() => MultiProvider(
            providers: [
              ChangeNotifierProvider.value(value: auth),
              ChangeNotifierProvider.value(value: fv),
              ChangeNotifierProvider.value(value: sched),
            ],
            child: const MaterialApp(home: FvScreen()),
          );

      // 1. Valid (> 30 days) -> no warning banner
      fv.dataForTest = _fvData(medDate: '2026-12-25');
      await tester.pumpWidget(wrap());
      await tester.pumpAndSettle();

      expect(find.text('Паспорт здоровья'), findsOneWidget);
      expect(find.text('Нужно продлить паспорт здоровья'), findsNothing);
      expect(find.textContaining('Паспорт здоровья истекает'), findsNothing);
      expect(find.text('Действует до: 25 декабря 2026'), findsOneWidget);

      // 2. Expiring soon (10 days) -> amber warning banner + chip
      fv.dataForTest = _fvData(medDate: '2026-11-29');
      await tester.pumpAndSettle();

      expect(find.text('Паспорт здоровья истекает через 10 дней'), findsOneWidget);
      expect(find.text('Осталось 10 дней'), findsOneWidget);
      expect(find.text('Действует до: 29 ноября 2026'), findsOneWidget);

      // 3. Expired (on expiry date itself) -> red banner + Недействителен chip
      fv.dataForTest = _fvData(medDate: '2026-11-19');
      await tester.pumpAndSettle();

      expect(find.text('Нужно продлить паспорт здоровья'), findsOneWidget);
      expect(find.text('Недействителен'), findsOneWidget);
      expect(find.text('Действовал до: 19 ноября 2026'), findsOneWidget);

      // 4. Guest mode -> no warning banner
      await auth.enterGuestMode(groupTitle: 'РК5-32Б', groupUuid: 'group-1');
      fv.loadGuestSample();
      await tester.pumpAndSettle();

      expect(find.text('Нужно продлить паспорт здоровья'), findsNothing);
      expect(find.textContaining('Паспорт здоровья истекает'), findsNothing);
      expect(find.text('Справка действует до: Справка активна'), findsOneWidget);
    });

    testWidgets('HomeScreen shows warning banner only for full auth when attention needed and opens FV on tap',
        (tester) async {
      final api = _FakeApi();
      final auth = await _signedInAuth(api);
      final sched = ScheduleProvider(apiService: api);
      final fv = FvProvider(apiService: api);
      var openedFv = 0;

      Widget wrap() => MultiProvider(
            providers: [
              ChangeNotifierProvider.value(value: auth),
              ChangeNotifierProvider.value(value: sched),
              ChangeNotifierProvider(create: (_) => ProgressProvider(apiService: api)),
              ChangeNotifierProvider.value(value: fv),
              ChangeNotifierProvider(create: (_) => HomeworkProvider()),
            ],
            child: MaterialApp(
              home: HomeScreen(
                onOpenSchedule: () {},
                onOpenGrades: () {},
                onOpenFv: () => openedFv++,
              ),
            ),
          );

      // Valid -> hidden
      fv.dataForTest = _fvData(medDate: '2026-12-25');
      await tester.pumpWidget(wrap());
      await tester.pumpAndSettle();
      expect(find.textContaining('Паспорт здоровья истекает'), findsNothing);

      // Expiring soon -> visible and tappable
      fv.dataForTest = _fvData(medDate: '2026-11-24');
      await tester.pumpAndSettle();
      expect(find.text('Паспорт здоровья истекает через 5 дней'), findsOneWidget);
      expect(find.text('Действует до 24 ноября · продлите в поликлинике'), findsOneWidget);

      await tester.tap(find.text('Паспорт здоровья истекает через 5 дней'));
      await tester.pumpAndSettle();
      expect(openedFv, 1);

      // Guest -> hidden even if medDate were set
      await auth.enterGuestMode(groupTitle: 'РК5-32Б', groupUuid: 'group-1');
      await tester.pumpAndSettle();
      expect(find.text('Паспорт здоровья истекает через 5 дней'), findsNothing);
    });

    testWidgets('MainNavigationScreen shows Badge on ФКиС tab only when full auth and passport needs attention',
        (tester) async {
      final api = _FakeApi(fvData: _fvData(medDate: '2026-12-25'));
      final auth = await _signedInAuth(api);
      final sched = ScheduleProvider(apiService: api);
      final fv = FvProvider(apiService: api);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: auth),
            ChangeNotifierProvider.value(value: sched),
            ChangeNotifierProxyProvider<AuthProvider, ProgressProvider>(
              create: (_) => ProgressProvider(apiService: api),
              update: (_, a, p) => p!,
            ),
            ChangeNotifierProvider.value(value: fv),
            ChangeNotifierProvider(create: (_) => HomeworkProvider()),
          ],
          child: const MaterialApp(home: MainNavigationScreen()),
        ),
      );
      await tester.pumpAndSettle();

      Badge fvBadge() => tester.widget<Badge>(
            find.descendant(
              of: find.byType(NavigationBar),
              matching: find.byType(Badge),
            ).first,
          );

      expect(fvBadge().isLabelVisible, isFalse);

      fv.dataForTest = _fvData(medDate: '2026-11-25');
      await tester.pumpAndSettle();
      expect(fvBadge().isLabelVisible, isTrue);

      fv.dataForTest = _fvData(medDate: '2026-12-30');
      await tester.pumpAndSettle();
      expect(fvBadge().isLabelVisible, isFalse);
    });

    testWidgets('FvScreen expiring passport banner renders without overflow at 2.0x text scale on 360px screen',
        (tester) async {
      await _loadAppFont();
      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final api = _FakeApi();
      final auth = await _signedInAuth(api);
      final sched = ScheduleProvider(apiService: api);
      final fv = FvProvider(apiService: api)..dataForTest = _fvData(medDate: '2026-11-29');

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: auth),
            ChangeNotifierProvider.value(value: fv),
            ChangeNotifierProvider.value(value: sched),
          ],
          child: MaterialApp(
            theme: ThemeData(useMaterial3: true, fontFamily: appFontFamily),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(2.0)),
              child: child!,
            ),
            home: const FvScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Паспорт здоровья истекает через 10 дней'), findsOneWidget);
      expect(find.text('Осталось 10 дней'), findsOneWidget);
    });
  });
}
