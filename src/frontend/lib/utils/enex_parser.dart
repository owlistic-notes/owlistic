import 'dart:convert';
import 'package:xml/xml.dart';
import 'package:html/parser.dart' as html;
import 'package:html/dom.dart' as dom;
import 'package:super_editor/super_editor.dart' hide Logger;
import '../utils/logger.dart';

class EnexResource {
  final String id;
  final String data;
  final String mime;
  final String filename;
  final String? sourceUrl;
  final String encoding;
  
  EnexResource({
    required this.id, 
    required this.data,
    required this.mime,
    required this.filename,
    this.sourceUrl,
    required this.encoding
  });
}

class EnexNote {
  final String title;
  final String content;
  final DateTime createdTime;
  final DateTime updatedTime;
  final List<String> tags;
  final List<EnexResource> resources;
  bool isTodo = false;
  DateTime? todoDueDate;
  DateTime? todoCompletedDate;
  
  EnexNote({
    required this.title,
    required this.content,
    required this.createdTime,
    required this.updatedTime,
    required this.tags,
    required this.resources,
  });
}

class EnexParser {
  final Logger _logger = Logger('EnexParser');
  
  /// Parses an ENEX file and returns a list of EnexNote objects
  Future<List<EnexNote>> parseEnexFile(String xmlContent) async {
    final List<EnexNote> notes = [];
    
    try {
      final document = XmlDocument.parse(xmlContent);
      final noteElements = document.findAllElements('note');
      
      for (final noteElement in noteElements) {
        try {
          final title = _getElementText(noteElement, 'title') ?? 'Untitled';
          final contentElement = noteElement.getElement('content');
          final content = contentElement != null ? _extractCdata(contentElement) : '';
          
          // Parse timestamps
          DateTime createdTime = DateTime.now();
          DateTime updatedTime = DateTime.now();
          
          try {
            final createdStr = _getElementText(noteElement, 'created');
            if (createdStr != null) {
              createdTime = _parseEnexTimestamp(createdStr);
            }
          } catch (e) {
            _logger.error('Error parsing creation timestamp: $e');
          }
          
          try {
            final updatedStr = _getElementText(noteElement, 'updated');
            if (updatedStr != null) {
              updatedTime = _parseEnexTimestamp(updatedStr);
            } else {
              // If no updated timestamp, use created timestamp
              updatedTime = createdTime;
            }
          } catch (e) {
            _logger.error('Error parsing update timestamp: $e');
          }
          
          // Extract tags
          final tags = noteElement
              .findElements('tag')
              .map((e) => e.innerText.trim())
              .toList();
          
          // Extract resources
          final resources = <EnexResource>[];
          for (final resourceElement in noteElement.findElements('resource')) {
            try {
              final dataElement = resourceElement.getElement('data');
              final mimeElement = resourceElement.getElement('mime');
              
              if (dataElement != null && mimeElement != null) {
                String encoding = dataElement.getAttribute('encoding') ?? 'base64';
                final data = _extractCdata(dataElement);
                final mime = mimeElement.innerText.trim();
                
                // Get resource attributes
                final resourceAttributesElement = resourceElement.getElement('resource-attributes');
                String? filename;
                String? sourceUrl;
                
                if (resourceAttributesElement != null) {
                  final filenameElement = resourceAttributesElement.getElement('file-name');
                  if (filenameElement != null) {
                    filename = filenameElement.innerText.trim();
                  }
                  
                  final sourceUrlElement = resourceAttributesElement.getElement('source-url');
                  if (sourceUrlElement != null) {
                    sourceUrl = sourceUrlElement.innerText.trim();
                  }
                }
                
                // Extract recognition data for object ID
                String id = '';
                final recognitionElement = resourceElement.getElement('recognition');
                if (recognitionElement != null) {
                  final recognitionData = _extractCdata(recognitionElement);
                  id = _extractRecognitionObjectId(recognitionData);
                }
                
                resources.add(EnexResource(
                  id: id,
                  data: data,
                  mime: mime,
                  filename: filename ?? 'untitled',
                  sourceUrl: sourceUrl,
                  encoding: encoding
                ));
              }
            } catch (e) {
              _logger.error('Error parsing resource: $e');
            }
          }
          
          // Parse note attributes for todo status
          final note = EnexNote(
            title: title,
            content: content,
            createdTime: createdTime,
            updatedTime: updatedTime,
            tags: tags,
            resources: resources
          );
          
          final noteAttributesElement = noteElement.getElement('note-attributes');
          if (noteAttributesElement != null) {
            final reminderOrder = _getElementText(noteAttributesElement, 'reminder-order');
            if (reminderOrder != null && reminderOrder != '0') {
              note.isTodo = true;
              
              final reminderTime = _getElementText(noteAttributesElement, 'reminder-time');
              if (reminderTime != null) {
                try {
                  note.todoDueDate = _parseEnexTimestamp(reminderTime);
                } catch (e) {
                  _logger.error('Error parsing todo due date: $e');
                }
              }
              
              final reminderDoneTime = _getElementText(noteAttributesElement, 'reminder-done-time');
              if (reminderDoneTime != null) {
                try {
                  note.todoCompletedDate = _parseEnexTimestamp(reminderDoneTime);
                } catch (e) {
                  _logger.error('Error parsing todo completed date: $e');
                }
              }
            }
          }
          
          notes.add(note);
        } catch (e) {
          _logger.error('Error parsing note: $e');
        }
      }
    } catch (e) {
      _logger.error('Error parsing ENEX file: $e');
      throw Exception('Failed to parse ENEX file: ${e.toString()}');
    }
    
    return notes;
  }
  
