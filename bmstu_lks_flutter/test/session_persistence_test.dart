import 'dart:convert';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:bmstu_neo/models/user_profile.dart';
import 'package:bmstu_neo/providers/auth_provider.dart';
import 'package:bmstu_neo/services/auth_storage.dart';
import 'package:bmstu_neo/services/bmstu_api_service.dart';
import 'package:bmstu_neo/services/secure_cookie_storage.dart';

UserProfile _profile(String group) => UserProfile(
      lastName: 'Тестов',
      firstName: 'Иван',
      middleName: 'Петрович',
      groupTitle: group,
      groupUuid: 'group-uuid',
      stageUuid: 'stage-uuid',
    );

// Scripted LKS: what the saved session check and the SSO login return
class ScriptedApi extends BmstuApiService {
  Future<UserProfile?> Function() onRestore;
  Future<UserProfile?> Function() onLogin;
  int restoreCalls = 0;
  int loginCalls = 0;

  ScriptedApi({required this.onRestore, required this.onLogin});

  @override
  Future<UserProfile?> restoreSession() {
    restoreCalls++;
    return onRestore();
  }

  @override
  Future<UserProfile?> login(String username, String password) {
    loginCalls++;
    return onLogin();
  }
}

void _cachedProfile({bool withCredentials = true}) {
  SharedPreferences.setMockInitialValues({
    'bmstu_cached_user_profile_v1': jsonEncode(_profile('РК5-32Б').toJson()),
  });
  FlutterSecureStorage.setMockInitialValues(
    withCredentials ? {'bmstu_username': 'student', 'bmstu_password': 'secret'} : {},
  );
}

Future<AuthProvider> _start(ScriptedApi api) async {
  final auth = AuthProvider(apiService: api, authStorage: AuthStorage());
  expect(await auth.checkSavedAuth(), isTrue);
  // Session resume runs in the background after the app is shown
  await Future<void>.delayed(const Duration(milliseconds: 20));
  return auth;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Session cookies survive an app restart in secure storage', () async {
    FlutterSecureStorage.setMockInitialValues({});
    final uri = Uri.parse('https://lks.bmstu.ru/lks-back/api/v1/person');

    final jar = PersistCookieJar(storage: SecureCookieStorage());
    await jar.saveFromResponse(uri, [Cookie('JSESSIONID', 'abc123')]);

    // A new jar = the next launch
    final restarted = PersistCookieJar(storage: SecureCookieStorage());
    final cookies = await restarted.loadForRequest(uri);
    expect(cookies.map((c) => '${c.name}=${c.value}'), contains('JSESSIONID=abc123'));

    await restarted.deleteAll();
    expect(await PersistCookieJar(storage: SecureCookieStorage()).loadForRequest(uri), isEmpty);
  });

  group('Startup with a cached profile', () {
    test('A valid saved session is resumed without sending the password', () async {
      _cachedProfile();
      final api = ScriptedApi(onRestore: () async => _profile('РК5-42Б'), onLogin: () async => _profile('x'));

      final auth = await _start(api);

      expect(api.restoreCalls, 1);
      expect(api.loginCalls, 0);
      expect(auth.userProfile?.groupTitle, 'РК5-42Б', reason: 'profile refreshed from LKS');
      expect(auth.needsLogin, isFalse);
    });

    test('An expired session falls back to a silent login and bumps the session generation', () async {
      _cachedProfile();
      final api = ScriptedApi(onRestore: () async => null, onLogin: () async => _profile('РК5-32Б'));

      final auth = await _start(api);

      expect(api.loginCalls, 1);
      expect(auth.needsLogin, isFalse);
      expect(auth.sessionGeneration, 1);
    });

    test('Expired session and no saved password: the student is asked to sign in', () async {
      _cachedProfile(withCredentials: false);
      final api = ScriptedApi(onRestore: () async => null, onLogin: () async => _profile('x'));

      final auth = await _start(api);

      expect(api.loginCalls, 0);
      expect(auth.isFullAuth, isTrue, reason: 'cached data stays on screen');
      expect(auth.needsLogin, isTrue);
    });

    test('LKS rejecting the saved password asks for a new login', () async {
      _cachedProfile();
      final api = ScriptedApi(
        onRestore: () async => null,
        onLogin: () async => throw Exception('Неверный логин или пароль студента'),
      );

      expect((await _start(api)).needsLogin, isTrue);
    });

    test('Being offline is not a reason to ask for the password', () async {
      _cachedProfile();
      final api = ScriptedApi(
        onRestore: () async => throw BmstuNetworkException('Нет подключения к серверу МГТУ. Проверьте интернет'),
        onLogin: () async => throw BmstuNetworkException('Нет подключения'),
      );

      final auth = await _start(api);
      expect(api.loginCalls, 0);
      expect(auth.needsLogin, isFalse);

      // A later relogin that also fails offline doesn't flag it either
      expect(await auth.reloginSilently(), isFalse);
      expect(auth.needsLogin, isFalse);
    });
  });

  test('Signing in again clears the flag and starts a new session generation', () async {
    _cachedProfile(withCredentials: false);
    final api = ScriptedApi(onRestore: () async => null, onLogin: () async => _profile('РК5-32Б'));
    final auth = await _start(api);
    expect(auth.needsLogin, isTrue);

    expect(await auth.login('student', 'secret'), isTrue);
    expect(auth.needsLogin, isFalse);
    expect(auth.sessionGeneration, 1);
  });

  test('Logout forgets the saved session cookies', () async {
    _cachedProfile();
    final uri = Uri.parse('https://lks.bmstu.ru/');
    final jar = CookieJar();
    await jar.saveFromResponse(uri, [Cookie('JSESSIONID', 'abc')]);
    final api = BmstuApiService(cookieJar: jar);
    final auth = AuthProvider(apiService: api, authStorage: AuthStorage());

    await auth.logout();
    expect(await jar.loadForRequest(uri), isEmpty);
  });
}
