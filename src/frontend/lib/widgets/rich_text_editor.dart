import 'package:flutter/material.dart';
import 'package:super_editor/super_editor.dart' hide Logger;
import '../providers/rich_text_editor_provider.dart';
import '../utils/logger.dart';

/// Widget for displaying a full-page rich text editor
class RichTextEditor extends StatelessWidget {
  final RichTextEditorProvider provider;
  final ScrollController? scrollController;
  final Logger _logger = Logger('RichTextEditor');
  
  RichTextEditor({
    Key? key, 
    required this.provider,
    this.scrollController,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    _logger.debug('Building RichTextEditor widget');
    
    return SuperEditor(
      editor: provider.editor,
      focusNode: provider.focusNode,
      scrollController: scrollController,
    );
  }
}