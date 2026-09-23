class ScheduleAudience {
  final String name;
  final String? building;
  final String? uuid;

  ScheduleAudience({
    required this.name,
    this.building,
    this.uuid,
  });

  String get formattedText {
    if (building != null && building!.isNotEmpty && building != 'None') {
      return '$name ($building)';
    }
    return name;
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'building': building,
        'uuid': uuid,
      };

  factory ScheduleAudience.fromJson(Map<String, dynamic> json) =>
      ScheduleAudience(
        name: json['name'] as String? ?? '—',
        building: json['building'] as String?,
        uuid: json['uuid'] as String?,
      );
}

class ScheduleTeacher {
  final String firstName;
  final String lastName;
  final String middleName;
  final String? uuid;

  ScheduleTeacher({
    required this.firstName,
    required this.lastName,
    required this.middleName,
    this.uuid,
  });

  String get formattedName {
    final f = firstName.isNotEmpty ? '${firstName[0]}.' : '';
    final m = middleName.isNotEmpty ? '${middleName[0]}.' : '';
    return '$lastName $f$m'.trim();
  }

  Map<String, dynamic> toJson() => {
        'firstName': firstName,
        'lastName': lastName,
        'middleName': middleName,
        'uuid': uuid,
      };

  factory ScheduleTeacher.fromJson(Map<String, dynamic> json) =>
      ScheduleTeacher(
        firstName: json['firstName'] as String? ?? '',
        lastName: json['lastName'] as String? ?? '',
        middleName: json['middleName'] as String? ?? '',
        uuid: json['uuid'] as String?,
      );
}

class ScheduleLesson {
  final String? id;
  final bool isCustom;
  final int day; // 1 (Пн) - 6 (Сб)
  final int time; // 1 - 7
  final String startTime;
  final String endTime;
  final String week; // 'all' | 'ch' | 'zn' | 'numerator' | 'denominator'
  final String disciplineTitle;
  final String actType; // 'lecture' | 'seminar' | 'lab' | 'military' | 'elective' | 'consultation'
  final List<ScheduleAudience> audiences;
  final List<ScheduleTeacher> teachers;
  final String? streamName;
  final bool isStream;

  ScheduleLesson({
    this.id,
    this.isCustom = false,
    required this.day,
    required this.time,
    required this.startTime,
    required this.endTime,
    required this.week,
    required this.disciplineTitle,
    required this.actType,
    required this.audiences,
    required this.teachers,
    this.streamName,
    this.isStream = false,
  });

  bool get isNumerator => week == 'ch' || week == 'numerator';
  bool get isDenominator => week == 'zn' || week == 'denominator';
  bool get isEveryWeek => week == 'all' || week.isEmpty;

  bool matchesWeek({required bool isNumeratorWeek}) {
    if (isEveryWeek) return true;
    if (isNumeratorWeek) return isNumerator;
    return isDenominator;
  }

  String get audiencesFormatted {
    if (audiences.isEmpty) return '—';
    return audiences.map((a) => a.formattedText).join(', ');
  }

  String get displayAudiences => audiencesFormatted;

  String get teachersFormatted {
    if (teachers.isEmpty) return 'Кафедра';
    return teachers.map((t) => t.formattedName).join(', ');
  }

  String get displayTeachers => teachersFormatted;

  String get actTypeTitle {
    switch (actType.toLowerCase()) {
      case 'lecture':
      case 'лекция':
        return 'Лекция';
      case 'seminar':
      case 'семинар':
        return 'Семинар';
      case 'lab':
      case 'лабораторная':
      case 'лабораторная работа':
        return 'Лабораторная';
      case 'military':
      case 'военная кафедра':
      case 'вк':
        return 'Военная кафедра';
      case 'elective':
      case 'факультатив':
        return 'Факультатив';
      case 'consultation':
      case 'консультация':
        return 'Консультация';
      default:
        return actType.isNotEmpty ? actType : 'Занятие';
    }
  }

  String get weekTitle {
    if (isNumerator) return 'Числ.';
    if (isDenominator) return 'Знам.';
    return 'Все нед.';
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'isCustom': isCustom,
        'day': day,
        'time': time,
        'startTime': startTime,
        'endTime': endTime,
        'week': week,
        'disciplineTitle': disciplineTitle,
        'actType': actType,
        'audiences': audiences.map((a) => a.toJson()).toList(),
        'teachers': teachers.map((t) => t.toJson()).toList(),
        'streamName': streamName,
        'isStream': isStream,
      };

  factory ScheduleLesson.fromJson(Map<String, dynamic> json) {
    final rawAuds = json['audiences'] as List? ?? [];
    final audiences = rawAuds
        .map((a) => ScheduleAudience.fromJson(a as Map<String, dynamic>))
        .toList();

    final rawTeachers = json['teachers'] as List? ?? [];
    final teachers = rawTeachers
        .map((t) => ScheduleTeacher.fromJson(t as Map<String, dynamic>))
        .toList();

    return ScheduleLesson(
      id: json['id'] as String?,
      isCustom: json['isCustom'] as bool? ?? false,
      day: json['day'] as int? ?? 1,
      time: json['time'] as int? ?? 1,
      startTime: json['startTime'] as String? ?? '08:30',
      endTime: json['endTime'] as String? ?? '10:00',
      week: json['week'] as String? ?? 'all',
      disciplineTitle: json['disciplineTitle'] as String? ?? 'Дисциплина',
      actType: json['actType'] as String? ?? 'seminar',
      audiences: audiences,
      teachers: teachers,
      streamName: json['streamName'] as String?,
      isStream: json['isStream'] as bool? ?? false,
    );
  }
}
