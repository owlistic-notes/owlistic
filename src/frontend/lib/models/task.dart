class Task {
  final String id;
  final String title;
  final bool isCompleted;
  final String userId;
  final String? description;
  final String? dueDate;
  final String? noteId;
  final String? blockId;
  final DateTime? createdAt;
  final DateTime? deletedAt;

  const Task({
    required this.id,
    required this.title,
    required this.isCompleted,
    required this.userId,
    this.description,
    this.dueDate,
    this.noteId,
    this.blockId,
    this.createdAt,
    this.deletedAt,
  });

  factory Task.fromJson(Map<String, dynamic> json) {
    // Parse createdAt and deletedAt
    DateTime? createdAt;
    if (json['created_at'] != null) {
      try {
        createdAt = DateTime.parse(json['created_at']);
      } catch (e) {
        print('Error parsing created_at: $e');
      }
    }

    DateTime? deletedAt;
    if (json['deleted_at'] != null) {
      try {
        deletedAt = DateTime.parse(json['deleted_at']);
      } catch (e) {
        print('Error parsing deleted_at: $e');
      }
    }

    return Task(
      id: json['id'] ?? '',
      title: json['title'] ?? '',
      isCompleted: json['is_completed'] ?? false,
      userId: json['user_id'] ?? '',
      description: json['description'],
      dueDate: json['due_date'],
      noteId: json['note_id'],
      blockId: json['block_id'],
      createdAt: createdAt,
      deletedAt: deletedAt,
    );
  }
  
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'is_completed': isCompleted,
      'user_id': userId,
      if (description != null) 'description': description,
      if (dueDate != null) 'due_date': dueDate,
      if (noteId != null) 'note_id': noteId,
      if (blockId != null) 'block_id': blockId,
      if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
      if (deletedAt != null) 'deleted_at': deletedAt!.toIso8601String(),
    };
  }

  /// Creates a payload specifically for task updates
  Map<String, dynamic> toUpdatePayload() {
    return {
      'title': title,
      'is_completed': isCompleted,
      if (description != null) 'description': description,
      if (dueDate != null) 'due_date': dueDate,
    };
  }

  /// Creates a copy of this task with the given fields replaced with the new values
  Task copyWith({
    String? id,
    String? title,
    bool? isCompleted,
    String? userId,
    String? description,
    String? dueDate,
    String? noteId,
    String? blockId,
    DateTime? createdAt,
    DateTime? deletedAt,
  }) {
    return Task(
      id: id ?? this.id,
      title: title ?? this.title,
      isCompleted: isCompleted ?? this.isCompleted,
      userId: userId ?? this.userId,
      description: description ?? this.description,
      dueDate: dueDate ?? this.dueDate,
      noteId: noteId ?? this.noteId,
      blockId: blockId ?? this.blockId,
      createdAt: createdAt ?? this.createdAt,
      deletedAt: deletedAt ?? this.deletedAt,
    );
  }
}
