import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/note.dart';
import '../models/block.dart';
import '../providers/notes_provider.dart';
import '../providers/block_provider.dart';
import '../providers/websocket_provider.dart';

class NoteEditorScreen extends StatefulWidget {
  final Note note;
  const NoteEditorScreen({Key? key, required this.note}) : super(key: key);

  @override
  _NoteEditorScreenState createState() => _NoteEditorScreenState();
}

class _NoteEditorScreenState extends State<NoteEditorScreen> {
  late TextEditingController _titleController;
  bool _isLoading = true;
  List<TextEditingController> _blockControllers = [];
  List<Block> _blocks = [];
  bool _ignoreBlockUpdates = false;
  bool _initialized = false;
  
  // Store provider references to use safely in dispose
  late WebSocketProvider _webSocketProvider;
  late NotesProvider _notesProvider;
  late BlockProvider _blockProvider;
  
  // Counter to force rebuilds when block content changes
  int _updateCounter = 0;
  
  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.note.title);
    
    // Use a Timer instead of microtask to avoid potential issues with setState during build
    Timer(Duration.zero, () {
      _initializeProviders();
    });
  }
  
  void _initializeProviders() {
    if (_initialized) return;
    _initialized = true;
    
    // Store provider references directly
    _notesProvider = Provider.of<NotesProvider>(context, listen: false);
    _blockProvider = Provider.of<BlockProvider>(context, listen: false);
    _webSocketProvider = Provider.of<WebSocketProvider>(context, listen: false);
    
    // Ensure WebSocket is connected
    _webSocketProvider.ensureConnected().then((_) {
      // Activate the note
      _notesProvider.activateNote(widget.note.id);
      _blockProvider.activateNote(widget.note.id);
      
      // Subscribe to WebSocket with multiple resource types
      _webSocketProvider.subscribe('note', id: widget.note.id);
      
      // Also subscribe to all blocks for this note
      _webSocketProvider.subscribe('block', id: null);
      
      // Add listener for block updates after connections are established
      _blockProvider.addListener(_onBlockProviderUpdate);
      
      print('NoteEditor: Subscribed to note ${widget.note.id} and its blocks');
    });
    
    // Fetch blocks regardless of WebSocket status
    _fetchBlocks();
    
    print('NoteEditor: Initialized providers for note ${widget.note.id}');
  }

  // Fetch blocks for this note
  Future<void> _fetchBlocks() async {
    setState(() => _isLoading = true);
    
    try {
      final blockProvider = Provider.of<BlockProvider>(context, listen: false);
      await blockProvider.fetchBlocksForNote(widget.note.id);
      
      // After fetching, get blocks from provider and sort by order
      _updateBlocksFromProvider();
      
      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      print('NoteEditor: Error fetching blocks: $e');
      setState(() => _isLoading = false);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load note blocks')),
        );
      }
    }
  }

  // Update blocks from provider
  void _updateBlocksFromProvider() {
    if (_ignoreBlockUpdates) {
      print('NoteEditor: Ignoring block updates due to local edit');
      return;
    }
    
    final blockProvider = Provider.of<BlockProvider>(context, listen: false);
    final blocks = blockProvider.getBlocksForNote(widget.note.id);
    
    print('NoteEditor: Updating with ${blocks.length} blocks from provider');
    
    // Save cursor positions and selections for existing controllers
    final Map<String, TextEditingValue> controllerValues = {};
    for (int i = 0; i < _blocks.length && i < _blockControllers.length; i++) {
      controllerValues[_blocks[i].id] = _blockControllers[i].value;
    }
    
    // Dispose existing controllers
    for (var controller in _blockControllers) {
      controller.dispose();
    }
    
    // Create new controllers
    _blockControllers = [];
    for (var block in blocks) {
      final controller = TextEditingController(text: block.content);
      
      // Restore cursor position/selection if this block existed before
      if (controllerValues.containsKey(block.id)) {
        final oldValue = controllerValues[block.id]!;
        
        // Only restore selection if the text hasn't changed
        if (oldValue.text == block.content) {
          controller.value = oldValue;
        }
      }
      
      _blockControllers.add(controller);
    }
    
    _blocks = blocks;
    _updateCounter++;
    
    if (mounted) {
      setState(() {});
    }
  }

  // Callback for block provider updates
  void _onBlockProviderUpdate() {
    if (!mounted) return;
    
    final blockProvider = Provider.of<BlockProvider>(context, listen: false);
    
    // Only update if this note is still active
    if (_blocks.isNotEmpty && 
        blockProvider.getBlocksForNote(widget.note.id).isNotEmpty) {
      print('NoteEditor: Block provider updated, refreshing blocks');
      _updateBlocksFromProvider();
    }
  }

  // Save note title
  void _saveTitle() {
    if (_titleController.text != widget.note.title) {
      Provider.of<NotesProvider>(context, listen: false)
          .updateNote(widget.note.id, _titleController.text);
    }
  }

  // Update a block with debounced saving
  void _updateBlock(int index) {
    final block = _blocks[index];
    final content = _blockControllers[index].text;
    
    if (content != block.content) {
      print('NoteEditor: Updating block ${block.id}');
      // Use the updateBlockContent method with debouncing
      Provider.of<BlockProvider>(context, listen: false)
          .updateBlockContent(block.id, content);
    }
  }

  // For saving on blur or explicit save request
  void _saveBlockImmediate(int index) {
    final block = _blocks[index];
    final content = _blockControllers[index].text;
    
    if (content != block.content) {
      print('NoteEditor: Saving block ${block.id} immediately');
      // Force immediate save
      Provider.of<BlockProvider>(context, listen: false)
          .updateBlockContent(block.id, content, immediate: true);
    }
  }

  // Add a new block
  Future<void> _addBlock() async {
    try {
      final blockProvider = Provider.of<BlockProvider>(context, listen: false);
      
      // Calculate the highest order value
      int newOrder = 0;
      if (_blocks.isNotEmpty) {
        newOrder = _blocks.map((b) => b.order).reduce((a, b) => a > b ? a : b) + 1;
      }
      
      // Create the new block
      final newBlock = await blockProvider.createBlock(
        widget.note.id,
        '',
        'text',
        newOrder,
      );
      
      // Add the block to local state
      setState(() {
        _blocks.add(newBlock);
        _blockControllers.add(TextEditingController(text: ''));
      });
      
      // Focus on the new block
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_blockControllers.isNotEmpty) {
          final controller = _blockControllers.last;
          controller.selection = TextSelection.fromPosition(TextPosition(offset: 0));
          FocusScope.of(context).requestFocus(FocusNode());
        }
      });
    } catch (e) {
      print('NoteEditor: Error adding block: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to add block')),
        );
      }
    }
  }

  // Delete a block
  Future<void> _deleteBlock(int index) async {
    try {
      final blockProvider = Provider.of<BlockProvider>(context, listen: false);
      final blockId = _blocks[index].id;
      
      await blockProvider.deleteBlock(blockId);
      _updateBlocksFromProvider();
    } catch (e) {
      print('NoteEditor: Error deleting block: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete block')),
        );
      }
    }
  }

  @override
  void dispose() {
    // Safely unsubscribe and clean up using stored provider references
    if (_initialized) {
      try {
        // Deactivate note in providers
        _notesProvider.deactivateNote(widget.note.id);
        _blockProvider.deactivateNote(widget.note.id);
        
        // Unsubscribe using stored provider reference
        _webSocketProvider.unsubscribe('note', id: widget.note.id);
        
        // Remove listener using stored provider reference
        _blockProvider.removeListener(_onBlockProviderUpdate);
      } catch (e) {
        print('Error during NoteEditor disposal: $e');
      }
    }
    
    // Dispose controllers
    _titleController.dispose();
    for (var controller in _blockControllers) {
      controller.dispose();
    }
    
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Monitor the WebSocket provider for any updates
    final wsProvider = Provider.of<WebSocketProvider>(context);
    final blockProvider = Provider.of<BlockProvider>(context);
    
    // Debug print
    print('Note editor rebuilding. Last event: ${wsProvider.lastEventType}:${wsProvider.lastEventAction} at ${wsProvider.lastEventTime?.toString() ?? "never"}');
    
    return Scaffold(
      appBar: AppBar(
        title: Text('Edit Note'),
        actions: [
          IconButton(
            icon: Icon(Icons.add),
            onPressed: _addBlock,
            tooltip: 'Add Block',
          ),
          IconButton(
            icon: Icon(Icons.save),
            onPressed: () {
              _saveTitle();
              Navigator.pop(context);
            },
            tooltip: 'Save Note',
          ),
        ],
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title field
                  TextField(
                    controller: _titleController,
                    decoration: InputDecoration(
                      labelText: 'Title',
                      border: OutlineInputBorder(),
                    ),
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                    onChanged: (_) => _saveTitle(),
                  ),
                  SizedBox(height: 24),
                  
                  // Blocks
                  if (_blocks.isEmpty)
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24.0),
                        child: Text(
                          'This note is empty. Add a block to start writing.',
                          style: TextStyle(color: Colors.grey),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  
                  ..._blocks.asMap().entries.map((entry) {
                    final index = entry.key;
                    final block = entry.value;
                    
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 16.0),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _blockControllers[index],
                              decoration: InputDecoration(
                                border: OutlineInputBorder(),
                                hintText: 'Write something...',
                              ),
                              maxLines: null,
                              minLines: 3,
                              onChanged: (_) => _updateBlock(index),
                              onEditingComplete: () => _saveBlockImmediate(index),
                              onSubmitted: (_) => _saveBlockImmediate(index),
                            ),
                          ),
                          IconButton(
                            icon: Icon(Icons.delete, color: Colors.red),
                            onPressed: () => _deleteBlock(index),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                  
                  // Add block button
                  Center(
                    child: TextButton.icon(
                      icon: Icon(Icons.add),
                      label: Text('Add Block'),
                      onPressed: _addBlock,
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
