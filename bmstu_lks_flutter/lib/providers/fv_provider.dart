import 'package:flutter/foundation.dart';
import '../models/physical_culture.dart';
import '../models/sync_status.dart';
import '../services/bmstu_api_service.dart';

class FvProvider with ChangeNotifier {
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

  Future<void> loadFv(String stageUuid) async {
    if (stageUuid.isEmpty) {
      _data = null;
      _isLoading = false;
      notifyListeners();
      return;
    }

    _stageUuid = stageUuid;
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final fv = await apiService.getPhysicalCulture(stageUuid);
      _data = fv;
      _syncStatus = SyncStatus(
        lastUpdated: DateTime.now(),
        isLive: true,
        itemCount: fv?.groups.length ?? 0,
      );
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _errorMessage = e.toString().replaceAll('Exception: ', '');
      _syncStatus = SyncStatus(
        lastUpdated: DateTime.now(),
        isLive: false,
        message: _errorMessage,
      );
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
