import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:bmstu_neo/demo/demo_api_service.dart';
import 'package:bmstu_neo/demo/demo_data.dart';
import 'package:bmstu_neo/providers/auth_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({'bmstu_username': 'real', 'bmstu_password': 'secret'});
  });

  test('Signs in the demo student without touching saved credentials', () async {
    final auth = AuthProvider(apiService: DemoApiService(), authStorage: DemoAuthStorage());
    expect(await auth.checkSavedAuth(), isTrue);
    expect(auth.isFullAuth, isTrue);
    expect(auth.userProfile!.fullName, 'Иванов Алексей Сергеевич');

    await auth.logout();
    expect(auth.isAuthenticated, isFalse);
    // The real student's Keychain entries are still there
    expect(await const FlutterSecureStorage().read(key: 'bmstu_password'), 'secret');
  });

  test('During the day there is a pair in progress and one after it', () {
    final data = DemoData(DateTime(2026, 10, 27, 11, 47)); // Tuesday
    final today = data.schedule.where((l) => l.day == 2).toList()
      ..sort((a, b) => a.startTime.compareTo(b.startTime));
    expect(today.map((l) => '${l.startTime}-${l.endTime}'), ['09:25-11:00', '11:15-12:50', '13:05-14:40']);
    // The rest of the week stays as in a regular timetable
    expect(data.schedule.where((l) => l.day == 1), isNotEmpty);
  });

  test('Late at night today falls back to regular pairs', () {
    final today = DemoData(DateTime(2026, 10, 27, 23, 30)).schedule.where((l) => l.day == 2).toList();
    expect(today.map((l) => l.startTime), ['10:15', '12:00']);
  });

  test('Progress has scored modules and deadlines this week', () {
    final data = DemoData(DateTime(2026, 10, 27, 12));
    final week = data.week.weekNumber;
    final events = data.progress.expand((d) => [...d.controls, ...d.laboratory]).toList();

    expect(events.where((e) => e.type == 'М' && e.moduleScore != null), hasLength(4));
    expect(events.where((e) => e.week == week && e.isIssued), isNotEmpty);
  });
}
