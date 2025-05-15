class Task {
  final String id;
  final String title;
  final bool isCompleted;
  final String userId;
  final String? description;
  final String? dueDate;
  final String? noteId;
  final String? blockId;
  final Map<String, dynamic>? metadata;
  final DateTime? createdAt;
  final DateTime? updatedAt;
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
    this.metadata,
    this.createdAt,
    this.updatedAt,
    this.deletedAt,
  });

  factory Task.fromJson(Map<String, dynamic> json) {
    // Parse datetime fields
    DateTime? createdAt;
    if (json['created_at'] != null) {
      try {
        createdAt = DateTime.parse(json['created_at']);
      } catch (e) {
        createdAt = DateTime.now();
      }
    }

    DateTime? updatedAt;
    if (json['updated_at'] != null) {
      try {
        updatedAt = DateTime.parse(json['updated_at']);
      } catch (e) {
        updatedAt = DateTime.now();
      }
    }

    DateTime? deletedAt;
    if (json['deleted_at'] != null) {
      try {
        deletedAt = DateTime.parse(json['deleted_at']);
      } catch (e) {
        updatedAt = DateTime.now();
      }
    }
    
    // Parse metadata if available
    Map<String, dynamic>? metadata;
    if (json['metadata'] != null && json['metadata'] is Map) {
      metadata = Map<String, dynamic>.from(json['metadata']);
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
      metadata: metadata,
      createdAt: createdAt,
      updatedAt: updatedAt,
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
      if (metadata != null) 'metadata': metadata,
      if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
      if (updatedAt != null) 'updated_at': updatedAt!.toIso8601String(),
      if (deletedAt != null) 'deleted_at': deletedAt!.toIso8601String(),
    };
  }

  Task copyWith({
    String? id,
    String? title,
    bool? isCompleted,
    String? userId,
    String? description,
    String? dueDate,
    String? noteId,
    String? blockId,
    Map<String, dynamic>? metadata,
    DateTime? createdAt,
    DateTime? updatedAt,
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
      metadata: metadata ?? this.metadata,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
    );
  }
}
