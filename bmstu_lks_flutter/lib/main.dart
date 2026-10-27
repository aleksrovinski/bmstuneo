import 'package:cookie_jar/cookie_jar.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:workmanager/workmanager.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'services/auth_storage.dart';
import 'services/bmstu_api_service.dart';
import 'services/secure_cookie_storage.dart';
import 'services/background_sync.dart';
import 'services/push_channel.dart';
import 'providers/auth_provider.dart';
import 'providers/schedule_provider.dart';
import 'providers/progress_provider.dart';
import 'providers/fv_provider.dart';
import 'providers/theme_provider.dart';
import 'providers/favorites_provider.dart';
import 'screens/login_screen.dart';
import 'screens/main_navigation_screen.dart';

import 'widgets/bmstu_neo_logo.dart';
import 'constants/app_version.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Registers the background progress check (scheduled only if the student enables it)
  Workmanager().initialize(backgroundSyncDispatcher);
  PushChannel.listen();
  // Push tokens can change; re-register on every launch while notifications are on
  BackgroundSync.isEnabled().then((on) => on ? PushChannel.enable() : null);
  final authStorage = AuthStorage();
  // The LKS session survives restarts, so the password isn't resent on every launch
  final apiService = BmstuApiService(
    cookieJar: PersistCookieJar(storage: SecureCookieStorage()),
  );

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => ThemeProvider(),
        ),
        ChangeNotifierProvider(
          create: (_) => FavoritesProvider(),
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
      ],
      child: const BmstuApp(),
    ),
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