  /// Converts an ENEX note to a SuperEditor document
  MutableDocument convertToDocument(EnexNote note) {
    // Convert HTML content to a Document structure
    return _htmlToDocument(note.content, note.resources);
  }
  
  /// Extracts CDATA content from an XML element
  String _extractCdata(XmlElement element) {
    final cdataNodes = element.children.whereType<XmlCDATA>();
    if (cdataNodes.isNotEmpty) {
      return cdataNodes.first.text;
    }
    return element.innerText;
  }
  
  /// Extracts object ID from recognition XML
  String _extractRecognitionObjectId(String recognitionXml) {
    final regex = RegExp(r'objID="(.*?)"');
    final match = regex.firstMatch(recognitionXml);
    return match != null ? match.group(1) ?? '' : '';
  }
  
  /// Gets the text content of a child element
  String? _getElementText(XmlElement parent, String childName) {
    final element = parent.getElement(childName);
    return element?.innerText.trim();
  }
  
  /// Parses Evernote timestamp format
  DateTime _parseEnexTimestamp(String timestamp) {
    // Try standard format: YYYYMMDDTHHmmssZ
    try {
      final year = int.parse(timestamp.substring(0, 4));
      final month = int.parse(timestamp.substring(4, 6));
      final day = int.parse(timestamp.substring(6, 8));
      
      if (timestamp.length > 9) {
        final hour = int.parse(timestamp.substring(9, 11));
        final minute = int.parse(timestamp.substring(11, 13));
        final second = int.parse(timestamp.substring(13, 15));
        return DateTime.utc(year, month, day, hour, minute, second);
      }
      
      return DateTime.utc(year, month, day);
    } catch (e) {
      // Fallback: try parsing directly
      try {
        return DateTime.parse(timestamp);
      } catch (e) {
        return DateTime.now();
      }
    }
  }
  
  /// Processes a single resource and decodes its data
  Future<Map<String, dynamic>> processResource(EnexResource resource) async {
    if (resource.encoding.toLowerCase() == 'base64') {
      try {
        return {
          'id': resource.id,
          'data': base64.decode(resource.data),
          'mime': resource.mime,
          'filename': resource.filename,
        };
      } catch (e) {
        _logger.error('Error decoding resource data: $e');
      }
    }
    
    return {
      'id': resource.id,
      'data': const Utf8Encoder().convert(resource.data),
      'mime': resource.mime,
      'filename': resource.filename,
    };
  }

  /// Converts HTML content to a Document structure
  MutableDocument _htmlToDocument(String htmlContent, List<EnexResource> resources) {
    final document = html.parse(htmlContent);
    final nodes = <DocumentNode>[];
    
    // Process body content
    _processHtmlNode(document, nodes, resources);
    
    // If no nodes were created, add an empty paragraph
    if (nodes.isEmpty) {
      nodes.add(ParagraphNode(
        id: Editor.createNodeId(),
        text: AttributedText(),
      ));
    }
    
    return MutableDocument(nodes: nodes);
  }
  
