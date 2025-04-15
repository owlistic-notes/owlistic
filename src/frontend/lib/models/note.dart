import 'block.dart';

class Note {
  final String id;
  final String title;
  final String userId;
  final String notebookId;
  final List<Block> blocks;

  Note({
    required this.id,
    required this.title,
    required this.userId,
    required this.notebookId,
    this.blocks = const [],
  });

  String get content {
    final contents = blocks.map((b) => b.content).where((c) => c.isNotEmpty);
    return contents.isEmpty ? '' : contents.join('\n');
  }

  factory Note.fromJson(Map<String, dynamic> json) {
    return Note(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      userId: json['user_id']?.toString() ?? '',
      notebookId: json['notebook_id']?.toString() ?? '',
      blocks: (json['blocks'] as List<dynamic>?)
          ?.map((block) => Block.fromJson(block))
          .toList() ?? [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'user_id': userId,
      'notebook_id': notebookId,
      'blocks': [
        {
          'content': '',
          'type': 'text',
          'order': 0
        }
      ],
    };
  }
}
