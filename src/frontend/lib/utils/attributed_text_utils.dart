import 'package:super_editor/super_editor.dart' hide Logger;
import 'package:owlistic/utils/logger.dart';

/// Class that handles mapping between Blocks and SuperEditor DocumentNodes
class AttributedTextUtils {
  // Add logger instance
  final Logger _logger = Logger('AttributedTextUtils');

  // Helper method to determine node's block type
  String detectBlockTypeFromNode(DocumentNode node) {
    if (node is ParagraphNode) {
      return node.metadata['blockType'].id;
    }
    else if (node is TaskNode) {
      return 'task';
    } else if (node is ListItemNode) {
      return 'listItem';
    } else if (node is HorizontalRuleNode) {
      return 'horizontalRule';
    }
    return 'paragraph';
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
      const NamedAttribution('italics'),
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
          while (
            end < text.length && 
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
  AttributedText createAttributedTextFromContent(String text, Map<String, dynamic> content) {
    // Safety check for empty text
    if (text.isEmpty) {
      return AttributedText('');
    }
    
    final attributedText = AttributedText(text);
    
    try {
      // Process spans if available
      List? spans;
      
      // Always check metadata first for spans
      if (content.containsKey('metadata') && content['metadata'] is Map) {
        final metadata = content['metadata'] as Map;
        if (metadata.containsKey('spans')) {
          spans = metadata['spans'] as List?;
        }
      }
    
      // Process spans if found
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
                  case 'italics':
                  case 'underline':
                  case 'strikethrough':
                    attributedText.addAttribution(
                      NamedAttribution(type), 
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
