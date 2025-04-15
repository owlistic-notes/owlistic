class Block {
  final String id;
  final String content;
  final String type;
  final int order;
  final String noteId;

  Block({
    required this.id,
    required this.content,
    required this.type,
    required this.order,
    required this.noteId,
  });

  factory Block.fromJson(Map<String, dynamic> json) {
    return Block(
      id: json['id']?.toString() ?? '',
      content: json['content']?.toString() ?? '',
      type: json['type']?.toString() ?? 'text',
      order: json['order'] as int? ?? 0,
      noteId: json['note_id']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'content': content,
      'type': type,
      'order': order,
      'note_id': noteId,
    };
  }
}
