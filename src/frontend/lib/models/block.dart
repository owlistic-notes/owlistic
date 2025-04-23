import 'dart:convert';

import '../utils/data_converter.dart';

class Block {
  final String id;
  final String noteId;
  final dynamic content;
  final String type;
  final int order;
  final DateTime createdAt;
  final DateTime updatedAt;

  Block({
    required this.id,
    required this.noteId,
    required this.content,
    required this.type,
    required this.order,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : this.createdAt = createdAt ?? DateTime.now(),
       this.updatedAt = updatedAt ?? DateTime.now();

  factory Block.fromJson(Map<String, dynamic> json) {
    // Use DataConverter for parsing numeric values
    final int orderValue = DataConverter.parseIntSafely(json['order']);
    
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
    
    return Block(
      id: json['id'] ?? '',
      content: json['content'], // Store as-is, will handle conversion when accessing
      type: json['type'] ?? 'text',
      noteId: json['note_id'] ?? '',
      order: orderValue,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'note_id': noteId,
      'content': content is String ? content : jsonEncode(content),
      'type': type,
      'order': order,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
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
}
