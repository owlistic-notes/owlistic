import 'dart:convert';
import 'package:flutter/material.dart';

/// Class to represent a structured WebSocket message
class WebSocketMessage {
  final String type;
  final String event;
  final Map<String, dynamic> payload;

  WebSocketMessage({
    required this.type,
    required this.event,
    required this.payload,
  });

  factory WebSocketMessage.fromJson(Map<String, dynamic> json) {
    return WebSocketMessage(
      type: json['type'] ?? 'unknown',
      event: json['event'] ?? 'unknown',
      payload: json['payload'] != null 
          ? Map<String, dynamic>.from(json['payload']) 
          : {},
    );
  }
}

/// Helper class for extracting entity IDs from WebSocket messages
class WebSocketModelExtractor {
  /// Extract note ID from various formats of WebSocket messages
  static String? extractNoteId(WebSocketMessage message) {
    final payload = message.payload;
    
    if (payload['data'] != null) {
      final data = payload['data'];
      
      // Try multiple possible field names
      return data['note_id']?.toString() ??
             data['noteId']?.toString() ??
             data['id']?.toString();
    }
    
    // Try payload-level fields
    return payload['note_id']?.toString() ??
           payload['noteId']?.toString() ??
           payload['id']?.toString();
  }

  /// Extract notebook ID from various formats of WebSocket messages
  static String? extractNotebookId(WebSocketMessage message) {
    final payload = message.payload;
    
    if (payload['data'] != null) {
      final data = payload['data'];
      
      // Try multiple possible field names
      return data['notebook_id']?.toString() ??
             data['notebookId']?.toString() ??
             data['id']?.toString();
    }
    
    // Try payload-level fields
    return payload['notebook_id']?.toString() ??
           payload['notebookId']?.toString() ??
           payload['id']?.toString();
  }

  /// Extract block ID from various formats of WebSocket messages
  static String? extractBlockId(WebSocketMessage message) {
    final payload = message.payload;
    
    if (payload['data'] != null) {
      final data = payload['data'];
      
      // Try multiple possible field names
      return data['block_id']?.toString() ??
             data['blockId']?.toString() ??
             data['id']?.toString();
    }
    
    // Try payload-level fields
    return payload['block_id']?.toString() ??
           payload['blockId']?.toString() ??
           payload['id']?.toString();
  }
}
