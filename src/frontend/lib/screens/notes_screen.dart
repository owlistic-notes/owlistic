import 'package:flutter/material.dart';
import 'package:owlistic/models/notebook.dart';
import 'package:owlistic/utils/data_converter.dart';
import 'dart:async';
import 'dart:io';
import 'package:provider/provider.dart';
import 'package:owlistic/widgets/app_drawer.dart';
import 'package:owlistic/widgets/card_container.dart';
import 'package:owlistic/widgets/empty_state.dart';
import 'package:owlistic/models/note.dart';
import 'package:owlistic/viewmodel/notes_viewmodel.dart';
import 'package:owlistic/utils/logger.dart';
import 'package:owlistic/core/theme.dart';
import 'note_editor_screen.dart';
import 'package:owlistic/widgets/app_bar_common.dart';
import 'package:owlistic/widgets/theme_switcher.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class NotesScreen extends StatefulWidget {
  const NotesScreen({super.key});

  @override
  _NotesScreenState createState() => _NotesScreenState();
}

class _NotesScreenState extends State<NotesScreen> {
  final Logger _logger = Logger('NotesScreen');
  final ScrollController _scrollController = ScrollController();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  bool _isInitialized = false;
  final bool _isLoadingMore = false;
  final Set<String> _loadedNoteIds = {};

