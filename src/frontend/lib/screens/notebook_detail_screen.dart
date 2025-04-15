import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/note.dart';
import '../providers/notes_provider.dart';
import '../providers/notebooks_provider.dart';
import 'note_editor_screen.dart';

class NotebookDetailScreen extends StatelessWidget {
  final String notebookId;

  const NotebookDetailScreen({required this.notebookId});

  void _showAddNoteDialog(BuildContext context, String notebookId) {
    final _titleController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Add Note'),
        content: TextField(
          controller: _titleController,
          decoration: InputDecoration(labelText: 'Title'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (_titleController.text.isNotEmpty) {
                try {
                  await Provider.of<NotebooksProvider>(context, listen: false)
                      .addNoteToNotebook(notebookId, _titleController.text);
                  Navigator.of(ctx).pop();
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

  void _showEditNoteDialog(BuildContext context, String notebookId, Note note) {
    final _titleController = TextEditingController(text: note.title);
    final _contentController = TextEditingController(text: note.content);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Edit Note'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _titleController,
              decoration: InputDecoration(labelText: 'Title'),
            ),
            SizedBox(height: 8),
            TextField(
              controller: _contentController,
              decoration: InputDecoration(labelText: 'Content'),
              maxLines: 5,
              minLines: 3,
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
              if (_titleController.text.isNotEmpty) {
                try {
                  await Provider.of<NotesProvider>(context, listen: false)
                      .updateNote(note.id, _titleController.text);
                  Navigator.of(ctx).pop();
                } catch (error) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Failed to update note')),
                  );
                }
              }
            },
            child: Text('Save'),
          ),
        ],
      ),
    );
  }

  void _navigateToNoteEditor(BuildContext context, Note note) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => NoteEditorScreen(note: note),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final notebook = Provider.of<NotebooksProvider>(context)
        .notebooks
        .firstWhere((nb) => nb.id == notebookId);

    return Scaffold(
      appBar: AppBar(title: Text(notebook.name)),
      body: ListView.builder(
        itemCount: notebook.notes.length,
        itemBuilder: (context, index) {
          final note = notebook.notes[index];
          return Card(
            margin: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: ListTile(
              title: Text(note.title),
              subtitle: Text(note.content),
              leading: Icon(Icons.note),
              onTap: () => _navigateToNoteEditor(context, note),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: Icon(Icons.edit),
                    onPressed: () => _showEditNoteDialog(context, notebookId, note),
                  ),
                  IconButton(
                    icon: Icon(Icons.delete),
                    onPressed: () async {
                      try {
                        await Provider.of<NotebooksProvider>(context, listen: false)
                            .deleteNoteFromNotebook(notebookId, note.id);
                      } catch (error) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Failed to delete note')),
                        );
                      }
                    },
                  ),
                ],
              ),
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddNoteDialog(context, notebookId),
        child: Icon(Icons.add),
      ),
    );
  }
}
