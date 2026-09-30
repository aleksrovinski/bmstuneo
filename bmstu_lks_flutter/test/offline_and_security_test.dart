import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:provider/provider.dart';
import 'package:bmstu_neo/models/schedule_lesson.dart';
import 'package:bmstu_neo/models/user_profile.dart';
import 'package:bmstu_neo/models/current_week.dart';
import 'package:bmstu_neo/models/discipline_progress.dart';
import 'package:bmstu_neo/models/physical_culture.dart';
import 'package:bmstu_neo/services/auth_storage.dart';
import 'package:bmstu_neo/services/bmstu_api_service.dart';
import 'package:bmstu_neo/providers/auth_provider.dart';
import 'package:bmstu_neo/providers/schedule_provider.dart';
import 'package:bmstu_neo/providers/progress_provider.dart';
import 'package:bmstu_neo/providers/fv_provider.dart';
import 'package:bmstu_neo/widgets/live_tracker_card.dart';
import 'package:bmstu_neo/widgets/offline_status_banner.dart';

// Mock API service that simulates network failure
class FailingApiService extends BmstuApiService {
  @override
  Future<UserProfile?> login(String username, String password) async {
    throw Exception('Сетевой сбой: нет подключения к серверу МГТУ');
  }

  @override
  Future<CurrentWeek?> getCurrentWeek({bool fallbackToDefault = true}) async {
    throw Exception('Сетевой сбой: нет подключения к серверу МГТУ');
  }

  @override
  Future<List<ScheduleLesson>> getGroupSchedule(String groupUuid) async {
    throw Exception('Сетевой сбой: нет подключения к серверу МГТУ');
  }

  @override
  Future<List<DisciplineProgress>> getProgress(String stageUuid) async {
    throw Exception('Сетевой сбой: нет подключения к серверу МГТУ');
  }

