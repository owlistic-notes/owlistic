import 'package:flutter/material.dart';
import 'package:super_editor/super_editor.dart' hide Logger;
import '../providers/rich_text_editor_provider.dart';
import '../utils/logger.dart';

/// Widget for displaying a full-page rich text editor
class RichTextEditor extends StatefulWidget {
  final RichTextEditorProvider provider;
  
  const RichTextEditor({
    Key? key,
    required this.provider,
  }) : super(key: key);
  
  @override
  _RichTextEditorState createState() => _RichTextEditorState();
}

class _RichTextEditorState extends State<RichTextEditor> {
  final Logger _logger = Logger('RichTextEditor');
  bool _editorReady = false;
  
  // Track document nodes to block mapping for selections
  final Map<DocumentNode, String> _nodeToBlockIdMap = {};
  
  @override
  void initState() {
    super.initState();
    _logger.debug('Initializing rich text editor widget');
    widget.provider.addListener(_handleProviderChange);
    
    // Build node-to-block mapping
    _updateNodeBlockMapping();
    
    // Request focus after build is complete
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.provider.requestFocus();
      setState(() {
        _editorReady = true;
      });
    });
  }
  
  void _updateNodeBlockMapping() {
    _nodeToBlockIdMap.clear();
    
    // Fixed the incorrect bracket placement and loop logic
    for (final node in widget.provider.document) {
      // Try to find a matching block ID in the provider's mapping
      String? blockId;
      
      // Look through the provider's node-to-block mapping
      final nodeToBlockMap = widget.provider.getNodeToBlockMapping();
      for (final entry in nodeToBlockMap.entries) {
        if (entry.key == node.id) {
          blockId = entry.value;
          break;
        }
      }
      
      if (blockId != null) {
        _nodeToBlockIdMap[node] = blockId;
      }
    }
  }
  
  @override
  void didUpdateWidget(RichTextEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    // If the provider changed, update listeners
    if (widget.provider != oldWidget.provider) {
      _logger.debug('Provider changed, updating listeners');
      oldWidget.provider.removeListener(_handleProviderChange);
      widget.provider.addListener(_handleProviderChange);
      
      // Update node mapping
      _updateNodeBlockMapping();
    }
  }
  
  @override
  void dispose() {
    _logger.debug('Disposing rich text editor widget');
    widget.provider.removeListener(_handleProviderChange);
    super.dispose();
  }
  
  void _handleProviderChange() {
    if (mounted) {
      _logger.debug('Provider updated, refreshing UI');
      // Update node-to-block mapping
      _updateNodeBlockMapping();
      setState(() {});
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: SuperEditor(
        key: ValueKey('editor-${widget.provider.blocks.length}'),
        editor: widget.provider.editor,
        focusNode: widget.provider.focusNode,
        stylesheet: defaultStylesheet,
        autofocus: true,
      ),
    );
  }
}
