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
  });

  String get fullName => '$lastName $firstName $middleName'.trim();
  String get initials {
    final l = lastName.isNotEmpty ? lastName[0] : '';
    final f = firstName.isNotEmpty ? firstName[0] : '';
    return '$l$f'.toUpperCase();
  }
}
