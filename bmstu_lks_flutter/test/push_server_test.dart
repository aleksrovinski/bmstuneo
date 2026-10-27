import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:bmstu_neo/models/user_profile.dart';
import 'package:bmstu_neo/providers/auth_provider.dart';
import 'package:bmstu_neo/services/push_server.dart';

// Records requests instead of sending them
class RecordingAdapter implements HttpClientAdapter {
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    requests.add(options);
    return ResponseBody.fromString('', options.method == 'POST' ? 201 : 204);
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late RecordingAdapter adapter;

  PushServer server({String url = 'https://push.example.org'}) {
    adapter = RecordingAdapter();
    return PushServer(baseUrl: url, dio: Dio()..httpClientAdapter = adapter);
  }

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({
      AuthProvider.cachedProfileKey: jsonEncode(UserProfile(
        lastName: 'Тестов',
        firstName: 'Иван',
        middleName: 'Петрович',
        groupTitle: 'РК5-32Б',
        groupUuid: '08e4210a-47ca-11ee-814c-005056961205',
        stageUuid: 'stage-1',
      ).toJson()),
    });
  });

  test('Registers the token with a stable installation id and secret, and nothing personal', () async {
    final push = server();
    expect(await push.register(token: 'ab' * 32, platform: 'apns'), isTrue);
    expect(await push.register(token: 'cd' * 32, platform: 'apns'), isTrue);

    final first = adapter.requests[0].data as Map<String, dynamic>;
    final second = adapter.requests[1].data as Map<String, dynamic>;
    expect(adapter.requests[0].uri.toString(), 'https://push.example.org/v1/devices');
    expect(first.keys.toSet(), {'installationId', 'secret', 'platform', 'token', 'groupUuid'});
    expect(first['installationId'], matches(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')));
    expect((first['secret'] as String).length, greaterThanOrEqualTo(32));
    expect(first['groupUuid'], '08e4210a-47ca-11ee-814c-005056961205');
    expect(second['installationId'], first['installationId']);
    expect(second['secret'], first['secret']);
    expect(second['token'], 'cd' * 32);
  });

  test('Unregistering proves ownership with the installation secret', () async {
    final push = server();
    await push.register(token: 'ab' * 32, platform: 'apns');
    final registered = adapter.requests.single.data as Map<String, dynamic>;

    await push.unregister();
    final delete = adapter.requests.last;
    expect(delete.method, 'DELETE');
    expect(delete.uri.path, '/v1/devices/${registered['installationId']}');
    expect(delete.headers['x-installation-secret'], registered['secret']);
  });

  test('Without a configured server nothing leaves the device', () async {
    final push = server(url: '');
    expect(push.isConfigured, isFalse);
    expect(await push.register(token: 'ab' * 32, platform: 'apns'), isFalse);
    await push.unregister();
    expect(adapter.requests, isEmpty);
  });
}
