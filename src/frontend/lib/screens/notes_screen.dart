import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../widgets/app_drawer.dart';
import '../providers/notes_provider.dart';
import '../providers/notebooks_provider.dart';
import '../models/note.dart';
import 'note_editor_screen.dart';

class NotesScreen extends StatefulWidget {
  @override
  _NotesScreenState createState() => _NotesScreenState();
}

class _NotesScreenState extends State<NotesScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      Provider.of<NotesProvider>(context, listen: false).fetchNotes();
      Provider.of<NotebooksProvider>(context, listen: false).fetchNotebooks();
    });
  }

  void _showAddNoteDialog() {
    final _titleController = TextEditingController();
    String? selectedNotebookId;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Add Note'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Consumer<NotebooksProvider>(
              builder: (context, notebooksProvider, _) {
                if (notebooksProvider.notebooks.isEmpty) {
                  return Text('Please create a notebook first');
                }
                return DropdownButtonFormField<String>(
                  decoration: InputDecoration(labelText: 'Notebook'),
                  value: selectedNotebookId,
                  items: notebooksProvider.notebooks.map((notebook) {
                    return DropdownMenuItem(
                      value: notebook.id,
                      child: Text(notebook.name),
                    );
                  }).toList(),
                  onChanged: (value) => selectedNotebookId = value,
                );
              },
            ),
            TextField(
              controller: _titleController,
              decoration: InputDecoration(labelText: 'Title'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (_titleController.text.isNotEmpty && selectedNotebookId != null) {
                try {
                  await Provider.of<NotesProvider>(context, listen: false)
                      .createNote(selectedNotebookId!, _titleController.text);
                  Navigator.of(ctx).pop();
                  await Provider.of<NotesProvider>(context, listen: false).fetchNotes();
                } catch (error) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Failed to create note')),
                  );
                }
              }
            },
            child: Text('Add'),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Notes')),
      drawer: AppDrawer(),
      body: Consumer<NotesProvider>(
        builder: (ctx, notesProvider, _) {
          if (notesProvider.isLoading) {
            return Center(child: CircularProgressIndicator());
          }
          
          if (notesProvider.notes.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('No notes found'),
                  SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => Provider.of<NotesProvider>(context, listen: false).fetchNotes(),
                    child: Text('Refresh'),
                  ),
                ],
              ),
            );
          }

          print('Building notes list with ${notesProvider.notes.length} items');
          return ListView.builder(
            itemCount: notesProvider.notes.length,
            itemBuilder: (context, index) {
              final note = notesProvider.notes[index];
              print('Building note ${index}: ${note.title}');
              return Card(
                margin: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: ListTile(
                  title: Text(note.title),
                  subtitle: Text(note.blocks.isNotEmpty ? note.blocks.first.content : ''),
                  leading: Icon(Icons.note),
                  onTap: () => _navigateToNoteEditor(note),
                  trailing: IconButton(
                    icon: Icon(Icons.delete),
                    onPressed: () async {
                      try {
                        await notesProvider.deleteNote(note.id);
                      } catch (error) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Failed to delete note')),
                        );
                      }
                    },
                  ),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddNoteDialog,
        child: Icon(Icons.add),
      ),
    );
  }
}
