import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CacheItem<T> {
  final T data;
  final DateTime cachedAt;
  final int sizeBytes;

  const CacheItem({
    required this.data,
    required this.cachedAt,
    required this.sizeBytes,
  });
}

class CacheStats {
  final int totalSizeBytes;
  final int entryCount;
  final Map<String, int> sizeByCategory;

  const CacheStats({
    required this.totalSizeBytes,
    required this.entryCount,
    required this.sizeByCategory,
  });

  String get formattedTotalSize {
    if (totalSizeBytes < 1024) return '$totalSizeBytes B';
    if (totalSizeBytes < 1024 * 1024) {
      return '${(totalSizeBytes / 1024).toStringAsFixed(1)} КБ';
    }
    return '${(totalSizeBytes / (1024 * 1024)).toStringAsFixed(2)} МБ';
  }
}

/// Centralized Cache Manager providing fast L1 in-memory cache and L2 disk persistence
class AppCacheManager {
  static final AppCacheManager instance = AppCacheManager._();
  AppCacheManager._();

  // In-Memory L1 Cache
  final Map<String, CacheItem<dynamic>> _memCache = {};

  // Prefixes for categorized tracking
  static const String prefixSchedule = 'bmstu_cache_sched_';
  static const String prefixProgress = 'bmstu_cache_prog_';
  static const String prefixFv = 'bmstu_cache_fv_';
  static const String prefixProfile = 'bmstu_cache_prof_';
  static const String prefixFavorites = 'bmstu_cache_fav_';
  static const String prefixTimeSuffix = '_time';

  /// Save data to L1 (memory) and L2 (SharedPreferences)
  Future<void> set<T>({
    required String key,
    required T data,
    String? category,
  }) async {
    final now = DateTime.now();
    final jsonStr = jsonEncode(data);
    final size = utf8.encode(jsonStr).length;

    // 1. Update L1 In-Memory
    _memCache[key] = CacheItem<dynamic>(
      data: data,
      cachedAt: now,
      sizeBytes: size,
    );

    // 2. Persist to L2 Disk
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, jsonStr);
      await prefs.setString('$key$prefixTimeSuffix', now.toIso8601String());
    } catch (e) {
      debugPrint('[AppCacheManager] Failed to persist key $key: $e');
    }
  }

  /// Read data, checking L1 (memory) first, then L2 (disk)
  Future<CacheItem<T>?> get<T>({
    required String key,
    required T Function(dynamic json) fromJson,
  }) async {
    // 1. Check L1 In-Memory
    if (_memCache.containsKey(key)) {
      final item = _memCache[key]!;
      try {
        return CacheItem<T>(
          data: item.data is T ? (item.data as T) : fromJson(item.data),
          cachedAt: item.cachedAt,
          sizeBytes: item.sizeBytes,
        );
      } catch (_) {}
    }

    // 2. Read from L2 Disk
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(key);
      if (raw == null || raw.isEmpty) return null;

      final timeStr = prefs.getString('$key$prefixTimeSuffix');
      final cachedAt = timeStr != null ? (DateTime.tryParse(timeStr) ?? DateTime.now()) : DateTime.now();
      final decoded = jsonDecode(raw);
      final size = utf8.encode(raw).length;
      final typedData = fromJson(decoded);

      // Populate L1 cache
      _memCache[key] = CacheItem<dynamic>(
        data: typedData,
        cachedAt: cachedAt,
        sizeBytes: size,
      );

      return CacheItem<T>(
        data: typedData,
        cachedAt: cachedAt,
        sizeBytes: size,
      );
    } catch (e) {
      debugPrint('[AppCacheManager] Error reading key $key: $e');
      return null;
    }
  }

  /// Remove a specific key
  Future<void> remove(String key) async {
    _memCache.remove(key);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(key);
      await prefs.remove('$key$prefixTimeSuffix');
    } catch (_) {}
  }

  /// Calculate total cache size and entry statistics
  Future<CacheStats> getStats() async {
    int totalBytes = 0;
    int entryCount = 0;
    final categorySizes = <String, int>{
      'Расписание': 0,
      'Прогресс и БРС': 0,
      'ФКиС': 0,
      'Профиль': 0,
      'Прочее': 0,
    };

    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys();

      for (final k in keys) {
        if (k.endsWith(prefixTimeSuffix)) continue;
        final val = prefs.get(k);
        if (val is String) {
          final bytes = utf8.encode(val).length;
          totalBytes += bytes;
          entryCount++;

          if (k.contains('sched')) {
            categorySizes['Расписание'] = (categorySizes['Расписание'] ?? 0) + bytes;
          } else if (k.contains('progress') || k.contains('prog')) {
            categorySizes['Прогресс и БРС'] = (categorySizes['Прогресс и БРС'] ?? 0) + bytes;
          } else if (k.contains('fv')) {
            categorySizes['ФКиС'] = (categorySizes['ФКиС'] ?? 0) + bytes;
          } else if (k.contains('prof') || k.contains('user')) {
            categorySizes['Профиль'] = (categorySizes['Профиль'] ?? 0) + bytes;
          } else {
            categorySizes['Прочее'] = (categorySizes['Прочее'] ?? 0) + bytes;
          }
        }
      }
    } catch (_) {}

    return CacheStats(
      totalSizeBytes: totalBytes,
      entryCount: entryCount,
      sizeByCategory: categorySizes,
    );
  }

  /// Clear cache by optional category prefix or everything
  Future<void> clearAll({String? categoryPrefix}) async {
    _memCache.clear();
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys().toList();
      for (final k in keys) {
        if (categoryPrefix != null) {
          if (k.startsWith(categoryPrefix) || k.contains(categoryPrefix)) {
            await prefs.remove(k);
          }
        } else {
          // Clear cache keys while keeping critical settings (e.g. auth tokens/theme)
          if (k.startsWith('bmstu_cache_') ||
              k.startsWith('cached_') ||
              k.startsWith('teacher_sched_') ||
              k.contains('cached_sched') ||
              k.contains('cached_progress') ||
              k.contains('cached_fv')) {
            await prefs.remove(k);
          }
        }
      }
    } catch (_) {}
  }
}
