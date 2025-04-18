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
  RichTextEditorState createState() => RichTextEditorState();
}

class RichTextEditorState extends State<RichTextEditor> {
  final Logger _logger = Logger('RichTextEditor');
  bool _editorReady = false;
  
  // Controls visibility of the toolbar
  final _popoverToolbarController = OverlayPortalController();

  @override
  void initState() {
    super.initState();
    _logger.debug('Initializing rich text editor widget');
    widget.provider.addListener(_handleProviderChange);
    
    // Listen for selection changes to show/hide toolbar
    widget.provider.composer.selectionNotifier.addListener(_hideOrShowToolbar);
    
    // Request focus after build is complete
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.provider.requestFocus();
      setState(() {
        _editorReady = true;
      });
    });
  }
  
  void _hideOrShowToolbar() {
    final selection = widget.provider.composer.selection;
    if (selection == null) {
      // Nothing is selected. We don't want to show a toolbar in this case.
      _popoverToolbarController.hide();
      return;
    }

    if (selection.isCollapsed) {
      // We only want to show the toolbar when a span of text
      // is selected. Therefore, we ignore collapsed selections.
      _popoverToolbarController.hide();
      return;
    }

    // We have an expanded selection. Show the toolbar.
    _popoverToolbarController.show();
  }
  
  @override
  void didUpdateWidget(RichTextEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    // If the provider changed, update listeners
    if (widget.provider != oldWidget.provider) {
      _logger.debug('Provider changed, updating listeners');
      oldWidget.provider.removeListener(_handleProviderChange);
      widget.provider.addListener(_handleProviderChange);
      
      // Update selection listener
      oldWidget.provider.composer.selectionNotifier.removeListener(_hideOrShowToolbar);
      widget.provider.composer.selectionNotifier.addListener(_hideOrShowToolbar);
    }
  }
  
  void _handleProviderChange() {
    if (mounted) {
      setState(() {});
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return OverlayPortal(
      controller: _popoverToolbarController,
      overlayChildBuilder: _buildPopoverToolbar,
      child: SuperEditor(
        key: ValueKey('editor-${widget.provider.blocks.length}'),
        editor: widget.provider.editor,
        focusNode: widget.provider.focusNode,
        stylesheet: defaultStylesheet,
        selectionLayerLinks: SelectionLayerLinks(),
        autofocus: true,
      ),
    );
  }
  
  Widget _buildPopoverToolbar(BuildContext context) {
    // Fixed position toolbar at the top of the screen
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Material(
        elevation: 4,
        color: Theme.of(context).primaryColor,
        child: Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              // Bold button
              IconButton(
                icon: const Icon(Icons.format_bold, color: Colors.white),
                onPressed: () => _applyFormatting('bold'),
              ),
              
              // Italic button
              IconButton(
                icon: const Icon(Icons.format_italic, color: Colors.white),
                onPressed: () => _applyFormatting('italic'),
              ),
              
              // Underline button
              IconButton(
                icon: const Icon(Icons.format_underline, color: Colors.white),
                onPressed: () => _applyFormatting('underline'),
              ),
              
              // Spacer to push optional buttons to the right
              const Spacer(),
              
              // Optional: Done button to hide toolbar
              TextButton(
                onPressed: () => _popoverToolbarController.hide(),
                child: const Text('Done', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  // Apply formatting to the selected text
  void _applyFormatting(String format) {
    Attribution attribution;
    switch (format) {
      case 'bold':
        attribution = const NamedAttribution('bold');
        break;
      case 'italic':
        attribution = const NamedAttribution('italic');
        break;
      case 'underline':
        attribution = const NamedAttribution('underline');
        break;
      default:
        return;
    }
    
    // Check if selection exists
    // if (widget.provider.composer.selection != null) {
    //   // Apply the formatting to selected text
    //   final documentSelection = widget.provider.composer.selection!;
      
    //   widget.provider.editor.execute(
    //     EditContent(
    //       (document, transaction) {
    //         // Find all spans of text with the given selection
    //         if (document is MutableDocument) {
    //           // Apply the attribution to the selected text
    //           transaction.formatText(
    //             documentSelection: documentSelection,
    //             attribution: attribution,
    //           );
    //         }
    //       },
    //     ),
    //   );
      
    //   // Make sure changes are committed to the backend
    //   widget.provider.commitAllContent();
    // }
  }
  
  @override
  void dispose() {
    _logger.debug('Disposing rich text editor widget');
    widget.provider.removeListener(_handleProviderChange);
    widget.provider.composer.selectionNotifier.removeListener(_hideOrShowToolbar);
    super.dispose();
  }
}
