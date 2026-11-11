class TeacherSearchItem {
  final String title;
  final String uuid;

  const TeacherSearchItem({
    required this.title,
    required this.uuid,
  });

  factory TeacherSearchItem.fromJson(Map<String, dynamic> json) => TeacherSearchItem(
        title: json['title']?.toString() ?? '',
        uuid: json['uuid']?.toString() ?? '',
      );

  Map<String, dynamic> toJson() => {
        'title': title,
        'uuid': uuid,
      };
}
