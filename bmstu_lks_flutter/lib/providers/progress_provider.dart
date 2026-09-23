import 'package:flutter/foundation.dart';
import '../models/discipline_progress.dart';
import '../models/sync_status.dart';
import '../services/bmstu_api_service.dart';

enum DeadlineStatus {
  passed,
  thisWeek,
  upcoming,
  overdue,
}

enum DeadlineTypeFilter {
  all,
  homework, // ДЗ
  control,  // РК, КР
  module,   // М
}

enum ProgressCategory {
  controls,   // Текущий прогресс (ДЗ, РК, КР, М)
  laboratory, // Лабораторные работы (ЛР)
  seminars,   // Семинарские занятия (СЗ)
}

enum ProgressStatusFilter {
  all,
  issued,     // Выдано (надо сдать)
  submitted,  // Сдано / Защищено
  notIssued,  // Не выдано
}

class ProgressProvider with ChangeNotifier {
  final BmstuApiService apiService;

  List<DisciplineProgress> _disciplines = [];
  bool _isLoading = false;
  String? _errorMessage;
  SyncStatus? _syncStatus;
  String _stageUuid = '';

  ProgressCategory _activeCategory = ProgressCategory.controls;
  ProgressStatusFilter _statusFilter = ProgressStatusFilter.all;
  DeadlineTypeFilter _typeFilter = DeadlineTypeFilter.all;
  String _searchQuery = '';
  Future<bool> Function()? onSilentRelogin;

  ProgressProvider({
    required this.apiService,
    this.onSilentRelogin,
  });

  List<DisciplineProgress> get disciplines => _disciplines;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  SyncStatus? get syncStatus => _syncStatus;
  String get stageUuid => _stageUuid;
  ProgressCategory get activeCategory => _activeCategory;
  ProgressStatusFilter get statusFilter => _statusFilter;
  DeadlineTypeFilter get typeFilter => _typeFilter;
  String get searchQuery => _searchQuery;

  void setActiveCategory(ProgressCategory category) {
    _activeCategory = category;
    notifyListeners();
  }

  void setStatusFilter(ProgressStatusFilter filter) {
    _statusFilter = filter;
    notifyListeners();
  }

  void setTypeFilter(DeadlineTypeFilter filter) {
    _typeFilter = filter;
    notifyListeners();
  }

  void setSearchQuery(String query) {
    _searchQuery = query;
    notifyListeners();
  }

