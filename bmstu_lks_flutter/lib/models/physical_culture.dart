class FvRecord {
  final String id;
  final String weekDay; // e.g. "Вторник"
  final String time; // e.g. "11:35"
  final String teacherName;
  final String section; // e.g. "ОФП", "Плавание"
  final String place; // e.g. "Манеж СК МГТУ 4 этаж"
  final String? medGroup;

  FvRecord({
    required this.id,
    required this.weekDay,
    required this.time,
    required this.teacherName,
    required this.section,
    required this.place,
    this.medGroup,
  });

  factory FvRecord.fromJson(Map<String, dynamic> json) {
    return FvRecord(
      id: json['id']?.toString() ?? '',
      weekDay: json['week']?.toString() ?? 'Занятие',
      time: json['time']?.toString() ?? '',
      teacherName: json['teacherName']?.toString() ?? 'Преподаватель кафедры ФВ',
      section: json['section']?.toString() ?? 'ФКиС',
      place: json['place']?.toString() ?? 'Спорткомплекс МГТУ',
      medGroup: json['medGroup']?.toString(),
    );
  }
}

class FvTermHistory {
  final String term;
  final int points;
  final int attend;

  FvTermHistory({
    required this.term,
    required this.points,
    required this.attend,
  });

  factory FvTermHistory.fromJson(Map<String, dynamic> json) {
    return FvTermHistory(
      term: json['term']?.toString() ?? '',
      points: (json['points'] as num?)?.toInt() ?? 0,
      attend: (json['attend'] as num?)?.toInt() ?? 0,
    );
  }
}

class PhysicalCultureData {
  final int studyPoints; // Target is 60
  final int studyAttends; // Target is 25
  final String? medGroup;
  final String? medDate;
  final bool medSwim;
  final bool canBookStudy;
  final String? canBookStudyDisplay;
  final List<FvRecord> groups;
  final List<FvTermHistory> studyResults;

  static const int targetPoints = 60;
  static const int targetAttends = 25;

  PhysicalCultureData({
    required this.studyPoints,
    required this.studyAttends,
    this.medGroup,
    this.medDate,
    this.medSwim = false,
    this.canBookStudy = false,
    this.canBookStudyDisplay,
    required this.groups,
    required this.studyResults,
  });

  double get pointsProgress => (studyPoints / targetPoints).clamp(0.0, 1.0);
  double get attendsProgress => (studyAttends / targetAttends).clamp(0.0, 1.0);

  bool get isPointsCompleted => studyPoints >= targetPoints;
  bool get isAttendsCompleted => studyAttends >= targetAttends;
  bool get isCreditReady => isPointsCompleted && isAttendsCompleted;

  factory PhysicalCultureData.fromJson(Map<String, dynamic> json) {
    final rawGroups = json['groups'] as List? ?? [];
    final groupsList = rawGroups.map((g) => FvRecord.fromJson(g as Map<String, dynamic>)).toList();

    final rawResults = json['studyResults'] as List? ?? [];
    final resultsList = rawResults.map((r) => FvTermHistory.fromJson(r as Map<String, dynamic>)).toList();

    return PhysicalCultureData(
      studyPoints: (json['studyPoints'] as num?)?.toInt() ?? 0,
      studyAttends: (json['studyAttends'] as num?)?.toInt() ?? 0,
      medGroup: json['medGroup']?.toString(),
      medDate: json['medDate']?.toString(),
      medSwim: json['medSwim'] == true,
      canBookStudy: json['canBookStudy'] == true,
      canBookStudyDisplay: json['canBookStudyDisplay']?.toString(),
      groups: groupsList,
      studyResults: resultsList,
    );
  }

  factory PhysicalCultureData.sampleGuest() {
    return PhysicalCultureData(
      studyPoints: 0,
      studyAttends: 0,
      medGroup: 'Основная с плаванием',
      medDate: 'Справка активна',
      medSwim: true,
      canBookStudy: true,
      canBookStudyDisplay: 'Требуется авторизация',
      groups: [],
      studyResults: [],
    );
  }
}
