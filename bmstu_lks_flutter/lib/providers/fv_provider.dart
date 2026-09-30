import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/physical_culture.dart';
import '../models/sync_status.dart';
import '../services/bmstu_api_service.dart';

class FvProvider with ChangeNotifier {
  static const _cacheFvPrefix = 'cached_fv_v1_';
  static const _cacheFvTimePrefix = 'cached_fv_time_v1_';

  final BmstuApiService apiService;

  PhysicalCultureData? _data;
  bool _isLoading = false;
  String? _errorMessage;
  SyncStatus? _syncStatus;
  String _stageUuid = '';

  FvProvider({required this.apiService});

  PhysicalCultureData? get data => _data;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  SyncStatus? get syncStatus => _syncStatus;

  int get studyPoints => _data?.studyPoints ?? 0;
  int get studyAttends => _data?.studyAttends ?? 0;
  double get pointsProgress => _data?.pointsProgress ?? 0.0;
  double get attendsProgress => _data?.attendsProgress ?? 0.0;
  List<FvRecord> get currentRecords => _data?.groups ?? [];
  String get medGroup => _data?.medGroup ?? 'Не указана';
  String get medDate => _data?.medDate ?? '—';

  Future<void> _saveFvToCache(String stageUuid, PhysicalCultureData data) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('$_cacheFvPrefix$stageUuid', jsonEncode(data.toJson()));
      await prefs.setString('$_cacheFvTimePrefix$stageUuid', DateTime.now().toIso8601String());
    } catch (_) {}
  }

  Future<PhysicalCultureData?> _loadFvFromCache(String stageUuid) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('$_cacheFvPrefix$stageUuid');
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return PhysicalCultureData.fromJson(decoded);
    } catch (_) {
      return null;
    }
  }

  Future<DateTime?> _loadCacheTimestamp(String stageUuid) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('$_cacheFvTimePrefix$stageUuid');
      if (raw != null) return DateTime.tryParse(raw);
    } catch (_) {}
    return null;
  }

  Future<void> loadFv(String stageUuid) async {
    if (stageUuid.isEmpty) {
      _data = null;
      _isLoading = false;
      notifyListeners();
      return;
    }

    _stageUuid = stageUuid;

    // Fast offline preview
    if (_data == null) {
      final cached = await _loadFvFromCache(stageUuid);
      if (cached != null) {
        _data = cached;
        final cachedTime = await _loadCacheTimestamp(stageUuid);
        _syncStatus = SyncStatus(
          lastUpdated: cachedTime ?? DateTime.now(),
          isLive: false,
          itemCount: cached.groups.length,
          message: 'Офлайн-режим (сохранённая копия)',
        );
        notifyListeners();
      }
    }

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final fv = await apiService.getPhysicalCulture(stageUuid);
      if (fv != null) {
        _data = fv;
        await _saveFvToCache(stageUuid, fv);
      } else if (_data == null) {
        final cached = await _loadFvFromCache(stageUuid);
        if (cached != null) {
          _data = cached;
        }
      }
      _syncStatus = SyncStatus(
        lastUpdated: DateTime.now(),
        isLive: true,
        itemCount: _data?.groups.length ?? 0,
      );
      _errorMessage = null;
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      if (_data == null) {
        final cached = await _loadFvFromCache(stageUuid);
        if (cached != null) {
          _data = cached;
        }
      }
      final cachedTime = await _loadCacheTimestamp(stageUuid);
      _syncStatus = SyncStatus(
        lastUpdated: cachedTime ?? DateTime.now(),
        isLive: false,
        itemCount: _data?.groups.length ?? 0,
        message: _data != null
            ? 'Офлайн-режим (сохранённая копия)'
            : 'Ошибка обновления: $e',
      );
      _errorMessage = _data != null ? null : e.toString().replaceAll('Exception: ', '');
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> refresh() async {
    if (_stageUuid.isNotEmpty) {
      await loadFv(_stageUuid);
    }
  }

  void loadGuestSample() {
    _data = PhysicalCultureData.sampleGuest();
    _isLoading = false;
    notifyListeners();
  }
}
