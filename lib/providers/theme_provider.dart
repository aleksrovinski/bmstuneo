import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppThemeMode {
  system,
  light,
  // Pure black: easy on OLED screens and the only dark variant
  dark;

  String get title {
    switch (this) {
      case AppThemeMode.system:
        return 'Системная';
      case AppThemeMode.light:
        return 'Светлая';
      case AppThemeMode.dark:
        return 'Тёмная';
    }
  }

  IconData get icon {
    switch (this) {
      case AppThemeMode.system:
        return Icons.brightness_auto_rounded;
      case AppThemeMode.light:
        return Icons.light_mode_rounded;
      case AppThemeMode.dark:
        return Icons.dark_mode_rounded;
    }
  }
}

enum AppAccentColor {
  // Wallpaper colors on Android 12+; elsewhere falls back to Bauman blue
  dynamicColor(Color(0xFF0070F3), 'Material You'),
  baumanBlue(Color(0xFF0070F3), 'Бауманский синий'),
  deepNavy(Color(0xFF0B4F9C), 'Академический'),
  emerald(Color(0xFF10B981), 'Изумрудный'),
  amethyst(Color(0xFF8B5CF6), 'Аметистовый'),
  crimson(Color(0xFFE11D48), 'Рубиновый'),
  amber(Color(0xFFF59E0B), 'Янтарный');

  final Color color;
  final String title;
  const AppAccentColor(this.color, this.title);
}

/// Bundled with the app (assets/fonts), see pubspec.yaml.
const String appFontFamily = 'Onest';

class ThemeProvider with ChangeNotifier {
  static const _keyThemeMode = 'bmstu_pref_theme_mode_v2';
  static const _keyAccentColor = 'bmstu_pref_accent_color_v2';

  AppThemeMode _themeMode = AppThemeMode.system;
  AppAccentColor _accentColor = AppAccentColor.dynamicColor;

  AppThemeMode get themeMode => _themeMode;
  AppAccentColor get accentColor => _accentColor;

  ThemeProvider() {
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final modeStr = prefs.getString(_keyThemeMode);
      if (modeStr != null) {
        // 'oled' was a separate mode before it became the dark theme
        _themeMode = modeStr == 'oled'
            ? AppThemeMode.dark
            : AppThemeMode.values.firstWhere(
                (m) => m.name == modeStr,
                orElse: () => AppThemeMode.system,
              );
      }
      final colorStr = prefs.getString(_keyAccentColor);
      if (colorStr != null) {
        _accentColor = AppAccentColor.values.firstWhere(
          (c) => c.name == colorStr,
          orElse: () => AppAccentColor.dynamicColor,
        );
      }
      notifyListeners();
    } catch (e) {
      debugPrint('[ThemeProvider] Failed to load theme settings: $e');
    }
  }

  Future<void> setThemeMode(AppThemeMode mode) async {
    _themeMode = mode;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyThemeMode, mode.name);
    } catch (e) {
      debugPrint('[ThemeProvider] Failed to save theme mode: $e');
    }
  }

  Future<void> setAccentColor(AppAccentColor color) async {
    _accentColor = color;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyAccentColor, color.name);
    } catch (e) {
      debugPrint('[ThemeProvider] Failed to save accent color: $e');
    }
  }

  ThemeMode get materialThemeMode {
    switch (_themeMode) {
      case AppThemeMode.system:
        return ThemeMode.system;
      case AppThemeMode.light:
        return ThemeMode.light;
      case AppThemeMode.dark:
        return ThemeMode.dark;
    }
  }

  /// Build Light ThemeData
  ThemeData buildLightTheme(ColorScheme? dynamicLight) {
    final colorScheme = (_accentColor == AppAccentColor.dynamicColor && dynamicLight != null)
        ? dynamicLight
        : ColorScheme.fromSeed(
            seedColor: _accentColor.color,
            brightness: Brightness.light,
          );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: colorScheme.surface,
      appBarTheme: AppBarTheme(
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 2,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        color: colorScheme.surfaceContainerLow,
        clipBehavior: Clip.antiAlias,
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 72,
        indicatorColor: colorScheme.secondaryContainer,
        indicatorShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        backgroundColor: colorScheme.surface,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      ),
      fontFamily: appFontFamily,
    );
  }

  /// Build the dark ThemeData: black background, accent surfaces from the scheme
  ThemeData buildDarkTheme(ColorScheme? dynamicDark) {
    final base = (_accentColor == AppAccentColor.dynamicColor && dynamicDark != null)
        ? dynamicDark
        : ColorScheme.fromSeed(
            seedColor: _accentColor.color,
            brightness: Brightness.dark,
          );
    final colorScheme = base.copyWith(
      surface: Colors.black,
      surfaceContainerLowest: Colors.black,
      surfaceContainerLow: const Color(0xFF0D0D0D),
      surfaceContainer: const Color(0xFF141414),
      surfaceContainerHigh: const Color(0xFF1C1C1C),
      surfaceContainerHighest: const Color(0xFF262626),
      onSurface: Colors.white,
      outlineVariant: const Color(0xFF2A2A2A),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: Colors.black,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.black,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 2,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        color: colorScheme.surfaceContainerLow,
        clipBehavior: Clip.antiAlias,
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 72,
        indicatorColor: colorScheme.secondaryContainer,
        indicatorShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        backgroundColor: Colors.black,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      ),
      fontFamily: appFontFamily,
    );
  }
}
