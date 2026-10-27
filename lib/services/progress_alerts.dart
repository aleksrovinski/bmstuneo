import '../models/discipline_progress.dart';

/// One notification about the student's progress.
class ProgressAlert {
  /// Stable id: the same event never produces the same alert twice.
  final String key;
  final String title;
  final String body;

  const ProgressAlert({required this.key, required this.title, required this.body});

  @override
  String toString() => '$title — $body';
}

/// Decides what to notify about when fresh LKS progress replaces the cached one.
///
/// [previous] is null on the very first sync: then only deadlines are reported,
/// so turning notifications on doesn't flood the student with every past grade.
/// [current] must already have the student's manual marks applied, so work they
/// marked as done is never nagged about. [alreadyNotified] holds keys of alerts
/// sent before.
List<ProgressAlert> computeProgressAlerts({
  required List<DisciplineProgress>? previous,
  required List<DisciplineProgress> current,
  required int currentWeek,
  required Set<String> alreadyNotified,
}) {
  final alerts = <ProgressAlert>[];
  void add(ProgressAlert alert) {
    if (!alreadyNotified.contains(alert.key) && alerts.every((a) => a.key != alert.key)) {
      alerts.add(alert);
    }
  }

  final before = <String, ControlEvent>{
    for (final d in previous ?? const <DisciplineProgress>[])
      for (final e in [...d.controls, ...d.laboratory]) e.markKey: e,
  };

  for (final d in current) {
    for (final e in [...d.controls, ...d.laboratory]) {
      final old = before[e.markKey];

      // 1. A module got its score
      final score = e.moduleScore;
      if (previous != null && score != null && old?.moduleScore != score) {
        add(ProgressAlert(
          key: 'module|${e.markKey}|$score',
          title: 'Баллы за ${e.title.toLowerCase()}',
          body: '${d.title}: ${_moduleVerdict(e, score)}',
        ));
      }

      // 2. Homework issued or a control scheduled since the last sync
      final newlyIssued = e.isIssued && e.manualMark == null && old != null && !old.isIssued && !old.isSubmitted;
      if (previous != null && newlyIssued && e.type != 'М') {
        add(ProgressAlert(
          key: 'issued|${e.markKey}',
          title: e.type == 'РК' || e.type == 'КР' ? 'Назначен ${e.title}' : 'Выдано ${e.title}',
          body: '${d.title} • срок — ${e.week} неделя',
        ));
      }

      // 3. Due this week and still not done (manual "Сдано" counts as done)
      if (e.isIssued && !e.isSubmitted && e.week == currentWeek && e.type != 'М') {
        add(ProgressAlert(
          key: 'due|${e.markKey}|$currentWeek',
          title: 'Срок на этой неделе: ${e.title}',
          body: '${d.title} • ${e.week} неделя',
        ));
      }
    }
  }
  return alerts;
}

String _moduleVerdict(ControlEvent module, int score) {
  final max = module.threshold('point_all');
  final scored = max != null ? '$score из $max' : '$score б.';
  if (module.isBelowThreshold) return '$scored — недобор, порог ${module.threshold('point_3')}';
  final p5 = module.threshold('point_5');
  final p4 = module.threshold('point_4');
  if (p5 != null && score >= p5) return '$scored — на «5»';
  if (p4 != null && score >= p4) return '$scored — на «4»';
  return '$scored — зачтено';
}
