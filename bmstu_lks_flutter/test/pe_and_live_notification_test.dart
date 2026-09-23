import 'package:flutter_test/flutter_test.dart';
import 'package:bmstu_neo/models/nearest_pe_lesson.dart';
import 'package:bmstu_neo/models/physical_culture.dart';
import 'package:bmstu_neo/models/schedule_lesson.dart';
import 'package:bmstu_neo/services/widget_sync_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('NearestPeLesson Calculation', () {
    test('Finds nearest PE lesson from FvRecord when today is before the lesson', () {
      final record = FvRecord(
        id: 'rec_1',
        weekDay: 'Вторник',
        time: '11:35',
        teacherName: 'Сидоров С.С.',
        section: 'Плавание',
        place: 'Бассейн СК МГТУ',
      );

      // Simulated current time: Tuesday 10:00 (day 2, 600 minutes)
      final mockNow = DateTime(2026, 9, 22, 10, 0); // Tuesday

      final nearest = NearestPeLesson.findNearest(
        records: [record],
        lessons: [],
        isCurrentWeekNumerator: true,
        mockNow: mockNow,
      );

      expect(nearest, isNotNull);
      expect(nearest!.isToday, isTrue);
      expect(nearest.isNow, isFalse);
      expect(nearest.dayTitle, 'Сегодня');
      expect(nearest.time, '11:35');
      expect(nearest.title, 'Плавание');
      expect(nearest.place, 'Бассейн СК МГТУ');
      expect(nearest.teacher, 'Сидоров С.С.');
      expect(nearest.minutesUntil, 95); // 11:35 is 695 - 600 = 95
    });

    test('Marks lesson as isNow when current time is during the lesson', () {
      final record = FvRecord(
        id: 'rec_1',
        weekDay: 'Вторник',
        time: '11:35',
        teacherName: 'Сидоров С.С.',
        section: 'Плавание',
        place: 'Бассейн СК МГТУ',
      );

      // Simulated current time: Tuesday 12:00 (day 2, during pair 11:35-13:10)
      final mockNow = DateTime(2026, 9, 22, 12, 0);

      final nearest = NearestPeLesson.findNearest(
        records: [record],
        lessons: [],
        isCurrentWeekNumerator: true,
        mockNow: mockNow,
      );

      expect(nearest, isNotNull);
      expect(nearest!.isNow, isTrue);
      expect(nearest.dayTitle, 'Идёт прямо сейчас');
    });

    test('Finds nearest PE lesson from academic schedule with week parity', () {
      final lessonNumerator = ScheduleLesson(
        day: 4, // Thursday
        time: 2,
        startTime: '10:15',
        endTime: '11:50',
        week: 'ch', // Numerator only
        disciplineTitle: 'Элективные курсы по физической культуре',
        actType: 'seminar',
        audiences: [ScheduleAudience(name: 'Манеж', building: 'СК')],
        teachers: [
          ScheduleTeacher(
            firstName: 'Ольга',
            lastName: 'Петрова',
            middleName: 'Ивановна',
          ),
        ],
      );

      // Simulated current time: Monday (day 1, numerator week)
      final mockNow = DateTime(2026, 9, 21, 9, 0); // Monday

      final nearest = NearestPeLesson.findNearest(
        records: [],
        lessons: [lessonNumerator],
        isCurrentWeekNumerator: true,
        mockNow: mockNow,
      );

      expect(nearest, isNotNull);
      expect(nearest!.dayTitle, 'В четверг');
      expect(nearest.time, '10:15');
      expect(nearest.place, contains('Манеж'));
    });

    test('Returns null when no PE records or lessons exist', () {
      final mathLesson = ScheduleLesson(
        day: 2,
        time: 1,
        startTime: '08:30',
        endTime: '10:05',
        week: 'all',
        disciplineTitle: 'Линейная алгебра',
        actType: 'lecture',
        audiences: [ScheduleAudience(name: '323', building: 'ГУК')],
        teachers: [
          ScheduleTeacher(firstName: 'А.', lastName: 'Б.', middleName: 'В.'),
        ],
      );

      final nearest = NearestPeLesson.findNearest(
        records: [],
        lessons: [mathLesson],
        isCurrentWeekNumerator: true,
      );

      expect(nearest, isNull);
    });
  });

  group('WidgetSyncService Live Notification', () {
    test('Handles live notification query safely on desktop/test environments', () async {
      final isEnabled = await WidgetSyncService.isLiveNotificationEnabled();
      // On non-native test environment without plugin, defaults gracefully to true
      expect(isEnabled, isTrue);

      final hasPermission = await WidgetSyncService.hasNotificationPermission();
      expect(hasPermission, isTrue);

      final requested = await WidgetSyncService.requestNotificationPermission();
      expect(requested, isTrue);

      await expectLater(
        WidgetSyncService.setLiveNotificationEnabled(false),
        completes,
      );
    });
  });
}
