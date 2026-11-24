import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bmstu_neo/models/user_profile.dart';
import 'package:bmstu_neo/providers/auth_provider.dart';
import 'package:bmstu_neo/providers/progress_provider.dart';
import 'package:bmstu_neo/providers/schedule_provider.dart';
import 'package:bmstu_neo/providers/theme_provider.dart';
import 'package:bmstu_neo/screens/login_screen.dart';
import 'package:bmstu_neo/screens/settings_screen.dart';
import 'package:bmstu_neo/services/auth_storage.dart';
import 'package:bmstu_neo/services/bmstu_api_service.dart';

// Accepts any login without the network, or rejects every one
class _FakeApi extends BmstuApiService {
  final bool accept;
  _FakeApi({this.accept = true});

  @override
  Future<UserProfile?> login(String username, String password) async {
    if (!accept) throw Exception('Неверный логин или пароль студента');
    return _profile;
  }
}

final _profile = UserProfile(
        lastName: 'Тестов',
        firstName: 'Иван',
        middleName: 'Петрович',
        groupTitle: 'РК5-32Б',
        groupUuid: 'group-1',
        stageUuid: 'stage-1',
      );

Widget _app(AuthProvider auth, BmstuApiService api, Widget home) => MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: auth),
        ChangeNotifierProvider(create: (_) => ScheduleProvider(apiService: api)),
        ChangeNotifierProvider(create: (_) => ProgressProvider(apiService: api)),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
      ],
      child: MaterialApp(home: home),
    );

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  testWidgets('Login: the student unticks "Сохранить пароль" and nothing is saved', (tester) async {
    final api = _FakeApi();
    final auth = AuthProvider(apiService: api, authStorage: AuthStorage());
    await tester.pumpWidget(_app(auth, api, const LoginScreen()));

    expect(find.text('Сохранить пароль'), findsOneWidget);
    expect(find.text(LoginScreen.passwordSavedHint), findsOneWidget, reason: 'ticked by default');

    await tester.tap(find.text('Сохранить пароль'));
    await tester.pump();
    expect(find.text(LoginScreen.passwordNotSavedHint), findsOneWidget);

    await tester.enterText(find.byType(TextField).at(0), 'student');
    await tester.enterText(find.byType(TextField).at(1), 'secret');
    final loginButton = find.widgetWithText(FilledButton, 'Войти через SSO МГТУ');
    await tester.ensureVisible(loginButton);
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(loginButton);
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump();

    expect(auth.isFullAuth, isTrue);
    expect(auth.isPasswordSaved, isFalse);
    expect((await tester.runAsync(() => AuthStorage().getCredentials()))!['password'], isNull);
  });

  testWidgets('Settings: switching "Сохранять пароль" off deletes the saved password', (tester) async {
    final api = _FakeApi();
    final auth = AuthProvider(apiService: api, authStorage: AuthStorage());
    await tester.runAsync(() => auth.login('student', 'secret'));
    expect(auth.isPasswordSaved, isTrue);

    await tester.pumpWidget(_app(auth, api, const SettingsScreen()));
    await tester.pumpAndSettle();

    final toggle = find.widgetWithText(SwitchListTile, 'Сохранять пароль');
    expect(toggle, findsOneWidget);
    expect(tester.widget<SwitchListTile>(toggle).value, isTrue);

    await tester.runAsync(() async {
      await tester.tap(toggle);
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();

    expect(auth.isPasswordSaved, isFalse);
    expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
    expect(find.text('Пароль удалён с устройства'), findsOneWidget);
    expect((await tester.runAsync(() => AuthStorage().getCredentials()))!['password'], isNull);
  });

  group('System password manager', () {
    // How the app ended the autofill context, from flutter_test's fake text input
    List<bool> finished(WidgetTester tester) => [
          for (final call in tester.testTextInput.log)
            if (call.method == 'TextInput.finishAutofillContext') call.arguments as bool,
        ];

    Future<void> signIn(WidgetTester tester, _FakeApi api) async {
      final auth = AuthProvider(apiService: api, authStorage: AuthStorage());
      await tester.pumpWidget(_app(auth, api, const LoginScreen()));
      await tester.enterText(find.byType(TextField).at(0), 'student');
      await tester.enterText(find.byType(TextField).at(1), 'secret');
      final loginButton = find.widgetWithText(FilledButton, 'Войти через SSO МГТУ');
      await tester.ensureVisible(loginButton);
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(loginButton);
        // Until the screen has reported how the attempt ended
        for (var i = 0; i < 100 && finished(tester).isEmpty; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });
      await tester.pump();
    }

    testWidgets('Login and password are marked for autofill in one group', (tester) async {
      final api = _FakeApi();
      await tester.pumpWidget(_app(AuthProvider(apiService: api, authStorage: AuthStorage()), api, const LoginScreen()));

      final fields = tester.widgetList<TextField>(find.byType(TextField)).toList();
      expect(fields[0].autofillHints, [AutofillHints.username]);
      expect(fields[1].autofillHints, [AutofillHints.password]);
      expect(find.ancestor(of: find.byType(TextField).at(1), matching: find.byType(AutofillGroup)), findsOneWidget);
    });

    testWidgets('A successful login offers to save it', (tester) async {
      await signIn(tester, _FakeApi());
      expect(finished(tester), [true]);
    });

    testWidgets('A rejected password is never offered for saving', (tester) async {
      await signIn(tester, _FakeApi(accept: false));
      expect(finished(tester), [false]);
    });
  });
}
