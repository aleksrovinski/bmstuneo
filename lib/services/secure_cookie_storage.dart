import 'package:cookie_jar/cookie_jar.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Keeps the LKS session cookies in the Keychain / Keystore, next to the
/// credentials, so the app resumes the session after a restart instead of
/// signing in with the password every time.
class SecureCookieStorage implements Storage {
  static const _prefix = 'lks_cookie_';

  final FlutterSecureStorage _secureStorage;

  SecureCookieStorage({FlutterSecureStorage? secureStorage})
      : _secureStorage = secureStorage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(resetOnError: true),
              iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
            );

  @override
  Future<void> init(bool persistSession, bool ignoreExpires) async {}

  // A failing Keychain only costs the persisted session: the app signs in again
  @override
  Future<String?> read(String key) async {
    try {
      return await _secureStorage.read(key: '$_prefix$key');
    } catch (e) {
      debugPrint('[SecureCookieStorage] Read failed: $e');
      return null;
    }
  }

  @override
  Future<void> write(String key, String value) async {
    try {
      await _secureStorage.write(key: '$_prefix$key', value: value);
    } catch (e) {
      debugPrint('[SecureCookieStorage] Write failed: $e');
    }
  }

  @override
  Future<void> delete(String key) async {
    try {
      await _secureStorage.delete(key: '$_prefix$key');
    } catch (e) {
      debugPrint('[SecureCookieStorage] Delete failed: $e');
    }
  }

  @override
  Future<void> deleteAll(List<String> keys) async {
    for (final key in keys) {
      await delete(key);
    }
  }
}
