import 'package:flutter/material.dart';

enum EventState {
  issued,     // Выдано (для ДЗ, ЛР) / Назначено (для РК, КР)
  submitted,  // Сдано / Выполнено / Защищено / Посещено
  notIssued,  // Не выдано (в плане семестра)
  missed,     // Пропущено / Не сдано
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
  });

  // Submitted / completed: ONLY when stage is 2 (Выполнено), 3/13 (Защищено), 4 (Посещено), 12 (Работа на семинаре)
  // or when points/value are graded for module.
  // Stage == '1' is strictly NOT submitted.
  bool get isSubmitted {
    if (stage == '1' || stage == '0') return false;
    if (stage == '2' || stage == '3' || stage == '13' || stage == '4') return true;
    if (stage == '12' && type == 'СЗ') return true;
    if (type == 'М' && value != null && value.toString().isNotEmpty && value.toString() != '0') {
      return true;
    }
    return false;
  }

  // Active / Issued: stage == '1'
  // For ДЗ/ЛР: "Выдано"
  // For РК/КР: "Назначено / Предстоит"
  bool get isIssued => stage == '1';

  // Missed / Failed: stage == '0'
  bool get isMissed => stage == '0';

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
      if (isSubmitted) return 'Зачтен ($value б.)';
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
}
