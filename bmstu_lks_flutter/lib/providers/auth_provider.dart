import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user_profile.dart';
import '../services/auth_storage.dart';
import '../services/bmstu_api_service.dart';
import '../services/bmstu_groups_catalog.dart';

class AuthProvider with ChangeNotifier {
  static const _keyCachedProfile = 'bmstu_cached_user_profile_v1';
  static const _keyIsGuest = 'bmstu_is_guest_v1';
  static const _keyGuestGroupTitle = 'bmstu_guest_group_title_v1';
  static const _keyGuestGroupUuid = 'bmstu_guest_group_uuid_v1';

  final BmstuApiService apiService;
  final AuthStorage authStorage;

  UserProfile? _userProfile;
  bool _isGuest = false;
  bool _isLoading = false;
  String? _errorMessage;

  String _guestGroupTitle = 'ИУ7-43Б';
  String _guestGroupUuid = '08e4210a-47ca-11ee-814c-005056961205';

  AuthProvider({
    required this.apiService,
    required this.authStorage,
  }) {
    apiService.onSilentRelogin = () => reloginSilently();
  }

  UserProfile? get userProfile => _userProfile;
  bool get isGuest => _isGuest;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool get isAuthenticated => _userProfile != null || _isGuest;
  bool get isFullAuth => _userProfile != null && !_isGuest;

  String get currentGroupTitle => _isGuest
      ? _guestGroupTitle
      : (_userProfile?.groupTitle.isNotEmpty == true
          ? _userProfile!.groupTitle
          : 'Студент');

  String get currentGroupUuid => _isGuest
      ? _guestGroupUuid
      : (_userProfile?.groupUuid ?? '');

  Future<void> setGuestGroup(String title, String uuid) async {
    _guestGroupTitle = title;
    _guestGroupUuid = uuid;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyGuestGroupTitle, title);
      await prefs.setString(_keyGuestGroupUuid, uuid);
    } catch (_) {}
    notifyListeners();
  }

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  // Attempt auto-login with offline cache fallback
  Future<bool> checkSavedAuth() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // 1. Check if user was in guest mode
      final wasGuest = prefs.getBool(_keyIsGuest) ?? false;
      if (wasGuest) {
        final savedTitle = prefs.getString(_keyGuestGroupTitle);
        final savedUuid = prefs.getString(_keyGuestGroupUuid);
        _isGuest = true;
        _userProfile = null;
        if (savedTitle != null && savedUuid != null) {
          _guestGroupTitle = savedTitle;
          _guestGroupUuid = savedUuid;
        }
        notifyListeners();
        return true;
      }

      // 2. Check if we have a cached user profile
      final cachedProfileJson = prefs.getString(_keyCachedProfile);
      if (cachedProfileJson != null && cachedProfileJson.isNotEmpty) {
        try {
          final decoded = jsonDecode(cachedProfileJson) as Map<String, dynamic>;
          _userProfile = UserProfile.fromJson(decoded);
          _isGuest = false;
          notifyListeners();
        } catch (e) {
          debugPrint('[AuthProvider] Failed to decode cached profile: $e');
        }
      }

      // 3. Check saved credentials
      final creds = await authStorage.getCredentials();
      final user = creds['username'];
      final pass = creds['password'];

      if (user != null && user.isNotEmpty && pass != null && pass.isNotEmpty) {
        // If we already have a cached profile, user is authenticated offline!
        if (_userProfile != null) {
          // Attempt silent background refresh without blocking or kicking to login
          reloginSilently().catchError((e) {
            debugPrint('[AuthProvider] Background silent relogin failed (likely offline): $e');
            return false;
          });
          return true;
        }

        // No cached profile yet -> attempt online login
        return await login(user, pass, rememberMe: true);
      }

      // If user profile was restored from offline cache, remain authenticated
      if (_userProfile != null) {
        return true;
      }
    } catch (e) {
      debugPrint('[AuthProvider] checkSavedAuth error: $e');
      if (_userProfile != null || _isGuest) {
        return true;
      }
    }
    return false;
  }

  // Silent background re-authentication without clearing UI state
  Future<bool> reloginSilently() async {
    try {
      final creds = await authStorage.getCredentials();
      final user = creds['username'];
      final pass = creds['password'];

      if (user != null && user.isNotEmpty && pass != null && pass.isNotEmpty) {
        final profile = await apiService.login(user.trim(), pass);
        if (profile != null) {
          _userProfile = profile;
          _isGuest = false;
          _errorMessage = null;

          // Update cached profile
          try {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString(_keyCachedProfile, jsonEncode(profile.toJson()));
          } catch (_) {}

          notifyListeners();
          debugPrint('[AuthProvider] Silent relogin succeeded for ${profile.fullName}');
          return true;
        }
      }
    } catch (e) {
      debugPrint('[AuthProvider] Silent relogin failed: $e');
    }
    return false;
  }

  // Real-time login via Keycloak SSO
  Future<bool> login(String username, String password, {bool rememberMe = true}) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final profile = await apiService.login(username.trim(), password);
      if (profile != null) {
        _userProfile = profile;
        _isGuest = false;
        if (rememberMe) {
          await authStorage.saveCredentials(username.trim(), password);
        }

        // Save cached profile and clear guest flag
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(_keyCachedProfile, jsonEncode(profile.toJson()));
          await prefs.setBool(_keyIsGuest, false);
        } catch (_) {}

        _isLoading = false;
        notifyListeners();
        return true;
      } else {
        _errorMessage = 'Не удалось получить профиль студента';
      }
    } catch (e) {
      _errorMessage = e.toString().replaceAll('Exception: ', '');
    }

    _isLoading = false;
    notifyListeners();
    return false;
  }

  // Enter Guest / Demo mode (schedule only)
  Future<void> enterGuestMode({String? groupTitle, String? groupUuid}) async {
    _isGuest = true;
    _userProfile = null;
    _errorMessage = null;

    if (groupTitle != null && groupUuid != null) {
      _guestGroupTitle = groupTitle;
      _guestGroupUuid = groupUuid;
    } else {
      // Default to first known active group if needed
      final defaultFound = BmstuGroupsCatalog.findByTitle('ИУ7-43Б') ??
          (BmstuGroupsCatalog.popularGroups.isNotEmpty ? BmstuGroupsCatalog.popularGroups.first : null);
      if (defaultFound != null) {
        _guestGroupTitle = defaultFound.title;
        _guestGroupUuid = defaultFound.uuid;
      }
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_keyIsGuest, true);
      await prefs.setString(_keyGuestGroupTitle, _guestGroupTitle);
      await prefs.setString(_keyGuestGroupUuid, _guestGroupUuid);
      await prefs.remove(_keyCachedProfile);
    } catch (_) {}

    notifyListeners();
  }

  // Logout
  Future<void> logout() async {
    _userProfile = null;
    _isGuest = false;
    _errorMessage = null;
    await authStorage.clearCredentials();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_keyCachedProfile);
      await prefs.remove(_keyIsGuest);
      await prefs.remove(_keyGuestGroupTitle);
      await prefs.remove(_keyGuestGroupUuid);
    } catch (_) {}
    notifyListeners();
  }
}
