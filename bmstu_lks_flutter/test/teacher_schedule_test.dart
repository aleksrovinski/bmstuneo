import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bmstu_neo/models/schedule_lesson.dart';
import 'package:bmstu_neo/services/bmstu_api_service.dart';
import 'package:bmstu_neo/widgets/pair_card.dart';
import 'package:bmstu_neo/widgets/teacher_details_sheet.dart';
import 'package:bmstu_neo/screens/teacher_schedule_screen.dart';

void main() {
  group('Teacher Model & Formatting Tests', () {
    test('ScheduleTeacher fullName returns full name or fallback', () {
      final t1 = ScheduleTeacher(
        firstName: 'Иван',
        lastName: 'Иванов',
        middleName: 'Иванович',
        uuid: 'uuid-1',
      );
      expect(t1.fullName, 'Иванов Иван Иванович');
      expect(t1.formattedName, 'Иванов И.И.');

      final t2 = ScheduleTeacher(
        firstName: '',
        lastName: 'Петров',
        middleName: '',
      );
      expect(t2.fullName, 'Петров');
      expect(t2.formattedName, 'Петров');

      final t3 = ScheduleTeacher(
        firstName: '',
        lastName: '',
        middleName: '',
      );
      expect(t3.fullName, 'Преподаватель кафедры');
      expect(t3.formattedName, 'Кафедра');
    });

    test('ScheduleLesson teachersFullFormatted correctly joins teacher full names', () {
      final lesson = ScheduleLesson(
        day: 1,
        time: 1,
        startTime: '08:30',
        endTime: '10:00',
        week: 'all',
        disciplineTitle: 'Высшая математика',
        actType: 'lecture',
        audiences: [ScheduleAudience(name: '305л', building: 'УЛК')],
        teachers: [
          ScheduleTeacher(firstName: 'Иван', lastName: 'Иванов', middleName: 'Иванович'),
          ScheduleTeacher(firstName: 'Петр', lastName: 'Сидоров', middleName: 'Алексеевич'),
        ],
      );

      expect(lesson.teachersFullFormatted, 'Иванов Иван Иванович, Сидоров Петр Алексеевич');
      expect(lesson.teachersFormatted, 'Иванов И.И., Сидоров П.А.');
      expect(lesson.audiencesFormatted, '305л (УЛК)');
    });

    test('TeacherSearchItem serialization works correctly', () {
      final json = {
        'title': 'Бабаян А.В.',
        'uuid': 'uuid-12345',
      };
      final item = TeacherSearchItem.fromJson(json);
      expect(item.title, 'Бабаян А.В.');
      expect(item.uuid, 'uuid-12345');
      expect(item.toJson(), json);
    });
  });

  group('Teacher UI Widget Tests', () {
    testWidgets('Tapping teacher in PairCard displays TeacherDetailsSheet', (WidgetTester tester) async {
      final lesson = ScheduleLesson(
        day: 1,
        time: 2,
        startTime: '10:15',
        endTime: '11:50',
        week: 'all',
        disciplineTitle: 'Основы программирования',
        actType: 'lab',
        audiences: [ScheduleAudience(name: '502', building: 'ГУК')],
        teachers: [
          ScheduleTeacher(
            firstName: 'Сергей',
            lastName: 'Кузнецов',
            middleName: 'Владимирович',
            uuid: 'teach-uuid-99',
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PairCard(lesson: lesson),
          ),
        ),
      );

      // Verify pair card renders teacher's short name
      expect(find.text('Кузнецов С.В.'), findsOneWidget);

      // Tap on teacher name
      await tester.tap(find.text('Кузнецов С.В.'));
      await tester.pumpAndSettle();

      // Verify TeacherDetailsSheet modal is shown with full name
      expect(find.byType(TeacherDetailsSheet), findsOneWidget);
      expect(find.text('Кузнецов Сергей Владимирович'), findsOneWidget);
      expect(find.text('Расписание преподавателя'), findsOneWidget);
    });

    testWidgets('TeacherScheduleScreen renders search prompt when opened empty', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: TeacherScheduleScreen(),
        ),
      );

      expect(find.text('Поиск по преподавателям'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
    });
  });
}
