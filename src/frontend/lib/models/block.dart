class Block {
  final String id;
  final dynamic content; // Changed from String to dynamic to support both String and Map
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
    
    // Handle content which could be a string (legacy) or a map (new format)
    final dynamic contentValue = json['content'];
            
    return Block(
      id: json['id'] ?? '',
      content: contentValue, // Store as-is, will handle conversion when accessing
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
    dynamic content,
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
  
  /// Gets the text content of this block, handling both string and map formats
  String getTextContent() {
    if (content is String) {
      return content as String;
    } else if (content is Map) {
      return (content as Map)['text']?.toString() ?? '';
    }
    return '';
  }
  
  /// Gets the raw content as a Map, handling both formats
  Map<String, dynamic> getContentMap() {
    if (content is Map) {
      return Map<String, dynamic>.from(content as Map);
    } else if (content is String) {
      // Convert legacy string content to the new format
      return {'text': content};
    }
    return {'text': ''};
  }
  
  /// Creates a content map for updating the block
  Map<String, dynamic> createContentMap(String text) {
    if (content is Map) {
      // Preserve other fields from the map
      final Map<String, dynamic> newMap = Map<String, dynamic>.from(content as Map);
      newMap['text'] = text;
      return newMap;
    }
    // Otherwise create a new map
    return {'text': text};
  }
}

extension BlockContentHelpers on Block {
  // Helper method to extract text content safely for display
  String getTextContent() {
    if (content == null) return '';
    
    try {
      // Handle different content structures
      if (content is Map) {
        final contentMap = content as Map;
        if (contentMap.containsKey('text')) {
          return contentMap['text']?.toString() ?? '';
        } else if (contentMap.containsKey('content')) {
          return contentMap['content']?.toString() ?? '';
        }
      }
      
      // If we can't extract structured content, convert the whole thing to string
      return content.toString();
    } catch (e) {
      return '';
    }
  }
}
