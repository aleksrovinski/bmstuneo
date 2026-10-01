import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/bmstu_groups_catalog.dart';
import '../services/bmstu_api_service.dart';

class FavoritesProvider with ChangeNotifier {
  static const _keyFavoriteGroups = 'bmstu_favorites_groups_v1';
  static const _keyFavoriteTeachers = 'bmstu_favorites_teachers_v1';

  List<GroupItem> _favoriteGroups = [];
  List<TeacherSearchItem> _favoriteTeachers = [];

  List<GroupItem> get favoriteGroups => _favoriteGroups;
  List<TeacherSearchItem> get favoriteTeachers => _favoriteTeachers;

  FavoritesProvider() {
    loadFavorites();
  }

  Future<void> loadFavorites() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Groups
      final groupsRaw = prefs.getString(_keyFavoriteGroups);
      if (groupsRaw != null && groupsRaw.isNotEmpty) {
        final decoded = jsonDecode(groupsRaw) as List;
        _favoriteGroups = decoded
            .map((e) => GroupItem(
                  title: e['title']?.toString() ?? '',
                  uuid: e['uuid']?.toString() ?? '',
                ))
            .where((g) => g.title.isNotEmpty && g.uuid.isNotEmpty)
            .toList();
      }

      // Teachers
      final teachersRaw = prefs.getString(_keyFavoriteTeachers);
      if (teachersRaw != null && teachersRaw.isNotEmpty) {
        final decoded = jsonDecode(teachersRaw) as List;
        _favoriteTeachers = decoded
            .map((e) => TeacherSearchItem(
                  title: e['title']?.toString() ?? '',
                  uuid: e['uuid']?.toString() ?? '',
                ))
            .where((t) => t.title.isNotEmpty && t.uuid.isNotEmpty)
            .toList();
      }

      notifyListeners();
    } catch (e) {
      debugPrint('[FavoritesProvider] Error loading favorites: $e');
    }
  }

  bool isGroupFavorite(String uuid) {
    if (uuid.isEmpty) return false;
    return _favoriteGroups.any((g) => g.uuid == uuid);
  }

  Future<void> toggleGroupFavorite(GroupItem group) async {
    final idx = _favoriteGroups.indexWhere((g) => g.uuid == group.uuid);
    if (idx >= 0) {
      _favoriteGroups.removeAt(idx);
    } else {
      _favoriteGroups.add(group);
    }
    notifyListeners();
    await _saveFavoriteGroups();
  }

  bool isTeacherFavorite(String uuid) {
    if (uuid.isEmpty) return false;
    return _favoriteTeachers.any((t) => t.uuid == uuid);
  }

  Future<void> toggleTeacherFavorite(TeacherSearchItem teacher) async {
    final idx = _favoriteTeachers.indexWhere((t) => t.uuid == teacher.uuid);
    if (idx >= 0) {
      _favoriteTeachers.removeAt(idx);
    } else {
      _favoriteTeachers.add(teacher);
    }
    notifyListeners();
    await _saveFavoriteTeachers();
  }

  Future<void> _saveFavoriteGroups() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = _favoriteGroups
          .map((g) => {'title': g.title, 'uuid': g.uuid})
          .toList();
      await prefs.setString(_keyFavoriteGroups, jsonEncode(list));
    } catch (_) {}
  }

  Future<void> _saveFavoriteTeachers() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = _favoriteTeachers
          .map((t) => {'title': t.title, 'uuid': t.uuid})
          .toList();
      await prefs.setString(_keyFavoriteTeachers, jsonEncode(list));
    } catch (_) {}
  }
}
