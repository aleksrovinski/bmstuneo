import 'dart:async';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:bmstu_neo/models/user_profile.dart';
import 'package:bmstu_neo/services/auth_storage.dart';
import 'package:bmstu_neo/services/bmstu_api_service.dart';
import 'package:bmstu_neo/providers/auth_provider.dart';

const _scheduleUrl = '${BmstuApiService.apiBase}/schedules/current';

// Answers each request from a handler, standing in for the real HTTP client
class FakeAdapter implements HttpClientAdapter {
  final FutureOr<ResponseBody> Function(RequestOptions options) handler;
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

// Counts SSO logins and lets the test decide whether the session becomes valid
class CountingLoginApiService extends BmstuApiService {
  int loginCalls = 0;
  final Completer<void> release = Completer<void>();

  @override
  Future<UserProfile?> login(String username, String password) async {
    loginCalls++;
    await release.future;
    return UserProfile(
      lastName: 'Тестов',
      firstName: 'Иван',
      middleName: 'Петрович',
      groupTitle: 'ИУ7-43Б',
      groupUuid: 'test-group-uuid',
      stageUuid: 'test-stage-uuid',
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('API interceptor silent relogin', () {
    test('401 inside the relogin itself fails fast instead of deadlocking', () async {
      final api = BmstuApiService();
      // SSO pages never redirect back, every LKS API call (including /person) is 401
      api.httpClientAdapter = FakeAdapter((options) {
        final url = options.uri.toString();
        if (url.contains('/portal4/cookie/login')) {
          return ResponseBody.fromString('', 302, headers: {'location': ['https://sso.bmstu.ru/x']});
        }
        if (url.startsWith('https://sso.bmstu.ru/x')) {
          return ResponseBody.fromString('<form id="kc-form-login" action="https://sso.bmstu.ru/auth">', 200);
        }
        if (url.contains('sso.bmstu.ru/auth')) return ResponseBody.fromString('', 200);
        return ResponseBody.fromString('', 401);
      });
      api.onSilentRelogin = () async => (await api.login('u', 'p')) != null;

      await expectLater(
        api.dio.get(_scheduleUrl).timeout(const Duration(seconds: 3)),
        throwsA(isA<DioException>()
            .having((e) => e.response?.statusCode, 'statusCode', 401)),
      );
    });

    test('Concurrent 401s share a single relogin and all succeed after it', () async {
      var sessionValid = false;
      var reloginCalls = 0;

      final api = BmstuApiService();
      api.httpClientAdapter = FakeAdapter(
        (_) => ResponseBody.fromString('{}', sessionValid ? 200 : 401),
      );
      api.onSilentRelogin = () async {
        reloginCalls++;
        await Future<void>.delayed(const Duration(milliseconds: 20));
        sessionValid = true;
        return true;
      };

      final responses = await Future.wait(List.generate(3, (_) => api.dio.get(_scheduleUrl)));

      expect(reloginCalls, 1);
      expect(responses.map((r) => r.statusCode), everyElement(200));
    });

    test('Request is retried only once if the session is still rejected', () async {
      var requests = 0;
      var reloginCalls = 0;

      final api = BmstuApiService();
      api.httpClientAdapter = FakeAdapter((_) {
        requests++;
        return ResponseBody.fromString('', 401);
      });
      api.onSilentRelogin = () async {
        reloginCalls++;
        return true;
      };

      await expectLater(api.dio.get(_scheduleUrl), throwsA(isA<DioException>()));
      expect(reloginCalls, 1);
      expect(requests, 2);
    });

    test('Relogin that throws synchronously does not wedge later relogins', () async {
      var reloginCalls = 0;

      final api = BmstuApiService();
      api.httpClientAdapter = FakeAdapter((_) => ResponseBody.fromString('', 401));
      api.onSilentRelogin = () {
        reloginCalls++;
        throw StateError('no credentials');
      };

      await expectLater(api.dio.get(_scheduleUrl), throwsA(isA<DioException>()));
      await expectLater(api.dio.get(_scheduleUrl), throwsA(isA<DioException>()));
      expect(reloginCalls, 2);
    });

    test('Network errors do not trigger a relogin', () async {
      var reloginCalls = 0;

      final api = BmstuApiService();
      api.httpClientAdapter = FakeAdapter(
        (options) => throw DioException(requestOptions: options, type: DioExceptionType.connectionError),
      );
      api.onSilentRelogin = () async {
        reloginCalls++;
        return true;
      };

      await expectLater(api.dio.get(_scheduleUrl), throwsA(isA<DioException>()));
      expect(reloginCalls, 0);
    });
  });

  test('AuthProvider.reloginSilently runs one SSO login for concurrent callers', () async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({
      'bmstu_username': 'student',
      'bmstu_password': 'secret',
    });

    final api = CountingLoginApiService();
    final auth = AuthProvider(apiService: api, authStorage: AuthStorage());

    final results = Future.wait(List.generate(3, (_) => auth.reloginSilently()));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    api.release.complete();

    expect(await results, [true, true, true]);
    expect(api.loginCalls, 1);
    expect(auth.isFullAuth, isTrue);

    // Once finished, a later expiry triggers a fresh login
    await auth.reloginSilently();
    expect(api.loginCalls, 2);
  });
}
