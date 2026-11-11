import 'package:cookie_jar/cookie_jar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:workmanager/workmanager.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'services/auth_storage.dart';
import 'services/bmstu_api_service.dart';
import 'services/secure_cookie_storage.dart';
import 'services/background_sync.dart';
import 'services/push_channel.dart';
import 'services/app_notifications.dart';
import 'services/mail_service.dart';
import 'services/mail_credentials_storage.dart';
import 'providers/auth_provider.dart';
import 'providers/schedule_provider.dart';
import 'providers/progress_provider.dart';
import 'providers/fv_provider.dart';
import 'providers/theme_provider.dart';
import 'providers/favorites_provider.dart';
import 'providers/homework_provider.dart';
import 'providers/mail_provider.dart';
import 'models/homework_note.dart';
import 'screens/login_screen.dart';
import 'screens/main_navigation_screen.dart';

import 'widgets/bmstu_neo_logo.dart';
import 'constants/app_version.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Registers the background progress check (scheduled only if the student enables it)
  Workmanager().initialize(backgroundSyncDispatcher);
  PushChannel.listen();
  // Tapping a notification opens its screen (MainNavigationScreen)
  AppNotifications.listenForTaps();
  // While notifications are on: keep the periodic check scheduled and the push token current
  BackgroundSync.resume().catchError((Object e) => debugPrint('[main] Background sync not resumed: $e'));

  runApp(buildApp(
    // The LKS session survives restarts, so the password isn't resent on every launch
    apiService: BmstuApiService(cookieJar: PersistCookieJar(storage: SecureCookieStorage())),
    authStorage: AuthStorage(),
    mailService: MailService(),
    mailStorage: MailCredentialsStorage(),
  ));
}

/// The app with its providers; the demo build passes its own data sources.
Widget buildApp({
  required BmstuApiService apiService,
  required AuthStorage authStorage,
  required MailService mailService,
  required MailCredentialsStorage mailStorage,
  List<HomeworkNote>? homeworkSeed,
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider(
        create: (_) => ThemeProvider(),
      ),
      ChangeNotifierProvider(
        create: (_) => FavoritesProvider(),
      ),
      ChangeNotifierProvider(
        create: (_) => HomeworkProvider(seed: homeworkSeed),
      ),
      ChangeNotifierProvider(
        create: (_) => AuthProvider(
          apiService: apiService,
          authStorage: authStorage,
        ),
      ),
      ChangeNotifierProvider(
        create: (_) => ScheduleProvider(
          apiService: apiService,
        ),
      ),
      ChangeNotifierProxyProvider<AuthProvider, ProgressProvider>(
        create: (_) => ProgressProvider(
          apiService: apiService,
        ),
        update: (_, auth, progress) {
          progress!.onSilentRelogin = () => auth.reloginSilently();
          return progress;
        },
      ),
      ChangeNotifierProvider(
        create: (_) => FvProvider(
          apiService: apiService,
        ),
      ),
      // Student mail; signing out of the app signs out of mail too
      ChangeNotifierProxyProvider<AuthProvider, MailProvider>(
        create: (_) => MailProvider(
          mailService: mailService,
          storage: mailStorage,
          authStorage: authStorage,
        ),
        update: (_, auth, mail) => mail!..onAuthChanged(auth.isAuthenticated),
      ),
    ],
    child: const BmstuApp(),
  );
}

class BmstuApp extends StatelessWidget {
  const BmstuApp({super.key});

  @override
  Widget build(BuildContext context) {
    ThemeProvider? themeProv;
    try {
      themeProv = context.watch<ThemeProvider>();
    } catch (_) {}
    themeProv ??= ThemeProvider();

    return DynamicColorBuilder(
      builder: (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
        return MaterialApp(
          title: AppVersion.appName,
          debugShowCheckedModeBanner: false,
          themeMode: themeProv!.materialThemeMode,
          theme: themeProv.buildLightTheme(lightDynamic),
          darkTheme: themeProv.buildDarkTheme(darkDynamic),
          locale: const Locale('ru'),
          supportedLocales: const [Locale('ru')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: const AuthGate(),
        );
      },
    );
  }
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool _isChecking = true;

  @override
  void initState() {
    super.initState();
    _checkSavedAuth();
  }

  Future<void> _checkSavedAuth() async {
    final auth = context.read<AuthProvider>();
    try {
      await auth.checkSavedAuth();
    } catch (e) {
      debugPrint('[AuthGate] Saved session check failed: $e');
    }
    if (mounted) {
      setState(() {
        _isChecking = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isChecking) {
      final theme = Theme.of(context);
      return Scaffold(
        backgroundColor: theme.colorScheme.surface,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const BmstuNeoLogo(size: 88, showBadge: true),
              const SizedBox(height: 20),
              Text(
                AppVersion.appName,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: theme.colorScheme.onSurface,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Личный кабинет студента',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final auth = context.watch<AuthProvider>();
    if (auth.isAuthenticated) {
      return const MainNavigationScreen();
    }
    return const LoginScreen();
  }
}
