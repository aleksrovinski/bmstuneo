import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AuthStorage {
  static const _keyUsername = 'bmstu_username';
  static const _keyPassword = 'bmstu_password';

  final FlutterSecureStorage _secureStorage;

  AuthStorage({FlutterSecureStorage? secureStorage})
      : _secureStorage = secureStorage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(resetOnError: true),
            );

  Future<void> saveCredentials(String username, String password) async {
    try {
      await _secureStorage.write(key: _keyUsername, value: username);
      await _secureStorage.write(key: _keyPassword, value: password);
    } catch (e) {
      debugPrint('[AuthStorage] Secure write error, fallback to SharedPreferences: $e');
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyUsername, username);
      await prefs.setString(_keyPassword, password);
      return;
    }

    // Clean up any plaintext credentials if they existed in SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyUsername);
    await prefs.remove(_keyPassword);
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

    // Seamless migration from legacy SharedPreferences if secure storage is empty or failed
    if (user == null && pass == null) {
      final prefs = await SharedPreferences.getInstance();
      final legacyUser = prefs.getString(_keyUsername);
      final legacyPass = prefs.getString(_keyPassword);

      if (legacyUser != null || legacyPass != null) {
        try {
          if (legacyUser != null) {
            await _secureStorage.write(key: _keyUsername, value: legacyUser);
            await prefs.remove(_keyUsername);
          }
          if (legacyPass != null) {
            await _secureStorage.write(key: _keyPassword, value: legacyPass);
            await prefs.remove(_keyPassword);
          }
        } catch (_) {}
        user = legacyUser;
        pass = legacyPass;
      }
    }

    return {'username': user, 'password': pass};
  }

  Future<void> clearCredentials() async {
    try {
      await _secureStorage.delete(key: _keyUsername);
      await _secureStorage.delete(key: _keyPassword);
    } catch (_) {}

    // Also ensure legacy SharedPreferences keys are wiped
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyUsername);
    await prefs.remove(_keyPassword);
  }
}
