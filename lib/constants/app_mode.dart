/// Which build is running. The demo build (lib/main_demo.dart) shows sample data and
/// must not touch the real student's LKS session, background sync or push registration.
class AppMode {
  static bool isDemo = false;
}
