import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bmstu_neo/services/push_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('ru.bmstu.neo/push');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  Future<Object?> deliverFromNative(String method) async {
    final reply = await messenger.handlePlatformMessage(
      channel.name,
      channel.codec.encodeMethodCall(MethodCall(method)),
      (_) {},
    );
    return reply == null ? null : channel.codec.decodeEnvelope(reply);
  }

  test('Native side is told Dart is ready, and a silent push runs the sync', () async {
    SharedPreferences.setMockInitialValues({}); // notifications off: the sync stops early
    final calls = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return null;
    });

    await PushChannel.listen();
    expect(calls, ['ready']);

    // iOS reports "no new data" for 0 alerts
    expect(await deliverFromNative('silentPush'), 0);
  });

  test('Enabling stores the push token, disabling forgets it', () async {
    SharedPreferences.setMockInitialValues({});
    messenger.setMockMethodCallHandler(channel, (call) async => call.method == 'enable' ? 'abc123' : null);

    expect(await PushChannel.enable(), 'abc123');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(PushChannel.tokenKey), 'abc123');

    await PushChannel.disable();
    expect(prefs.getString(PushChannel.tokenKey), isNull);
  });

  test('A platform without push support does not break enabling notifications', () async {
    SharedPreferences.setMockInitialValues({});
    messenger.setMockMethodCallHandler(channel, (call) async => throw PlatformException(code: 'unavailable'));
    expect(await PushChannel.enable(), isNull);
  });
}
