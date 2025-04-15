class Block {
  final String id;
  final String content;
  final String type;
  final String noteId;
  final int order;

  Block({
    required this.id,
    required this.content,
    required this.type,
    required this.noteId,
    required this.order,
  });

  factory Block.fromJson(Map<String, dynamic> json) {
    return Block(
      id: json['id'] ?? '',
      content: json['content'] ?? '',
      type: json['type'] ?? 'text',
      noteId: json['note_id'] ?? '',
      order: json['order'] ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'content': content,
      'type': type,
      'note_id': noteId,
      'order': order,
    };
  }
}
