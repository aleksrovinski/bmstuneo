import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:provider/provider.dart';
import 'package:bmstu_neo/models/schedule_lesson.dart';
import 'package:bmstu_neo/services/auth_storage.dart';
import 'package:bmstu_neo/services/bmstu_api_service.dart';
import 'package:bmstu_neo/providers/schedule_provider.dart';
import 'package:bmstu_neo/widgets/live_tracker_card.dart';

// Mock API service that simulates network failure
class FailingApiService extends BmstuApiService {
  @override
  Future<List<ScheduleLesson>> getGroupSchedule(String groupUuid) async {
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
      // 1. Arrange: legacy credentials stored in plaintext SharedPreferences
      SharedPreferences.setMockInitialValues({
        'bmstu_username': 'student_legacy',
        'bmstu_password': 'super_secret_password',
      });
      FlutterSecureStorage.setMockInitialValues({});

      final authStorage = AuthStorage();

      // 2. Act: read credentials
      final creds = await authStorage.getCredentials();

      // 3. Assert: correctly returned
      expect(creds['username'], 'student_legacy');
      expect(creds['password'], 'super_secret_password');

      // Assert: removed from legacy SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('bmstu_username'), isFalse);
      expect(prefs.containsKey('bmstu_password'), isFalse);

      // Assert: securely stored in FlutterSecureStorage
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

      // SharedPreferences must have zero credentials
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('bmstu_username'), isFalse);
      expect(prefs.containsKey('bmstu_password'), isFalse);

      // Secure storage must contain new values
      final creds = await authStorage.getCredentials();
      expect(creds['username'], 'fresh_student');
      expect(creds['password'], 'fresh_secure_pass');

      // Clear credentials
      await authStorage.clearCredentials();
      final cleared = await authStorage.getCredentials();
      expect(cleared['username'], isNull);
      expect(cleared['password'], isNull);
    });
  });

  group('ScheduleProvider Offline Caching', () {
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

      // Seed cache in SharedPreferences
      SharedPreferences.setMockInitialValues({
        'cached_sched_v1_$groupUuid': jsonEncode([cachedLesson.toJson()]),
        'cached_sched_time_v1_$groupUuid': DateTime.now().toIso8601String(),
      });

      final failingApi = FailingApiService();
      final provider = ScheduleProvider(apiService: failingApi);

      // Attempt loading schedule with network failure
      await provider.loadSchedule(groupUuid: groupUuid, groupTitle: 'ИУ7-31Б');

      // Lessons must be restored from cache
      expect(provider.allLessons.length, 1);
      expect(provider.allLessons.first.disciplineTitle, 'Информатика');

      // Sync status must indicate offline copy
      expect(provider.syncStatus, isNotNull);
      expect(provider.syncStatus!.isLive, isFalse);
      expect(provider.syncStatus!.message, contains('Офлайн'));
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
