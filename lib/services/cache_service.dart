import 'cache_store.dart';

class CacheStats {
  final int totalSizeBytes;
  final int entryCount;

  const CacheStats({required this.totalSizeBytes, required this.entryCount});

  String get formattedTotalSize {
    if (totalSizeBytes < 1024) return '$totalSizeBytes Б';
    if (totalSizeBytes < 1024 * 1024) {
      return '${(totalSizeBytes / 1024).toStringAsFixed(1)} КБ';
    }
    return '${(totalSizeBytes / (1024 * 1024)).toStringAsFixed(2)} МБ';
  }
}

/// What the settings screen shows and clears: the downloaded data in [CacheStore].
class AppCacheManager {
  static final AppCacheManager instance = AppCacheManager._();
  AppCacheManager._();

  Future<CacheStats> getStats() async {
    final sizes = await CacheStore.instance.sizes();
    return CacheStats(
      totalSizeBytes: sizes.values.fold(0, (sum, size) => sum + size),
      // A value and its timestamp are one entry
      entryCount: sizes.keys.where((k) => !k.contains('_time_')).length,
    );
  }

  Future<void> clearAll() => CacheStore.instance.clear();
}
