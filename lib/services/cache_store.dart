import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../constants/app_mode.dart';

/// Where downloaded data lives between launches: schedules, progress, PE, session
/// results, teacher schedules and the groups catalog. One file per key.
///
/// It used to be SharedPreferences, which Android loads into memory whole on every
/// start (the background sync isolate included) and which is part of the device
/// backup. Preferences now hold only settings and the student's own notes.
///
/// Values written by older versions are moved over on first use ([read]) and by
/// [migrateLegacy]. Where there is no files directory (`flutter test`, a broken
/// platform channel) the store keeps working on top of SharedPreferences.
class CacheStore {
  /// Replaceable in tests.
  static CacheStore instance = CacheStore();

  /// Keys (or key prefixes) that hold cached data, as opposed to settings.
  static const cachePrefixes = [
    'cached_sched_v1_',
    'cached_sched_time_v1_',
    'cached_progress_v1_',
    'cached_progress_time_v1_',
    'cached_fv_v1_',
    'cached_fv_time_v1_',
    'teacher_sched_',
    'bmstu_session_results_cache',
    'bmstu_groups_catalog_v1',
  ];

  static bool isCacheKey(String key) => cachePrefixes.any(key.startsWith);

  final Future<Directory?> _directory;
  final _random = Random();

  CacheStore() : _directory = _defaultDirectory();

  /// Files in [directory]; used by tests.
  CacheStore.inDirectory(Directory directory) : _directory = Future.value(directory);

  static Future<Directory?> _defaultDirectory() async {
    // `flutter test`: no real file I/O inside widget tests (it never completes under
    // their fake clock), and the same behaviour on every host OS
    if (Platform.environment.containsKey('FLUTTER_TEST')) return null;
    try {
      final support = await getApplicationSupportDirectory();
      // The demo build keeps its data apart, like its preferences
      final dir = Directory('${support.path}/${AppMode.isDemo ? 'demo_cache_v1' : 'cache_v1'}');
      await dir.create(recursive: true);
      return dir;
    } catch (e) {
      debugPrint('[CacheStore] No files directory, caching in preferences: $e');
      return null;
    }
  }

  static File _file(Directory dir, String key) => File('${dir.path}/${Uri.encodeComponent(key)}.json');

  Future<String?> read(String key) async {
    final dir = await _directory;
    final prefs = await SharedPreferences.getInstance();
    if (dir == null) return prefs.getString(key);
    try {
      final file = _file(dir, key);
      if (await file.exists()) return await file.readAsString();
    } on FileSystemException catch (e) {
      debugPrint('[CacheStore] Failed to read $key: $e');
      return null;
    }
    // Written by a version that cached in preferences: move it over
    final legacy = prefs.getString(key);
    if (legacy == null) return null;
    await _moveFromPrefs(dir, prefs, key, legacy);
    return legacy;
  }

  Future<void> write(String key, String value) async {
    final dir = await _directory;
    if (dir == null) {
      await (await SharedPreferences.getInstance()).setString(key, value);
      return;
    }
    await _writeFile(dir, key, value);
  }

  Future<void> remove(String key) async {
    final dir = await _directory;
    if (dir != null) {
      final file = _file(dir, key);
      if (await file.exists()) await file.delete();
    }
    await (await SharedPreferences.getInstance()).remove(key);
  }

  /// Size in bytes of every cached value, by key.
  Future<Map<String, int>> sizes() async {
    final result = <String, int>{};
    final prefs = await SharedPreferences.getInstance();
    for (final key in prefs.getKeys().where(isCacheKey)) {
      final value = prefs.get(key);
      if (value is String) result[key] = utf8.encode(value).length;
    }
    final dir = await _directory;
    if (dir != null && await dir.exists()) {
      await for (final entity in dir.list()) {
        if (entity is! File || !entity.path.endsWith('.json')) continue;
        final name = entity.uri.pathSegments.last;
        result[Uri.decodeComponent(name.substring(0, name.length - '.json'.length))] = await entity.length();
      }
    }
    return result;
  }

  /// Deletes all cached data; settings and the student's own notes are not touched.
  Future<void> clear() async {
    final dir = await _directory;
    if (dir != null && await dir.exists()) {
      await for (final entity in dir.list()) {
        if (entity is File) await entity.delete();
      }
    }
    final prefs = await SharedPreferences.getInstance();
    for (final key in prefs.getKeys().where(isCacheKey).toList()) {
      await prefs.remove(key);
    }
  }

  /// Moves everything older versions cached in preferences into files. Cheap when
  /// there is nothing left to move, so the app calls it on every start.
  Future<void> migrateLegacy() async {
    final dir = await _directory;
    if (dir == null) return;
    final prefs = await SharedPreferences.getInstance();
    for (final key in prefs.getKeys().where(isCacheKey).toList()) {
      final value = prefs.get(key);
      if (value is String) {
        await _moveFromPrefs(dir, prefs, key, value);
      } else {
        await prefs.remove(key);
      }
    }
  }

  Future<void> _moveFromPrefs(Directory dir, SharedPreferences prefs, String key, String value) async {
    try {
      // A file that appeared meanwhile is newer than the preferences copy
      if (!await _file(dir, key).exists()) await _writeFile(dir, key, value);
      await prefs.remove(key);
    } on FileSystemException catch (e) {
      debugPrint('[CacheStore] Failed to move $key out of preferences: $e');
    }
  }

  // Written next to the target and renamed over it: a reader (the background sync runs
  // in its own isolate) sees the old value or the new one, never half a file
  Future<void> _writeFile(Directory dir, String key, String value) async {
    final file = _file(dir, key);
    final tmp = File('${file.path}.${_random.nextInt(1 << 32)}.tmp');
    try {
      await tmp.writeAsString(value, flush: true);
      await tmp.rename(file.path);
    } on FileSystemException {
      if (await tmp.exists()) await tmp.delete();
      rethrow;
    }
  }
}
