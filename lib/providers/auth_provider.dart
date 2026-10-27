import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user_profile.dart';
import '../services/auth_storage.dart';
import '../services/background_sync.dart';
import '../services/bmstu_api_service.dart';
import '../services/bmstu_groups_catalog.dart';

class AuthProvider with ChangeNotifier {
  static const cachedProfileKey = 'bmstu_cached_user_profile_v1';
  static const _keyIsGuest = 'bmstu_is_guest_v1';
  static const _keyGuestGroupTitle = 'bmstu_guest_group_title_v1';
  static const _keyGuestGroupUuid = 'bmstu_guest_group_uuid_v1';

  final BmstuApiService apiService;
  final AuthStorage authStorage;

  UserProfile? _userProfile;
  bool _isGuest = false;
  bool _isLoading = false;
  String? _errorMessage;
  Future<bool>? _reloginInFlight;
  bool _needsLogin = false;
  int _sessionGeneration = 0;

  // Overwritten by the saved or picked group; the default must exist in the current catalog
  String _guestGroupTitle = BmstuGroupsCatalog.popularGroups.first.title;
  String _guestGroupUuid = BmstuGroupsCatalog.popularGroups.first.uuid;

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

  /// The cached profile is shown, but LKS can't be reached with it: there is no
  /// saved password (or LKS rejected it). The UI asks the student to sign in again.
  bool get needsLogin => _needsLogin;

  /// Grows with every successful (re)login, so screens know to reload the data
  /// they failed to fetch while the session was expired.
  int get sessionGeneration => _sessionGeneration;

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
    } catch (e) {
      debugPrint('[AuthProvider] Failed to save guest group: $e');
    }
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
      final cachedProfileJson = prefs.getString(cachedProfileKey);
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

      // 3. Cached profile: open the app right away and resume the session in the background
      if (_userProfile != null) {
        _resumeSession();
        return true;
      }

      // 4. No cached profile yet: sign in online with the saved credentials
      final creds = await authStorage.getCredentials();
      final user = creds['username'];
      final pass = creds['password'];
      if (user != null && user.isNotEmpty && pass != null && pass.isNotEmpty) {
        return await login(user, pass, rememberMe: true);
      }
    } catch (e) {
      debugPrint('[AuthProvider] checkSavedAuth error: $e');
      if (_userProfile != null || _isGuest) {
        return true;
      }
    }
    return false;
  }

  // Silent background re-authentication without clearing UI state.
  // Concurrent callers (API interceptor, providers, screens) share one SSO login.
  Future<bool> reloginSilently() {
    final pending = _reloginInFlight;
    if (pending != null) return pending;

    final relogin = _reloginSilently();
    _reloginInFlight = relogin;
    relogin.whenComplete(() {
      if (identical(_reloginInFlight, relogin)) _reloginInFlight = null;
    });
    return relogin;
  }

  // Saved cookies first (no password sent); a full SSO login only if LKS rejects them
  Future<void> _resumeSession() async {
    try {
      final profile = await apiService.restoreSession();
      if (profile != null) {
        _userProfile = profile;
        _needsLogin = false;
        await _cacheProfile(profile);
        notifyListeners();
        debugPrint('[AuthProvider] Saved LKS session resumed');
        return;
      }
    } on BmstuNetworkException catch (e) {
      debugPrint('[AuthProvider] Offline, keeping the cached profile: $e');
      return;
    } catch (e) {
      debugPrint('[AuthProvider] Saved session check failed: $e');
    }
    await reloginSilently();
  }

  Future<bool> _reloginSilently() async {
    try {
      final creds = await authStorage.getCredentials();
      final user = creds['username'];
      final pass = creds['password'];

      if (user == null || user.isEmpty || pass == null || pass.isEmpty) {
        // Nothing to sign in with (not remembered, or the Keychain was reset)
        debugPrint('[AuthProvider] Silent relogin impossible: no saved credentials');
        _setNeedsLogin(true);
        return false;
      }

      final profile = await apiService.login(user.trim(), pass);
      if (profile != null) {
        _userProfile = profile;
        _isGuest = false;
        _errorMessage = null;
        _needsLogin = false;
        _sessionGeneration++;
        await _cacheProfile(profile);
        notifyListeners();
        debugPrint('[AuthProvider] Silent relogin succeeded for ${profile.fullName}');
        return true;
      }
    } on BmstuNetworkException catch (e) {
      // Offline: the session may still be fine later, don't ask for the password
      debugPrint('[AuthProvider] Silent relogin failed: $e');
      return false;
    } catch (e) {
      // LKS rejected the saved credentials (e.g. password changed on the website)
      debugPrint('[AuthProvider] Silent relogin failed: $e');
    }
    _setNeedsLogin(true);
    return false;
  }

  void _setNeedsLogin(bool value) {
    if (_needsLogin == value || !isFullAuth) return;
    _needsLogin = value;
    notifyListeners();
  }

  Future<void> _cacheProfile(UserProfile profile) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(cachedProfileKey, jsonEncode(profile.toJson()));
    } catch (e) {
      debugPrint('[AuthProvider] Failed to cache profile: $e');
    }
  }

  // Real-time login via Keycloak SSO
  Future<bool> login(String username, String password, {bool rememberMe = true}) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      // Typed credentials must really be checked, not skipped thanks to a live SSO session
      await apiService.clearSession();
      final profile = await apiService.login(username.trim(), password);
      if (profile != null) {
        _userProfile = profile;
        _isGuest = false;
        _needsLogin = false;
        _sessionGeneration++;
        if (rememberMe) {
          try {
            await authStorage.saveCredentials(username.trim(), password);
          } on AuthStorageException catch (e) {
            // Session stays valid; credentials just won't survive an app restart
            debugPrint('[AuthProvider] Credentials not remembered: $e');
          }
        }

        // Save cached profile and clear guest flag
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(cachedProfileKey, jsonEncode(profile.toJson()));
          await prefs.setBool(_keyIsGuest, false);
        } catch (e) {
          debugPrint('[AuthProvider] Failed to cache profile after login: $e');
        }

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
    _needsLogin = false;
    await apiService.clearSession();

    if (groupTitle != null && groupUuid != null) {
      _guestGroupTitle = groupTitle;
      _guestGroupUuid = groupUuid;
    } else {
      final defaultGroup = BmstuGroupsCatalog.popularGroups.first;
      _guestGroupTitle = defaultGroup.title;
      _guestGroupUuid = defaultGroup.uuid;
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_keyIsGuest, true);
      await prefs.setString(_keyGuestGroupTitle, _guestGroupTitle);
      await prefs.setString(_keyGuestGroupUuid, _guestGroupUuid);
      await prefs.remove(cachedProfileKey);
    } catch (e) {
      debugPrint('[AuthProvider] Failed to save guest mode: $e');
    }

    notifyListeners();
  }

  // Logout
  Future<void> logout() async {
    _userProfile = null;
    _isGuest = false;
    _errorMessage = null;
    _needsLogin = false;
    await authStorage.clearCredentials();
    await apiService.clearSession();
    // No account, nothing to sync: stop background checks and server pushes
    try {
      if (await BackgroundSync.isEnabled()) await BackgroundSync.setEnabled(false);
    } catch (e) {
      debugPrint('[AuthProvider] Failed to turn off notifications on logout: $e');
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(cachedProfileKey);
      await prefs.remove(_keyIsGuest);
      await prefs.remove(_keyGuestGroupTitle);
      await prefs.remove(_keyGuestGroupUuid);
    } catch (e) {
      debugPrint('[AuthProvider] Failed to clear saved session on logout: $e');
    }
    notifyListeners();
  }
}
