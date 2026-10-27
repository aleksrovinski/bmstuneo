import 'dart:convert';
import 'package:flutter/material.dart';

enum EventState {
  issued,     // Выдано (для ДЗ, ЛР) / Назначено (для РК, КР)
  submitted,  // Сдано / Выполнено / Защищено / Посещено
  notIssued,  // Не выдано (в плане семестра)
  missed,     // Пропущено / Не сдано
}

/// Status the student set by hand when LKS is behind (or wrong).
enum ManualMark {
  submitted('Сдано'),
  missed('Не сдано'),
  issued('Выдано'),
  notIssued('Не выдано');

  final String title;
  const ManualMark(this.title);

  /// Manual marks as stored on the device ({markKey: mark name}); unknown or
  /// corrupted entries are skipped.
  static Map<String, ManualMark> decodeAll(String? raw) {
    if (raw == null || raw.isEmpty) return {};
    try {
      final byName = ManualMark.values.asNameMap();
      return {
        for (final entry in (jsonDecode(raw) as Map<String, dynamic>).entries)
          if (byName[entry.value] != null) entry.key: byName[entry.value]!,
      };
    } catch (_) {
      return {};
    }
  }

  static String encodeAll(Map<String, ManualMark> marks) =>
      jsonEncode(marks.map((key, value) => MapEntry(key, value.name)));
}

class ControlEvent {
  final String type; // 'РК', 'ДЗ', 'КР', 'М', 'ЛР', 'СЗ'
  final String title;
  final int week;
  final dynamic value;
  final String? stage;
  final String? passStatus; // 'early', 'in-time', 'late'
  final String? setDate;
  final String disciplineTitle;
  final int controlIndex;
  final String? controlId;
  final Map<String, dynamic>? points; // rating thresholds e.g. point_3, point_4, point_5, point_all
  /// Set when the student overrode the LKS status; [lksOriginal] keeps the LKS version.
  final ManualMark? manualMark;
  final ControlEvent? lksOriginal;

  ControlEvent({
    required this.type,
    required this.title,
    required this.week,
    this.value,
    this.stage,
    this.passStatus,
    this.setDate,
    required this.disciplineTitle,
    required this.controlIndex,
    this.controlId,
    this.points,
    this.manualMark,
    this.lksOriginal,
  });

  /// Stable id for storing a manual mark: the LKS control id, or a composite
  /// of discipline, type and index for events that have none.
  String get markKey =>
      (controlId != null && controlId!.isNotEmpty) ? controlId! : '$disciplineTitle|$type|$controlIndex';

  /// Modules are graded with points, so their status is not set by hand.
  bool get canMarkManually => type != 'М';

  /// This event as the student marked it: the LKS stage is replaced with the one
  /// that means [mark] for this event type, everything else is kept.
  ControlEvent withManualMark(ManualMark mark) {
    final String newStage;
    switch (mark) {
      case ManualMark.submitted:
        newStage = type == 'СЗ' ? '4' : '2';
      case ManualMark.missed:
        newStage = '0';
      case ManualMark.issued:
        newStage = '1';
      case ManualMark.notIssued:
        newStage = '';
    }
    return ControlEvent(
      type: type,
      title: title,
      week: week,
      value: value,
      stage: newStage,
      passStatus: mark == ManualMark.submitted ? passStatus : null,
      setDate: setDate,
      disciplineTitle: disciplineTitle,
      controlIndex: controlIndex,
      controlId: controlId,
      points: points,
      manualMark: mark,
      lksOriginal: lksOriginal ?? this,
    );
  }

  static int? _asInt(dynamic raw) {
    if (raw is num) return raw.toInt();
    if (raw is String) return int.tryParse(raw.trim());
    return null;
  }

  /// Points scored for a graded module (`М`); null while it is not graded yet.
  /// '0' is how LKS shows a module that has not been graded, so it counts as null.
  int? get moduleScore {
    if (type != 'М') return null;
    final score = _asInt(value);
    return (score == null || score == 0) ? null : score;
  }

