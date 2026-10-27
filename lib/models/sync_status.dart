class SyncStatus {
  final DateTime? lastSyncedAt;
  final bool isLive;
  final int count;
  final String? error;

  SyncStatus({
    DateTime? lastUpdated,
    DateTime? lastSyncedAt,
    required this.isLive,
    int? count,
    int? itemCount,
    String? message,
    String? error,
  })  : lastSyncedAt = lastUpdated ?? lastSyncedAt ?? DateTime.now(),
        count = count ?? itemCount ?? 0,
        error = message ?? error;

  DateTime get lastUpdated => lastSyncedAt ?? DateTime.now();
  int get itemCount => count;
  String? get message => error;
}
