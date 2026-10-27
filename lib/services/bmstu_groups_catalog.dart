import 'package:flutter/foundation.dart';
import 'bmstu_groups_bundled.dart';

class GroupItem {
  final String title;
  final String uuid;
  final int? course;
  final int? semester;

  const GroupItem({
    required this.title,
    required this.uuid,
    this.course,
    this.semester,
  });

  factory GroupItem.fromJson(Map<String, dynamic> json) => GroupItem(
        title: json['title']?.toString() ?? '',
        uuid: json['uuid']?.toString() ?? '',
        course: (json['course'] as num?)?.toInt(),
        semester: (json['semester'] as num?)?.toInt(),
      );

  Map<String, dynamic> toJson() => {
        'title': title,
        'uuid': uuid,
        if (course != null) 'course': course,
        if (semester != null) 'semester': semester,
      };
}

typedef BmstuGroup = GroupItem;

/// Catalog of study groups for the group picker and guest mode.
///
/// Uses the list downloaded from LKS (see [GroupsCatalogSync]) once it is
/// available, and the bundled snapshot from [bundledGroups] until then.
class BmstuGroupsCatalog {
  static const List<GroupItem> _popularCandidates = [
    GroupItem(title: 'РК5-32Б', uuid: 'bad86778-ed29-11ef-becd-8753117d52b2'),
    GroupItem(title: 'РК5-31Б', uuid: 'bad71d71-ed29-11ef-becd-8753117d52b2'),
    GroupItem(title: 'ИУ7-31Б', uuid: 'bad351b6-ed29-11ef-becd-8753117d52b2'),
    GroupItem(title: 'ИУ7-32Б', uuid: 'bad8684b-ed29-11ef-becd-8753117d52b2'),
    GroupItem(title: 'ИУ7-11Б', uuid: 'ab0cda86-1624-11f1-9d39-005056aae53e'),
    GroupItem(title: 'СМ1-31', uuid: 'bad49018-ed29-11ef-becd-8753117d52b2'),
    GroupItem(title: 'БМТ1-31Б', uuid: 'bad0aa78-ed29-11ef-becd-8753117d52b2'),
    GroupItem(title: 'ИБМ4-31Б', uuid: 'bad5dd25-ed29-11ef-becd-8753117d52b2'),
    GroupItem(title: 'РЛ1-31', uuid: 'bad0ac91-ed29-11ef-becd-8753117d52b2'),
  ];

  static Map<String, GroupItem>? _live;
  static final Map<String, GroupItem> _bundled =
      bundledGroups.map((title, uuid) => MapEntry(title, GroupItem(title: title, uuid: uuid)));

  static Map<String, GroupItem> get _groups => _live ?? _bundled;

  /// Replaces the bundled snapshot with a catalog downloaded from LKS.
  static void useLive(List<GroupItem> groups) {
    if (groups.isEmpty) return;
    _live = {for (final g in groups) g.title: g};
  }

  @visibleForTesting
  static void resetToBundled() => _live = null;

  static bool get isLive => _live != null;

  static int get count => _groups.length;

  /// Shortcuts shown before the user types; groups are renamed every semester,
  /// so only those still present in the current catalog are offered.
  static List<GroupItem> get popularGroups {
    final groups = _groups;
    final present = _popularCandidates
        .where((g) => groups[g.title]?.uuid == g.uuid)
        .toList();
    if (present.isNotEmpty) return present;
    return groups.values.take(_popularCandidates.length).toList();
  }

  static List<GroupItem> search(String query, {int limit = 40}) {
    if (query.trim().isEmpty) return popularGroups;
    final clean = _normalize(query);
    final results = <GroupItem>[];
    for (final group in _groups.values) {
      if (_normalize(group.title).contains(clean)) {
        results.add(group);
        if (results.length >= limit) break;
      }
    }
    return results;
  }

  static GroupItem? findByTitle(String title) => _groups[title];

  /// Flattens the `/structure` tree (university → faculty → department → course → group).
  static List<GroupItem> parseStructure(Map<String, dynamic> json) {
    final groups = <GroupItem>[];
    void walk(Map<String, dynamic> node) {
      final uuid = node['uuid']?.toString();
      final title = node['abbr']?.toString();
      if (node['nodeType'] == 'group' && uuid != null && uuid.isNotEmpty && title != null && title.isNotEmpty) {
        groups.add(GroupItem(
          title: title,
          uuid: uuid,
          course: (node['course'] as num?)?.toInt(),
          semester: (node['semester'] as num?)?.toInt(),
        ));
      }
      for (final child in (node['children'] as List? ?? const []).whereType<Map<String, dynamic>>()) {
        walk(child);
      }
    }

    final root = json['data'] ?? json;
    if (root is Map<String, dynamic>) walk(root);
    groups.sort((a, b) => a.title.compareTo(b.title));
    return groups;
  }

  static String _normalize(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-zа-яё0-9]'), '');
}