  // ViewModels
  late NotesViewModel _notesViewModel;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    if (!_isInitialized) {
      _isInitialized = true;

      // Get ViewModel
      _notesViewModel = context.read<NotesViewModel>();

      // Initialize data
      _initializeData();
    }
  }

  Future<void> _initializeData() async {
    try {
      _notesViewModel.activate();
      await _notesViewModel.fetchNotes();
    } catch (e) {
      _logger.error('Error initializing NotesScreen', e);
    }
  }

  Future<void> _refreshNotes() async {
    _logger.info('Refreshing notes data');
    try {
      await _notesViewModel.fetchNotes();
    } catch (e) {
      _logger.error('Error refreshing notes', e);
    }
  }

  void _showAddNoteDialog(BuildContext context) {
    final titleController = TextEditingController();
    String? selectedNotebookId;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.note_add_outlined,
                color: Theme.of(context).primaryColor),
            const SizedBox(width: 8),
            const Text('Add Note'),
          ],
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Replace Consumer with proper extension usage
            Builder(
              builder: (context) {
                final notebooks = _notesViewModel.notebooks;
                // If no notebooks, show message
                if (notebooks.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8.0),
                    child: Text(
                      'You need to create a notebook first',
                      style: TextStyle(color: AppTheme.dangerColor),
                    ),
                  );
                }

                // Set the initial value if not set
                if (selectedNotebookId == null && notebooks.isNotEmpty) {
                  selectedNotebookId = notebooks.first.id;
                }

                return DropdownButtonFormField<String>(
                  decoration: const InputDecoration(
                    labelText: 'Notebook',
                    prefixIcon: Icon(Icons.folder_outlined),
                  ),
                  value: selectedNotebookId,
                  isExpanded: true,
                  items: notebooks.map((notebook) {
                    return DropdownMenuItem<String>(
                      value: notebook.id,
                      child: Text(
                        notebook.name,
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  }).toList(),
                  onChanged: (value) {
                    selectedNotebookId = value;
                  },
                );
              }
            ),
            const SizedBox(height: 16),
            TextField(
              controller: titleController,
              decoration: const InputDecoration(
                labelText: 'Title',
                prefixIcon: Icon(Icons.title),
              ),
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (titleController.text.isNotEmpty &&
                  selectedNotebookId != null) {
                try {
                  _logger.info('Creating note: ${titleController.text} in notebook: $selectedNotebookId');
                  
                  await _notesViewModel.addNoteToNotebook(
                    selectedNotebookId!,
                    titleController.text,
                  );
                  
                  Navigator.of(ctx).pop();
                  
                  // Display success message
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Note "${titleController.text}" created successfully')),
                  );
                  
                  // Note: WebSocket event will handle UI update
                } catch (error) {
                  _logger.error('Failed to create note: $error');
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Failed to create note')),
                  );
                }
              } else {
                // Show error if no notebook is selected
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content:
                          Text('Please select a notebook and enter a title')),
                );
              }
            },
            style: AppTheme.getSuccessButtonStyle(),
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  void _navigateToNoteEditor(Note note) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => NoteEditorScreen(note: note),
      ),
    );
  }

  void _showDeleteConfirmation(
      BuildContext context, String noteId, String noteTitle) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Note'),
        content: Text('Are you sure you want to delete "$noteTitle"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              try {
                _logger.info('Deleting note: $noteId');
                
                // First remove from UI for immediate feedback
                _notesViewModel.handleNoteDeleted(noteId);
                
                // Then delete from server
                await _notesViewModel.deleteNote(noteId);
                
                // Update tracking set
                setState(() {
                  _loadedNoteIds.remove(noteId);
                });

                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Note deleted successfully')),
                );
              } catch (error) {
                _logger.error('Failed to delete note: $error');
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Failed to delete note')),
                );
              }
            },
            style: AppTheme.getDangerButtonStyle(),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(NotesViewModel notesViewModel) {
    if (notesViewModel.isLoading && notesViewModel.notes.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    
    // Get all notes, remove the notebook filtering
    List<Note> notesToDisplay = notesViewModel.notes;

    if (notesToDisplay.isEmpty) {
      return EmptyState(
        title: 'No notes found',
        message: 'Create your first note to get started',
        icon: Icons.note_add_outlined,
        onAction: () => _showAddNoteDialog(context),
        actionLabel: 'Create Note',
      );
    }

    return RefreshIndicator(
      onRefresh: _refreshNotes,
      color: Theme.of(context).primaryColor,
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemCount: notesToDisplay.length + (_isLoadingMore ? 1 : 0),
        itemBuilder: (context, index) {
          // Show loading indicator at the end
          if (index == notesToDisplay.length) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(8.0),
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            );
          }

          final note = notesToDisplay[index];
          // Get notebook name
          final notebookName = _notesViewModel.notebooks
            .firstWhere((nb) => nb.id == note.notebookId)
            .name;
          final lastEdited = note.updatedAt ?? note.createdAt;
          
          return CardContainer(
            key: ValueKey('note_${note.id}'),
            onTap: () => _navigateToNoteEditor(note),
            leading: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: Theme.of(context).primaryColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.description_outlined,
                color: Theme.of(context).primaryColor,
              ),
            ),
            title: note.title,
            subtitle: '$notebookName · ${DataConverter.formatDate(lastEdited)}',
            trailing: PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              onSelected: (value) {
                if (value == 'delete') {
                  _showDeleteConfirmation(
                    context,
                    note.id,
                    note.title,
                  );
                } else if (value == 'move') {
                  _showMoveNoteDialog(context, note);
                }
              },
              itemBuilder: (BuildContext context) => [
                const PopupMenuItem<String>(
                  value: 'move',
                  child: ListTile(
                    leading: Icon(Icons.drive_file_move),
                    title: Text('Move'),
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
                const PopupMenuItem<String>(
                  value: 'delete',
                  child: ListTile(
                    leading: Icon(Icons.delete_outline, color: Colors.red),
                    title: Text('Delete', style: TextStyle(color: Colors.red)),
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
            ),
            child: note.blocks.isEmpty
                ? const Text('Empty note',
                    style: TextStyle(fontStyle: FontStyle.italic))
                : Text(
                    note.blocks.isNotEmpty
                        ? note.blocks.first.getTextContent()
                        : '',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
          );
        },
      ),
    );
  }

  // Show dialog to move note to another notebook - Add this method
  void _showMoveNoteDialog(BuildContext context, Note note) {
    String? selectedNotebookId;
    
    // Get list of notebooks excluding current one
    final notebooks = _notesViewModel.notebooks
          .where((nb) => nb.id != note.notebookId)
          .toList();

    if (notebooks.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No other notebooks available to move to'))
      );
      return;
    }
    
    // Default to first notebook
    selectedNotebookId = notebooks.first.id;
    
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Move Note'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Select a notebook to move "${note.title}" to:'),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              decoration: const InputDecoration(
                labelText: 'Destination Notebook',
                prefixIcon: Icon(Icons.book),
              ),
              value: selectedNotebookId,
              items: notebooks.map((notebook) {
                return DropdownMenuItem<String>(
                  value: notebook.id,
                  child: Text(notebook.name),
                );
              }).toList(),
              onChanged: (value) {
                selectedNotebookId = value;
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (selectedNotebookId != null) {
                try {
                  Navigator.of(ctx).pop();
                  await _notesViewModel.moveNote(note.id, selectedNotebookId!);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Note moved successfully')),
                  );
                } catch (e) {
                  _logger.error('Error moving note', e);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error moving note: ${e.toString()}')),
                  );
                }
              }
            },
            child: const Text('Move'),
          ),
        ],
      ),
    );
  }

  void _showImportMarkdownDialog(BuildContext context) {
    String? selectedNotebookId;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.upload_file, color: Theme.of(context).primaryColor),
            const SizedBox(width: 8),
            const Text('Import Markdown'),
          ],
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Builder(
              builder: (context) {
                final notebooks = _notesViewModel.notebooks;
                // If no notebooks, show message
                if (notebooks.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8.0),
                    child: Text(
                      'You need to create a notebook first',
                      style: TextStyle(color: AppTheme.dangerColor),
                    ),
                  );
                }

                // Set the initial value if not set
                if (selectedNotebookId == null && notebooks.isNotEmpty) {
                  selectedNotebookId = notebooks.first.id;
                }

                return DropdownButtonFormField<String>(
                  decoration: const InputDecoration(
                    labelText: 'Notebook',
                    prefixIcon: Icon(Icons.folder_outlined),
                  ),
                  value: selectedNotebookId,
                  isExpanded: true,
                  items: notebooks.map((notebook) {
                    return DropdownMenuItem<String>(
                      value: notebook.id,
                      child: Text(
                        notebook.name,
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  }).toList(),
                  onChanged: (value) {
                    selectedNotebookId = value;
                  },
                );
              }
            ),
            const SizedBox(height: 16),
            const Text(
              'Select a Markdown (.md) file to import as a new note.',
              style: TextStyle(fontSize: 14),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (selectedNotebookId != null) {
                Navigator.of(ctx).pop();
                await _pickAndImportMarkdownFile(selectedNotebookId!);
              } else {
                // Show error if no notebook is selected
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Please select a notebook')),
                );
              }
            },
            style: AppTheme.getSuccessButtonStyle(),
            child: const Text('Select File'),
          ),
        ],
      ),
    );
  }

  Future<void> _pickAndImportMarkdownFile(String notebookId) async {
    try {
      // Use FilePicker to pick a markdown file
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['md', 'markdown'],
      );

      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        
        // Show loading indicator
        _showLoadingDialog(context, 'Importing markdown...');
        
        // Read file content
        String content;
        if (file.bytes != null) {
          // Web platform returns bytes
          content = String.fromCharCodes(file.bytes!);
        } else if (file.path != null) {
          // Mobile/desktop platforms return a file path
          final fileObj = File(file.path!);
          content = await fileObj.readAsString();
        } else {
          throw Exception('Unable to read file content');
        }
        
        // Import markdown content
        final note = await _notesViewModel.importMarkdownFile(
          content, 
          file.name,
          notebookId,
        );
        
        // Close loading dialog
        Navigator.of(context, rootNavigator: true).pop();
        
        if (note != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Imported "${note.title}" successfully')),
          );
          
          // Navigate to the note editor
          _navigateToNoteEditor(note);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to import markdown file')),
          );
        }
      }
    } catch (e) {
      // Close loading dialog if open
      if (Navigator.of(context, rootNavigator: true).canPop()) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      
      _logger.error('Error importing markdown file', e);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: ${e.toString()}')),
      );
    }
  }
  
  void _showLoadingDialog(BuildContext context, String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return Dialog(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(width: 20),
                Text(message),
              ],
            ),
          ),
        );
      },
    );
  }
  
  Future<void> _exportNoteToMarkdown(Note note) async {
    try {
      // Show loading indicator
      _showLoadingDialog(context, 'Exporting markdown...');
      
      // Get markdown content
      final markdown = await _notesViewModel.exportNoteToMarkdown(note.id);
      
      // Close loading dialog
      Navigator.of(context, rootNavigator: true).pop();
      
      // Generate filename
      final filename = '${note.title.replaceAll(RegExp(r'[^\w\s.-]'), '_')}.md';
      
      // Share the file on mobile platforms or save on desktop
      if (Platform.isAndroid || Platform.isIOS) {
        // Save to temp directory and share
        final directory = await getTemporaryDirectory();
        final file = File('${directory.path}/$filename');
        await file.writeAsString(markdown);
        
        // Share the file
        await Share.shareXFiles(
          [XFile(file.path)],
          subject: note.title,
          text: 'Exported note as Markdown',
        );
      } else {
        // Use file picker to save the file on desktop platforms
        final path = await FilePicker.platform.saveFile(
          dialogTitle: 'Save Markdown File',
          fileName: filename,
          type: FileType.custom,
          allowedExtensions: ['md'],
        );
        
        if (path != null) {
          final file = File(path);
          await file.writeAsString(markdown);
          
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Saved to ${file.path}')),
          );
        }
      }
    } catch (e) {
      // Close loading dialog if open
      if (Navigator.of(context, rootNavigator: true).canPop()) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      
      _logger.error('Error exporting note to markdown', e);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: ${e.toString()}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBarCommon(
        title: 'Notes',
        showBackButton: false,
        onMenuPressed: () => _scaffoldKey.currentState?.openDrawer(),
        actions: const [ThemeSwitcher()],
      ),
      drawer: const SidebarDrawer(),
      body: Consumer<NotesViewModel>(
        builder: (context, notesViewModel, _) {
          return _buildBody(notesViewModel);
        },
      ),
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FloatingActionButton.small(
            onPressed: () => _showImportMarkdownDialog(context),
            tooltip: 'Import Markdown',
            heroTag: 'importMarkdown',
            child: const Icon(Icons.upload_file),
          ),
          const SizedBox(height: 8),
          FloatingActionButton(
            onPressed: () => _showAddNoteDialog(context),
            tooltip: 'Add Note',
            heroTag: 'addNote',
            child: const Icon(Icons.add),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    if (_isInitialized) {
      _notesViewModel.deactivate();
    }
    super.dispose();
  }
}
