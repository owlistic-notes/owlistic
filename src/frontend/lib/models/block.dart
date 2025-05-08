
import '../utils/data_converter.dart';

class Block {
  final String id;
  final String noteId;
  final dynamic content;
  final String type;
  final double order;  // Changed from int to double
  final DateTime createdAt;
  final DateTime updatedAt;
  final Map<String, dynamic>? metadata;

  Block({
    required this.id,
    required this.noteId,
    required this.content,
    required this.type,
    required this.order,
    this.metadata,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  factory Block.fromJson(Map<String, dynamic> json) {
    // Use DataConverter for parsing numeric values as double
    final double orderValue = DataConverter.parseDoubleSafely(json['order']);
    
    // Parse datetime fields with appropriate fallback
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
    
    // Parse metadata if available
    Map<String, dynamic>? metadata;
    if (json['metadata'] != null) {
      metadata = json['metadata'] is Map 
          ? Map<String, dynamic>.from(json['metadata']) 
          : null;
    }
    
    return Block(
      id: json['id'] ?? '',
      content: json['content'], // Store as-is, will handle conversion when accessing
      type: json['type'] ?? 'text',
      noteId: json['note_id'] ?? '',
      order: orderValue,
      metadata: metadata,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'note_id': noteId,
      'content': content,
      'block_type': type, // Always use block_type for API serialization
      'metadata': metadata,
      'order': order,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  /// Creates a block update with new content text
  Map<String, dynamic> createUpdateWithText(String text) {
    final Map<String, dynamic> contentMap = DataConverter.normalizeContent(content);
    contentMap['text'] = text;
    
    return {
      'note_id': noteId,
      'block_type': type, // Always use block_type
      'content': contentMap,
      'order': order,
    };
  }

  // Helper method to extract text content from various block types
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

  /// Get the document blockType for rendering
  String getBlockType() {
    // First check metadata if it contains blockType
    if (metadata != null && metadata!.containsKey('blockType')) {
      return metadata!['blockType'].toString();
    }
    
    // Fallback to inferring from block type
    switch (type) {
      case 'heading':
        final level = getHeadingLevel();
        return 'heading$level';
      case 'checklist':
        return 'listItem';
      case 'code':
        return 'codeBlock';
      case 'text':
      default:
        return 'paragraph';
    }
  }
  
  /// Get raw markdown if available
  String? getRawMarkdown() {
    // First check metadata (preferred location)
    if (metadata != null && metadata!.containsKey('raw_markdown')) {
      return metadata!['raw_markdown']?.toString();
    }
    
    // Fallback to checking content for backward compatibility
    final contentMap = getContentMap();
    return contentMap['raw_markdown']?.toString();
  }

  /// Get inline styles for text formatting
  List<Map<String, dynamic>>? getInlineStyles() {
    final contentMap = getContentMap();
    
    // Try to get styles from spans in content
    if (contentMap.containsKey('spans')) {
      final spans = contentMap['spans'];
      if (spans is List) {
        return List<Map<String, dynamic>>.from(
          spans.map((span) => span is Map ? Map<String, dynamic>.from(span) : {})
        );
      }
    }
    
    return null;
  }

  // Add a copyWith method to make local updates easier
  Block copyWith({
    String? id,
    String? noteId,
    String? userId,
    String? type,
    Map<String, dynamic>? content,
    Map<String, dynamic>? metadata,
    double? order,  // Changed from int to double
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Block(
      id: id ?? this.id,
      noteId: noteId ?? this.noteId,
      type: type ?? this.type,
      content: content ?? this.content,
      metadata: metadata ?? this.metadata,
      order: order ?? this.order,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }

  // Add a method to handle style metadata
  List<Map<String, dynamic>>? getStyleSpans() {
    // First try to get from metadata (preferred location)
    if (metadata != null && 
        metadata!.containsKey('styling') && 
        metadata!['styling'] is Map &&
        metadata!['styling']['spans'] is List) {
      return List<Map<String, dynamic>>.from(metadata!['styling']['spans']);
    }
    
    // Fallback to content spans
    return getSpans();
  }
}
