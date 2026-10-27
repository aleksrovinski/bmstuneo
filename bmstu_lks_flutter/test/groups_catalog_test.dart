import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bmstu_neo/services/bmstu_api_service.dart';
import 'package:bmstu_neo/services/bmstu_groups_bundled.dart';
import 'package:bmstu_neo/services/bmstu_groups_catalog.dart';
import 'package:bmstu_neo/services/groups_catalog_sync.dart';

Map<String, dynamic> _structure(List<Map<String, dynamic>> groups) => {
      'data': {
        'abbr': 'МГТУ им. Н.Э. Баумана',
        'nodeType': 'university',
        'uuid': 'u-1',
        'children': [
          {
            'abbr': 'ИУ',
            'nodeType': 'faculty',
            'uuid': 'f-1',
            'children': [
              {
                'abbr': 'ИУ7',
                'nodeType': 'department',
                'uuid': 'd-1',
                'children': [
                  {'abbr': '2 курс', 'nodeType': 'course', 'course': 2, 'children': groups},
                ],
              },
            ],
          },
        ],
      },
      'date': '2026-10-21T12:00:00.000+03:00',
    };

// Serves a catalog without network and counts downloads
class FakeCatalogApi extends BmstuApiService {
  final List<GroupItem> groups;
  final Object? error;
  int fetchCalls = 0;
  Completer<void>? gate;

  FakeCatalogApi(this.groups, {this.error});

  @override
  Future<List<GroupItem>> fetchGroupsCatalog() async {
    fetchCalls++;
    if (gate != null) await gate!.future;
    if (error != null) throw error!;
    return groups;
  }
}

const _newGroup = GroupItem(title: 'ТСТ9-99Б', uuid: 'new-uuid', course: 1, semester: 1);
const _iu7 = GroupItem(title: 'ИУ7-31Б', uuid: 'bad351b6-ed29-11ef-becd-8753117d52b2', course: 2, semester: 3);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(BmstuGroupsCatalog.resetToBundled);

  group('BmstuGroupsCatalog', () {
    test('Bundled snapshot is non-trivial and contains every popular group', () {
      expect(bundledGroups.length, greaterThan(3000));
      expect(BmstuGroupsCatalog.isLive, isFalse);
      expect(BmstuGroupsCatalog.popularGroups, isNotEmpty);
      for (final g in BmstuGroupsCatalog.popularGroups) {
        expect(bundledGroups[g.title], g.uuid, reason: g.title);
      }
    });

    test('parseStructure flattens only group nodes, sorted, with course and semester', () {
      final groups = BmstuGroupsCatalog.parseStructure(_structure([
        {'abbr': 'ИУ7-32Б', 'nodeType': 'group', 'uuid': 'g-2', 'course': 2, 'semester': 3},
        {'abbr': 'ИУ7-31Б', 'nodeType': 'group', 'uuid': 'g-1', 'course': 2, 'semester': 3},
        {'abbr': 'без uuid', 'nodeType': 'group'},
      ]));

      expect(groups.map((g) => g.title), ['ИУ7-31Б', 'ИУ7-32Б']);
      expect(groups.first.uuid, 'g-1');
      expect(groups.first.course, 2);
      expect(groups.first.semester, 3);
    });

    test('Live catalog replaces the bundled one: new groups found, removed ones gone', () {
      expect(BmstuGroupsCatalog.findByTitle('ТСТ9-99Б'), isNull);
      final removed = bundledGroups.keys.firstWhere((t) => t != _iu7.title);

      BmstuGroupsCatalog.useLive([_iu7, _newGroup]);

      expect(BmstuGroupsCatalog.isLive, isTrue);
      expect(BmstuGroupsCatalog.count, 2);
      expect(BmstuGroupsCatalog.findByTitle('ТСТ9-99Б')?.uuid, 'new-uuid');
      expect(BmstuGroupsCatalog.search('тст9').map((g) => g.title), ['ТСТ9-99Б']);
      expect(BmstuGroupsCatalog.findByTitle(removed), isNull);
    });

    test('Popular groups drop entries that no longer exist after a semester rollover', () {
      BmstuGroupsCatalog.useLive([_iu7, _newGroup]);
      expect(BmstuGroupsCatalog.popularGroups.map((g) => g.title), ['ИУ7-31Б']);

      // None of the shortcuts survive: fall back to real groups instead of dead UUIDs
      BmstuGroupsCatalog.useLive([_newGroup]);
      expect(BmstuGroupsCatalog.popularGroups.map((g) => g.title), ['ТСТ9-99Б']);
    });

    test('Empty download keeps the current catalog', () {
      BmstuGroupsCatalog.useLive([]);
      expect(BmstuGroupsCatalog.isLive, isFalse);
      expect(BmstuGroupsCatalog.count, bundledGroups.length);
    });
  });

  group('GroupsCatalogSync', () {
    final now = DateTime(2026, 10, 21, 12);

    test('Downloads, caches, and skips the download while the cache is fresh', () async {
      SharedPreferences.setMockInitialValues({});
      final api = FakeCatalogApi([_iu7, _newGroup]);

      expect(await GroupsCatalogSync.ensureFresh(api, now: now), isTrue);
      expect(api.fetchCalls, 1);
      expect(BmstuGroupsCatalog.findByTitle('ТСТ9-99Б'), isNotNull);

      final prefs = await SharedPreferences.getInstance();
      final cached = jsonDecode(prefs.getString('bmstu_groups_catalog_v1')!) as List;
      expect(cached, hasLength(2));

      // App restart within a week: the cache is used, no network
      BmstuGroupsCatalog.resetToBundled();
      expect(await GroupsCatalogSync.ensureFresh(api, now: now.add(const Duration(days: 6))), isTrue);
      expect(api.fetchCalls, 1);
      expect(BmstuGroupsCatalog.findByTitle('ТСТ9-99Б')?.uuid, 'new-uuid');
    });

    test('Stale cache is used offline and kept when the refresh fails', () async {
      SharedPreferences.setMockInitialValues({
        'bmstu_groups_catalog_v1': jsonEncode([_newGroup.toJson()]),
        'bmstu_groups_catalog_updated_at_v1': now.subtract(const Duration(days: 8)).millisecondsSinceEpoch,
      });
      final api = FakeCatalogApi([], error: Exception('offline'));

      expect(await GroupsCatalogSync.ensureFresh(api, now: now), isTrue);
      expect(api.fetchCalls, 1);
      expect(BmstuGroupsCatalog.count, 1);
      expect(BmstuGroupsCatalog.findByTitle('ТСТ9-99Б'), isNotNull);
    });

    test('No cache and no network falls back to the bundled list without throwing', () async {
      SharedPreferences.setMockInitialValues({});
      final api = FakeCatalogApi([], error: Exception('offline'));

      expect(await GroupsCatalogSync.ensureFresh(api, now: now), isFalse);
      expect(BmstuGroupsCatalog.isLive, isFalse);
      expect(BmstuGroupsCatalog.count, bundledGroups.length);
    });

    test('Concurrent callers share one download', () async {
      SharedPreferences.setMockInitialValues({});
      final api = FakeCatalogApi([_iu7])..gate = Completer<void>();

      final calls = Future.wait(List.generate(3, (_) => GroupsCatalogSync.ensureFresh(api, now: now)));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      api.gate!.complete();

      expect(await calls, [true, true, true]);
      expect(api.fetchCalls, 1);
    });
  });
}
