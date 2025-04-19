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
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDarkMode ? Colors.white : Colors.black;
    
    // Create a custom stylesheet that properly uses the copyWith method parameters
    final customStylesheet = defaultStylesheet.copyWith(
      // Use inlineTextStyler to handle text styling
      inlineTextStyler: (attributions, existingStyle) {
        // Start with text color based on theme mode
        var style = existingStyle.copyWith(
          color: textColor,
        );
        
        // Apply styling based on attributions
        for (final attribution in attributions) {
          if (attribution.id == 'bold') {
            style = style.copyWith(fontWeight: FontWeight.bold);
          } else if (attribution.id == 'italic') {
            style = style.copyWith(fontStyle: FontStyle.italic);
          } else if (attribution.id == 'underline') {
            style = style.copyWith(decoration: TextDecoration.underline);
          }
        }
        
        return style;
      },
      // Use addRulesBefore to add custom styling rules with the correct parameter types
      addRulesBefore: [
        StyleRule(
          const BlockSelector("header1"),
          (doc, node) => {
            'textStyle': TextStyle(
              fontSize: 24, 
              fontWeight: FontWeight.bold, 
              color: textColor,
              height: 1.5,
            ),
          },
        ),
        StyleRule(
          const BlockSelector("header2"),
          (doc, node) => {
            'textStyle': TextStyle(
              fontSize: 20, 
              fontWeight: FontWeight.bold, 
              color: textColor,
              height: 1.5,
            ),
          },
        ),
        StyleRule(
          const BlockSelector("header3"),
          (doc, node) => {
            'textStyle': TextStyle(
              fontSize: 18, 
              fontWeight: FontWeight.bold, 
              color: textColor,
              height: 1.5,
            ),
          },
        ),
        StyleRule(
          const BlockSelector("header"),
          (doc, node) => {
            'textStyle': TextStyle(
              fontSize: 16,
              color: textColor,
              height: 1.5,
            ),
          },
        ),
        // Add code block styling
        StyleRule(
          const BlockSelector("code"),
          (doc, node) => {
            'textStyle': TextStyle(
              fontFamily: 'monospace',
              fontSize: 14,
              color: textColor,
              height: 1.5,
            ),
            'padding': const EdgeInsets.all(16),
            'backgroundColor': isDarkMode ? Colors.grey[850] : Colors.grey[200],
          },
        ),
      ],
    );

    return OverlayPortal(
      controller: _popoverToolbarController,
      overlayChildBuilder: _buildPopoverToolbar,
      child: SuperEditor(
        key: ValueKey('editor-${widget.provider.blocks.length}'),
        editor: widget.provider.editor,
        focusNode: widget.provider.focusNode,
        stylesheet: customStylesheet,
        selectionLayerLinks: SelectionLayerLinks(),
        autofocus: true,
        inputSource: TextInputSource.keyboard,
        selectionStyle: SelectionStyles(
          selectionColor: Theme.of(context).primaryColor.withOpacity(0.3),
          highlightEmptyTextBlocks: true,
        ),
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
  
  // Apply formatting to selected text using SuperEditor's built-in commands
  void _applyFormatting(String format) {
    final editor = widget.provider.editor;
    final selection = widget.provider.composer.selection;
    
    // Exit if there's no selection or it's collapsed (cursor only)
    if (selection == null || selection.isCollapsed) return;
    
    // Create the appropriate attribution based on formatting type
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
    
    // Use the editor's command system to toggle the attribution
    // editor.execute(
    //   ToggleAttributionsRequest(
    //     documentSelection: selection,
    //     attributions: {attribution},
    //   ),
    // );
  }

  @override
  void dispose() {
    _logger.debug('Disposing rich text editor widget');
    widget.provider.removeListener(_handleProviderChange);
    widget.provider.composer.selectionNotifier.removeListener(_hideOrShowToolbar);
    super.dispose();
  }
}