import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Login and password of the student mail (student.bmstu.ru), kept apart from the LKS
/// ones: the mail password can differ, and signing out of mail keeps LKS signed in.
/// Stored only in secure storage (Keychain / Keystore), never in plain preferences.
class MailCredentialsStorage {
  static const _keyUsername = 'bmstu_mail_username';
  static const _keyPassword = 'bmstu_mail_password';

  final FlutterSecureStorage _secureStorage;

  MailCredentialsStorage({FlutterSecureStorage? secureStorage})
      : _secureStorage = secureStorage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(resetOnError: true),
              iOptions: IOSOptions(
                accessibility: KeychainAccessibility.first_unlock,
              ),
            );

  /// Returns false when secure storage refused the write: the session still works,
  /// the student just signs in again after a restart.
  Future<bool> save(String username, String password) async {
    try {
      await _secureStorage.write(key: _keyUsername, value: username);
      await _secureStorage.write(key: _keyPassword, value: password);
      return true;
    } catch (e) {
      debugPrint('[MailCredentialsStorage] Secure write error, mail login not saved: $e');
      await clear();
      return false;
    }
  }

  Future<({String? username, String? password})> read() async {
    try {
      return (
        username: await _secureStorage.read(key: _keyUsername),
        password: await _secureStorage.read(key: _keyPassword),
      );
    } catch (e) {
      debugPrint('[MailCredentialsStorage] Secure read error: $e');
      return (username: null, password: null);
    }
  }

  /// Forgets the password but keeps the login to prefill the form.
  Future<void> forgetPassword() async {
    try {
      await _secureStorage.delete(key: _keyPassword);
    } catch (e) {
      debugPrint('[MailCredentialsStorage] Secure delete error: $e');
    }
  }

  Future<void> clear() async {
    try {
      await _secureStorage.delete(key: _keyUsername);
      await _secureStorage.delete(key: _keyPassword);
    } catch (e) {
      debugPrint('[MailCredentialsStorage] Secure delete error: $e');
    }
  }
}
