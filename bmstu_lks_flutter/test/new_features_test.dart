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
import 'package:bmstu_neo/screens/session_screen.dart';

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

  group('ThemeProvider', () {
    test('Defaults to the system mode and Material You; dark is pure black', () async {
      final themeProv = ThemeProvider();

      expect(themeProv.themeMode, AppThemeMode.system);
      expect(themeProv.accentColor, AppAccentColor.dynamicColor);

      await themeProv.setThemeMode(AppThemeMode.dark);
      final darkTheme = themeProv.buildDarkTheme(null);
      expect(darkTheme.scaffoldBackgroundColor, Colors.black);
      expect(darkTheme.colorScheme.surface, Colors.black);
    });

    test('The former OLED mode opens as the dark theme', () async {
      SharedPreferences.setMockInitialValues({'bmstu_pref_theme_mode_v2': 'oled'});
      final themeProv = ThemeProvider();
      await Future<void>.delayed(Duration.zero);
      expect(themeProv.themeMode, AppThemeMode.dark);
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
        'photoUrl': 'https://lks.bmstu.ru/media/avatar/photo123.jpg',
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
      expect(profile.photoUrl, 'https://lks.bmstu.ru/media/avatar/photo123.jpg');
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
    // Module thresholds as LKS sends them (strings), from a real 3-module discipline
    Map<String, dynamic> thresholds(int p3, int p4, int p5, int all) =>
        {'point_3': '$p3', 'point_4': '$p4', 'point_5': '$p5', 'point_all': '$all'};

    ControlEvent module(int index, String? value, Map<String, dynamic>? points) => ControlEvent(
          type: 'М',
          title: 'Модуль $index',
          week: index * 5,
          value: value,
          points: points,
          disciplineTitle: 'Дисциплина',
          controlIndex: index,
        );

    DisciplineProgress discipline(List<ControlEvent> modules, {Map<String, dynamic> points = const {}}) =>
        DisciplineProgress(title: 'Дисциплина', points: points, controls: modules);

    test('Mid-semester grade compares graded modules with their own thresholds', () {
      // Module 1: 27 of 33 (thresholds 19/23/28) -> "4"; modules 2 and 3 not graded yet
      final good = discipline([
        module(1, '27', thresholds(19, 23, 28, 33)),
        module(2, null, thresholds(19, 23, 28, 33)),
        module(3, null, thresholds(20, 23, 28, 34)),
      ]);
      expect(good.estimatedGrade, 4);
      expect(good.isPassed, isTrue);

      // 9 of 35 with a pass threshold of 21: a real shortfall
      final behind = discipline([module(1, '9', thresholds(21, 24, 29, 35))]);
      expect(behind.estimatedGrade, 2);
      expect(behind.isPassed, isFalse);

      // Two graded modules: 28 + 26 = 54 vs 5-threshold 28 + 28 = 56 -> "4"
      final twoGraded = discipline([
        module(1, '28', thresholds(19, 23, 28, 33)),
        module(2, '26', thresholds(19, 23, 28, 33)),
        module(3, null, thresholds(20, 23, 28, 34)),
      ]);
      expect(twoGraded.estimatedGrade, 4);
      expect(twoGraded.gradeDisplay, 'Хорошо (4)');
    });

    test('Nothing graded yet is "in progress", not a fail', () {
      final none = discipline([
        module(1, null, thresholds(19, 23, 28, 33)),
        module(2, '0', thresholds(19, 23, 28, 33)),
      ]);
      expect(none.estimatedGrade, isNull);
      expect(none.isPassed, isFalse);
      expect(none.gradeDisplay, 'В процессе');

      // point_all of the discipline is its maximum, not a score
      expect(discipline([], points: {'point_all': 100}).estimatedGrade, isNull);
    });

    test('Without module thresholds only a fully graded discipline gets a grade', () {
      final partial = discipline([module(1, '40', null), module(2, null, null)]);
      expect(partial.estimatedGrade, isNull);
      expect(partial.gradeDisplay, 'В процессе (40 б.)');

      expect(discipline([module(1, '45', null), module(2, '43', null)]).estimatedGrade, 5);
      expect(discipline([module(1, '30', null), module(2, '42', null)]).estimatedGrade, 4);
      expect(discipline([module(1, '30', null), module(2, '20', null)]).estimatedGrade, 2);
    });

    test('Calculates GPA and scholarship status from module estimates', () {
      final loaded = [
        discipline([module(1, '30', thresholds(19, 23, 28, 33))]), // 5
        discipline([module(1, '29', thresholds(19, 23, 28, 33))]), // 5
      ].map((d) => DisciplineProgress.fromJson(d.toJson())).toList();

      expect(loaded[0].estimatedGrade, 5);
      expect(loaded[1].estimatedGrade, 5);

      final prog = ProgressProvider(apiService: BmstuApiService());
      prog.setDisciplinesForTest([
        ...loaded,
        discipline([module(1, '25', thresholds(19, 23, 28, 33))]), // 4
      ]);
      expect(prog.gpa, closeTo(4.66, 0.02));
      expect(prog.scholarshipStatus, isNot(ScholarshipStatus.atRisk));

      prog.setDisciplinesForTest([
        ...loaded,
        discipline([module(1, '20', thresholds(19, 23, 28, 33))]), // 3
      ]);
      expect(prog.scholarshipStatus, ScholarshipStatus.atRisk);

      // Mid-semester with nothing graded is not a scholarship risk
      prog.setDisciplinesForTest([
        discipline([module(1, null, thresholds(19, 23, 28, 33))]),
      ]);
      expect(prog.scholarshipStatus, ScholarshipStatus.inProgress);
    });
  });

  group('PE 2-Visits/Week Completion Forecast Tests', () {
    test('Calculates weeks needed based on 2-visits/week BMSTU limit', () {
      final data = PhysicalCultureData(
        studyPoints: 30, // 30 of 60 needed (30 remaining)
        studyAttends: 15, // 15 of 25 needed (10 remaining)
        groups: [],
        studyResults: [],
      );

      final attendsLeft = PhysicalCultureData.targetAttends - data.studyAttends;
      expect(attendsLeft, 10);

      // Max 2 visits per week in BMSTU
      final weeksNeeded = (attendsLeft / 2).ceil();
      expect(weeksNeeded, 5);

      // 1 attend left -> 1 week
      expect(((1) / 2).ceil(), 1);
      // 0 attends left -> 0 weeks
      expect(((0) / 2).ceil(), 0);
    });
  });

  group('LKS Scraping & Session Parsing Tests', () {
    test('parseProfilePhotoHtml extracts photo from _img_1rxc3_40 _visible_1rxc3_45', () {
      const html1 = '<div class="profile"><img class="_img_1rxc3_40 _visible_1rxc3_45" src="/media/avatar/student1.jpg" alt="Student" /></div>';
      final photo1 = BmstuApiService.parseProfilePhotoHtml(html1);
      expect(photo1, 'https://lks.bmstu.ru/media/avatar/student1.jpg');

      const htmlDataUri = '<img src="data:image/jpeg;base64,abc123xyz" class="other _img_1rxc3_40 _visible_1rxc3_45" />';
      final photo2 = BmstuApiService.parseProfilePhotoHtml(htmlDataUri);
      expect(photo2, 'data:image/jpeg;base64,abc123xyz');

      const htmlNone = '<div><img src="/logo.png" class="header-logo" /></div>';
      final photo3 = BmstuApiService.parseProfilePhotoHtml(htmlNone);
      expect(photo3, isNull);
    });

    test('parseSessionHtml correctly parses semester tables, disciplines, hours, and grades', () {
      const sampleHtml = '''
<section class="_section_1abj1_40">
  <div class="_date_1abj1_46"><i>Данные актуальны на 5 сентября 15:45</i></div>
  <article class="table-container">
    <h1>Семестр 2</h1>
    <table>
      <tbody class="p-datatable-tbody">
        <tr role="row">
          <td><div>Иностранный язык<span class="text-color-secondary"> (Л3, Зач)</span></div></td>
          <td class="_hours-column_qowe5_83">72</td>
          <td class="_mark-column_qowe5_72"><div title="Зачтено"> Зачтено</div></td>
        </tr>
        <tr role="row">
          <td><div>Теоретическая механика<span class="text-color-secondary"> (ФН3, Экз)</span></div></td>
          <td class="_hours-column_qowe5_83">144</td>
          <td class="_mark-column_qowe5_72"><div title="Не аттестован"> Не аттестован</div></td>
        </tr>
        <tr role="row">
          <td><div>Учебно-технологический практикум<span class="text-color-secondary"> (МТ13, Прк)</span></div></td>
          <td class="_hours-column_qowe5_83">72</td>
          <td class="_mark-column_qowe5_72"><div title="Отлично"> Отлично</div></td>
        </tr>
      </tbody>
    </table>
  </article>
</section>
''';

      final sessions = BmstuApiService.parseSessionHtml(sampleHtml);
      expect(sessions.length, 1);
      final s2 = sessions.first;
      expect(s2.semesterTitle, 'Семестр 2');
      expect(s2.semesterNumber, 2);
      expect(s2.lastUpdated, 'Данные актуальны на 5 сентября 15:45');
      expect(s2.disciplines.length, 3);

      final d1 = s2.disciplines[0];
      expect(d1.title, 'Иностранный язык');
      expect(d1.department, 'Л3');
      expect(d1.controlType, 'Зач');
      expect(d1.hours, 72);
      expect(d1.grade, 'Зачтено');
      expect(d1.isPassed, isTrue);
      expect(d1.isDebt, isFalse);

      final d2 = s2.disciplines[1];
      expect(d2.title, 'Теоретическая механика');
      expect(d2.department, 'ФН3');
      expect(d2.controlType, 'Экз');
      expect(d2.hours, 144);
      expect(d2.grade, 'Не аттестован');
      expect(d2.isPassed, isFalse);
      expect(d2.isDebt, isTrue);

      final d3 = s2.disciplines[2];
      expect(d3.title, 'Учебно-технологический практикум');
      expect(d3.isExcellent, isTrue);
    });

    test('parseSessionJson correctly parses official LKS REST API payload', () {
      final sampleJson = {
        'date': '2026-10-01T18:46:43.857+03:00',
        'data': [
          {
            'term': 1,
            'marks': [
              {
                'disciplineName': 'Иностранный язык',
                'disciplineDepartment': 'Л3',
                'testTitleShort': 'Зач',
                'audlek': 72,
                'title': 'Зачтено'
              },
              {
                'disciplineName': 'Математический анализ',
                'disciplineDepartment': 'ФН1',
                'testTitleShort': 'Экз',
                'audlek': 180,
                'title': 'Хорошо'
              }
            ]
          },
          {
            'term': 2,
            'marks': [
              {
                'disciplineName': 'Теоретическая механика',
                'disciplineDepartment': 'ФН3',
                'testTitleShort': 'Экз',
                'audlek': 144,
                'title': 'Не аттестован'
              }
            ]
          }
        ]
      };

      final sessions = BmstuApiService.parseSessionJson(sampleJson);
      expect(sessions.length, 2);
      expect(sessions.first.semesterNumber, 2);
      expect(sessions.first.disciplines.first.title, 'Теоретическая механика');
      expect(sessions.first.disciplines.first.isDebt, isTrue);
      expect(sessions.last.semesterNumber, 1);
      expect(sessions.last.disciplines.length, 2);
      expect(sessions.last.lastUpdated, contains('1 октября'));
    });
  });

  group('SessionScreen Widget Tests', () {
    testWidgets('SessionScreen displays session header and handles state', (tester) async {
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
            home: SessionScreen(),
          ),
        ),
      );

      expect(find.text('Результаты сессий'), findsOneWidget);
      await tester.pumpAndSettle();
      expect(find.text('Результаты сессий'), findsOneWidget);
    });
  });
}