  /// Module threshold from LKS: `point_3` / `point_4` / `point_5` (minimum for
  /// that grade) or `point_all` (maximum).
  int? threshold(String key) => _asInt(points?[key]);

  /// A graded module that scored below its pass threshold (`point_3`).
  bool get isBelowThreshold {
    final score = moduleScore;
    final pass = threshold('point_3');
    return score != null && pass != null && score < pass;
  }

  // Submitted / completed: ONLY when stage is 2 (Выполнено), 3/13 (Защищено), 4 (Посещено), 12 (Работа на семинаре)
  // or when a module is graded at or above its pass threshold.
  // Stage == '1' is strictly NOT submitted.
  bool get isSubmitted {
    if (stage == '1' || stage == '0') return false;
    // Graded modules come with stage '10'/'13' too; the score decides, not the stage
    if (isBelowThreshold) return false;
    if (stage == '2' || stage == '3' || stage == '13' || stage == '4') return true;
    if (stage == '12' && type == 'СЗ') return true;
    if (moduleScore != null) return !isBelowThreshold;
    return false;
  }

  // Active / Issued: stage == '1'
  // For ДЗ/ЛР: "Выдано"
  // For РК/КР: "Назначено / Предстоит"
  bool get isIssued => stage == '1';

  // Missed / Failed: stage == '0', or a module graded below its pass threshold
  bool get isMissed => stage == '0' || isBelowThreshold;

  // Not yet issued / Planned: stage is null or empty
  bool get isNotIssued => (stage == null || stage!.isEmpty) && !isSubmitted && !isMissed;

  bool get isPlanned => isNotIssued;
  bool get isPassed => isSubmitted;

  EventState get eventState {
    if (isMissed) return EventState.missed;
    if (isSubmitted) return EventState.submitted;
    if (isIssued) return EventState.issued;
    return EventState.notIssued;
  }

  // Intuitive icons specific to event type and state
  IconData get statusIcon {
    if (isMissed) return Icons.cancel_rounded;
    if (isSubmitted) return Icons.check_circle_rounded;
    if (isIssued) {
      if (type == 'РК' || type == 'КР') return Icons.assignment_late_rounded; // exam/test milestone
      if (type == 'М') return Icons.military_tech_rounded;
      return Icons.edit_note_rounded; // notebook/pencil for homework & labs
    }
    return Icons.schedule_rounded; // Clock: scheduled in semester plan
  }

  // Intuitive colors specific to event type and state
  Color get statusColor {
    if (isMissed) {
      return const Color(0xFFEF4444); // Red: Пропущено / Не сдано
    }
    if (isSubmitted) {
      return const Color(0xFF10B981); // Emerald Green: Сдано / Выполнено / Защищено
    }
    if (isIssued) {
      if (type == 'РК' || type == 'КР') {
        return const Color(0xFF2563EB); // Royal Blue for RK/KR milestone
      }
      return const Color(0xFF0070F3);   // Blue for issued homework
    }
    return const Color(0xFF64748B);     // Slate Gray: В плане / Не выдано
  }

  Color get statusBgColor {
    return statusColor.withValues(alpha: 0.14);
  }

  // Short badge text for chips — type-aware (RK CANNOT BE "Выдано"!)
  String get shortBadgeText {
    if (isSubmitted) {
      if (type == 'СЗ') return 'Посещено';
      if (type == 'ЛР') {
        if (stage == '3' || stage == '13') return 'Защищена';
        if (stage == '2') return 'Выполнена';
        return 'Сдана';
      }
      if (type == 'РК' || type == 'КР') return 'Сдано';
      if (stage == '3' || stage == '13') return 'Защищено';
      if (stage == '2') return 'Выполнено';
      return 'Сдано';
    }
    if (isMissed) {
      if (type == 'РК' || type == 'КР') return 'Не сдан';
      if (isBelowThreshold) return 'Недобор';
      return 'Пропущено';
    }
    if (isIssued) {
      if (type == 'РК') return 'Назначен';
      if (type == 'КР') return 'Назначена';
      if (type == 'ЛР') return 'Выдана';
      if (type == 'М' || type == 'СЗ') return 'Предстоит';
      return 'Выдано';
    }
    // Not issued / in semester plan
    if (type == 'РК' || type == 'КР' || type == 'М' || type == 'СЗ') {
      return 'В плане';
    }
    return 'Не выдано';
  }