  void _processHtmlNode(dom.Node node, List<DocumentNode> nodes, List<EnexResource> resources) {
    if (node is dom.Text) {
      final text = node.text.trim();
      if (text.isNotEmpty && nodes.isNotEmpty && nodes.last is ParagraphNode) {
        final paragraph = nodes.last as ParagraphNode;
        final newText = AttributedText(paragraph.text.text + node.text);
        nodes[nodes.length - 1] = ParagraphNode(
          id: paragraph.id,
          text: newText,
        );
      } else if (text.isNotEmpty) {
        nodes.add(ParagraphNode(
          id: Editor.createNodeId(),
          text: AttributedText(text),
        ));
      }
      return;
    }
    
    if (node is! dom.Element) return;
    
    // Process based on tag name
    switch (node.localName?.toLowerCase()) {
      case 'div':
      case 'p':
        final textContent = _extractTextWithFormatting(node);
        if (textContent.text.isNotEmpty) {
          nodes.add(ParagraphNode(
            id: Editor.createNodeId(),
            text: textContent,
          ));
        }
        break;
        
      case 'h1':
      case 'h2':
      case 'h3':
      case 'h4':
      case 'h5':
      case 'h6':
        final level = int.parse(node.localName!.substring(1));
        final textContent = _extractTextWithFormatting(node);
        if (textContent.text.isNotEmpty) {
          final headingNode = ParagraphNode(
            id: Editor.createNodeId(),
            text: textContent,
            metadata: {
              'blockType': NamedAttribution('heading$level'),
            },
          );
          nodes.add(headingNode);
        }
        break;
        
      case 'ul':
      case 'ol':
        for (final child in node.children) {
          if (child.localName == 'li') {
            final textContent = _extractTextWithFormatting(child);
            if (textContent.text.isNotEmpty) {
              nodes.add(ListItemNode(
                id: Editor.createNodeId(),
                text: textContent,
                itemType: node.localName == 'ol' ? ListItemType.ordered : ListItemType.unordered,
              ));
            }
          }
        }
        break;
        
      case 'input':
        // Check if this is a checkbox
        final type = node.attributes['type']?.toLowerCase();
        final checked = node.attributes['checked'] != null;
        
        if (type == 'checkbox') {
          // Find the parent or next sibling for the label
          String taskText = '';
          if (node.parent != null) {
            taskText = node.parent!.text.trim();
          }
          
          if (taskText.isNotEmpty) {
            nodes.add(TaskNode(
              id: Editor.createNodeId(),
              text: AttributedText(taskText),
              isComplete: checked,
            ));
          }
        }
        break;
        
      case 'en-todo':
        // Evernote specific todo item
        final checked = node.attributes['checked']?.toLowerCase() == 'true';
        String taskText = '';
        
        // Get the task text from the parent or next sibling
        if (node.parent != null) {
          taskText = node.parent!.text.replaceFirst(node.outerHtml, '').trim();
        }
        
        if (taskText.isNotEmpty) {
          nodes.add(TaskNode(
            id: Editor.createNodeId(),
            text: AttributedText(taskText),
            isComplete: checked,
          ));
        }
        break;
        
      case 'img':
        // Process image
        final src = node.attributes['src'];
        if (src != null) {
          // Check if this is a resource reference
          if (src.startsWith('data:') || _isResourceHash(src, resources)) {
            final resource = _findResourceBySrc(src, resources);
            if (resource != null) {
              nodes.add(ImageNode(
                id: Editor.createNodeId(),
                imageUrl: resource.id,
                altText: node.attributes['alt'] ?? '',
              ));
            } else {
              nodes.add(ImageNode(
                id: Editor.createNodeId(),
                imageUrl: src,
                altText: node.attributes['alt'] ?? '',
              ));
            }
          } else {
            // External image
            nodes.add(ImageNode(
              id: Editor.createNodeId(),
              imageUrl: src,
              altText: node.attributes['alt'] ?? '',
            ));
          }
        }
        break;
        
      case 'hr':
        nodes.add(HorizontalRuleNode(
          id: Editor.createNodeId(),
        ));
        break;
        
      case 'pre':
      case 'code':
        final codeContent = node.text.trim();
        if (codeContent.isNotEmpty) {
          final paragraphNode = ParagraphNode(
            id: Editor.createNodeId(),
            text: AttributedText(codeContent),
            metadata: {
              'blockType': NamedAttribution('code'),
            },
          );
          nodes.add(paragraphNode);
        }
        break;
        
      case 'en-media':
        // Process Evernote media
        final hash = node.attributes['hash'];
        final type = node.attributes['type'];
        
        if (hash != null) {
          final resource = _findResourceByHash(hash, resources);
          if (resource != null) {
            if (type != null && type.startsWith('image/')) {
              nodes.add(ImageNode(
                id: Editor.createNodeId(),
                imageUrl: resource.id,
                altText: '',
              ));
            } else {
              // For non-image media, create a link or reference
              nodes.add(ParagraphNode(
                id: Editor.createNodeId(),
                text: AttributedText('Attachment: ${resource.filename}'),
              ));
            }
          }
        }
        break;
        
      default:
        // Process children recursively for unsupported elements
        for (final child in node.nodes) {
          _processHtmlNode(child, nodes, resources);
        }
        break;
    }
  }
  