  @override
  Future<PhysicalCultureData?> getPhysicalCulture(String stageUuid) async {
    throw Exception('Сетевой сбой: нет подключения к серверу МГТУ');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ScheduleLesson JSON Serialization', () {
    test('toJson and fromJson preserves all lesson properties and relations', () {
      final lesson = ScheduleLesson(
        day: 2,
        time: 3,
        startTime: '12:00',
        endTime: '13:35',
        week: 'ch',
        disciplineTitle: 'Вычислительная математика',
        actType: 'lecture',
        audiences: [
          ScheduleAudience(name: '423', building: 'ГУК', uuid: 'aud-423'),
        ],
        teachers: [
          ScheduleTeacher(
            firstName: 'Иван',
            lastName: 'Иванов',
            middleName: 'Иванович',
            uuid: 'teach-1',
          ),
        ],
        streamName: 'ИУ7-31Б; ИУ7-32Б',
        isStream: true,
      );

      final json = lesson.toJson();
      final restored = ScheduleLesson.fromJson(json);

      expect(restored.day, 2);
      expect(restored.time, 3);
      expect(restored.startTime, '12:00');
      expect(restored.endTime, '13:35');
      expect(restored.week, 'ch');
      expect(restored.isNumerator, isTrue);
      expect(restored.disciplineTitle, 'Вычислительная математика');
      expect(restored.actTypeTitle, 'Лекция');
      expect(restored.audiences.length, 1);
      expect(restored.audiences.first.formattedText, '423 (ГУК)');
      expect(restored.teachers.length, 1);
      expect(restored.teachers.first.formattedName, 'Иванов И.И.');
      expect(restored.isStream, isTrue);
      expect(restored.streamName, 'ИУ7-31Б; ИУ7-32Б');
    });
  });

  group('AuthStorage Security & Migration', () {
    test('Migrates legacy plaintext credentials from SharedPreferences to FlutterSecureStorage', () async {
      SharedPreferences.setMockInitialValues({
        'bmstu_username': 'student_legacy',
        'bmstu_password': 'super_secret_password',
      });
      FlutterSecureStorage.setMockInitialValues({});

      final authStorage = AuthStorage();
      final creds = await authStorage.getCredentials();

      expect(creds['username'], 'student_legacy');
      expect(creds['password'], 'super_secret_password');

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('bmstu_username'), isFalse);
      expect(prefs.containsKey('bmstu_password'), isFalse);

      const secureStorage = FlutterSecureStorage();
      final secureUser = await secureStorage.read(key: 'bmstu_username');
      final securePass = await secureStorage.read(key: 'bmstu_password');
      expect(secureUser, 'student_legacy');
      expect(securePass, 'super_secret_password');
    });

    test('saveCredentials writes to secure storage and wipes any plaintext traces', () async {
      SharedPreferences.setMockInitialValues({
        'bmstu_username': 'old_plain',
        'bmstu_password': 'old_pass',
      });
      FlutterSecureStorage.setMockInitialValues({});

      final authStorage = AuthStorage();
      await authStorage.saveCredentials('fresh_student', 'fresh_secure_pass');

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('bmstu_username'), isFalse);
      expect(prefs.containsKey('bmstu_password'), isFalse);

      final creds = await authStorage.getCredentials();
      expect(creds['username'], 'fresh_student');
      expect(creds['password'], 'fresh_secure_pass');

      await authStorage.clearCredentials();
      final cleared = await authStorage.getCredentials();
      expect(cleared['username'], isNull);
      expect(cleared['password'], isNull);
    });
  });

  group('AuthProvider Offline Authentication & Persistence', () {
    test('Restores cached user profile offline when network fails', () async {
      final sampleProfile = UserProfile(
        lastName: 'Тестов',
        firstName: 'Иван',
        middleName: 'Петрович',
        groupTitle: 'ИУ7-43Б',
        groupUuid: 'test-group-uuid',
        stageUuid: 'test-stage-uuid',
      );

      SharedPreferences.setMockInitialValues({
        'bmstu_cached_user_profile_v1': jsonEncode(sampleProfile.toJson()),
      });
      FlutterSecureStorage.setMockInitialValues({
        'bmstu_username': 'test_student',
        'bmstu_password': 'test_password',
      });

      final failingApi = FailingApiService();
      final authStorage = AuthStorage();
      final authProvider = AuthProvider(apiService: failingApi, authStorage: authStorage);

      final isAuthed = await authProvider.checkSavedAuth();

      expect(isAuthed, isTrue);
      expect(authProvider.isAuthenticated, isTrue);
      expect(authProvider.isFullAuth, isTrue);
      expect(authProvider.userProfile?.lastName, 'Тестов');
      expect(authProvider.currentGroupTitle, 'ИУ7-43Б');
    });

    test('Restores guest mode offline from SharedPreferences', () async {
      SharedPreferences.setMockInitialValues({
        'bmstu_is_guest_v1': true,
        'bmstu_guest_group_title_v1': 'РК6-51',
        'bmstu_guest_group_uuid_v1': 'uuid-rk6-51',
      });
      FlutterSecureStorage.setMockInitialValues({});

      final failingApi = FailingApiService();
      final authStorage = AuthStorage();
      final authProvider = AuthProvider(apiService: failingApi, authStorage: authStorage);

      final isAuthed = await authProvider.checkSavedAuth();

      expect(isAuthed, isTrue);
      expect(authProvider.isGuest, isTrue);
      expect(authProvider.isAuthenticated, isTrue);
      expect(authProvider.currentGroupTitle, 'РК6-51');
      expect(authProvider.currentGroupUuid, 'uuid-rk6-51');
    });
  });

  group('ScheduleProvider Offline Caching & Week Calculation', () {
    test('Loads cached schedule when network request fails and marks syncStatus as offline', () async {
      const groupUuid = 'test-group-iu7';
      final cachedLesson = ScheduleLesson(
        day: 1,
        time: 1,
        startTime: '08:30',
        endTime: '10:05',
        week: 'all',
        disciplineTitle: 'Информатика',
        actType: 'lecture',
        audiences: [ScheduleAudience(name: '323', building: 'ГУК')],
        teachers: [],
      );

      SharedPreferences.setMockInitialValues({
        'cached_sched_v1_$groupUuid': jsonEncode([cachedLesson.toJson()]),
        'cached_sched_time_v1_$groupUuid': DateTime.now().toIso8601String(),
      });

      final failingApi = FailingApiService();
      final provider = ScheduleProvider(apiService: failingApi);

      await provider.loadSchedule(groupUuid: groupUuid, groupTitle: 'ИУ7-31Б');

      expect(provider.allLessons.length, 1);
      expect(provider.allLessons.first.disciplineTitle, 'Информатика');
      expect(provider.syncStatus, isNotNull);
      expect(provider.syncStatus!.isLive, isFalse);
      expect(provider.syncStatus!.message, contains('Офлайн'));
    });

    test('Computes current week progression correctly from cached week and elapsed time', () async {
      // Cached week 3, numerator (ch), saved 14 days ago (2 weeks ago)
      final pastDate = DateTime.now().subtract(const Duration(days: 14));
      final cachedWeek = CurrentWeek(
        weekNumber: 3,
        weekName: 'числитель',
        weekShortName: 'чс',
        term: 1,
        semesterStarts: '2026-09-01',
        semesterEnds: '2027-01-05',
      );

      SharedPreferences.setMockInitialValues({
        'bmstu_cached_current_week_v1': jsonEncode(cachedWeek.toJson()),
        'bmstu_cached_current_week_time_v1': pastDate.toIso8601String(),
      });

      final failingApi = FailingApiService();
      final provider = ScheduleProvider(apiService: failingApi);

      await provider.loadSchedule(groupUuid: 'some-uuid', groupTitle: 'ИУ7');

      // 2 weeks passed -> weekNumber should advance by 2 (3 + 2 = 5), parity remains numerator
      expect(provider.currentWeek, isNotNull);
      expect(provider.currentWeek!.weekNumber, 5);
      expect(provider.currentWeek!.isNumerator, isTrue);
    });
  });

  group('ProgressProvider Offline Caching', () {
    test('Loads cached progress when offline and sets syncStatus to offline', () async {
      const stageUuid = 'test-stage-progress-1';
      final sampleDiscipline = DisciplineProgress(
        title: 'Базы данных',
        disciplineUuid: 'db-uuid-1',
        points: {'point_all': 100},
        controls: [
          ControlEvent(
            type: 'РК',
            title: 'РК-1',
            week: 7,
            disciplineTitle: 'Базы данных',
            controlIndex: 1,
            stage: '2', // Выполнено
          ),
        ],
      );

      SharedPreferences.setMockInitialValues({
        'cached_progress_v1_$stageUuid': jsonEncode([sampleDiscipline.toJson()]),
        'cached_progress_time_v1_$stageUuid': DateTime.now().toIso8601String(),
      });

      final failingApi = FailingApiService();
      final prog = ProgressProvider(apiService: failingApi);

      await prog.loadProgress(stageUuid);

      expect(prog.disciplines.length, 1);
      expect(prog.disciplines.first.title, 'Базы данных');
      expect(prog.disciplines.first.controls.length, 1);
      expect(prog.disciplines.first.controls.first.isSubmitted, isTrue);
      expect(prog.errorMessage, isNull);
      expect(prog.syncStatus, isNotNull);
      expect(prog.syncStatus!.isLive, isFalse);
      expect(prog.syncStatus!.message, contains('Офлайн'));
    });
  });

  group('FvProvider Offline Caching', () {
    test('Loads cached physical culture data offline and sets syncStatus to offline', () async {
      const stageUuid = 'test-stage-fv-1';
      final sampleFv = PhysicalCultureData(
        studyPoints: 45,
        studyAttends: 18,
        medGroup: 'Спец. А',
        groups: [
          FvRecord(
            id: 'rec-1',
            weekDay: 'Вторник',
            time: '12:00',
            teacherName: 'Сидоров А.А.',
            section: 'Плавание',
            place: 'Бассейн СК',
          ),
        ],
        studyResults: [
          FvTermHistory(term: '1 семестр', points: 60, attend: 25),
        ],
      );

      SharedPreferences.setMockInitialValues({
        'cached_fv_v1_$stageUuid': jsonEncode(sampleFv.toJson()),
        'cached_fv_time_v1_$stageUuid': DateTime.now().toIso8601String(),
      });

      final failingApi = FailingApiService();
      final fv = FvProvider(apiService: failingApi);

      await fv.loadFv(stageUuid);

      expect(fv.data, isNotNull);
      expect(fv.studyPoints, 45);
      expect(fv.studyAttends, 18);
      expect(fv.medGroup, 'Спец. А');
      expect(fv.currentRecords.length, 1);
      expect(fv.currentRecords.first.section, 'Плавание');
      expect(fv.errorMessage, isNull);
      expect(fv.syncStatus, isNotNull);
      expect(fv.syncStatus!.isLive, isFalse);
      expect(fv.syncStatus!.message, contains('Офлайн'));
    });
  });

  group('OfflineStatusBanner Widget', () {
    testWidgets('Renders properly with custom offline message and timestamp', (tester) async {
      final now = DateTime(2026, 9, 30, 10, 30);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OfflineStatusBanner(
              message: 'Офлайн-режим (сохранённая копия)',
              lastUpdated: now,
            ),
          ),
        ),
      );

      expect(find.byType(OfflineStatusBanner), findsOneWidget);
      expect(find.byIcon(Icons.cloud_off_rounded), findsOneWidget);
      expect(find.text('Офлайн-режим (сохранённая копия)'), findsOneWidget);
      expect(find.textContaining('30.09 в 10:30'), findsOneWidget);
    });
  });

  group('LiveTrackerCard Widget', () {
    testWidgets('Renders properly without errors and displays live status', (tester) async {
      final failingApi = FailingApiService();
      final provider = ScheduleProvider(apiService: failingApi);

      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<ScheduleProvider>.value(
            value: provider,
            child: const Scaffold(
              body: LiveTrackerCard(),
            ),
          ),
        ),
      );

      expect(find.byType(LiveTrackerCard), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_outline_rounded), findsOneWidget);
    });
  });
}
