import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bmstu_neo/models/homework_note.dart';
import 'package:bmstu_neo/models/schedule_lesson.dart';
import 'package:bmstu_neo/providers/homework_provider.dart';
import 'package:bmstu_neo/widgets/homework_sheet.dart';

ScheduleLesson _pair(int day, String start, {String week = 'all', String title = 'Физика'}) => ScheduleLesson(
      day: day,
      time: 2,
      startTime: start,
      endTime: '11:50',
      week: week,
      disciplineTitle: title,
      actType: 'seminar',
      audiences: const [],
      teachers: const [],
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Next pair of a discipline', () {
    // Tuesday 27 Oct 2026, a numerator week
    final now = DateTime(2026, 10, 27, 12, 0);

    test('Later today if the pair is still ahead, otherwise its next day', () {
      final lessons = [_pair(2, '13:50'), _pair(4, '10:15')];
      expect(nextPairOf('Физика', lessons, currentWeekIsNumerator: true, now: now)!.start, DateTime(2026, 10, 27, 13, 50));
      expect(nextPairOf('Физика', [_pair(2, '10:15'), _pair(4, '10:15')], currentWeekIsNumerator: true, now: now)!.start,
          DateTime(2026, 10, 29, 10, 15));
    });

    test('A denominator-only pair is found in next week', () {
      final lessons = [_pair(1, '08:30', week: 'zn')];
      // Monday 2 Nov starts the denominator week
      expect(nextPairOf('Физика', lessons, currentWeekIsNumerator: true, now: now)!.start, DateTime(2026, 11, 2, 8, 30));
      // In a denominator week the same pair is two weeks away
      expect(nextPairOf('Физика', lessons, currentWeekIsNumerator: false, now: now)!.start, DateTime(2026, 11, 9, 8, 30));
    });

    test('No pairs of the discipline: null', () {
      expect(nextPairOf('Химия', [_pair(2, '13:50')], currentWeekIsNumerator: true, now: now), isNull);
    });
  });

  group('HomeworkProvider', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('Notes survive a restart, pending ones soonest first', () async {
      final first = HomeworkProvider();
      await Future<void>.delayed(Duration.zero);
      await first.add(disciplineTitle: 'Физика', text: ' Задачи 3.14 ', kind: HomeworkKind.quick, due: DateTime(2026, 11, 3, 10, 15));
      final long = await first.add(
          disciplineTitle: 'Инженерная графика', text: 'Чертёж А3', kind: HomeworkKind.long, due: DateTime(2026, 11, 1, 23, 59));
      await first.setDone(long, true);

      final second = HomeworkProvider();
      await Future<void>.delayed(Duration.zero);
      expect(second.pending.map((n) => n.text), ['Задачи 3.14']);
      expect(second.done.single.disciplineTitle, 'Инженерная графика');
    });

    test('Old done notes are dropped, deleted ones can be restored', () async {
      final now = DateTime(2026, 11, 20);
      SharedPreferences.setMockInitialValues({});
      final seed = [
        HomeworkNote(id: 'a', disciplineTitle: 'Физика', text: 'old', kind: HomeworkKind.quick,
            due: DateTime(2026, 10, 1), done: true, createdAt: DateTime(2026, 9, 30)),
        HomeworkNote(id: 'b', disciplineTitle: 'Физика', text: 'new', kind: HomeworkKind.quick,
            due: DateTime(2026, 11, 25), createdAt: DateTime(2026, 11, 19)),
      ];
      final homework = HomeworkProvider(clock: () => now, seed: seed);
      await Future<void>.delayed(Duration.zero);
      expect(homework.done, isEmpty);

      final note = homework.pending.single;
      await homework.remove(note);
      expect(homework.pending, isEmpty);
      await homework.restore(note);
      expect(homework.pending.single.text, 'new');
    });

    String stored(List<String> texts) => jsonEncode([
          for (final (i, t) in texts.indexed)
            HomeworkNote(id: 's$i', disciplineTitle: 'Физика', text: t, kind: HomeworkKind.long,
                    due: DateTime(2026, 12, 1), createdAt: DateTime(2026, 11, 1))
                .toJson(),
        ]);

    test('A note added right at launch does not replace the stored ones', () async {
      SharedPreferences.setMockInitialValues({'homework_notes_v1': stored(['первое', 'второе'])});
      final homework = HomeworkProvider();
      // No wait for loading: the student adds a note at once
      await homework.add(disciplineTitle: 'Физика', text: 'новое', kind: HomeworkKind.long, due: DateTime(2026, 12, 2));

      final restarted = HomeworkProvider();
      await Future<void>.delayed(Duration.zero);
      expect(restarted.pending.map((n) => n.text), containsAll(['первое', 'второе', 'новое']));
    });

    test('An unreadable note is kept aside, the others still load', () async {
      final raw = '[${stored(['целое']).substring(1, stored(['целое']).length - 1)},{"id":"bad"}]';
      SharedPreferences.setMockInitialValues({'homework_notes_v1': raw});
      final homework = HomeworkProvider();
      await Future<void>.delayed(Duration.zero);
      expect(homework.pending.single.text, 'целое');

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(HomeworkProvider.backupKey), raw);
    });
  });

  test('Quick homework shows on its own pair only, long on the deadline day', () {
    final day = DateTime(2026, 11, 2);
    final lecture = _pair(1, '08:30');
    final seminar = _pair(1, '10:15');
    HomeworkNote note(HomeworkKind kind, DateTime due) =>
        HomeworkNote(id: 'x', disciplineTitle: 'Физика', text: 't', kind: kind, due: due, createdAt: day);

    final quick = note(HomeworkKind.quick, DateTime(2026, 11, 2, 8, 30));
    expect(quick.isFor(lecture, day), isTrue);
    expect(quick.isFor(seminar, day), isFalse);
    expect(quick.isFor(lecture, DateTime(2026, 11, 9)), isFalse);
    expect(note(HomeworkKind.long, DateTime(2026, 11, 2, 23, 59)).isFor(seminar, day), isTrue);
  });

  test('Due labels', () {
    final now = DateTime(2026, 10, 27, 12);
    HomeworkNote note(HomeworkKind kind, DateTime due) =>
        HomeworkNote(id: 'x', disciplineTitle: 'Физика', text: 't', kind: kind, due: due, createdAt: now);

    expect(homeworkDueLabel(note(HomeworkKind.quick, DateTime(2026, 10, 28, 10, 15)), now), 'К паре · завтра, 10:15');
    expect(homeworkDueLabel(note(HomeworkKind.long, DateTime(2026, 11, 5, 23, 59)), now), 'Срок · чт, 5 нояб.');
    expect(homeworkDueLabel(note(HomeworkKind.quick, DateTime(2026, 10, 26, 10, 15)), now), 'Просрочено · вчера');
  });
}
