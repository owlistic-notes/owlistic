import 'block.dart';

class Note {
  final String id;
  final String title;
  final String userId;
  final String notebookId;
  final List<Block> blocks;
  final DateTime? deletedAt;

  const Note({
    required this.id,
    required this.title,
    required this.userId,
    required this.notebookId,
    this.blocks = const [],
    this.deletedAt,
  });

  String get content {
    final contents = blocks.map((b) => b.content).where((c) => c.isNotEmpty);
    return contents.isEmpty ? '' : contents.join('\n');
  }

  factory Note.fromJson(Map<String, dynamic> json) {
    DateTime? deletedAt;
    if (json['deleted_at'] != null) {
      try {
        deletedAt = DateTime.parse(json['deleted_at']);
      } catch (_) {}
    }
    
    return Note(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      userId: json['user_id']?.toString() ?? '',
      notebookId: json['notebook_id']?.toString() ?? '',
      blocks: (json['blocks'] as List<dynamic>?)
          ?.map((block) => Block.fromJson(block))
          .toList() ?? const [],
      deletedAt: deletedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'user_id': userId,
      'notebook_id': notebookId,
      'blocks': blocks.map((block) => block.toJson()).toList(),
    };
  }
  
  /// Creates a copy of this note with the given fields replaced with the new values
  Note copyWith({
    String? id,
    String? title,
    String? userId,
    String? notebookId,
    List<Block>? blocks,
  }) {
    return Note(
      id: id ?? this.id,
      title: title ?? this.title,
      userId: userId ?? this.userId,
      notebookId: notebookId ?? this.notebookId,
      blocks: blocks ?? this.blocks,
    );
  }
}
