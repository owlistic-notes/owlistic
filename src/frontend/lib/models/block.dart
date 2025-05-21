import 'package:owlistic/utils/data_converter.dart';

class Block {
  final String id;
  final String noteId;
  final Map<String, dynamic> content; // Changed from dynamic to Map<String, dynamic>
  final Map<String, dynamic>? metadata; // Keep metadata as optional Map
  final String type;
  final double order;
  final DateTime createdAt;
  final DateTime updatedAt;

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
    // Parse order as double
    final double orderValue = DataConverter.parseDoubleSafely(json['order']);
    
    // Parse datetime fields
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
    
    // Ensure content is a map
    Map<String, dynamic> contentMap = {};
    if (json['content'] is Map) {
      contentMap = Map<String, dynamic>.from(json['content']);
    } else if (json['content'] is String) {
      contentMap = {'text': json['content']};
    }
    
    // Parse metadata if available
    Map<String, dynamic>? metadata;
    if (json['metadata'] != null && json['metadata'] is Map) {
      metadata = Map<String, dynamic>.from(json['metadata']);
    }
    
    return Block(
      id: json['id'] ?? '',
      content: contentMap,
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
      'type': type,
      'metadata': metadata,
      'order': order,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  // Helper method to extract text content
  String getTextContent() {
    if (content.containsKey('text') && content['text'] is String) {
      return content['text'] as String;
    }
    return '';
  }
  
  // Creates update data with new text
  Map<String, dynamic> createUpdateWithText(String text) {
    final updatedContent = Map<String, dynamic>.from(content);
    updatedContent['text'] = text;
    
    return {
      'note_id': noteId,
      'type': type,
      'content': updatedContent,
      'order': order,
    };
  }

  Block copyWith({
    String? id,
    String? noteId,
    String? userId,
    String? type,
    Map<String, dynamic>? content,
    Map<String, dynamic>? metadata,
    double? order,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Block(
      id: id ?? this.id,
      noteId: noteId ?? this.noteId,
      type: type ?? this.type,
      content: content ?? Map<String, dynamic>.from(this.content),
      metadata: metadata ?? (this.metadata != null ? Map<String, dynamic>.from(this.metadata!) : null),
      order: order ?? this.order,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }
 
}
