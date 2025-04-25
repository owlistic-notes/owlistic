import 'dart:convert';
import 'package:flutter/material.dart';
import '../utils/logger.dart';

/// Class to represent a standardized WebSocket message with RBAC information
class WebSocketMessage {
  final String id;
  final String type;
  final String event;
  final DateTime timestamp;
  final Map<String, dynamic> payload;
  final String? resourceType;
  final String? resourceId;

  WebSocketMessage({
    required this.id,
    required this.type,
    required this.event,
    required this.timestamp,
    required this.payload,
    this.resourceType,
    this.resourceId,
  });

  factory WebSocketMessage.fromJson(Map<String, dynamic> json) {
    // Parse timestamp from ISO string or use current time as fallback
    DateTime timestamp;
    try {
      timestamp = json['timestamp'] != null
          ? DateTime.parse(json['timestamp'])
          : DateTime.now();
    } catch (e) {
      timestamp = DateTime.now();
      Logger("WebSocketMessageParser").error('Failed to parse timestamp: $e');
    }
    
    return WebSocketMessage(
      id: json['id'] ?? '',
      type: json['type'] ?? 'unknown',
      event: json['event'] ?? 'unknown',
      timestamp: timestamp,
      payload: json['payload'] != null 
          ? Map<String, dynamic>.from(json['payload']) 
          : {},
      resourceType: json['resource_type'],
      resourceId: json['resource_id'],
    );
  }
  
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type,
      'event': event,
      'timestamp': timestamp.toIso8601String(),
      'payload': payload,
      if (resourceType != null) 'resource_type': resourceType,
      if (resourceId != null) 'resource_id': resourceId,
    };
  }
}

/// Helper class for extracting entity IDs from WebSocket messages
class WebSocketModelExtractor {
  /// Extract note ID from message payload
  static String? extractNoteId(WebSocketMessage message) {
    // First check if resourceId is already set and resource type is note
    if (message.resourceType == 'note' && message.resourceId != null) {
      return message.resourceId;
    }
    
    final payload = message.payload;
    
    // Check direct payload fields
    if (payload.containsKey('note_id')) {
      return payload['note_id']?.toString();
    }
    
    // Check in data structure if present
    if (payload.containsKey('data')) {
      final data = payload['data'];
      if (data is Map) {
        return data['note_id']?.toString() ?? 
               data['id']?.toString();
      }
    }
    
    return null;
  }

  /// Extract notebook ID from message payload
  static String? extractNotebookId(WebSocketMessage message) {
    // First check if resourceId is already set and resource type is notebook
    if (message.resourceType == 'notebook' && message.resourceId != null) {
      return message.resourceId;
    }
    
    final payload = message.payload;
    
    // Check direct payload fields
    if (payload.containsKey('notebook_id')) {
      return payload['notebook_id']?.toString();
    }
    
    // Check in data structure if present
    if (payload.containsKey('data')) {
      final data = payload['data'];
      if (data is Map) {
        return data['notebook_id']?.toString() ?? 
               data['id']?.toString();
      }
    }
    
    return null;
  }

  /// Extract block ID from message payload
  static String? extractBlockId(WebSocketMessage message) {
    // First check if resourceId is already set and resource type is block
    if (message.resourceType == 'block' && message.resourceId != null) {
      return message.resourceId;
    }
    
    final payload = message.payload;
    
    // Check direct payload fields
    if (payload.containsKey('id')) {
      return payload['id']?.toString();
    }
    
    // Check in data structure if present
    if (payload.containsKey('data')) {
      final data = payload['data'];
      if (data is Map) {
        return data['block_id']?.toString() ?? 
               data['id']?.toString();
      }
    }
    
    return null;
  }
}
