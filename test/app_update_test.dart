import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bmstu_neo/services/app_update.dart';

// Serves a fixed version.json and counts requests
class ManifestAdapter implements HttpClientAdapter {
  Object? manifest;
  int requests = 0;

  ManifestAdapter(this.manifest);

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    requests++;
    return ResponseBody.fromString(jsonEncode(manifest), 200, headers: {
      Headers.contentTypeHeader: ['application/json'],
    });
  }

  @override
  void close({bool force = false}) {}
}

const _sha = 'a1f0f8037d96227d758106a4b0bc85f9368de799a1f0f8037d96227d758106a4';

Map<String, dynamic> _manifest({int code = 13, String apk = 'downloads/bmstu-neo-1.5.0.apk'}) => {
      'versionCode': code,
      'versionName': '1.5.0',
      'apk': apk,
      'size': 63000000,
      'sha256': _sha,
      'notes': 'Обновления по воздуху',
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ManifestAdapter adapter;

  AppUpdater updater(Object? manifest, {int build = 12}) {
    adapter = ManifestAdapter(manifest);
    return AppUpdater(
      manifest: 'https://bmstuneo.xyz/version.json',
      currentBuild: build,
      dio: Dio()..httpClientAdapter = adapter,
    );
  }

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('Offers a newer build and resolves the APK next to the manifest', () async {
    final info = await updater(_manifest()).check();
    expect(info, isNotNull);
    expect(info!.versionCode, 13);
    expect(info.apkUrl.toString(), 'https://bmstuneo.xyz/downloads/bmstu-neo-1.5.0.apk');
    expect(info.notes, 'Обновления по воздуху');
  });

  test('Stays quiet when the installed build is the same or newer', () async {
    expect(await updater(_manifest(code: 12)).check(), isNull);
    SharedPreferences.setMockInitialValues({});
    expect(await updater(_manifest(code: 13), build: 14).check(), isNull);
  });

  test('Asks the website at most every 12 hours unless forced', () async {
    final u = updater(_manifest());
    expect(await u.check(), isNotNull);
    expect(await u.check(), isNull);
    expect(adapter.requests, 1);
    expect(await u.check(force: true), isNotNull);
    expect(adapter.requests, 2);
  });

  test('A skipped version is not offered again, but a manual check still shows it', () async {
    final u = updater(_manifest());
    final info = await u.check();
    await u.skip(info!);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(AppUpdater.lastCheckKey);
    expect(await u.check(), isNull);
    expect(await u.check(force: true), isNotNull);
  });

  test('Rejects plain HTTP and malformed manifests', () async {
    expect(await updater(_manifest(apk: 'http://evil.example/app.apk')).check(force: true), isNull);
    expect(await updater({..._manifest(), 'sha256': 'nope'}).check(force: true), isNull);
    expect(await updater({'versionCode': '13'}).check(force: true), isNull);
    expect(await updater(null).check(force: true), isNull);
  });
}
