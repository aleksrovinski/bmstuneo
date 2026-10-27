import 'package:flutter/services.dart';

class AppVersion {
  static const String appName = 'BMSTU neo';

  // Embedded by `flutter build` / `flutter run` from `version:` in pubspec.yaml
  // (or --build-name / --build-number), so there is a single place to bump it.
  static const String version = appBuildName ?? 'dev';
  static const String buildNumber = appBuildNumber ?? '0';

  static const String fullVersion = 'v$version ($buildNumber)';
  static const String displayVersion = 'Версия $version (сборка $buildNumber)';
}