  // Human readable stage status matching official BMSTU academic processes
  String get statusTitle {
    if (type == 'СЗ') {
      if (stage == '0') return 'Пропущено';
      if (stage == '4') return 'Посещено';
      if (stage == '12') return 'Работа на семинаре';
      return 'Запланировано';
    }
    if (type == 'РК') {
      if (isSubmitted) return 'Сдано / Зачтено';
      if (isMissed) return 'Не сдан / Пропущен';
      if (isIssued) return 'Назначен (предстоит)';
      return 'Запланирован';
    }
    if (type == 'КР') {
      if (isSubmitted) return 'Сдана / Зачтена';
      if (isMissed) return 'Не сдана';
      if (isIssued) return 'Назначена (предстоит)';
      return 'Запланирована';
    }
    if (type == 'ЛР') {
      if (stage == '3' || stage == '13') return 'Защищена';
      if (stage == '2') return 'Выполнена';
      if (isIssued) return 'Выдана (в работе)';
      if (isMissed) return 'Пропущена';
      return 'Не выдана';
    }
    if (type == 'М') {
      final max = threshold('point_all');
      final scored = max != null ? '$moduleScore из $max' : '$moduleScore';
      if (isBelowThreshold) return 'Недобор ($scored б., порог ${threshold('point_3')})';
      if (isSubmitted) return 'Зачтен ($scored б.)';
      if (isMissed) return 'Не зачтен';
      if (isIssued) return 'Предстоит';
      return 'Запланирован';
    }
    // ДЗ
    if (stage == '1') return 'Выдано';
    if (stage == '2') return 'Выполнено';
    if (stage == '3' || stage == '13') return 'Защищено';
    if (isSubmitted) return 'Сдано';
    if (stage == '0') return 'Пропущено';
    return 'Не выдано';
  }

  // Pass timing label matching official BMSTU LKS
  String? get passStatusTitle {
    if (passStatus == 'early') return 'раньше срока';
    if (passStatus == 'in-time') return 'вовремя';
    if (passStatus == 'late') return 'с опозданием';
    return null;
  }

  // Status explanations for modals and tooltips — type-aware!
  String get statusHeadline {
    if (isSubmitted) {
      if (type == 'РК') return 'Рубежный контроль сдан и зачтен';
      if (type == 'КР') return 'Контрольная работа сдана';
      if (type == 'ЛР') return 'Лабораторная работа защищена';
      if (type == 'СЗ') return 'Семинар посещен';
      if (type == 'М') return 'Модуль аттестован';
      return 'Работа сдана и защищена';
    }
    if (isMissed) {
      if (type == 'РК' || type == 'КР') return 'Контроль не сдан в срок';
      if (isBelowThreshold) return 'Баллов за модуль меньше порога на «3»';
      return 'Мероприятие пропущено';
    }
    if (isIssued) {
      if (type == 'РК') return 'Рубежный контроль назначен на $week неделе';
      if (type == 'КР') return 'Контрольная работа назначена на $week неделе';
      if (type == 'ЛР') return 'Лабораторная работа выдана (в работе)';
      if (type == 'М') return 'Аттестация по модулю на $week неделе';
      return 'Задание выдано (требуется сдать)';
    }
    if (type == 'РК') return 'Рубежный контроль в плане семестра ($week нед.)';
    if (type == 'КР') return 'Контрольная работа в плане семестра ($week нед.)';
    if (type == 'М') return 'Модуль в плане семестра ($week нед.)';
    return 'Задание ещё не выдавалось';
  }

