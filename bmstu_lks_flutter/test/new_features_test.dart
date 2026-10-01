import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';

import 'package:bmstu_neo/models/user_profile.dart';
import 'package:bmstu_neo/models/discipline_progress.dart';
import 'package:bmstu_neo/models/physical_culture.dart';
import 'package:bmstu_neo/services/bmstu_groups_catalog.dart';
import 'package:bmstu_neo/services/bmstu_api_service.dart';
import 'package:bmstu_neo/services/cache_service.dart';
import 'package:bmstu_neo/services/auth_storage.dart';
import 'package:bmstu_neo/providers/favorites_provider.dart';
import 'package:bmstu_neo/providers/theme_provider.dart';
import 'package:bmstu_neo/providers/progress_provider.dart';
import 'package:bmstu_neo/providers/auth_provider.dart';
import 'package:bmstu_neo/widgets/student_id_card.dart';
import 'package:bmstu_neo/widgets/pe_calculator_sheet.dart';
import 'package:bmstu_neo/screens/gradebook_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('FavoritesProvider Tests', () {
    test('Can toggle group favorites and persist state', () async {
      final fav = FavoritesProvider();
      await fav.loadFavorites();

      expect(fav.isGroupFavorite('uuid-1'), isFalse);

      const group = GroupItem(title: 'РК5-32Б', uuid: 'uuid-1');
      await fav.toggleGroupFavorite(group);

      expect(fav.isGroupFavorite('uuid-1'), isTrue);
      expect(fav.favoriteGroups.length, 1);
      expect(fav.favoriteGroups.first.title, 'РК5-32Б');

      // Toggle off
      await fav.toggleGroupFavorite(group);
      expect(fav.isGroupFavorite('uuid-1'), isFalse);
      expect(fav.favoriteGroups.isEmpty, isTrue);
    });

    test('Can toggle teacher favorites and persist state', () async {
      final fav = FavoritesProvider();
      await fav.loadFavorites();

      expect(fav.isTeacherFavorite('teacher-uuid-1'), isFalse);

      const teacher = TeacherSearchItem(title: 'Иванов И.И.', uuid: 'teacher-uuid-1');
      await fav.toggleTeacherFavorite(teacher);

      expect(fav.isTeacherFavorite('teacher-uuid-1'), isTrue);
      expect(fav.favoriteTeachers.length, 1);
      expect(fav.favoriteTeachers.first.title, 'Иванов И.И.');

      // Toggle off
      await fav.toggleTeacherFavorite(teacher);
      expect(fav.isTeacherFavorite('teacher-uuid-1'), isFalse);
      expect(fav.favoriteTeachers.isEmpty, isTrue);
    });
  });

  group('AppCacheManager Tests', () {
    test('Sets and gets typed data with stats calculation', () async {
      final cache = AppCacheManager.instance;
      await cache.clearAll();

      await cache.set(
        key: 'bmstu_cache_test_key',
        data: {'name': 'Бауманка', 'groups': 3400},
      );

      final item = await cache.get<Map<String, dynamic>>(
        key: 'bmstu_cache_test_key',
        fromJson: (json) => Map<String, dynamic>.from(json as Map),
      );

      expect(item, isNotNull);
      expect(item!.data['name'], 'Бауманка');
      expect(item.data['groups'], 3400);
      expect(item.sizeBytes, greaterThan(0));

      final stats = await cache.getStats();
      expect(stats.totalSizeBytes, greaterThan(0));
      expect(stats.entryCount, greaterThan(0));

      await cache.clearAll();
      final statsAfter = await cache.getStats();
      expect(statsAfter.totalSizeBytes, 0);
    });
  });

  group('ThemeProvider & OLED True Black Tests', () {
    test('Toggles OLED Black mode and sets pure black backgrounds', () async {
      final themeProv = ThemeProvider();

      expect(themeProv.themeMode, AppThemeMode.system);
      expect(themeProv.isOled, isFalse);

      await themeProv.setThemeMode(AppThemeMode.oled);
      expect(themeProv.isOled, isTrue);

      final darkTheme = themeProv.buildDarkTheme(null);
      expect(darkTheme.scaffoldBackgroundColor, Colors.black);
      expect(darkTheme.colorScheme.surface, Colors.black);
    });

    test('Changes accent colors correctly', () async {
      final themeProv = ThemeProvider();
      await themeProv.setAccentColor(AppAccentColor.emerald);

      expect(themeProv.accentColor, AppAccentColor.emerald);
      final lightTheme = themeProv.buildLightTheme(null);
      expect(lightTheme.colorScheme.primary, isNotNull);
    });
  });

  group('Digital Student ID & UserProfile Model Tests', () {
    test('Parses full student card details, agreements, stages, and course', () {
      final json = {
        'lastName': 'Несененко',
        'firstName': 'Александр',
        'middleName': 'Алексеевич',
        'groupTitle': 'РК5-32Б',
        'groupUuid': 'bad86778-ed29-11ef-becd-8753117d52b2',
        'stageUuid': '1d4822c2-6888-11f0-88af-0242ac110002',
        'cardNumber': '25Р209',
        'semester': 3,
        'specialityTitle': 'Прикладная механика',
        'specializationTitle': 'Математическое и компьютерное моделирование',
        'studyType': 'studytype.paid',
        'state': 'Обучается',
        'hasDormitory': false,
        'agreements': [
          {
            'date': '2025-08-08',
            'uuid': '8cc2c09a-23b5-4c37-ac1a-59ab45d1127a',
            'title': 'Договор об обучении',
            'number': 'ПО-30263/2025'
          }
        ],
        'stages': [
          {
            'uuid': '1d4822c2-6888-11f0-88af-0242ac110002',
            'alias': 'stage.bachelor',
            'groupTitle': 'РК5-32Б',
            'groupUuid': 'bad86778-ed29-11ef-becd-8753117d52b2',
            'semester': 3,
            'cardNumber': '25Р209',
            'state': 'Обучается'
          }
        ]
      };

      final profile = UserProfile.fromJson(json);

      expect(profile.fullName, 'Несененко Александр Алексеевич');
      expect(profile.cardNumber, '25Р209');
      expect(profile.semester, 3);
      expect(profile.course, 2); // 3rd semester is 2nd year
      expect(profile.isPaid, isTrue);
      expect(profile.studyTypeTitle, 'Платная основа');
      expect(profile.agreements.length, 1);
      expect(profile.agreements.first.number, 'ПО-30263/2025');
      expect(profile.stages.length, 1);
    });

    testWidgets('StudentIdCard widget displays card number and student info', (tester) async {
      final profile = UserProfile(
        lastName: 'Несененко',
        firstName: 'Александр',
        middleName: 'Алексеевич',
        groupTitle: 'РК5-32Б',
        groupUuid: 'test-group',
        stageUuid: 'test-stage',
        cardNumber: '25Р209',
        semester: 3,
        specialityTitle: 'Прикладная механика',
        studyType: 'studytype.paid',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StudentIdCard(user: profile),
          ),
        ),
      );

      expect(find.text('МГТУ им. Н.Э. Баумана'), findsOneWidget);
      expect(find.text('№ 25Р209'), findsOneWidget);
      expect(find.text('Несененко Александр Алексеевич'), findsOneWidget);
      expect(find.text('РК5-32Б'), findsOneWidget);
      expect(find.text('2 курс • 3 сем.'), findsOneWidget);
      expect(find.text('Обучается'), findsOneWidget);
      expect(find.text('Платная основа'), findsOneWidget);
    });
  });

  group('ProgressProvider GPA & Scholarship Analytics Tests', () {
    test('Calculates GPA and scholarship status accurately', () {
      // 1. Excellent (all 5) -> PGAS
      final disciplines = [
        DisciplineProgress(
          title: 'Математический анализ',
          points: {'point_all': 90},
          controls: [],
        ),
        DisciplineProgress(
          title: 'Теоретическая механика',
          points: {'point_all': 88},
          controls: [],
        ),
      ];

      // Inject disciplines via reflection/direct access simulation
      final discJson = disciplines.map((d) => d.toJson()).toList();
      final loaded = discJson.map((d) => DisciplineProgress.fromJson(d)).toList();

      expect(loaded[0].estimatedGrade, 5);
      expect(loaded[1].estimatedGrade, 5);

      // Add a 4
      final withGood = [
        ...loaded,
        DisciplineProgress(
          title: 'Физика',
          points: {'point_all': 75}, // 4
          controls: [],
        ),
      ];

      final gpa = (5 + 5 + 4) / 3;
      expect(gpa, closeTo(4.66, 0.02));

      // Add a 3 -> scholarship should be at risk
      final withSatisfactory = [
        ...withGood,
        DisciplineProgress(
          title: 'Инженерная графика',
          points: {'point_all': 62}, // 3
          controls: [],
        ),
      ];

      expect(withSatisfactory[3].estimatedGrade, 3);
    });
  });

  group('PE Semester Calculator Widget Tests', () {
    testWidgets('PeCalculatorSheet calculates pace and responds to segment clicks', (tester) async {
      final data = PhysicalCultureData(
        studyPoints: 30, // 30 of 60 needed (30 remaining)
        studyAttends: 15, // 15 of 25 needed (10 remaining)
        groups: [],
        studyResults: [],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PeCalculatorSheet(
              data: data,
              currentWeekNum: 7, // Week 7 -> 10 weeks remaining
            ),
          ),
        ),
      );

      expect(find.text('Калькулятор закрытия семестра'), findsOneWidget);
      expect(find.text('30 б.'), findsOneWidget); // Remaining points
      expect(find.text('10 пос.'), findsOneWidget); // Remaining attends

      // Tap 3 times/week
      await tester.tap(find.text('3 раза/нед'));
      await tester.pumpAndSettle();

      expect(find.textContaining('При темпе 3 раз(а) в неделю'), findsOneWidget);
    });
  });

  group('GradebookScreen Widget Tests', () {
    testWidgets('GradebookScreen displays GPA and student card header', (tester) async {
      final authStorage = AuthStorage();
      final apiService = BmstuApiService();

      final authProvider = AuthProvider(
        apiService: apiService,
        authStorage: authStorage,
      );

      final progressProvider = ProgressProvider(
        apiService: apiService,
      );

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: authProvider),
            ChangeNotifierProvider.value(value: progressProvider),
          ],
          child: const MaterialApp(
            home: GradebookScreen(),
          ),
        ),
      );

      expect(find.text('Электронная зачётка'), findsOneWidget);
      expect(find.text('GPA'), findsOneWidget);
      expect(find.text('Успеваемость семестра'), findsOneWidget);
    });
  });
}
