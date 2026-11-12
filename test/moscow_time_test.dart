import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bmstu_neo/constants/moscow_time.dart';
import 'package:bmstu_neo/models/current_week.dart';
import 'package:bmstu_neo/models/schedule_lesson.dart';
import 'package:bmstu_neo/providers/schedule_provider.dart';
import 'package:bmstu_neo/services/bmstu_api_service.dart';

ScheduleLesson _lesson(int day, String start, String end) =>
    ScheduleLesson.fromJson({'day': day, 'startTime': start, 'endTime': end, 'disciplineTitle': 'Физика'});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() => MoscowTime.clock = DateTime.now);

  test('Moscow wall clock from any instant, and back', () {
    // 2026-11-12 23:30 UTC is already Friday 02:30 in Moscow
    final instant = DateTime.utc(2026, 11, 12, 23, 30);
    final msk = MoscowTime.of(instant);
    expect([msk.year, msk.month, msk.day, msk.hour, msk.minute], [2026, 11, 13, 2, 30]);
    expect(msk.weekday, DateTime.friday);
    expect(MoscowTime.instantOf(msk), instant);
  });

  test('Today and the current pair follow Moscow, not the phone', () {
    // Wednesday 10:00 in Moscow: 07:00 UTC, 17:00 in Vladivostok, 09:00 in Kaliningrad
    MoscowTime.clock = () => DateTime.utc(2026, 11, 11, 7, 0);
    final sched = ScheduleProvider(apiService: BmstuApiService());
    sched.lessonsForTest = [_lesson(3, '08:30', '10:00'), _lesson(3, '10:15', '11:50'), _lesson(4, '08:30', '10:00')];

    expect(sched.lessonsForToday.length, 2);
    expect(sched.tomorrowWeekday, DateTime.thursday);
    final status = sched.getLivePairStatus();
    expect(status.type, LivePairType.upcoming);
    expect(status.nextLesson?.startTime, '10:15');
  });

  test('The week number turns over on Monday in Moscow', () {
    // Sunday 22:30 UTC is Monday 01:30 in Moscow
    final sundayNight = MoscowTime.of(DateTime.utc(2026, 9, 13, 22, 30));
    final mondayWeek = CurrentWeek.defaultWeek(MoscowTime.of(DateTime.utc(2026, 9, 14, 6))).weekNumber;
    expect(CurrentWeek.defaultWeek(sundayNight).weekNumber, mondayWeek);
  });
}
