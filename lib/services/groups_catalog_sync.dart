import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'bmstu_api_service.dart';
import 'bmstu_groups_catalog.dart';

/// Keeps [BmstuGroupsCatalog] in sync with the live LKS structure.
///
/// The downloaded catalog is cached on the device and refreshed once it is
/// older than [maxAge]; without network the cached (or bundled) list is used.
class GroupsCatalogSync {
  static const _keyCatalog = 'bmstu_groups_catalog_v1';
  static const _keyUpdatedAt = 'bmstu_groups_catalog_updated_at_v1';
  static const maxAge = Duration(days: 7);

  static Future<bool>? _inFlight;

  /// Loads the cached catalog and downloads a new one if it is stale.
  /// Returns true if the catalog in use changed. Never throws.
  static Future<bool> ensureFresh(BmstuApiService api, {DateTime? now}) {
    final pending = _inFlight;
    if (pending != null) return pending;

    final sync = _ensureFresh(api, now ?? DateTime.now());
    _inFlight = sync;
    sync.whenComplete(() {
      if (identical(_inFlight, sync)) _inFlight = null;
    });
    return sync;
  }

  static Future<bool> _ensureFresh(BmstuApiService api, DateTime now) async {
    var changed = false;
    SharedPreferences? prefs;
    DateTime? updatedAt;

    try {
      prefs = await SharedPreferences.getInstance();
      final millis = prefs.getInt(_keyUpdatedAt);
      updatedAt = millis != null ? DateTime.fromMillisecondsSinceEpoch(millis) : null;

      if (!BmstuGroupsCatalog.isLive) {
        final cached = prefs.getString(_keyCatalog);
        if (cached != null) {
          final groups = (jsonDecode(cached) as List)
              .whereType<Map<String, dynamic>>()
              .map(GroupItem.fromJson)
              .toList();
          if (groups.isNotEmpty) {
            BmstuGroupsCatalog.useLive(groups);
            changed = true;
          }
        }
      }
    } catch (e) {
      debugPrint('[GroupsCatalogSync] Failed to read cached catalog: $e');
    }

    if (updatedAt != null && now.difference(updatedAt) < maxAge && BmstuGroupsCatalog.isLive) {
      return changed;
    }

    try {
      final groups = await api.fetchGroupsCatalog();
      if (groups.isEmpty) return changed;
      BmstuGroupsCatalog.useLive(groups);
      await prefs?.setString(_keyCatalog, jsonEncode(groups.map((g) => g.toJson()).toList()));
      await prefs?.setInt(_keyUpdatedAt, now.millisecondsSinceEpoch);
      return true;
    } catch (e) {
      debugPrint('[GroupsCatalogSync] Catalog refresh failed, keeping current list: $e');
      return changed;
    }
  }
}
