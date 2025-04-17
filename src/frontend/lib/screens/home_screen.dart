import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../widgets/app_drawer.dart';
import '../providers/notes_provider.dart';
import '../providers/tasks_provider.dart';
import '../providers/notebooks_provider.dart';
import '../providers/websocket_provider.dart';

class HomeScreen extends StatefulWidget {
  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  bool _isInitialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    
    if (!_isInitialized) {
      _isInitialized = true;
      
      // Ensure WebSocket is connected
      Provider.of<WebSocketProvider>(context, listen: false).ensureConnected();
      
      // Fetch data from providers
      Future.microtask(() {
        Provider.of<NotesProvider>(context, listen: false).fetchNotes();
        Provider.of<TasksProvider>(context, listen: false).fetchTasks();
        Provider.of<NotebooksProvider>(context, listen: false).fetchNotebooks();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        title: Text('ThinkStack'),
        leading: IconButton(
          icon: Icon(Icons.menu),
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
        ),
      ),
      drawer: AppDrawer(),
      body: Padding(
        padding: EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionHeader(context, 'Recent Notebooks', Icons.book),
            SizedBox(height: 8),
            Expanded(
              child: Consumer<NotebooksProvider>(
                builder: (ctx, notebooksProvider, _) {
                  if (notebooksProvider.isLoading) {
                    return Center(child: CircularProgressIndicator());
                  }
                  
                  final recentNotebooks = notebooksProvider.notebooks.take(5).toList();
                  
                  if (recentNotebooks.isEmpty) {
                    return Center(child: Text('No notebooks found'));
                  }
                  
                  return ListView.builder(
                    itemCount: recentNotebooks.length,
                    itemBuilder: (context, index) {
                      final notebook = recentNotebooks[index];
                      return Card(
                        key: ValueKey('notebook_${notebook.id}'), // Add key for stable identity
                        child: ListTile(
                          title: Text(notebook.name),
                          subtitle: Text(
                            '${notebook.notes.length} notes',
                            style: TextStyle(color: Colors.grey),
                          ),
                          leading: CircleAvatar(
                            backgroundColor: Colors.blue.withOpacity(0.1),
                            child: Icon(Icons.book, color: Colors.blue),
                          ),
                          onTap: () => context.go('/notebooks/${notebook.id}'),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
            SizedBox(height: 24),
            _buildSectionHeader(context, 'Recent Notes', Icons.note),
            SizedBox(height: 8),
            Expanded(
              child: Consumer<NotesProvider>(
                builder: (ctx, notesProvider, _) {
                  if (notesProvider.isLoading) {
                    return Center(child: CircularProgressIndicator());
                  }
                  
                  if (notesProvider.recentNotes.isEmpty) {
                    return Center(child: Text('No recent notes'));
                  }
                  
                  return ListView.builder(
                    itemCount: notesProvider.recentNotes.length,
                    itemBuilder: (context, index) {
                      final note = notesProvider.recentNotes[index];
                      return Card(
                        key: ValueKey('note_${note.id}'), // Add key for stable identity
                        child: ListTile(
                          title: Text(
                            note.title,
                            style: TextStyle(fontWeight: FontWeight.w500),
                          ),
                          subtitle: Text(
                            note.content,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          leading: CircleAvatar(
                            backgroundColor: Colors.blue.withOpacity(0.1),
                            child: Icon(Icons.note, color: Colors.blue),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
            SizedBox(height: 24),
            _buildSectionHeader(context, 'Recent Tasks', Icons.task_alt),
            SizedBox(height: 8),
            Expanded(
              child: Consumer<TasksProvider>(
                builder: (ctx, tasksProvider, _) {
                  if (tasksProvider.isLoading) {
                    return Center(child: CircularProgressIndicator());
                  }
                  
                  if (tasksProvider.recentTasks.isEmpty) {
                    return Center(child: Text('No recent tasks'));
                  }
                  
                  return ListView.builder(
                    itemCount: tasksProvider.recentTasks.length,
                    itemBuilder: (context, index) {
                      final task = tasksProvider.recentTasks[index];
                      return Card(
                        child: ListTile(
                          title: Text(
                            task.title,
                            style: TextStyle(
                              fontWeight: FontWeight.w500,
                              decoration: task.isCompleted
                                  ? TextDecoration.lineThrough
                                  : null,
                            ),
                          ),
                          leading: CircleAvatar(
                            backgroundColor: Colors.blue.withOpacity(0.1),
                            child: Icon(Icons.task_alt, color: Colors.blue),
                          ),
                          trailing: Transform.scale(
                            scale: 1.2,
                            child: Checkbox(
                              value: task.isCompleted,
                              onChanged: (value) async {
                                try {
                                  await tasksProvider
                                      .toggleTaskCompletion(
                                          task.id, value ?? false);
                                } catch (error) {
                                  ScaffoldMessenger.of(context)
                                      .showSnackBar(
                                    SnackBar(
                                        content: Text(
                                            'Failed to update task status')),
                                  );
                                }
                              },
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddNotebookDialog(context),
        child: Icon(Icons.add),
        tooltip: 'Add Notebook',
      ),
    );
  }

  void _showAddNotebookDialog(BuildContext context) {
    // ...existing code...
  }

  Widget _buildSectionHeader(BuildContext context, String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: Colors.blue),
        SizedBox(width: 8),
        Text(
          title,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
        ),
      ],
    );
  }
}
