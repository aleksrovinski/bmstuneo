import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'constants/app_mode.dart';
import 'demo/demo_api_service.dart';
import 'demo/demo_data.dart';
import 'demo/demo_mail_service.dart';
import 'main.dart';

/// Demo build with sample data: `flutter run -t lib/main_demo.dart`.
///
/// Signs in a made-up student right away and never calls LKS. Settings, caches and
/// credentials live apart from the real app's, so trying the demo on a phone with
/// BMSTU neo installed doesn't log the student out or mix up their data.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  AppMode.isDemo = true;
  // Must run before anything opens SharedPreferences
  SharedPreferences.setPrefix('demo.');
  runApp(buildApp(
    apiService: DemoApiService(),
    authStorage: DemoAuthStorage(),
    mailService: DemoMailService(),
    mailStorage: DemoMailCredentialsStorage(),
    // Shown on the first launch only; the student's own edits are kept afterwards
    homeworkSeed: DemoData().homework,
  ));
}