  String get statusSubtitle {
    final timing = passStatusTitle != null ? ' ($passStatusTitle)' : '';
    if (isSubmitted) {
      if (type == 'М' && value != null) {
        return 'Оценка выставлена в ЛКС: $value б.$timing';
      }
      return 'Отметка зафиксирована преподавателем$timing';
    }
    if (isIssued) {
      if (type == 'РК' || type == 'КР') {
        return 'Контрольное мероприятие назначено на $week неделю семестра.';
      }
      if (type == 'ЛР') {
        return 'Лабораторная работа выдана$timing. Выполните и защитите до $week недели.';
      }
      return 'Преподаватель выдал задание$timing. Срок сдачи: $week неделя.';
    }
    if (isMissed) {
      return 'Не сдано или пропущено в установленный срок.';
    }
    if (type == 'РК' || type == 'КР') {
      return 'Запланировано проведение на $week неделе семестра.';
    }
    return 'Запланировано в учебном плане на $week неделе семестра.';
  }

  // Formatted date
  String? get formattedSetDate {
    if (setDate == null || setDate!.isEmpty) return null;
    try {
      final dt = DateTime.parse(setDate!.replaceFirst(' ', 'T'));
      final months = [
        '',
        'янв',
        'фев',
        'мар',
        'апр',
        'мая',
        'июн',
        'июл',
        'авг',
        'сен',
        'окт',
        'ноя',
        'дек'
      ];
      final monthStr = dt.month <= 12 ? months[dt.month] : '';
      final minStr = dt.minute.toString().padLeft(2, '0');
      final hourStr = dt.hour.toString().padLeft(2, '0');
      return '${dt.day} $monthStr ${dt.year}, $hourStr:$minStr';
    } catch (_) {
      return setDate;
    }
  }

  Map<String, dynamic> toJson() => {
        'type': type,
        'title': title,
        'week': week,
        'value': value,
        'stage': stage,
        'passStatus': passStatus,
        'setDate': setDate,
        'disciplineTitle': disciplineTitle,
        'controlIndex': controlIndex,
        'controlId': controlId,
        'points': points,
      };

  factory ControlEvent.fromJson(Map<String, dynamic> json) => ControlEvent(
        type: json['type'] as String? ?? '',
        title: json['title']?.toString() ?? '',
        week: json['week'] as int? ?? 1,
        value: json['value'],
        stage: json['stage']?.toString(),
        passStatus: json['passStatus']?.toString(),
        setDate: json['setDate']?.toString(),
        disciplineTitle: json['disciplineTitle']?.toString() ?? '',
        controlIndex: json['controlIndex'] as int? ?? 1,
        controlId: json['controlId']?.toString(),
        points: json['points'] is Map
            ? Map<String, dynamic>.from(json['points'] as Map)
            : null,
      );
}

class DisciplineProgress {
  final String title;
  final String? disciplineUuid;
  final Map<String, dynamic> points;
  final List<ControlEvent> controls;
  final List<ControlEvent> laboratory;
  final List<ControlEvent> seminars;

  DisciplineProgress({
    required this.title,
    this.disciplineUuid,
    required this.points,
    required this.controls,
    this.laboratory = const [],
    this.seminars = const [],
  });

  /// This discipline with the student's manual marks laid over the LKS statuses.
  DisciplineProgress withManualMarks(Map<String, ManualMark> marks) {
    if (marks.isEmpty) return this;
    List<ControlEvent> mark(List<ControlEvent> events) => [
          for (final e in events)
            (e.canMarkManually && marks[e.markKey] != null) ? e.withManualMark(marks[e.markKey]!) : e,
        ];
    return DisciplineProgress(
      title: title,
      disciplineUuid: disciplineUuid,
      points: points,
      controls: mark(controls),
      laboratory: mark(laboratory),
      seminars: mark(seminars),
    );
  }

