import 'dart:io';
import 'package:bmstu_neo/services/cache_service.dart';
import 'package:bmstu_neo/services/cache_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late Directory dir;
  late CacheStore store;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    dir = await Directory.systemTemp.createTemp('cache_store_test');
    store = CacheStore.inDirectory(dir);
  });

  tearDown(() async {
    CacheStore.instance = CacheStore();
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  test('Values live in files, not in preferences, and survive a new store instance', () async {
    await store.write('cached_sched_v1_group/1 ё', '[{"a":1}]');

    expect(await CacheStore.inDirectory(dir).read('cached_sched_v1_group/1 ё'), '[{"a":1}]');
    expect((await SharedPreferences.getInstance()).getKeys(), isEmpty);
    expect(await store.read('cached_sched_v1_other'), isNull);

    await store.write('cached_sched_v1_group/1 ё', '[]');
    expect(await store.read('cached_sched_v1_group/1 ё'), '[]');
    expect(dir.listSync().where((f) => f.path.endsWith('.tmp')), isEmpty, reason: 'no leftovers of the atomic write');

    await store.remove('cached_sched_v1_group/1 ё');
    expect(await store.read('cached_sched_v1_group/1 ё'), isNull);
  });

  test('A value cached in preferences by an older version is moved over when read', () async {
    SharedPreferences.setMockInitialValues({'cached_progress_v1_stage': '[1]'});
    final prefs = await SharedPreferences.getInstance();

    expect(await store.read('cached_progress_v1_stage'), '[1]');
    expect(prefs.getString('cached_progress_v1_stage'), isNull);
    expect(await store.read('cached_progress_v1_stage'), '[1]', reason: 'now served from the file');
  });

  test('migrateLegacy moves cached data, keeps settings and never overwrites a newer file', () async {
    SharedPreferences.setMockInitialValues({
      'cached_sched_v1_g': 'old schedule',
      'cached_fv_v1_s': 'pe',
      'teacher_sched_t': 'teacher',
      'bmstu_session_results_cache': 'sessions',
      'bmstu_groups_catalog_v1': 'catalog',
      'homework_notes_v1': 'my notes',
      'notifications_progress_enabled_v1': true,
      'bmstu_groups_catalog_updated_at_v1': 123,
    });
    await store.write('cached_sched_v1_g', 'fresh schedule');

    await store.migrateLegacy();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getKeys(), {'homework_notes_v1', 'notifications_progress_enabled_v1', 'bmstu_groups_catalog_updated_at_v1'});
    expect(await store.read('cached_sched_v1_g'), 'fresh schedule');
    expect(await store.read('cached_fv_v1_s'), 'pe');
    expect(await store.read('teacher_sched_t'), 'teacher');
    expect(await store.read('bmstu_session_results_cache'), 'sessions');
    expect(await store.read('bmstu_groups_catalog_v1'), 'catalog');
  });

  test('The settings screen counts and clears cached data only', () async {
    SharedPreferences.setMockInitialValues({'cached_fv_v1_old': 'ёж', 'homework_notes_v1': 'my notes'});
    CacheStore.instance = store;
    await store.write('cached_sched_v1_g', '12345');
    await store.write('cached_sched_time_v1_g', '2026');

    final stats = await AppCacheManager.instance.getStats();
    expect(stats.totalSizeBytes, 5 + 4 + 4, reason: 'bytes, including what is still in preferences');
    expect(stats.entryCount, 2, reason: 'a timestamp is not an entry of its own');

    await AppCacheManager.instance.clearAll();
    expect((await AppCacheManager.instance.getStats()).totalSizeBytes, 0);
    expect(await store.read('cached_sched_v1_g'), isNull);
    expect((await SharedPreferences.getInstance()).getString('homework_notes_v1'), 'my notes');
  });

  test('Without a files directory the store works on top of preferences', () async {
    // The default store under `flutter test`
    final fallback = CacheStore();
    await fallback.write('cached_sched_v1_g', 'x');
    expect((await SharedPreferences.getInstance()).getString('cached_sched_v1_g'), 'x');
    expect(await fallback.read('cached_sched_v1_g'), 'x');
    await fallback.clear();
    expect(await fallback.read('cached_sched_v1_g'), isNull);
  });
}
