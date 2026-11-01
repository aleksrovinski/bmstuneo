import 'package:cookie_jar/cookie_jar.dart';
import '../models/current_week.dart';
import '../models/discipline_progress.dart';
import '../models/physical_culture.dart';
import '../models/schedule_lesson.dart';
import '../models/session_result.dart';
import '../models/user_profile.dart';
import '../services/auth_storage.dart';
import '../services/bmstu_api_service.dart';
import '../services/bmstu_groups_catalog.dart';
import 'demo_data.dart';

/// LKS stand-in for the demo build: answers every request from [DemoData] and never
/// touches the network. Any login succeeds and signs in the demo student.
class DemoApiService extends BmstuApiService {
  DemoApiService() : super(cookieJar: CookieJar());

  // Fresh data on every call: "today" and the current week follow the clock
  DemoData get _data => DemoData();
  bool _signedIn = false;

  // A short pause makes loading states visible, as with the real LKS
  Future<T> _reply<T>(T value) => Future.delayed(const Duration(milliseconds: 250), () => value);

  @override
  bool get isAuthenticated => _signedIn;

  @override
  Future<UserProfile?> login(String username, String password) {
    _signedIn = true;
    return _reply(_data.profile);
  }

  @override
  Future<UserProfile?> restoreSession() => _reply(_signedIn ? _data.profile : null);

  @override
  Future<UserProfile?> fetchUserProfile() => _reply(_signedIn ? _data.profile : null);

  @override
  Future<void> clearSession() async => _signedIn = false;

  @override
  Future<CurrentWeek?> getCurrentWeek({bool fallbackToDefault = true}) => _reply(_data.week);

  @override
  Future<List<ScheduleLesson>> getGroupSchedule(String groupUuid) => _reply(_data.schedule);

  @override
  Future<List<ScheduleLesson>> getTeacherSchedule(String teacherUuid) =>
      _reply(_data.scheduleOfTeacher(teacherUuid));

  @override
  Future<List<TeacherSearchItem>> searchTeachersOnline(String query) {
    final q = query.trim().toLowerCase();
    return _reply([
      for (final t in DemoData.teachers)
        if (q.isEmpty || '${t.lastName} ${t.firstName} ${t.middleName}'.toLowerCase().contains(q))
          TeacherSearchItem(title: '${t.lastName} ${t.firstName} ${t.middleName}', uuid: t.uuid!),
    ]);
  }

  @override
  Future<List<DisciplineProgress>> getProgress(String stageUuid) => _reply(_data.progress);

  @override
  Future<PhysicalCultureData?> getPhysicalCulture(String stageUuid) => _reply(_data.physicalCulture);

  @override
  Future<List<SemesterSession>> getSessionResults({String? stageUuid, bool forceRefresh = false}) =>
      _reply(_data.sessions);

  // The bundled catalog is enough; nothing to download
  @override
  Future<List<GroupItem>> fetchGroupsCatalog() async => const [];
}

/// Credentials for the demo student, kept in memory only: the demo never reads or
/// overwrites the real Keychain / Keystore entries.
class DemoAuthStorage extends AuthStorage {
  bool _cleared = false;

  @override
  Future<void> saveCredentials(String username, String password) async => _cleared = false;

  @override
  Future<Map<String, String?>> getCredentials() async =>
      _cleared ? {'username': null, 'password': null} : {'username': 'demo', 'password': 'demo'};

  @override
  Future<void> clearCredentials() async => _cleared = true;
}
