import 'package:flutter/foundation.dart';
import '../models/user_profile.dart';
import '../services/auth_storage.dart';
import '../services/bmstu_api_service.dart';
import '../services/bmstu_groups_catalog.dart';

class AuthProvider with ChangeNotifier {
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
  });

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

  void setGuestGroup(String title, String uuid) {
    _guestGroupTitle = title;
    _guestGroupUuid = uuid;
    notifyListeners();
  }

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  // Attempt auto-login if credentials exist
  Future<bool> checkSavedAuth() async {
    try {
      final creds = await authStorage.getCredentials();
      final user = creds['username'];
      final pass = creds['password'];

      if (user != null && user.isNotEmpty && pass != null && pass.isNotEmpty) {
        return await login(user, pass, rememberMe: true);
      }
    } catch (_) {}
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
  void enterGuestMode({String? groupTitle, String? groupUuid}) {
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

    notifyListeners();
  }

  // Logout
  Future<void> logout() async {
    _userProfile = null;
    _isGuest = false;
    _errorMessage = null;
    await authStorage.clearCredentials();
    notifyListeners();
  }
}
