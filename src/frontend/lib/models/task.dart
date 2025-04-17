class Task {
  final String id;
  final String title;
  final bool isCompleted;
  final String userId;
  final String? description;
  final String? dueDate;
  final String? noteId;
  final String? blockId;

  const Task({
    required this.id,
    required this.title,
    required this.isCompleted,
    required this.userId,
    this.description,
    this.dueDate,
    this.noteId,
    this.blockId,
  });

  factory Task.fromJson(Map<String, dynamic> json) {
    return Task(
      id: json['ID'] ?? '',
      title: json['Title'] ?? '',
      isCompleted: json['IsCompleted'] ?? false,
      userId: json['UserID'] ?? '',
      description: json['Description'],
      dueDate: json['DueDate'],
      noteId: json['NoteID'],
      blockId: json['block_id'],
    );
  }
  
  Map<String, dynamic> toJson() {
    return {
      'ID': id,
      'Title': title,
      'IsCompleted': isCompleted,
      'UserID': userId,
      if (description != null) 'Description': description,
      if (dueDate != null) 'DueDate': dueDate,
      if (noteId != null) 'NoteID': noteId,
      if (blockId != null) 'block_id': blockId,
    };
  }
}
