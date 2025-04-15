import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../widgets/app_drawer.dart';
import '../providers/notebooks_provider.dart';

class NotebooksScreen extends StatefulWidget {
  @override
  _NotebooksScreenState createState() => _NotebooksScreenState();
}

class _NotebooksScreenState extends State<NotebooksScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(
      () => Provider.of<NotebooksProvider>(context, listen: false).fetchNotebooks(),
    );
  }

  void _showAddNotebookDialog() {
    final _nameController = TextEditingController();
    final _descriptionController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Add Notebook'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nameController,
              decoration: InputDecoration(labelText: 'Name'),
            ),
            TextField(
              controller: _descriptionController,
              decoration: InputDecoration(labelText: 'Description'),
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
              if (_nameController.text.isNotEmpty) {
                try {
                  await Provider.of<NotebooksProvider>(context, listen: false)
                      .createNotebook(_nameController.text, _descriptionController.text);
                  Navigator.of(ctx).pop();
                } catch (error) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Failed to create notebook')),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Notebooks')),
      drawer: AppDrawer(),
      body: Consumer<NotebooksProvider>(
        builder: (ctx, notebooksProvider, _) {
          if (notebooksProvider.isLoading) {
            return Center(child: CircularProgressIndicator());
          }

          return ListView.builder(
            itemCount: notebooksProvider.notebooks.length,
            itemBuilder: (context, index) {
              final notebook = notebooksProvider.notebooks[index];
              return Card(
                margin: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: ListTile(
                  title: Text(notebook.name),
                  subtitle: Text(notebook.description),
                  leading: Icon(Icons.book),
                  onTap: () => context.go('/notebooks/${notebook.id}'),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddNotebookDialog,
        child: Icon(Icons.add),
      ),
    );
  }
}
