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

  /// Best guess of the academic week when neither LKS nor the cache is available.
  ///
  /// Week 1 is the week (Mon–Sun) the semester starts in, odd weeks are
  /// numerators. Autumn starts on September 1 (January still belongs to it);
  /// spring starts on the second Monday of February, as in 2024–2026. LKS's
  /// own answer always wins when there is one.
  factory CurrentWeek.defaultWeek([DateTime? at]) {
    final now = at ?? DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final isSpring = now.month >= 2 && now.month <= 7;
    final autumnYear = now.month == 1 ? now.year - 1 : now.year;
    final start = isSpring ? _secondMondayOfFebruary(now.year) : DateTime(autumnYear, 9, 1);
    final end = isSpring ? DateTime(now.year, 6, 30) : DateTime(autumnYear + 1, 1, 31);

    final startMonday = start.subtract(Duration(days: start.weekday - 1));
    final weekNumber = (today.difference(startMonday).inDays ~/ 7 + 1).clamp(1, 17);
    final isNum = weekNumber.isOdd;

    return CurrentWeek(
      weekNumber: weekNumber,
      weekName: isNum ? 'числитель' : 'знаменатель',
      weekShortName: isNum ? 'чс' : 'зн',
      term: isSpring ? 2 : 1,
      semesterStarts: _isoDate(start),
      semesterEnds: _isoDate(end),
    );
  }

  static DateTime _secondMondayOfFebruary(int year) {
    final feb1 = DateTime(year, 2, 1);
    final firstMonday = feb1.add(Duration(days: (DateTime.monday - feb1.weekday + 7) % 7));
    return firstMonday.add(const Duration(days: 7));
  }

  static String _isoDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  factory CurrentWeek.fromJson(Map<String, dynamic> json) {
    // Missing fields fall back to today's estimate, not to a fixed year
    final fallback = CurrentWeek.defaultWeek();
    return CurrentWeek(
      weekNumber: json['weekNumber'] as int? ?? fallback.weekNumber,
      weekName: json['weekName'] as String? ?? fallback.weekName,
      weekShortName: json['weekShortName'] as String? ?? fallback.weekShortName,
      term: json['term'] as int? ?? fallback.term,
      semesterStarts: json['semesterStarts'] as String? ?? fallback.semesterStarts,
      semesterEnds: json['semesterEnds'] as String? ?? fallback.semesterEnds,
    );
  }

  Map<String, dynamic> toJson() => {
        'weekNumber': weekNumber,
        'weekName': weekName,
        'weekShortName': weekShortName,
        'term': term,
        'semesterStarts': semesterStarts,
        'semesterEnds': semesterEnds,
      };
}
