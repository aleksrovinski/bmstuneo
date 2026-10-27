import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'background_sync.dart';
import 'push_server.dart';

/// Silent push glue: APNs on iOS (native, in AppDelegate), FCM on Android
/// (PushMessagingService). A push with {"type": "sync"} runs [BackgroundSync.run];
/// on Android it goes through WorkManager, on iOS through [listen].
class PushChannel {
  static const _channel = MethodChannel('ru.bmstu.neo/push');
  static const tokenKey = 'push_token_v1';
  static const platformKey = 'push_platform_v1';

  /// Replaceable in tests.
  static PushServer server = PushServer();

  /// Call once at startup, before runApp: a cold start caused by a silent push
  /// waits on the native side until this handler is attached.
  static Future<void> listen() async {
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'silentPush') throw MissingPluginException();
      debugPrint('[PushChannel] Silent push received');
      final alerts = await BackgroundSync.run();
      return alerts.length;
    });
    try {
      await _channel.invokeMethod<void>('ready');
    } on MissingPluginException {
      // Android delivers pushes through WorkManager, nothing to flush here
      if (defaultTargetPlatform == TargetPlatform.iOS) debugPrint('[PushChannel] Native push channel missing');
    } on PlatformException catch (e) {
      debugPrint('[PushChannel] ready failed: $e');
    }
  }

  /// Registers this device for silent pushes and remembers the token for the push
  /// server. Returns the token, or null if the platform couldn't provide one.
  static Future<String?> enable() async {
    try {
      final token = await _channel.invokeMethod<String>('enable');
      final prefs = await SharedPreferences.getInstance();
      if (token != null && token.isNotEmpty) {
        final platform = defaultTargetPlatform == TargetPlatform.iOS ? 'apns' : 'fcm';
        await prefs.setString(tokenKey, token);
        await prefs.setString(platformKey, platform);
        // Lets the push server wake this app on a schedule
        await server.register(token: token, platform: platform);
      }
      return token;
    } catch (e) {
      debugPrint('[PushChannel] Registration failed, periodic checks still work: $e');
      return null;
    }
  }

  static Future<void> disable() async {
    await server.unregister();
    try {
      await _channel.invokeMethod<void>('disable');
    } catch (e) {
      debugPrint('[PushChannel] Unregistration failed: $e');
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(tokenKey);
    await prefs.remove(platformKey);
  }
}
