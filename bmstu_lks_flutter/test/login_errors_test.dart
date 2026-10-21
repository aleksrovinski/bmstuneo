import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:bmstu_neo/services/auth_storage.dart';
import 'package:bmstu_neo/services/bmstu_api_service.dart';
import 'package:bmstu_neo/providers/auth_provider.dart';

const _ssoUrl = 'https://sso.bmstu.ru/realms/bmstu/login';
const _ssoHtml = '<form id="kc-form-login" action="https://sso.bmstu.ru/realms/bmstu/authenticate?x=1&amp;y=2">';

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

ResponseBody _text(String body, int status, {Map<String, List<String>> headers = const {}}) =>
    ResponseBody.fromString(body, status, headers: headers);

ResponseBody _json(Object body, int status) => ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );

// Login page redirects to SSO, SSO accepts the credentials, then [api] answers LKS API calls
ResponseBody Function(RequestOptions) _ssoFlowThen(ResponseBody Function(RequestOptions) api) {
  return (options) {
    final url = options.uri.toString();
    if (url.contains('/portal4/cookie/login')) {
      return _text('', 302, headers: {'location': [_ssoUrl]});
    }
    if (url.startsWith(_ssoUrl)) return _text(_ssoHtml, 200);
    if (url.contains('/authenticate')) {
      return _text('', 302, headers: {'location': ['https://lks.bmstu.ru/portal4/upstream/callback/kc?code=1']});
    }
    if (url.contains('/callback/kc')) return _text('', 302);
    return api(options);
  };
}

BmstuApiService _apiWith(ResponseBody Function(RequestOptions) handler) {
  final api = BmstuApiService();
  api.dio.httpClientAdapter = FakeAdapter(handler);
  return api;
}

BmstuApiService _apiThrowing(DioExceptionType type) {
  final api = BmstuApiService();
  api.dio.httpClientAdapter = FakeAdapter(
    (options) => throw DioException(requestOptions: options, type: type),
  );
  return api;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Login distinguishes network failures from bad credentials', () {
    test('No connection is reported as a network error', () async {
      final api = _apiThrowing(DioExceptionType.connectionError);
      await expectLater(
        api.login('student', 'secret'),
        throwsA(isA<BmstuNetworkException>()
            .having((e) => e.message, 'message', contains('Нет подключения'))),
      );
      expect(api.isAuthenticated, isFalse);
    });

    test('Timeout is reported as server not responding', () async {
      final api = _apiThrowing(DioExceptionType.receiveTimeout);
      await expectLater(
        api.login('student', 'secret'),
        throwsA(isA<BmstuNetworkException>()
            .having((e) => e.message, 'message', contains('не отвечает'))),
      );
    });

    test('5xx from LKS is reported as server unavailable with status code', () async {
      final api = _apiWith((_) => _text('Bad Gateway', 502));
      await expectLater(
        api.login('student', 'secret'),
        throwsA(isA<BmstuNetworkException>()
            .having((e) => e.message, 'message', contains('код 502'))),
      );
    });

    test('Network failure while loading the profile is not reported as wrong password', () async {
      final api = _apiWith(_ssoFlowThen(
        (options) => throw DioException(requestOptions: options, type: DioExceptionType.connectionError),
      ));
      await expectLater(api.login('student', 'secret'), throwsA(isA<BmstuNetworkException>()));
    });

    test('Keycloak error page is still reported as wrong credentials', () async {
      final api = _apiWith((options) {
        final url = options.uri.toString();
        if (url.contains('/portal4/cookie/login')) {
          return _text('', 302, headers: {'location': [_ssoUrl]});
        }
        if (url.startsWith(_ssoUrl)) return _text(_ssoHtml, 200);
        return _text('<span id="kc-feedback-text">Неверное имя пользователя или пароль</span>', 200);
      });
      await expectLater(
        api.login('student', 'wrong'),
        throwsA(predicate((e) =>
            e is! BmstuNetworkException && e.toString().contains('Неверный логин или пароль'))),
      );
    });

    test('Successful SSO flow returns the profile', () async {
      final api = _apiWith(_ssoFlowThen((options) {
        final path = options.uri.path;
        if (path.endsWith('/person')) {
          return _json({'data': {'firstName': 'Иван', 'lastName': 'Тестов', 'uuid': 'p-1'}}, 200);
        }
        if (path.endsWith('/student')) {
          return _json({
            'data': {
              'stages': [
                {
                  'uuid': 'stage-1',
                  'group': {'title': 'ИУ7-43Б', 'uuid': 'group-1', 'semester': 4},
                },
              ],
            },
          }, 200);
        }
        return _json({}, 404);
      }));

      final profile = await api.login('student', 'secret');
      expect(profile?.lastName, 'Тестов');
      expect(profile?.groupTitle, 'ИУ7-43Б');
      expect(api.isAuthenticated, isTrue);
    });
  });

  test('AuthProvider shows the network message instead of wrong password', () async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});

    final auth = AuthProvider(
      apiService: _apiThrowing(DioExceptionType.connectionError),
      authStorage: AuthStorage(),
    );
    final ok = await auth.login('student', 'secret');

    expect(ok, isFalse);
    expect(auth.errorMessage, 'Нет подключения к серверу МГТУ. Проверьте интернет');
  });
}
