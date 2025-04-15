import 'dart:convert';
import 'package:flutter/foundation.dart';

/// Utility class for inspecting WebSocket messages
class WebSocketDebugger {
  /// Extract and print all relevant IDs from a WebSocket event
  static void analyzeMessage(Map<String, dynamic> message, {bool verbose = false}) {
    if (!kDebugMode) return;
    
    final StringBuffer log = StringBuffer();
    log.writeln("WebSocket Message Analysis:");
    
    // Analyze Type and Event
    final String type = message['type'] ?? 'unknown';
    final String event = message['event'] ?? 'unknown';
    log.writeln("- Type: $type");
    log.writeln("- Event: $event");
    
    // Extract resource IDs from payload structure
    if (message.containsKey('payload')) {
      final payload = message['payload'];
      
      // Check for payload.data which contains the resource IDs
      if (payload is Map<String, dynamic> && payload.containsKey('data')) {
        final data = payload['data'];
        if (data is Map<String, dynamic>) {
          log.writeln("- Resource IDs in payload.data:");
          
          // Print all resource IDs we find in data
          if (data.containsKey('note_id')) {
            log.writeln("  * note_id: ${data['note_id']}");
          }
          if (data.containsKey('notebook_id')) {
            log.writeln("  * notebook_id: ${data['notebook_id']}");
          }
          if (data.containsKey('block_id')) {
            log.writeln("  * block_id: ${data['block_id']}");
          }
          if (data.containsKey('task_id')) {
            log.writeln("  * task_id: ${data['task_id']}");
          }
        }
      } else {
        log.writeln("- No 'data' field found in payload");
      }
    }
    
    // Print complete message for debugging with standard structure
    if (verbose) {
      log.writeln("\nComplete message:");
      log.writeln(const JsonEncoder.withIndent('  ').convert(message));
    }
    
    debugPrint(log.toString());
  }
}
