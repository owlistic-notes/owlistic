import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'logger.dart';

/// Utility class for inspecting WebSocket messages
class WebSocketDebugger {
  static final Logger _logger = Logger('WebSocketDebugger');
  
  /// Extract and print all relevant IDs from a WebSocket event
  static void analyzeMessage(Map<String, dynamic> message, {bool verbose = false}) {
    // Early return if not in debug mode to avoid unnecessary processing
    if (!kDebugMode) return;
    
    final buffer = StringBuffer();
    buffer.writeln("WebSocket Message Analysis:");
    
    // Analyze Type and Event - use null-aware operator with conditional assignment
    final type = message['type'] ?? 'unknown';
    final event = message['event'] ?? 'unknown';
    buffer.writeln("- Type: $type");
    buffer.writeln("- Event: $event");
    
    // Extract resource IDs from payload structure - using containsKey for null safety
    if (message.containsKey('payload')) {
      final payload = message['payload'];
      
      // Check for payload.data which contains the resource IDs
      if (payload is Map<String, dynamic>) {
        _analyzePayload(buffer, payload);
      }
    }
    
    // Print complete message for debugging with standard structure
    if (verbose) {
      buffer.writeln("\nComplete message:");
      // Use const for the encoder to avoid recreation
      buffer.writeln(const JsonEncoder.withIndent('  ').convert(message));
    }
    
    _logger.debug(buffer.toString());
  }
  
  /// Helper method to analyze payload data and extract resource IDs
  static void _analyzePayload(StringBuffer buffer, Map<String, dynamic> payload) {
    // Check for data field
    if (payload.containsKey('data')) {
      final data = payload['data'];
      if (data is Map<String, dynamic>) {
        buffer.writeln("- Resource IDs in payload.data:");
        
        // Create a list of resource ID fields to check
        const resourceIdFields = [
          'note_id',
          'notebook_id',
          'block_id',
          'task_id',
        ];
        
        // Check for each resource ID and add to output if found
        bool foundAny = false;
        for (final field in resourceIdFields) {
          if (data.containsKey(field)) {
            buffer.writeln("  * $field: ${data[field]}");
            foundAny = true;
          }
        }
        
        // If no resource IDs were found, indicate that
        if (!foundAny) {
          buffer.writeln("  * No specific resource IDs found");
        }
      }
    } else {
      buffer.writeln("- No 'data' field found in payload");
    }
  }
}
