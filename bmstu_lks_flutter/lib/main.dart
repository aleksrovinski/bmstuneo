import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'services/auth_storage.dart';
import 'services/bmstu_api_service.dart';
import 'providers/auth_provider.dart';
import 'providers/schedule_provider.dart';
import 'providers/progress_provider.dart';
import 'providers/fv_provider.dart';
import 'screens/login_screen.dart';
import 'screens/main_navigation_screen.dart';

import 'widgets/bmstu_neo_logo.dart';
import 'constants/app_version.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final authStorage = AuthStorage();
  final apiService = BmstuApiService();

  runApp(
    MultiProvider(
      providers: [
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

  // Default brand seed color (Bauman Blue) when dynamic colors are unavailable
  static const _defaultBrandSeed = Color(0xFF0070F3);

  @override
  Widget build(BuildContext context) {
    return DynamicColorBuilder(
      builder: (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
        ColorScheme lightColorScheme;
        ColorScheme darkColorScheme;

        if (lightDynamic != null && darkDynamic != null) {
          // Dynamic colors from Android 12+ wallpaper (Material You Monet)
          lightColorScheme = lightDynamic.harmonized();
          darkColorScheme = darkDynamic.harmonized();
        } else {
          // Fallback brand color scheme
          lightColorScheme = ColorScheme.fromSeed(
            seedColor: _defaultBrandSeed,
            brightness: Brightness.light,
          );
          darkColorScheme = ColorScheme.fromSeed(
            seedColor: _defaultBrandSeed,
            brightness: Brightness.dark,
          );
        }

        final lightTextTheme = GoogleFonts.interTextTheme(ThemeData.light().textTheme);
        final darkTextTheme = GoogleFonts.interTextTheme(ThemeData.dark().textTheme);

        return MaterialApp(
          title: AppVersion.appName,
          debugShowCheckedModeBanner: false,
          themeMode: ThemeMode.system,
          // Material You Light Theme
          theme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.light,
            colorScheme: lightColorScheme,
            scaffoldBackgroundColor: lightColorScheme.surface,
            appBarTheme: AppBarTheme(
              backgroundColor: lightColorScheme.surface,
              foregroundColor: lightColorScheme.onSurface,
              elevation: 0,
              scrolledUnderElevation: 2,
              surfaceTintColor: lightColorScheme.surfaceTint,
              centerTitle: false,
            ),
            cardTheme: CardThemeData(
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              color: lightColorScheme.surfaceContainerLow,
            ),
            navigationBarTheme: NavigationBarThemeData(
              height: 68,
              indicatorColor: lightColorScheme.secondaryContainer,
              backgroundColor: lightColorScheme.surface,
              surfaceTintColor: lightColorScheme.surfaceTint,
              iconTheme: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) {
                  return IconThemeData(color: lightColorScheme.onSecondaryContainer);
                }
                return IconThemeData(color: lightColorScheme.onSurfaceVariant);
              }),
              labelTextStyle: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) {
                  return TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: lightColorScheme.onSurface,
                  );
                }
                return TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: lightColorScheme.onSurfaceVariant,
                );
              }),
              labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
            ),
            textTheme: lightTextTheme,
          ),
          // Material You Dark Theme
          darkTheme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.dark,
            colorScheme: darkColorScheme,
            scaffoldBackgroundColor: darkColorScheme.surface,
            appBarTheme: AppBarTheme(
              backgroundColor: darkColorScheme.surface,
              foregroundColor: darkColorScheme.onSurface,
              elevation: 0,
              scrolledUnderElevation: 2,
              surfaceTintColor: darkColorScheme.surfaceTint,
              centerTitle: false,
            ),
            cardTheme: CardThemeData(
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              color: darkColorScheme.surfaceContainerLow,
            ),
            navigationBarTheme: NavigationBarThemeData(
              height: 68,
              indicatorColor: darkColorScheme.secondaryContainer,
              backgroundColor: darkColorScheme.surface,
              surfaceTintColor: darkColorScheme.surfaceTint,
              iconTheme: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) {
                  return IconThemeData(color: darkColorScheme.onSecondaryContainer);
                }
                return IconThemeData(color: darkColorScheme.onSurfaceVariant);
              }),
              labelTextStyle: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) {
                  return TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: darkColorScheme.onSurface,
                  );
                }
                return TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: darkColorScheme.onSurfaceVariant,
                );
              }),
              labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
            ),
            textTheme: darkTextTheme,
          ),
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
    } catch (_) {}
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
