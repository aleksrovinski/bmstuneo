import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppThemeMode {
  system,
  light,
  dark,
  oled;

  String get title {
    switch (this) {
      case AppThemeMode.system:
        return 'Системная';
      case AppThemeMode.light:
        return 'Светлая';
      case AppThemeMode.dark:
        return 'Тёмная';
      case AppThemeMode.oled:
        return 'OLED Black';
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
      case AppThemeMode.oled:
        return Icons.contrast_rounded;
    }
  }
}

enum AppAccentColor {
  baumanBlue(Color(0xFF0070F3), 'Бауманский синий'),
  deepNavy(Color(0xFF0B4F9C), 'Академический'),
  emerald(Color(0xFF10B981), 'Изумрудный'),
  amethyst(Color(0xFF8B5CF6), 'Аметистовый'),
  crimson(Color(0xFFE11D48), 'Рубиновый'),
  amber(Color(0xFFF59E0B), 'Янтарный'),
  dynamicColor(Color(0xFF6366F1), 'Material You');

  final Color color;
  final String title;
  const AppAccentColor(this.color, this.title);
}

class ThemeProvider with ChangeNotifier {
  static const _keyThemeMode = 'bmstu_pref_theme_mode_v2';
  static const _keyAccentColor = 'bmstu_pref_accent_color_v2';

  AppThemeMode _themeMode = AppThemeMode.system;
  AppAccentColor _accentColor = AppAccentColor.baumanBlue;

  AppThemeMode get themeMode => _themeMode;
  AppAccentColor get accentColor => _accentColor;
  bool get isOled => _themeMode == AppThemeMode.oled;

  ThemeProvider() {
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final modeStr = prefs.getString(_keyThemeMode);
      if (modeStr != null) {
        _themeMode = AppThemeMode.values.firstWhere(
          (m) => m.name == modeStr,
          orElse: () => AppThemeMode.system,
        );
      }
      final colorStr = prefs.getString(_keyAccentColor);
      if (colorStr != null) {
        _accentColor = AppAccentColor.values.firstWhere(
          (c) => c.name == colorStr,
          orElse: () => AppAccentColor.baumanBlue,
        );
      }
      notifyListeners();
    } catch (_) {}
  }

  Future<void> setThemeMode(AppThemeMode mode) async {
    _themeMode = mode;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyThemeMode, mode.name);
    } catch (_) {}
  }

  Future<void> setAccentColor(AppAccentColor color) async {
    _accentColor = color;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyAccentColor, color.name);
    } catch (_) {}
  }

  ThemeMode get materialThemeMode {
    switch (_themeMode) {
      case AppThemeMode.system:
        return ThemeMode.system;
      case AppThemeMode.light:
        return ThemeMode.light;
      case AppThemeMode.dark:
      case AppThemeMode.oled:
        return ThemeMode.dark;
    }
  }

  /// Build Light ThemeData
  ThemeData buildLightTheme(ColorScheme? dynamicLight) {
    final seedColor = (_accentColor == AppAccentColor.dynamicColor && dynamicLight != null)
        ? dynamicLight.primary
        : _accentColor.color;

    final colorScheme = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: Brightness.light,
    );

    final textTheme = GoogleFonts.interTextTheme(ThemeData.light().textTheme);

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
      textTheme: textTheme,
    );
  }

  /// Build Dark / OLED ThemeData
  ThemeData buildDarkTheme(ColorScheme? dynamicDark) {
    final isOledActive = _themeMode == AppThemeMode.oled;

    final seedColor = (_accentColor == AppAccentColor.dynamicColor && dynamicDark != null)
        ? dynamicDark.primary
        : _accentColor.color;

    var colorScheme = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: Brightness.dark,
    );

    if (isOledActive) {
      colorScheme = colorScheme.copyWith(
        surface: Colors.black,
        surfaceContainerLowest: Colors.black,
        surfaceContainerLow: const Color(0xFF0D0D0D),
        surfaceContainer: const Color(0xFF121212),
        surfaceContainerHigh: const Color(0xFF181818),
        surfaceContainerHighest: const Color(0xFF222222),
        onSurface: Colors.white,
        outlineVariant: const Color(0xFF282828),
      );
    }

    final textTheme = GoogleFonts.interTextTheme(ThemeData.dark().textTheme);

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: isOledActive ? Colors.black : colorScheme.surface,
      appBarTheme: AppBarTheme(
        backgroundColor: isOledActive ? Colors.black : colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 2,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        color: isOledActive ? const Color(0xFF0D0D0D) : colorScheme.surfaceContainerLow,
        clipBehavior: Clip.antiAlias,
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 72,
        indicatorColor: colorScheme.secondaryContainer,
        indicatorShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        backgroundColor: isOledActive ? Colors.black : colorScheme.surface,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      ),
      textTheme: textTheme,
    );
  }
}
