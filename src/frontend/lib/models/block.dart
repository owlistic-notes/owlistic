import '../utils/data_converter.dart';

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
    // Use DataConverter for parsing numeric values
    final int orderValue = DataConverter.parseIntSafely(json['order']);
    
    return Block(
      id: json['id'] ?? '',
      content: json['content'], // Store as-is, will handle conversion when accessing
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
    return DataConverter.extractTextContent(content);
  }
  
  /// Gets the raw content as a Map, handling both formats
  Map<String, dynamic> getContentMap() {
    return DataConverter.normalizeContent(content);
  }
  
  /// Creates a content map for updating the block
  Map<String, dynamic> createContentMap(String text) {
    final Map<String, dynamic> contentMap = DataConverter.normalizeContent(content);
    contentMap['text'] = text;
    return contentMap;
  }
  
  /// Gets the heading level if this is a heading block
  int getHeadingLevel() {
    if (type == 'heading') {
      final contentMap = getContentMap();
      return DataConverter.parseIntSafely(contentMap['level'], defaultValue: 1);
    }
    return 0;
  }
  
  /// Check if this is a checklist item and whether it's checked
  bool isChecklistChecked() {
    if (type == 'checklist') {
      final contentMap = getContentMap();
      return contentMap['checked'] == true;
    }
    return false;
  }
  
  /// Get code block language if this is a code block
  String getCodeLanguage() {
    if (type == 'code') {
      final contentMap = getContentMap();
      return contentMap['language']?.toString() ?? 'plain';
    }
    return 'plain';
  }
  
  /// Extract span/formatting information from content
  List<Map<String, dynamic>>? getSpans() {
    return DataConverter.extractSpans(content);
  }
}
