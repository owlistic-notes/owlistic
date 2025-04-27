import 'package:flutter/material.dart';
import 'package:super_editor/super_editor.dart' hide Logger;
import '../providers/rich_text_editor_provider.dart';
import '../utils/logger.dart';
import 'dart:async';

/// Widget for displaying a full-page rich text editor
class RichTextEditor extends StatefulWidget {
  final RichTextEditorProvider provider;
  final ScrollController? scrollController;
  final DocumentGestureMode? gestureMode;
  
  const RichTextEditor({
    Key? key, 
    required this.provider,
    this.scrollController,
    this.gestureMode,
  }) : super(key: key);
  
  @override
  State<RichTextEditor> createState() => _RichTextEditorState();
}

class _RichTextEditorState extends State<RichTextEditor> {
  final Logger _logger = Logger('RichTextEditor');
  late RichTextEditorProvider _provider;
  bool _isDisposed = false;
  Timer? _debounceTimer;
  
  @override
  void initState() {
    super.initState();
    _provider = widget.provider;
    // Use a microtask to ensure listener is added after build completes
    Future.microtask(() {
      if (!_isDisposed) {
        _provider.addListener(_handleProviderUpdate);
        _logger.debug('RichTextEditor initialized and listener added');
      }
    });
  }
  
  @override
  void didUpdateWidget(RichTextEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.provider != widget.provider) {
      oldWidget.provider.removeListener(_handleProviderUpdate);
      _provider = widget.provider;
      
      // Add listener in microtask to avoid potential issues during build
      Future.microtask(() {
        if (!_isDisposed) {
          _provider.addListener(_handleProviderUpdate);
          _logger.debug('RichTextEditor provider changed');
        }
      });
    }
  }
  
  @override
  void dispose() {
    _logger.debug('Disposing RichTextEditor');
    _isDisposed = true;
    
    // Cancel debounce timer if active
    _debounceTimer?.cancel();
    
    // Remove listener safely
    _provider.removeListener(_handleProviderUpdate);
    
    super.dispose();
  }
  
  void _handleProviderUpdate() {
    // Use the flag instead of mounted to be extra safe
    if (_isDisposed) {
      _logger.warning('Provider update received after widget was marked as disposed - ignoring');
      return;
    }
    
    // Debounce frequent updates to prevent UI freezes
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 100), () {
      if (!_isDisposed && mounted) {
        _logger.debug('Provider update processed (debounced)');
        // Let the UI update naturally without setState
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    _logger.debug('Building RichTextEditor widget');
    
    try {
      return SuperEditor(
        editor: _provider.editor,
        focusNode: _provider.focusNode,
        scrollController: widget.scrollController,
        gestureMode: widget.gestureMode,
      );
    } catch (e, stackTrace) {
      _logger.error('Error building SuperEditor: $e');
      _logger.debug('Stack trace: $stackTrace');
      
      // Return a fallback widget instead of crashing
      return Center(
        child: Text('Editor error: ${e.toString()}', 
          style: TextStyle(color: Theme.of(context).colorScheme.error)),
      );
    }
  }
}