class CurrentWeek {
  final int weekNumber;
  final String weekName;
  final String weekShortName;
  final int term;
  final String semesterStarts;
  final String semesterEnds;

  CurrentWeek({
    required this.weekNumber,
    required this.weekName,
    required this.weekShortName,
    required this.term,
    required this.semesterStarts,
    required this.semesterEnds,
  });

  bool get isNumerator =>
      weekShortName.toLowerCase() == 'чс' ||
      weekName.toLowerCase().contains('числ');

  String get currentType => isNumerator ? 'ch' : 'zn';
  String get oppositeType => isNumerator ? 'zn' : 'ch';

  factory CurrentWeek.defaultWeek() {
    final now = DateTime.now();
    final semStart = DateTime(now.year, 9, 1);
    final diffWeeks = (now.difference(semStart).inDays / 7).ceil().clamp(1, 17);
    final isNum = diffWeeks % 2 == 1;

    return CurrentWeek(
      weekNumber: diffWeeks,
      weekName: isNum ? 'числитель' : 'знаменатель',
      weekShortName: isNum ? 'чс' : 'зн',
      term: 1,
      semesterStarts: '${now.year}-09-01',
      semesterEnds: '${now.year + 1}-01-05',
    );
  }

  factory CurrentWeek.fromJson(Map<String, dynamic> json) {
    return CurrentWeek(
      weekNumber: json['weekNumber'] as int? ?? 3,
      weekName: json['weekName'] as String? ?? 'числитель',
      weekShortName: json['weekShortName'] as String? ?? 'чс',
      term: json['term'] as int? ?? 1,
      semesterStarts: json['semesterStarts'] as String? ?? '2026-09-01',
      semesterEnds: json['semesterEnds'] as String? ?? '2027-01-05',
    );
  }
}
