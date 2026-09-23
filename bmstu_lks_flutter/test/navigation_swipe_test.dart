import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bmstu_neo/services/auth_storage.dart';
import 'package:bmstu_neo/services/bmstu_api_service.dart';
import 'package:bmstu_neo/providers/auth_provider.dart';
import 'package:bmstu_neo/providers/schedule_provider.dart';
import 'package:bmstu_neo/providers/progress_provider.dart';
import 'package:bmstu_neo/providers/fv_provider.dart';
import 'package:bmstu_neo/screens/main_navigation_screen.dart';
import 'package:bmstu_neo/screens/schedule_screen.dart';
import 'package:bmstu_neo/models/schedule_lesson.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('ScheduleScreen supports horizontal swipe gestures between days of week', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final apiService = BmstuApiService();
    final authStorage = AuthStorage();
    final schedProvider = ScheduleProvider(apiService: apiService);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(
            create: (_) => AuthProvider(apiService: apiService, authStorage: authStorage),
          ),
          ChangeNotifierProvider.value(
            value: schedProvider,
          ),
          ChangeNotifierProxyProvider<AuthProvider, ProgressProvider>(
            create: (_) => ProgressProvider(apiService: apiService),
            update: (_, auth, progress) => progress!,
          ),
          ChangeNotifierProvider(
            create: (_) => FvProvider(apiService: apiService),
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: ScheduleScreen(),
          ),
        ),
      ),
    );

    // ScheduleScreen contains a PageView for weekdays
    expect(find.byType(PageView), findsOneWidget);

    // Initial day can be swiped
    final initialDay = schedProvider.selectedDay;
    if (initialDay < 6) {
      await tester.fling(find.byType(PageView), const Offset(-400, 0), 1000);
      await tester.pumpAndSettle();
      expect(schedProvider.selectedDay, initialDay + 1);
    } else {
      await tester.fling(find.byType(PageView), const Offset(400, 0), 1000);
      await tester.pumpAndSettle();
      expect(schedProvider.selectedDay, initialDay - 1);
    }
  });

  testWidgets('MainNavigationScreen switches tabs via NavigationBar', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final apiService = BmstuApiService();
    final authStorage = AuthStorage();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(
            create: (_) => AuthProvider(apiService: apiService, authStorage: authStorage),
          ),
          ChangeNotifierProvider(
            create: (_) => ScheduleProvider(apiService: apiService),
          ),
          ChangeNotifierProxyProvider<AuthProvider, ProgressProvider>(
            create: (_) => ProgressProvider(apiService: apiService),
            update: (_, auth, progress) => progress!,
          ),
          ChangeNotifierProvider(
            create: (_) => FvProvider(apiService: apiService),
          ),
        ],
        child: const MaterialApp(
          home: MainNavigationScreen(),
        ),
      ),
    );

    // Tap on Schedule tab (index 2) via NavigationBar
    await tester.tap(find.text('Расписание'));
    await tester.pumpAndSettle();

    // ScheduleScreen should now be in tree
    expect(find.byType(ScheduleScreen), findsOneWidget);
  });

  group('Custom Lessons in ScheduleProvider', () {
    test('Can add, persist, and delete custom lessons', () async {
      SharedPreferences.setMockInitialValues({});
      final apiService = BmstuApiService();
      final sched = ScheduleProvider(apiService: apiService);

      final custom = ScheduleLesson(
        id: 'custom_test_1',
        isCustom: true,
        day: 3,
        time: 2,
        startTime: '10:15',
        endTime: '11:50',
        week: 'all',
        disciplineTitle: 'Военная кафедра',
        actType: 'military',
        audiences: [ScheduleAudience(name: 'ВУЦ', building: 'ГУК')],
        teachers: [
          ScheduleTeacher(
            firstName: 'Иван',
            lastName: 'Иванов',
            middleName: 'Иванович',
          ),
        ],
      );

      await sched.addCustomLesson(custom);

      // Verify custom lesson is in allLessons
      expect(sched.allLessons.any((l) => l.isCustom && l.disciplineTitle == 'Военная кафедра'), isTrue);

      // Verify custom lesson appears on day 3
      final wednesdayLessons = sched.getLessonsForDay(3, 'all');
      expect(wednesdayLessons.any((l) => l.disciplineTitle == 'Военная кафедра'), isTrue);

      // Delete custom lesson
      await sched.deleteCustomLesson(custom.id!);
      expect(sched.allLessons.any((l) => l.disciplineTitle == 'Военная кафедра'), isFalse);
    });
  });
}