  AttributedText _extractTextWithFormatting(dom.Element element) {
    final buffer = StringBuffer();
    final spans = <SpanMarker>[];
    
    int extractFromNode(dom.Node node, int offset, {Map<String, dynamic>? styles}) {
      if (node is dom.Text) {
        final text = node.text;
        buffer.write(text);
        
        if (styles != null && styles.isNotEmpty && text.isNotEmpty) {
          final start = offset;
          final end = offset + text.length;
          
          if (styles['bold'] == true) {
            spans.add(SpanMarker(start, end, 'bold'));
          }
          if (styles['italic'] == true) {
            spans.add(SpanMarker(start, end, 'italic'));
          }
          if (styles['underline'] == true) {
            spans.add(SpanMarker(start, end, 'underline'));
          }
          if (styles['strikethrough'] == true) {
            spans.add(SpanMarker(start, end, 'strikethrough'));
          }
          if (styles['link'] != null) {
            spans.add(SpanMarker(start, end, 'link', styles['link']));
          }
        }
        
        return text.length;
      } else if (node is dom.Element) {
        final nodeStyles = {...?styles};
        
        // Update styles based on element
        switch (node.localName?.toLowerCase()) {
          case 'b':
          case 'strong':
            nodeStyles['bold'] = true;
            break;
          case 'i':
          case 'em':
            nodeStyles['italic'] = true;
            break;
          case 'u':
            nodeStyles['underline'] = true;
            break;
          case 's':
          case 'strike':
          case 'del':
            nodeStyles['strikethrough'] = true;
            break;
          case 'a':
            final href = node.attributes['href'];
            if (href != null && href.isNotEmpty) {
              nodeStyles['link'] = href;
            }
            break;
        }
        
        int addedLength = 0;
        
        for (final child in node.nodes) {
          addedLength += extractFromNode(child, offset + addedLength, styles: nodeStyles);
        }
        
        return addedLength;
      }
      
      return 0;
    }
    
    extractFromNode(element, 0);
    
    // Now create the attributed text with the spans
    final text = buffer.toString();
    final attributedText = AttributedText(text);
    
    // Apply the spans
    for (final span in spans) {
      switch (span.type) {
        case 'bold':
          attributedText.addAttribution(
            const NamedAttribution('bold'),
            SpanRange(span.start, span.end),
          );
          break;
        case 'italic':
          attributedText.addAttribution(
            const NamedAttribution('italic'),
            SpanRange(span.start, span.end),
          );
          break;
        case 'underline':
          attributedText.addAttribution(
            const NamedAttribution('underline'),
            SpanRange(span.start, span.end),
          );
          break;
        case 'strikethrough':
          attributedText.addAttribution(
            const NamedAttribution('strikethrough'),
            SpanRange(span.start, span.end),
          );
          break;
        case 'link':
          attributedText.addAttribution(
            const NamedAttribution('link'),
            SpanRange(span.start, span.end),
          );
          break;
      }
    }
    
    return attributedText;
  }
  
  bool _isResourceHash(String src, List<EnexResource> resources) {
    // Check if src matches a resource hash pattern
    return src.startsWith('hash:') || resources.any((r) => r.id == src);
  }
  
  EnexResource? _findResourceBySrc(String src, List<EnexResource> resources) {
    // Try to find a resource that matches the src
    if (src.startsWith('hash:')) {
      final hash = src.substring(5);
      return resources.firstWhere(
        (r) => r.id == hash,
        orElse: () => null as EnexResource,
      );
    }
    
    return resources.firstWhere(
      (r) => r.id == src,
      orElse: () => null as EnexResource,
    );
  }
  
  EnexResource? _findResourceByHash(String hash, List<EnexResource> resources) {
    return resources.firstWhere(
      (r) => r.id == hash,
      orElse: () => null as EnexResource,
    );
  }
}

// Helper class to track text spans
class SpanMarker {
  final int start;
  final int end;
  final String type; // 'bold', 'italic', 'underline', 'link', etc.
  final dynamic data; // For links, etc.
  
  SpanMarker(this.start, this.end, this.type, [this.data]);
}

/// Deserializes an ENEX file into a SuperEditor document
Future<MutableDocument> deserializeEnexToDocument(String enexContent) async {
  final parser = EnexParser();
  final notes = await parser.parseEnexFile(enexContent);
  
  if (notes.isEmpty) {
    // Return an empty document if no notes were found
    return MutableDocument(nodes: [
      ParagraphNode(
        id: Editor.createNodeId(),
        text: AttributedText(),
      ),
    ]);
  }
  
  // For simplicity, we'll just convert the first note
  // You could extend this to handle multiple notes if needed
  return parser.convertToDocument(notes.first);
}