  bool get hasControls => controls.isNotEmpty;
  bool get hasLaboratory => laboratory.isNotEmpty;
  bool get hasSeminars => seminars.isNotEmpty;

  // Rating or point info if available
  String? get currentPointsSummary {
    if (points.isEmpty) return null;
    final total = points['point_all']?.toString();
    if (total != null && total.isNotEmpty) {
      return 'Макс: $total б.';
    }
    return null;
  }

  List<ControlEvent> get _modules => controls.where((c) => c.type == 'М').toList();

  /// Points scored on the modules graded so far.
  int get scoredModulePoints =>
      _modules.map((m) => m.moduleScore).whereType<int>().fold(0, (a, b) => a + b);

  /// Estimated 5-point grade (5, 4, 3, 2) for the modules graded so far,
  /// or null while nothing can be judged yet.
  ///
  /// Each module carries its own thresholds (`point_3/4/5`), so the scored
  /// points are compared with the thresholds of the same graded modules: being
  /// halfway through the semester is not a fail. `points['point_all']` of the
  /// discipline is its maximum, not the score, and is not used here.
  int? get estimatedGrade {
    final graded = _modules.where((m) => m.moduleScore != null).toList();
    if (graded.isEmpty) return null;
    final scored = scoredModulePoints;

    final withThresholds = graded.every((m) =>
        m.threshold('point_3') != null && m.threshold('point_4') != null && m.threshold('point_5') != null);
    if (withThresholds) {
      int sumOf(String key) => graded.fold(0, (a, m) => a + m.threshold(key)!);
      if (scored >= sumOf('point_5')) return 5;
      if (scored >= sumOf('point_4')) return 4;
      if (scored >= sumOf('point_3')) return 3;
      return 2;
    }

    // No per-module thresholds: only the final 100-point total can be judged
    if (graded.length < _modules.length) return null;
    if (scored >= 85) return 5;
    if (scored >= 71) return 4;
    if (scored >= 60) return 3;
    return 2;
  }

  String get gradeDisplay {
    final grade = estimatedGrade;
    if (grade == 5) return 'Отлично (5)';
    if (grade == 4) return 'Хорошо (4)';
    if (grade == 3) return 'Удовл. (3)';
    if (grade == 2) return 'Неудовл. (2)';
    final scored = scoredModulePoints;
    if (scored > 0) return 'В процессе ($scored б.)';
    return 'В процессе';
  }

  bool get isPassed {
    final g = estimatedGrade;
    if (g != null && g >= 3) return true;
    return false;
  }

  Map<String, dynamic> toJson() => {
        'title': title,
        'disciplineUuid': disciplineUuid,
        'points': points,
        'controls': controls.map((c) => c.toJson()).toList(),
        'laboratory': laboratory.map((l) => l.toJson()).toList(),
        'seminars': seminars.map((s) => s.toJson()).toList(),
      };

  factory DisciplineProgress.fromJson(Map<String, dynamic> json) =>
      DisciplineProgress(
        title: json['title'] as String? ?? 'Дисциплина',
        disciplineUuid: json['disciplineUuid'] as String?,
        points: json['points'] is Map
            ? Map<String, dynamic>.from(json['points'] as Map)
            : {},
        controls: (json['controls'] as List? ?? [])
            .map((c) => ControlEvent.fromJson(c as Map<String, dynamic>))
            .toList(),
        laboratory: (json['laboratory'] as List? ?? [])
            .map((l) => ControlEvent.fromJson(l as Map<String, dynamic>))
            .toList(),
        seminars: (json['seminars'] as List? ?? [])
            .map((s) => ControlEvent.fromJson(s as Map<String, dynamic>))
            .toList(),
      );
}