  Future<void> loadProgress(String stageUuid, {bool isRetry = false}) async {
    if (stageUuid.isEmpty) {
      _disciplines = [];
      _isLoading = false;
      notifyListeners();
      return;
    }

    _stageUuid = stageUuid;
    if (!isRetry) {
      _isLoading = true;
      _errorMessage = null;
      notifyListeners();
    }

    try {
      _disciplines = await apiService.getProgress(stageUuid);
      _syncStatus = SyncStatus(
        lastUpdated: DateTime.now(),
        isLive: true,
        itemCount: _disciplines.length,
      );
      _errorMessage = null;
      _isLoading = false;
      notifyListeners();
    } on BmstuAuthException catch (authErr) {
      debugPrint('[ProgressProvider] Auth failure caught: $authErr. Attempting auto-relogin...');
      if (!isRetry && onSilentRelogin != null) {
        final reloginSuccess = await onSilentRelogin!();
        if (reloginSuccess) {
          debugPrint('[ProgressProvider] Silent relogin succeeded, retrying loadProgress...');
          return await loadProgress(_stageUuid, isRetry: true);
        }
      }
      _errorMessage = 'Сессия ЛКС устарела. Не удалось обновить прогресс.';
      _syncStatus = SyncStatus(
        lastUpdated: DateTime.now(),
        isLive: false,
        itemCount: _disciplines.length,
        message: _errorMessage,
      );
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      debugPrint('[ProgressProvider] Error loading progress: $e. Attempting auto-relogin...');
      if (!isRetry && onSilentRelogin != null) {
        final reloginSuccess = await onSilentRelogin!();
        if (reloginSuccess) {
          debugPrint('[ProgressProvider] Silent relogin succeeded, retrying loadProgress...');
          return await loadProgress(_stageUuid, isRetry: true);
        }
      }
      _errorMessage = e.toString().replaceAll('Exception: ', '');
      _syncStatus = SyncStatus(
        lastUpdated: DateTime.now(),
        isLive: false,
        itemCount: _disciplines.length,
        message: 'Ошибка обновления: $_errorMessage',
      );
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> refresh() async {
    if (_stageUuid.isNotEmpty) {
      await loadProgress(_stageUuid);
    }
  }

  // Disciplines filtered for the active category, status filter and search query
  List<DisciplineProgress> get filteredDisciplines {
    var list = _disciplines;

    // 1. Filter by active category
    if (_activeCategory == ProgressCategory.controls) {
      list = list.where((d) => d.controls.isNotEmpty).toList();
    } else if (_activeCategory == ProgressCategory.laboratory) {
      list = list.where((d) => d.laboratory.isNotEmpty).toList();
    } else if (_activeCategory == ProgressCategory.seminars) {
      list = list.where((d) => d.seminars.isNotEmpty).toList();
    }

    // 2. Filter by status (issued, submitted, notIssued)
    if (_statusFilter != ProgressStatusFilter.all) {
      list = list.where((d) {
        final events = getEventsForDiscipline(d, _activeCategory);
        if (_statusFilter == ProgressStatusFilter.issued) {
          return events.any((e) => e.isIssued);
        } else if (_statusFilter == ProgressStatusFilter.submitted) {
          return events.any((e) => e.isSubmitted);
        } else if (_statusFilter == ProgressStatusFilter.notIssued) {
          return events.any((e) => e.isNotIssued);
        }
        return true;
      }).toList();
    }

    // 3. Filter by search query
    if (_searchQuery.trim().isNotEmpty) {
      final q = _searchQuery.trim().toLowerCase();
      list = list.where((d) {
        final titleMatch = d.title.toLowerCase().contains(q);
        if (titleMatch) return true;
        // Check events
        final events = getEventsForDiscipline(d, _activeCategory);
        return events.any((e) =>
            e.title.toLowerCase().contains(q) ||
            e.type.toLowerCase().contains(q));
      }).toList();
    }

    return list;
  }

  // Helper to extract the list of events for a category from a discipline
  List<ControlEvent> getEventsForDiscipline(
      DisciplineProgress disc, ProgressCategory category) {
    switch (category) {
      case ProgressCategory.controls:
        return disc.controls;
      case ProgressCategory.laboratory:
        return disc.laboratory;
      case ProgressCategory.seminars:
        return disc.seminars;
    }
  }

  // Current category events across all disciplines
  List<ControlEvent> get currentCategoryAllEvents {
    final list = <ControlEvent>[];
    for (final disc in _disciplines) {
      list.addAll(getEventsForDiscipline(disc, _activeCategory));
    }
    return list;
  }

  int get currentCategoryTotalCount => currentCategoryAllEvents.length;
  int get currentCategoryIssuedCount => currentCategoryAllEvents.where((e) => e.isIssued).length;
  int get currentCategorySubmittedCount => currentCategoryAllEvents.where((e) => e.isSubmitted).length;
  int get currentCategoryNotIssuedCount => currentCategoryAllEvents.where((e) => e.isNotIssued).length;
  int get currentCategoryMissedCount => currentCategoryAllEvents.where((e) => e.isMissed).length;

  // All controls across all disciplines sorted chronologically by week (1 to 17)
  List<ControlEvent> getAllControlEvents() {
    final list = <ControlEvent>[];
    for (final disc in _disciplines) {
      list.addAll(disc.controls);
    }
    list.sort((a, b) {
      final wCmp = a.week.compareTo(b.week);
      if (wCmp != 0) return wCmp;
      final dCmp = a.disciplineTitle.compareTo(b.disciplineTitle);
      if (dCmp != 0) return dCmp;
      return a.type.compareTo(b.type);
    });
    return list;
  }

  // Filtered list based on type filter and search query (for deadlines list)
  List<ControlEvent> getFilteredDeadlines() {
    final all = getAllControlEvents();

    return all.where((event) {
      // Type filter
      if (_typeFilter == DeadlineTypeFilter.homework && event.type != 'ДЗ') {
        return false;
      }
      if (_typeFilter == DeadlineTypeFilter.control && !['РК', 'КР'].contains(event.type)) {
        return false;
      }
      if (_typeFilter == DeadlineTypeFilter.module && event.type != 'М') {
        return false;
      }

      // Search query
      if (_searchQuery.trim().isNotEmpty) {
        final q = _searchQuery.trim().toLowerCase();
        final inDisc = event.disciplineTitle.toLowerCase().contains(q);
        final inTitle = event.title.toLowerCase().contains(q);
        final inType = event.type.toLowerCase().contains(q);
        if (!inDisc && !inTitle && !inType) return false;
      }

      return true;
    }).toList();
  }

  // Group filtered deadlines by week
  Map<int, List<ControlEvent>> getDeadlinesGroupedByWeek() {
    final filtered = getFilteredDeadlines();
    final map = <int, List<ControlEvent>>{};
    for (final event in filtered) {
      map.putIfAbsent(event.week, () => []).add(event);
    }
    return map;
  }

  // Nearest deadlines for Home Screen:
  // Priority 1: Issued homeworks and controls that are not yet submitted (they are ACTIVE tasks!)
  // Priority 2: Upcoming deadlines close to current week
  List<ControlEvent> getNearestDeadlines(int currentWeekNum, {int limit = 4}) {
    final all = getAllControlEvents();
    if (all.isEmpty) return [];

    final issued = all.where((c) => c.isIssued).toList();
    final otherPending = all.where((c) => !c.isSubmitted && !c.isIssued).toList();

    issued.sort((a, b) => a.week.compareTo(b.week));
    otherPending.sort((a, b) {
      final diffA = (a.week - currentWeekNum).abs();
      final diffB = (b.week - currentWeekNum).abs();
      if (diffA != diffB) return diffA.compareTo(diffB);
      return a.week.compareTo(b.week);
    });

    final result = <ControlEvent>[...issued, ...otherPending];
    if (result.isNotEmpty) {
      return result.take(limit).toList();
    }

    return all.take(limit).toList();
  }

  DeadlineStatus getStatusForEvent(ControlEvent event, int currentWeekNum) {
    if (event.isSubmitted) return DeadlineStatus.passed;
    if (event.week < currentWeekNum) return DeadlineStatus.overdue;
    if (event.week == currentWeekNum) return DeadlineStatus.thisWeek;
    return DeadlineStatus.upcoming;
  }

  // Overall Statistics for Controls
  int get totalControlsCount => getAllControlEvents().length;
  int get issuedControlsCount => getAllControlEvents().where((c) => c.isIssued).length;
  int get submittedCount => getAllControlEvents().where((c) => c.isSubmitted).length;
  int get notIssuedControlsCount => getAllControlEvents().where((c) => c.isNotIssued).length;
  int get remainingCount => totalControlsCount - submittedCount;

  // Statistics for Labs
  int get totalLabsCount {
    int total = 0;
    for (final d in _disciplines) {
      total += d.laboratory.length;
    }
    return total;
  }

  int get issuedLabsCount {
    int count = 0;
    for (final d in _disciplines) {
      count += d.laboratory.where((l) => l.isIssued).length;
    }
    return count;
  }

  int get submittedLabsCount {
    int count = 0;
    for (final d in _disciplines) {
      count += d.laboratory.where((l) => l.isSubmitted).length;
    }
    return count;
  }

  // Statistics for Seminars
  int get totalSeminarsCount {
    int total = 0;
    for (final d in _disciplines) {
      total += d.seminars.length;
    }
    return total;
  }

  int get attendedSeminarsCount {
    int count = 0;
    for (final d in _disciplines) {
      count += d.seminars.where((s) => s.isSubmitted).length;
    }
    return count;
  }
}
