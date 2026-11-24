import 'package:flutter/foundation.dart';

/// In release builds `debugPrint` still goes to logcat / the system log, which other
/// tools on the device and bug-report dumps can read. Our messages carry error texts
/// with LKS and mail URLs, group and person UUIDs, sometimes the student's name, so
/// release builds drop them. Debug and profile builds keep logging.
///
/// Every isolate has its own `debugPrint`: call this at the start of each entry point
/// (the app's `main` and the background sync dispatcher).
void silenceDebugLogsInRelease() {
  if (kReleaseMode) debugPrint = (String? message, {int? wrapWidth}) {};
}
