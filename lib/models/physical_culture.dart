import '../constants/moscow_time.dart';

enum HealthPassportState { unknown, valid, expiringSoon, expired }

class HealthPassportInfo {
  static const int warningWindowDays = 30;

  static const _monthsGenitive = [
    'января',
    'февраля',
    'марта',
    'апреля',
    'мая',
    'июня',
    'июля',
    'августа',
    'сентября',
    'октября',
    'ноября',
    'декабря',
  ];

  final HealthPassportState state;
  final DateTime? expiryDate;
  final int? daysRemaining;
  final int? referenceYear;

  const HealthPassportInfo._({
    required this.state,
    this.expiryDate,
    this.daysRemaining,
    this.referenceYear,
  });

  const HealthPassportInfo.unknown()
      : state = HealthPassportState.unknown,
        expiryDate = null,
        daysRemaining = null,
        referenceYear = null;

  factory HealthPassportInfo.fromMedDate(String? medDate, {DateTime? now}) {
    final expiry = parseDate(medDate);
    if (expiry == null) return const HealthPassportInfo.unknown();

    final today = (now ?? MoscowTime.now()).dateOnly;
    final days = today.calendarDaysUntil(expiry);
    final HealthPassportState state;
    if (days <= 0) {
      state = HealthPassportState.expired;
    } else if (days <= warningWindowDays) {
      state = HealthPassportState.expiringSoon;
    } else {
      state = HealthPassportState.valid;
    }

    return HealthPassportInfo._(
      state: state,
      expiryDate: expiry,
      daysRemaining: days,
      referenceYear: today.year,
    );
  }

  static DateTime? parseDate(String? raw) {
    if (raw == null) return null;
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;

    final ruMatch = RegExp(r'^(\d{1,2})\.(\d{1,2})\.(\d{4})$').firstMatch(trimmed);
    if (ruMatch != null) {
      final day = int.tryParse(ruMatch.group(1)!);
      final month = int.tryParse(ruMatch.group(2)!);
      final year = int.tryParse(ruMatch.group(3)!);
      if (day == null || month == null || year == null) return null;
      final dt = DateTime(year, month, day);
      if (dt.year != year || dt.month != month || dt.day != day) return null;
      return dt;
    }

    if (!RegExp(r'^\d{4}-\d{2}-\d{2}').hasMatch(trimmed)) return null;
    final parsed = DateTime.tryParse(trimmed);
    if (parsed == null) return null;
    return parsed.isUtc ? MoscowTime.of(parsed).dateOnly : parsed.dateOnly;
  }

  static String daysWord(int n) {
    final absN = n.abs();
    final mod100 = absN % 100;
    if (mod100 >= 11 && mod100 <= 14) return 'дней';
    switch (absN % 10) {
      case 1:
        return 'день';
      case 2:
      case 3:
      case 4:
        return 'дня';
      default:
        return 'дней';
    }
  }

  bool get isExpired => state == HealthPassportState.expired;
  bool get isExpiringSoon => state == HealthPassportState.expiringSoon;
  bool get needsAttention => isExpired || isExpiringSoon;

  String? get formattedDate {
    final d = expiryDate;
    if (d == null) return null;
    final base = '${d.day} ${_monthsGenitive[d.month - 1]}';
    return (referenceYear != null && d.year == referenceYear) ? base : '$base ${d.year}';
  }

  String? get formattedFullDate {
    final d = expiryDate;
    if (d == null) return null;
    return '${d.day} ${_monthsGenitive[d.month - 1]} ${d.year}';
  }

  String? get shortBadge {
    if (isExpired) return 'Недействителен';
    if (isExpiringSoon && daysRemaining != null) {
      return daysRemaining == 1 ? 'Истекает завтра' : 'Осталось $daysRemaining ${daysWord(daysRemaining!)}';
    }
    return null;
  }

  String? get warningTitle {
    if (isExpired) return 'Нужно продлить паспорт здоровья';
    if (isExpiringSoon && daysRemaining != null) {
      return daysRemaining == 1
          ? 'Паспорт здоровья истекает завтра'
          : 'Паспорт здоровья истекает через $daysRemaining ${daysWord(daysRemaining!)}';
    }
    return null;
  }

  String? get warningDescription {
    if (isExpired) {
      return 'Срок действия закончился $formattedDate — сейчас посещать занятия ФКиС нельзя. '
          'Обратитесь в Бауманскую поликлинику для продления.';
    }
    if (isExpiringSoon) {
      return 'Действует до $formattedDate — начиная с этой даты посещать занятия ФКиС будет нельзя. '
          'Обратитесь в Бауманскую поликлинику для продления.';
    }
    return null;
  }

  String? get homeSubtitle {
    if (isExpired) return 'Действовал до $formattedDate · занятия ФКиС недоступны';
    if (isExpiringSoon) return 'Действует до $formattedDate · продлите в поликлинике';
    return null;
  }
}

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

  Map<String, dynamic> toJson() => {
        'id': id,
        'week': weekDay,
        'time': time,
        'teacherName': teacherName,
        'section': section,
        'place': place,
        'medGroup': medGroup,
      };
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

  Map<String, dynamic> toJson() => {
        'term': term,
        'points': points,
        'attend': attend,
      };
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

  HealthPassportInfo healthPassportInfo({DateTime? now}) =>
      HealthPassportInfo.fromMedDate(medDate, now: now);

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

  Map<String, dynamic> toJson() => {
        'studyPoints': studyPoints,
        'studyAttends': studyAttends,
        'medGroup': medGroup,
        'medDate': medDate,
        'medSwim': medSwim,
        'canBookStudy': canBookStudy,
        'canBookStudyDisplay': canBookStudyDisplay,
        'groups': groups.map((g) => g.toJson()).toList(),
        'studyResults': studyResults.map((r) => r.toJson()).toList(),
      };

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
