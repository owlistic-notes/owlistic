class Note {
  final String id;
  final String title;
  final String content;
  final String userId;

  Note({
    required this.id,
    required this.title,
    required this.content,
    required this.userId,
  });

  factory Note.fromJson(Map<String, dynamic> json) {
    return Note(
      id: json['ID']?.toString() ?? '',
      title: json['Title']?.toString() ?? '',
      content: json['Content']?.toString() ?? '',
      userId: json['UserID']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'Title': title,
      'Content': content,
      'UserID': userId,
    };
  }
}
