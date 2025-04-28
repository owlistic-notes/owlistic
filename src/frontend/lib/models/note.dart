import 'block.dart';

class Note {
  final String id;
  final String title;
  final String notebookId;
  final String userId;
  final List<Block> blocks;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? deletedAt;

  const Note({
    required this.id,
    required this.title,
    required this.notebookId,
    required this.userId,
    this.blocks = const [],
    this.createdAt,
    this.updatedAt,
    this.deletedAt,
  });

  String get content {
    final contents = blocks.map((b) => b.content).where((c) => c.isNotEmpty);
    return contents.isEmpty ? '' : contents.join('\n');
  }

  factory Note.fromJson(Map<String, dynamic> json) {
    List<Block> blocksList = [];
    
    // Parse blocks if available
    if (json.containsKey('blocks')) {
      final blocksJson = json['blocks'];
      if (blocksJson != null) {
        try {
          if (blocksJson is List) {
            blocksList = blocksJson
              .where((blockJson) => blockJson != null)
              .map<Block>((blockJson) => Block.fromJson(blockJson))
              .toList();
          }
        } catch (e) {
          print('Error parsing blocks in note: $e');
        }
      }
    }
    
    // Parse dates
    DateTime? createdAt;
    if (json['created_at'] != null) {
      try {
        createdAt = DateTime.parse(json['created_at']);
      } catch (e) {
        print('Error parsing created_at: $e');
      }
    }

    DateTime? updatedAt;
    if (json['updated_at'] != null) {
      try {
        updatedAt = DateTime.parse(json['updated_at']);
      } catch (e) {
        print('Error parsing updated_at: $e');
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

    return Note(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      notebookId: json['notebook_id']?.toString() ?? '',
      userId: json['user_id']?.toString() ?? '',
      blocks: blocksList,
      createdAt: createdAt,
      updatedAt: updatedAt,
      deletedAt: deletedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'notebook_id': notebookId,
      'user_id': userId,
      'blocks': blocks.map((block) => block.toJson()).toList(),
      if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
      if (updatedAt != null) 'updated_at': updatedAt!.toIso8601String(),
      if (deletedAt != null) 'deleted_at': deletedAt!.toIso8601String(),
    };
  }
  
  /// Creates a copy of this note with the given fields replaced with the new values
  Note copyWith({
    String? id,
    String? title,
    String? notebookId,
    String? userId,
    List<Block>? blocks,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? deletedAt,
  }) {
    return Note(
      id: id ?? this.id,
      title: title ?? this.title,
      notebookId: notebookId ?? this.notebookId,
      userId: userId ?? this.userId,
      blocks: blocks ?? this.blocks,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
    );
  }
}
