class SessionDiscipline {
  final String title;
  final String department; // e.g. 'ФН1', 'Л3', 'РК6'
  final String controlType; // e.g. 'Экз', 'Зач', 'РЭ', 'Прк'
  final int hours;
  final String grade; // e.g. 'Отлично', 'Хорошо', 'Зачтено', 'Не аттестован'

  const SessionDiscipline({
    required this.title,
    required this.department,
    required this.controlType,
    required this.hours,
    required this.grade,
  });

  bool get isPassed {
    final g = grade.trim().toLowerCase();
    if (g.contains('не аттестован') ||
        g.contains('не зачтено') ||
        g.contains('неуд') ||
        g.contains('не яв')) {
      return false;
    }
    return g.contains('зачтено') ||
        g.contains('отлично') ||
        g.contains('хорошо') ||
        g.contains('удовл');
  }

  bool get isExcellent => grade.trim().toLowerCase().contains('отлично');
  bool get isGood => grade.trim().toLowerCase().contains('хорошо');
  bool get isSatisfactory => grade.trim().toLowerCase().contains('удовл');
  bool get isCreditPassed => grade.trim().toLowerCase().contains('зачтено');
  bool get isDebt => !isPassed && grade.trim().isNotEmpty && grade != '—';

  Map<String, dynamic> toJson() => {
        'title': title,
        'department': department,
        'controlType': controlType,
        'hours': hours,
        'grade': grade,
      };

  factory SessionDiscipline.fromJson(Map<String, dynamic> json) => SessionDiscipline(
        title: json['title']?.toString() ?? '',
        department: json['department']?.toString() ?? '',
        controlType: json['controlType']?.toString() ?? '',
        hours: (json['hours'] as num?)?.toInt() ?? 0,
        grade: json['grade']?.toString() ?? '',
      );
}

class SemesterSession {
  final String semesterTitle; // e.g. 'Семестр 2'
  final int semesterNumber; // 2
  final List<SessionDiscipline> disciplines;
  final String? lastUpdated;

  const SemesterSession({
    required this.semesterTitle,
    required this.semesterNumber,
    required this.disciplines,
    this.lastUpdated,
  });

  int get passedCount => disciplines.where((d) => d.isPassed).length;
  int get debtCount => disciplines.where((d) => d.isDebt).length;

  /// Mean of graded exams (5/4/3); pass/fail credits don't count. Null if none.
  double? get averageGrade {
    final grades = disciplines
        .map((d) => d.isExcellent ? 5 : d.isGood ? 4 : d.isSatisfactory ? 3 : null)
        .whereType<int>()
        .toList();
    if (grades.isEmpty) return null;
    return grades.reduce((a, b) => a + b) / grades.length;
  }

  Map<String, dynamic> toJson() => {
        'semesterTitle': semesterTitle,
        'semesterNumber': semesterNumber,
        'disciplines': disciplines.map((d) => d.toJson()).toList(),
        'lastUpdated': lastUpdated,
      };

  factory SemesterSession.fromJson(Map<String, dynamic> json) => SemesterSession(
        semesterTitle: json['semesterTitle']?.toString() ?? '',
        semesterNumber: (json['semesterNumber'] as num?)?.toInt() ?? 1,
        disciplines: (json['disciplines'] as List? ?? [])
            .whereType<Map<String, dynamic>>()
            .map((d) => SessionDiscipline.fromJson(d))
            .toList(),
        lastUpdated: json['lastUpdated']?.toString(),
      );
}
