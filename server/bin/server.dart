import 'dart:async';
import 'dart:io';
import 'package:bmstu_neo_push/bmstu_neo_push.dart';
import 'package:shelf/shelf_io.dart' as io;

/// Configuration comes from the environment (see server/README.md). Secrets are
/// read from files or variables and never logged.
Future<void> main() async {
  final env = Platform.environment;
  String? secret(String name) {
    final file = env['${name}_FILE'];
    if (file != null && file.isNotEmpty) return File(file).readAsStringSync();
    final value = env[name];
    return (value == null || value.isEmpty) ? null : value;
  }

  final dataDir = env['DATA_DIR'] ?? 'data';
  final store = await FileDeviceStore.open('$dataDir/devices.json');

  final senders = <String, PushSender>{};
  final apnsKey = secret('APNS_KEY');
  if (apnsKey != null && env['APNS_KEY_ID'] != null && env['APNS_TEAM_ID'] != null) {
    senders['apns'] = ApnsClient(
      keyId: env['APNS_KEY_ID']!,
      teamId: env['APNS_TEAM_ID']!,
      bundleId: env['APNS_BUNDLE_ID'] ?? 'ru.bmstu.neo',
      privateKeyPem: apnsKey,
    );
  } else {
    stderr.writeln('APNs disabled: set APNS_KEY_FILE (or APNS_KEY), APNS_KEY_ID, APNS_TEAM_ID');
  }
  final fcmAccount = secret('FCM_SERVICE_ACCOUNT');
  if (fcmAccount != null) {
    senders['fcm'] = FcmClient.fromServiceAccount(fcmAccount);
  } else {
    stderr.writeln('FCM disabled: set FCM_SERVICE_ACCOUNT_FILE (or FCM_SERVICE_ACCOUNT)');
  }

  final scheduler = SyncScheduler(
    store: store,
    senders: senders,
    interval: Duration(minutes: int.parse(env['SYNC_INTERVAL_MINUTES'] ?? '120')),
  );
  final timer = scheduler.start(
    every: Duration(seconds: int.parse(env['TICK_SECONDS'] ?? '300')),
    onTick: (stats) => stdout.writeln('${DateTime.now().toUtc().toIso8601String()} tick: $stats'),
  );

  final handler = buildHandler(store: store, scheduler: scheduler, adminToken: env['ADMIN_TOKEN']);
  final server = await io.serve(handler, InternetAddress.anyIPv4, int.parse(env['PORT'] ?? '8080'));
  stdout.writeln('BMSTU neo push server on :${server.port}, '
      '${(await store.all()).length} devices, senders: ${senders.keys.join(', ')}');

  // Container stop: finish in-flight requests, then exit
  await Future.any([ProcessSignal.sigterm.watch().first, ProcessSignal.sigint.watch().first]);
  timer.cancel();
  await server.close();
  exit(0);
}
