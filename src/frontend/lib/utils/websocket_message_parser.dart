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
    // Handle both original format and new standardized format
    String type = json['type'] ?? 'event';
    String event = json['event'] ?? '';
    
    // Handle the payload extraction differently based on format
    Map<String, dynamic> payload = {};
    
    if (json.containsKey('payload')) {
      // New format with 'payload' field
      payload = json['payload'] is Map<String, dynamic> 
          ? json['payload'] 
          : (json['payload'] is String 
              ? jsonDecode(json['payload']) 
              : {});
    } else if (json.containsKey('data')) {
      // Legacy format with 'data' field
      payload = json['data'] is Map<String, dynamic> 
          ? json['data'] 
          : (json['data'] is String 
              ? jsonDecode(json['data']) 
              : {});
      
      // Try to extract the event from legacy format
      if (event.isEmpty && json.containsKey('event')) {
        event = json['event'].toString();
      }
    } else {
      // Assume the entire message is the payload
      payload = Map<String, dynamic>.from(json);
    }

    return WebSocketMessage(
      type: type,
      event: event,
      payload: payload,
    );
  }
}

/// Helper class for extracting entity IDs from WebSocket messages
class WebSocketModelExtractor {
  /// Extract note ID from various formats of WebSocket messages
  static String? extractNoteId(WebSocketMessage message) {
    // Check payload.data.note_id (new standard format)
    if (message.payload.containsKey('data') && 
        message.payload['data'] is Map<String, dynamic> &&
        message.payload['data'].containsKey('note_id')) {
      return message.payload['data']['note_id']?.toString();
    }
    
    // Check payload.data.id (fallback if entity is a note)
    if (message.payload.containsKey('data') && 
        message.payload['data'] is Map<String, dynamic> &&
        message.payload['data'].containsKey('id') &&
        (message.payload['entity'] == 'note' || message.event.contains('note'))) {
      return message.payload['data']['id']?.toString();
    }
    
    // Check payload.id (direct id in payload)
    if (message.payload.containsKey('id')) {
      return message.payload['id']?.toString();
    }
    
    // Check payload.note_id (common format)
    if (message.payload.containsKey('note_id')) {
      return message.payload['note_id']?.toString();
    }
    
    // Legacy event format
    if (message.payload.containsKey('event_data')) {
      var eventData = message.payload['event_data'];
      if (eventData is Map<String, dynamic>) {
        if (eventData.containsKey('note_id')) {
          return eventData['note_id']?.toString();
        }
      }
    }
    
    return null;
  }

  /// Extract notebook ID from various formats of WebSocket messages
  static String? extractNotebookId(WebSocketMessage message) {
    // Check payload.data.notebook_id (new standard format)
    if (message.payload.containsKey('data') && 
        message.payload['data'] is Map<String, dynamic> &&
        message.payload['data'].containsKey('notebook_id')) {
      return message.payload['data']['notebook_id']?.toString();
    }
    
    // Check payload.data.id (fallback if entity is a notebook)
    if (message.payload.containsKey('data') && 
        message.payload['data'] is Map<String, dynamic> &&
        message.payload['data'].containsKey('id') &&
        (message.payload['entity'] == 'notebook' || message.event.contains('notebook'))) {
      return message.payload['data']['id']?.toString();
    }
    
    // Check payload.id (direct id in payload)
    if (message.payload.containsKey('id') && 
        (message.event.contains('notebook') || message.type.contains('notebook'))) {
      return message.payload['id']?.toString();
    }
    
    // Check payload.notebook_id (common format)
    if (message.payload.containsKey('notebook_id')) {
      return message.payload['notebook_id']?.toString();
    }
    
    // Legacy event format
    if (message.payload.containsKey('event_data')) {
      var eventData = message.payload['event_data'];
      if (eventData is Map<String, dynamic>) {
        if (eventData.containsKey('notebook_id')) {
          return eventData['notebook_id']?.toString();
        }
      }
    }
    
    return null;
  }

  /// Extract block ID from various formats of WebSocket messages
  static String? extractBlockId(WebSocketMessage message) {
    // Check payload.data.block_id (new standard format)
    if (message.payload.containsKey('data') && 
        message.payload['data'] is Map<String, dynamic> &&
        message.payload['data'].containsKey('block_id')) {
      return message.payload['data']['block_id']?.toString();
    }
    
    // Check payload.data.id (fallback if entity is a block)
    if (message.payload.containsKey('data') && 
        message.payload['data'] is Map<String, dynamic> &&
        message.payload['data'].containsKey('id') &&
        (message.payload['entity'] == 'block' || message.event.contains('block'))) {
      return message.payload['data']['id']?.toString();
    }
    
    // Check payload.id (direct id in payload)
    if (message.payload.containsKey('id') && 
        (message.event.contains('block') || message.type.contains('block'))) {
      return message.payload['id']?.toString();
    }
    
    // Check payload.block_id (common format)
    if (message.payload.containsKey('block_id')) {
      return message.payload['block_id']?.toString();
    }
    
    // Legacy event format
    if (message.payload.containsKey('event_data')) {
      var eventData = message.payload['event_data'];
      if (eventData is Map<String, dynamic>) {
        if (eventData.containsKey('block_id')) {
          return eventData['block_id']?.toString();
        }
      }
    }
    
    return null;
  }
}
