import 'package:flutter_test/flutter_test.dart';
import 'package:bmstu_neo/models/current_week.dart';

void main() {
  group('Fallback academic week', () {
    test('Autumn: matches LKS for 22 October 2026 (week 8, denominator)', () {
      final w = CurrentWeek.defaultWeek(DateTime(2026, 10, 22));
      expect(w.weekNumber, 8);
      expect(w.isNumerator, isFalse);
      expect(w.term, 1);
      expect(w.semesterStarts, '2026-09-01');
    });

    test('Week 1 is the whole week containing September 1', () {
      // 1 Sep 2026 is a Tuesday; that Sunday is still week 1, the next Monday is week 2
      expect(CurrentWeek.defaultWeek(DateTime(2026, 9, 6)).weekNumber, 1);
      expect(CurrentWeek.defaultWeek(DateTime(2026, 9, 7)).weekNumber, 2);
      expect(CurrentWeek.defaultWeek(DateTime(2026, 9, 7)).isNumerator, isFalse);
    });

    test('Spring starts on the second Monday of February', () {
      // 2026: Feb 1 is a Sunday, so the second Monday is Feb 9
      final first = CurrentWeek.defaultWeek(DateTime(2026, 2, 9));
      expect(first.semesterStarts, '2026-02-09');
      expect(first.weekNumber, 1);
      expect(first.isNumerator, isTrue);
      expect(first.term, 2);
      expect(CurrentWeek.defaultWeek(DateTime(2026, 3, 2)).weekNumber, 4);
    });

    test('January belongs to the autumn semester of the previous year', () {
      final w = CurrentWeek.defaultWeek(DateTime(2027, 1, 12));
      expect(w.semesterStarts, '2026-09-01');
      expect(w.term, 1);
      expect(w.weekNumber, 17, reason: 'clamped to the 17-week semester');
    });

    test('Missing LKS fields use the estimate instead of a hard-coded year', () {
      final w = CurrentWeek.fromJson({'weekNumber': 5, 'weekShortName': 'чс', 'weekName': 'числитель'});
      expect(w.weekNumber, 5);
      expect(w.semesterStarts, matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')));
    });
  });
}
