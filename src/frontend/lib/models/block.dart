class Block {
  final String id;
  final String content;
  final String type;
  final String noteId;
  final int order;

  const Block({
    required this.id,
    required this.content,
    required this.type,
    required this.noteId,
    required this.order,
  });

  factory Block.fromJson(Map<String, dynamic> json) {
    // Handle numeric order value (could be int or String)
    final dynamic rawOrder = json['order'];
    final int orderValue = rawOrder is String
        ? int.tryParse(rawOrder) ?? 0
        : rawOrder is int
            ? rawOrder
            : 0;
            
    return Block(
      id: json['id'] ?? '',
      content: json['content'] ?? '',
      type: json['type'] ?? 'text',
      noteId: json['note_id'] ?? '',
      order: orderValue,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'content': content,
      'type': type,
      'note_id': noteId,
      'order': order.toString(), // Serialize as string to avoid numeric type issues
    };
  }
  
  /// Creates a copy of this block with the given fields replaced with the new values
  Block copyWith({
    String? id,
    String? content,
    String? type,
    String? noteId,
    int? order,
  }) {
    return Block(
      id: id ?? this.id,
      content: content ?? this.content,
      type: type ?? this.type,
      noteId: noteId ?? this.noteId,
      order: order ?? this.order,
    );
  }
}
