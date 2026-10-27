import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bmstu_neo/models/physical_culture.dart';
import 'package:bmstu_neo/models/session_result.dart';
import 'package:bmstu_neo/services/bmstu_api_service.dart';
import 'package:bmstu_neo/providers/fv_provider.dart';

// Answers each request from a handler, standing in for the real HTTP client
class FakeAdapter implements HttpClientAdapter {
  final ResponseBody Function(RequestOptions options) handler;
  FakeAdapter(this.handler);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async =>
      handler(options);

  @override
  void close({bool force = false}) {}
}

BmstuApiService _offlineApi() {
  final api = BmstuApiService();
  api.httpClientAdapter = FakeAdapter(
    (options) => throw DioException(requestOptions: options, type: DioExceptionType.connectionError),
  );
  return api;
}

final _networkError = throwsA(isA<BmstuNetworkException>());

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Network failures are reported instead of looking like empty data', () {
    test('Teacher schedule: offline is an error, not "no lessons"', () async {
      await expectLater(_offlineApi().getTeacherSchedule('teacher-uuid'), _networkError);
    });

    test('Teacher search: offline is an error, not "teacher not found"', () async {
      await expectLater(_offlineApi().searchTeachersOnline('Иванов'), _networkError);
    });

    test('Physical culture: offline is an error, not "no data"', () async {
      await expectLater(_offlineApi().getPhysicalCulture('stage-uuid'), _networkError);
    });
  });

  test('FvProvider shows cached PE data as offline when the network is down', () async {
    const stageUuid = 'stage-fv-1';
    final cached = PhysicalCultureData(studyPoints: 18, studyAttends: 8, groups: [], studyResults: []);
    SharedPreferences.setMockInitialValues({
      'cached_fv_v1_$stageUuid': jsonEncode(cached.toJson()),
      'cached_fv_time_v1_$stageUuid': DateTime(2026, 10, 20).toIso8601String(),
    });

    final fv = FvProvider(apiService: _offlineApi());
    await fv.loadFv(stageUuid);

    expect(fv.data?.studyPoints, 18);
    expect(fv.syncStatus?.isLive, isFalse, reason: 'offline must not be shown as fresh data');
    expect(fv.syncStatus?.message, contains('Офлайн'));
    expect(fv.errorMessage, isNull);
  });

  group('Session results', () {
    const cacheKey = 'bmstu_session_results_cache';
    final cachedSessions = [
      const SemesterSession(
        semesterTitle: 'Семестр 2',
        semesterNumber: 2,
        disciplines: [
          SessionDiscipline(title: 'Физика', department: 'ФН4', controlType: 'Экз', hours: 144, grade: 'Хорошо'),
        ],
      ),
    ];

    test('Refresh while offline falls back to the cached results', () async {
      SharedPreferences.setMockInitialValues({
        cacheKey: jsonEncode(cachedSessions.map((s) => s.toJson()).toList()),
      });

      final sessions = await _offlineApi().getSessionResults(stageUuid: 'stage-1', forceRefresh: true);

      expect(sessions, hasLength(1));
      expect(sessions.first.disciplines.first.grade, 'Хорошо');
    });

    test('Refresh while offline without a cache reports the network error', () async {
      SharedPreferences.setMockInitialValues({});
      await expectLater(
        _offlineApi().getSessionResults(stageUuid: 'stage-1', forceRefresh: true),
        _networkError,
      );
    });

    test('LKS answering with no results yet is an empty list, not an error', () async {
      SharedPreferences.setMockInitialValues({});
      final api = BmstuApiService();
      api.httpClientAdapter = FakeAdapter((options) {
        if (options.uri.path.endsWith('/sessions')) return ResponseBody.fromString('', 404);
        return ResponseBody.fromString('<html><body>Нет данных</body></html>', 200);
      });

      expect(await api.getSessionResults(stageUuid: 'stage-1', forceRefresh: true), isEmpty);
    });
  });
}
