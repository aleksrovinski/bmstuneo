class StudentAgreement {
  final String date;
  final String uuid;
  final String title;
  final String number;

  const StudentAgreement({
    required this.date,
    required this.uuid,
    required this.title,
    required this.number,
  });

  Map<String, dynamic> toJson() => {
        'date': date,
        'uuid': uuid,
        'title': title,
        'number': number,
      };

  factory StudentAgreement.fromJson(Map<String, dynamic> json) =>
      StudentAgreement(
        date: json['date']?.toString() ?? '',
        uuid: json['uuid']?.toString() ?? '',
        title: json['title']?.toString() ?? '',
        number: json['number']?.toString() ?? '',
      );
}

class StudentStage {
  final String uuid;
  final String alias;
  final String groupTitle;
  final String? groupCode;
  final String groupUuid;
  final int semester;
  final String? specialityTitle;
  final String? specializationTitle;
  final String? cardNumber;
  final String? state;
  final String? studyType;
  final List<StudentAgreement> agreements;

  const StudentStage({
    required this.uuid,
    required this.alias,
    required this.groupTitle,
    this.groupCode,
    required this.groupUuid,
    this.semester = 1,
    this.specialityTitle,
    this.specializationTitle,
    this.cardNumber,
    this.state,
    this.studyType,
    this.agreements = const [],
  });

  Map<String, dynamic> toJson() => {
        'uuid': uuid,
        'alias': alias,
        'groupTitle': groupTitle,
        'groupCode': groupCode,
        'groupUuid': groupUuid,
        'semester': semester,
        'specialityTitle': specialityTitle,
        'specializationTitle': specializationTitle,
        'cardNumber': cardNumber,
        'state': state,
        'studyType': studyType,
        'agreements': agreements.map((a) => a.toJson()).toList(),
      };

  factory StudentStage.fromJson(Map<String, dynamic> json) {
    final grp = json['group'] is Map ? json['group'] as Map<String, dynamic> : <String, dynamic>{};
    final rawAgreements = json['agreements'] as List? ?? [];
    return StudentStage(
      uuid: json['uuid']?.toString() ?? '',
      alias: json['alias']?.toString() ?? 'stage.bachelor',
      groupTitle: grp['title']?.toString() ?? json['groupTitle']?.toString() ?? 'Студент',
      groupCode: grp['code']?.toString() ?? json['groupCode']?.toString(),
      groupUuid: grp['uuid']?.toString() ?? json['groupUuid']?.toString() ?? '',
      semester: (grp['semester'] as num?)?.toInt() ?? (json['semester'] as num?)?.toInt() ?? 1,
      specialityTitle: grp['specialityTitle']?.toString() ?? json['specialityTitle']?.toString(),
      specializationTitle: grp['specializationTitle']?.toString() ?? json['specializationTitle']?.toString(),
      cardNumber: json['cardNumber']?.toString(),
      state: json['state']?.toString() ?? 'Обучается',
      studyType: json['studyType']?.toString(),
      agreements: rawAgreements
          .whereType<Map<String, dynamic>>()
          .map((a) => StudentAgreement.fromJson(a))
          .toList(),
    );
  }
}

class UserProfile {
  final String lastName;
  final String firstName;
  final String middleName;
  final String groupTitle;
  final String? groupCode;
  final String groupUuid;
  final String stageUuid;
  final String? personUuid;
  final String? qrUrl;

  // Extended Digital Student ID fields
  final String? cardNumber;
  final int semester;
  final String? specialityTitle;
  final String? specializationTitle;
  final String? studyType;
  final String state;
  final bool hasDormitory;
  final String? birthDate;
  final List<StudentAgreement> agreements;
  final List<StudentStage> stages;

  UserProfile({
    required this.lastName,
    required this.firstName,
    required this.middleName,
    required this.groupTitle,
    this.groupCode,
    required this.groupUuid,
    required this.stageUuid,
    this.personUuid,
    this.qrUrl,
    this.cardNumber,
    this.semester = 1,
    this.specialityTitle,
    this.specializationTitle,
    this.studyType,
    this.state = 'Обучается',
    this.hasDormitory = false,
    this.birthDate,
    this.agreements = const [],
    this.stages = const [],
  });

  String get fullName => '$lastName $firstName $middleName'.trim();
  String get initials {
    final l = lastName.isNotEmpty ? lastName[0] : '';
    final f = firstName.isNotEmpty ? firstName[0] : '';
    return '$l$f'.toUpperCase();
  }

  String get studyTypeTitle {
    if (studyType == null || studyType!.isEmpty) return 'Бюджетная основа';
    if (studyType!.contains('paid')) return 'Платная основа';
    if (studyType!.contains('budget') || studyType!.contains('free')) return 'Бюджетная основа';
    return studyType!;
  }

  bool get isPaid => studyType?.contains('paid') ?? false;
  bool get isBudget => !isPaid;

  int get course => ((semester + 1) / 2).floor().clamp(1, 6);

  Map<String, dynamic> toJson() => {
        'lastName': lastName,
        'firstName': firstName,
        'middleName': middleName,
        'groupTitle': groupTitle,
        'groupCode': groupCode,
        'groupUuid': groupUuid,
        'stageUuid': stageUuid,
        'personUuid': personUuid,
        'qrUrl': qrUrl,
        'cardNumber': cardNumber,
        'semester': semester,
        'specialityTitle': specialityTitle,
        'specializationTitle': specializationTitle,
        'studyType': studyType,
        'state': state,
        'hasDormitory': hasDormitory,
        'birthDate': birthDate,
        'agreements': agreements.map((a) => a.toJson()).toList(),
        'stages': stages.map((s) => s.toJson()).toList(),
      };

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    final rawAgreements = json['agreements'] as List? ?? [];
    final rawStages = json['stages'] as List? ?? [];

    return UserProfile(
      lastName: json['lastName'] as String? ?? '',
      firstName: json['firstName'] as String? ?? '',
      middleName: json['middleName'] as String? ?? '',
      groupTitle: json['groupTitle'] as String? ?? 'Студент',
      groupCode: json['groupCode'] as String?,
      groupUuid: json['groupUuid'] as String? ?? '',
      stageUuid: json['stageUuid'] as String? ?? '',
      personUuid: json['personUuid'] as String?,
      qrUrl: json['qrUrl'] as String?,
      cardNumber: json['cardNumber'] as String?,
      semester: (json['semester'] as num?)?.toInt() ?? 1,
      specialityTitle: json['specialityTitle'] as String?,
      specializationTitle: json['specializationTitle'] as String?,
      studyType: json['studyType'] as String?,
      state: json['state'] as String? ?? 'Обучается',
      hasDormitory: json['hasDormitory'] as bool? ?? false,
      birthDate: json['birthDate'] as String?,
      agreements: rawAgreements
          .whereType<Map<String, dynamic>>()
          .map((a) => StudentAgreement.fromJson(a))
          .toList(),
      stages: rawStages
          .whereType<Map<String, dynamic>>()
          .map((s) => StudentStage.fromJson(s))
          .toList(),
    );
  }
}
