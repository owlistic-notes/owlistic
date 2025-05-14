import 'package:super_editor/super_editor.dart' hide Logger;
import '../utils/logger.dart';

/// Class that handles mapping between Blocks and SuperEditor DocumentNodes
class AttributedTextUtils {
  // Add logger instance
  final Logger _logger = Logger('AttributedTextUtils');

  // Helper method to determine node's block type
  String detectBlockTypeFromNode(DocumentNode node) {
    if (node is ParagraphNode) {
      final blockType = node.metadata['blockType'];
      
      String blockTypeStr = '';
      // Convert blockType to string if it's a NamedAttribution
      if (blockType is NamedAttribution) {
        blockTypeStr = blockType.id;
      } else if (blockType is String) {
        blockTypeStr = blockType;
      }
      
      if (blockTypeStr == 'heading') {
        return 'heading';
      } else if (blockTypeStr == 'code') {
        return 'code';
      }
    } 
    else if (node is TaskNode) {
      return 'task';
    }
    
    // Default type
    return 'text';
  }

  // Extract spans (formatting information) from AttributedText with better handling
  List<Map<String, dynamic>> extractSpansFromAttributedText(AttributedText attributedText) {
    final List<Map<String, dynamic>> spans = [];
    final text = attributedText.toPlainText();
    
    // If text is empty, return empty spans
    if (text.isEmpty) {
      return [];
    }
    
    // Use the same attribution types that SuperEditor uses in defaultStyleBuilder
    final attributions = [
      const NamedAttribution('bold'),
      const NamedAttribution('italic'),
      const NamedAttribution('underline'),
      const NamedAttribution('strikethrough')
    ];
    
    // Extract spans for each standard attribution type
    for (final attribution in attributions) {
      final attributionSpans = attributedText.getAttributionSpans({attribution});
      for (final span in attributionSpans) {
        // Ensure span bounds are valid
        if (span.start >= 0 && span.end <= text.length && span.end > span.start) {
          spans.add({
            'start': span.start,
            'end': span.end,
            'type': attribution.id,
          });
        }
      }
    }
    
    // Handle links separately as they're a different type of attribution
    for (int i = 0; i < text.length; i++) {
      final attributionsAtPosition = attributedText.getAllAttributionsAt(i);
      for (final attribution in attributionsAtPosition) {
        if (attribution is LinkAttribution) {
          int end = i;
          while (end < text.length && 
                attributedText.getAllAttributionsAt(end).contains(attribution)) {
            end++;
          }
          
          // Only add if span bounds are valid
          if (i >= 0 && end <= text.length && end > i) {
            spans.add({
              'start': i,
              'end': end,
              'type': 'link',
              'href': attribution.url,
            });
          }
          
          i = end - 1;
          break;
        }
      }
    }
    
    // Merge adjacent spans of the same type to optimize storage
    return _mergeAdjacentSpans(spans);
  }
  
  // Improved helper method to merge adjacent spans of the same type
  List<Map<String, dynamic>> _mergeAdjacentSpans(List<Map<String, dynamic>> spans) {
    if (spans.isEmpty) return [];
    
    // Sort spans by start position for easier processing
    spans.sort((a, b) => a['start'].compareTo(b['start']));
    
    final List<Map<String, dynamic>> mergedSpans = [];
    Map<String, dynamic>? currentSpan;
    
    for (final span in spans) {
      if (currentSpan == null) {
        currentSpan = Map<String, dynamic>.from(span);
      } else if (currentSpan['end'] >= span['start'] && 
                 currentSpan['type'] == span['type'] &&
                 // For links, only merge if they have the same href
                 (span['type'] != 'link' || currentSpan['href'] == span['href'])) {
        // Merge by extending the end of the current span
        currentSpan['end'] = span['end'] > currentSpan['end'] ? span['end'] : currentSpan['end'];
      } else {
        // Different type or non-adjacent spans, add current and start a new one
        mergedSpans.add(currentSpan);
        currentSpan = Map<String, dynamic>.from(span);
      }
    }
    
    // Add the last span if it exists
    if (currentSpan != null) {
      mergedSpans.add(currentSpan);
    }
    
    return mergedSpans;
  }

  // Create AttributedText from content including spans with better error handling
  AttributedText createAttributedTextFromContent(String text, dynamic content) {
    // Safety check for empty text
    if (text.isEmpty) {
      return AttributedText('');
    }
    
    final attributedText = AttributedText(text);
    
    try {
      // Process spans if available
      List? spans;
      if (content is Map) {
        if (content.containsKey('spans')) {
          spans = content['spans'] as List?;
        } else if (content.containsKey('inlineStyles')) {
          spans = content['inlineStyles'] as List?;
        } else if (content.containsKey('metadata')) {
          // Check if spans are in metadata.styling
          final metadata = content['metadata'] as Map?;
          if (metadata != null && metadata.containsKey('styling')) {
            final styling = metadata['styling'] as Map?;
            if (styling != null && styling.containsKey('spans')) {
              spans = styling['spans'] as List?;
            }
          }
        }
      }
      
      if (spans != null) {
        for (final span in spans) {
          if (span is Map && 
              span.containsKey('start') && 
              span.containsKey('end') && 
              span.containsKey('type')) {
            try {
              final start = span['start'] is int ? span['start'] : int.tryParse(span['start'].toString()) ?? 0;
              final end = span['end'] is int ? span['end'] : int.tryParse(span['end'].toString()) ?? 0;
              final type = span['type'] as String? ?? '';
              
              // Validate span range to avoid errors
              if (start >= 0 && end > start && end <= text.length) {
                // Apply attributions based on the type
                switch (type) {
                  case 'bold':
                    attributedText.addAttribution(
                      const NamedAttribution('bold'), 
                      SpanRange(start, end)
                    );
                    break;
                  case 'italic':
                    attributedText.addAttribution(
                      const NamedAttribution('italic'), 
                      SpanRange(start, end)
                    );
                    break;
                  case 'link':
                    final href = span['href'] as String?;
                    if (href != null) {
                      attributedText.addAttribution(
                        LinkAttribution(href), 
                        SpanRange(start, end)
                      );
                    }
                    break;
                  case 'underline':
                    attributedText.addAttribution(
                      const NamedAttribution('underline'), 
                      SpanRange(start, end)
                    );
                    break;
                  case 'strikethrough':
                    attributedText.addAttribution(
                      const NamedAttribution('strikethrough'), 
                      SpanRange(start, end)
                    );
                    break;
                }
              }
            } catch (e) {
              _logger.warning('Error processing span: $e');
              // Continue with next span
            }
          }
        }
      }
    } catch (e) {
      _logger.error('Error processing text spans: $e');
      // Return plain text if span processing fails
    }
    
    return attributedText;
  }
}
