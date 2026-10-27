import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AuthStorageException implements Exception {
  final String message;
  final Object? cause;
  AuthStorageException(this.message, [this.cause]);
  @override
  String toString() => cause == null ? message : '$message ($cause)';
}

class AuthStorage {
  static const _keyUsername = 'bmstu_username';
  static const _keyPassword = 'bmstu_password';

  final FlutterSecureStorage _secureStorage;

  AuthStorage({FlutterSecureStorage? secureStorage})
      : _secureStorage = secureStorage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(resetOnError: true),
              iOptions: IOSOptions(
                accessibility: KeychainAccessibility.first_unlock,
              ),
            );

  // Credentials are stored only in secure storage (Keychain / Keystore).
  // If it is unavailable we refuse to persist them rather than fall back to plaintext.
  Future<void> saveCredentials(String username, String password) async {
    try {
      await _secureStorage.write(key: _keyUsername, value: username);
      await _secureStorage.write(key: _keyPassword, value: password);
    } catch (e) {
      debugPrint('[AuthStorage] Secure write error, credentials not saved: $e');
      // Don't leave a half-written pair (username without password) behind
      await _deleteSecure();
      await _wipeLegacy();
      throw AuthStorageException('Не удалось сохранить данные входа в защищённое хранилище', e);
    }

    // Clean up any plaintext credentials if they existed in SharedPreferences
    await _wipeLegacy();
  }

  Future<Map<String, String?>> getCredentials() async {
    String? user;
    String? pass;

    try {
      user = await _secureStorage.read(key: _keyUsername);
      pass = await _secureStorage.read(key: _keyPassword);
    } catch (e) {
      debugPrint('[AuthStorage] Secure read error: $e');
    }

    // One-time migration from legacy plaintext SharedPreferences
    if (user == null && pass == null) {
      final prefs = await SharedPreferences.getInstance();
      final legacyUser = prefs.getString(_keyUsername);
      final legacyPass = prefs.getString(_keyPassword);

      if (legacyUser != null || legacyPass != null) {
        try {
          if (legacyUser != null) {
            await _secureStorage.write(key: _keyUsername, value: legacyUser);
          }
          if (legacyPass != null) {
            await _secureStorage.write(key: _keyPassword, value: legacyPass);
          }
        } catch (e) {
          debugPrint('[AuthStorage] Legacy migration to secure storage failed, '
              'plaintext copy is wiped anyway: $e');
        }
        // Plaintext must not survive even if migration failed: the values are still
        // returned for this session, and the user re-enters them on next launch.
        await _wipeLegacy();
        user = legacyUser;
        pass = legacyPass;
      }
    }

    return {'username': user, 'password': pass};
  }

  Future<void> clearCredentials() async {
    await _deleteSecure();
    // Also ensure legacy SharedPreferences keys are wiped
    await _wipeLegacy();
  }

  Future<void> _deleteSecure() async {
    try {
      await _secureStorage.delete(key: _keyUsername);
      await _secureStorage.delete(key: _keyPassword);
    } catch (e) {
      debugPrint('[AuthStorage] Secure delete error: $e');
    }
  }

  Future<void> _wipeLegacy() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_keyUsername);
      await prefs.remove(_keyPassword);
    } catch (e) {
      debugPrint('[AuthStorage] Failed to wipe legacy plaintext credentials: $e');
    }
  }
}
