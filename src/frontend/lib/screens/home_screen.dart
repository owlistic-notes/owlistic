import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../widgets/app_drawer.dart';
import '../widgets/card_container.dart';
import '../widgets/empty_state.dart';
import '../providers/notes_provider.dart';
import '../providers/tasks_provider.dart';
import '../providers/notebooks_provider.dart';
import '../providers/websocket_provider.dart';
import '../utils/logger.dart';
import '../core/theme.dart';

class HomeScreen extends StatefulWidget {
  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final Logger _logger = Logger('HomeScreen');
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  bool _isInitialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    
    if (!_isInitialized) {
      _isInitialized = true;
      _logger.info('Initializing home screen');
      
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
        title: const Text('ThinkStack'),
        leading: IconButton(
          icon: const Icon(Icons.menu),
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () {
              // Implement search
            },
          ),
        ],
      ),
      drawer: const AppDrawer(),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildWelcomeCard(context),
            _buildSectionHeader(context, 'Recent Notebooks', Icons.folder_outlined),
            _buildRecentNotebooks(),
            _buildSectionHeader(context, 'Recent Notes', Icons.note_outlined),
            _buildRecentNotes(),
            _buildSectionHeader(context, 'Recent Tasks', Icons.assignment_outlined),
            _buildRecentTasks(),
            const SizedBox(height: 80), // Space for FAB
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showQuickCreateMenu(context),
        child: const Icon(Icons.add),
        tooltip: 'Create New',
      ),
    );
  }

  Widget _buildWelcomeCard(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).primaryColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).primaryColor.withOpacity(0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text(
                  'Welcome back!',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  'Organize your thoughts and ideas all in one place.',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.white,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: 70,
            height: 70,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(35),
            ),
            child: const Icon(
              Icons.psychology, // Brain icon for "ThinkStack"
              color: Colors.white,
              size: 32,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        children: [
          Icon(icon, color: Theme.of(context).primaryColor),
          const SizedBox(width: 8),
          Text(
            title,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const Spacer(),
          TextButton(
            onPressed: () {
              // Navigate to section
              if (title.contains('Notebooks')) context.go('/notebooks');
              if (title.contains('Notes')) context.go('/notes');
              if (title.contains('Tasks')) context.go('/tasks');
            },
            child: const Text('View All'),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentNotebooks() {
    return SizedBox(
      height: 160,
      child: Consumer<NotebooksProvider>(
        builder: (ctx, notebooksProvider, _) {
          if (notebooksProvider.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          final notebooks = notebooksProvider.notebooks.take(5).toList();
          
          if (notebooks.isEmpty) {
            return EmptyState(
              title: 'No notebooks yet',
              message: 'Create your first notebook to organize your notes.',
              icon: Icons.folder_outlined,
              onAction: () => _showAddNotebookDialog(context),
              actionLabel: 'Create Notebook',
            );
          }

          return ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            itemCount: notebooks.length,
            itemBuilder: (context, index) {
              final notebook = notebooks[index];
              return SizedBox(
                width: 160,
                child: CardContainer(
                  onTap: () => context.go('/notebooks/${notebook.id}'),
                  padding: const EdgeInsets.all(0),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: Theme.of(context).primaryColor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(24),
                          ),
                          child: Icon(
                            Icons.folder_outlined,
                            color: Theme.of(context).primaryColor,
                            size: 24,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          notebook.name,
                          style: Theme.of(context).textTheme.titleMedium,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${notebook.notes.length} notes',
                          style: Theme.of(context).textTheme.bodySmall,
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildRecentNotes() {
    return Consumer<NotesProvider>(
      builder: (ctx, notesProvider, _) {
        if (notesProvider.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }

        if (notesProvider.recentNotes.isEmpty) {
          return EmptyState(
            title: 'No notes yet',
            message: 'Create your first note to get started.',
            icon: Icons.note_outlined,
          );
        }

        return ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: notesProvider.recentNotes.take(3).length,
          itemBuilder: (context, index) {
            final note = notesProvider.recentNotes[index];
            return CardContainer(
              leading: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Theme.of(context).primaryColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.note_outlined,
                  color: Theme.of(context).primaryColor,
                ),
              ),
              title: note.title,
              subtitle: note.notebookId,
              onTap: () {
                // Navigate to note
              },
              // Use getTextContent from the first block if available
              child: note.blocks.isNotEmpty
                ? Text(
                    note.blocks.first.getTextContent(),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium,
                  )
                : const SizedBox.shrink(), // Don't show anything if no blocks
            );
          },
        );
      },
    );
  }

  Widget _buildRecentTasks() {
    return Consumer<TasksProvider>(
      builder: (ctx, tasksProvider, _) {
        if (tasksProvider.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }

        if (tasksProvider.recentTasks.isEmpty) {
          return EmptyState(
            title: 'No tasks yet',
            message: 'Create tasks to stay organized and boost productivity.',
            icon: Icons.check_circle_outline, // Check circle for tasks
          );
        }

        // Card wrapping all tasks
        return CardContainer(
          padding: EdgeInsets.zero,
          child: ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: tasksProvider.recentTasks.length,
            separatorBuilder: (_, __) => const Divider(height: 1, indent: 56),
            itemBuilder: (context, index) {
              final task = tasksProvider.recentTasks[index];
              return ListTile(
                leading: Transform.scale(
                  scale: 1.2,
                  child: Checkbox(
                    value: task.isCompleted,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                    onChanged: (bool? value) async {
                      try {
                        await tasksProvider.toggleTaskCompletion(
                          task.id,
                          value ?? false,
                        );
                      } catch (error) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Failed to update task status')),
                        );
                      }
                    },
                  ),
                ),
                title: Text(
                  task.title,
                  style: TextStyle(
                    decoration: task.isCompleted ? TextDecoration.lineThrough : null,
                    color: task.isCompleted
                        ? Theme.of(context).textTheme.bodySmall?.color
                        : Theme.of(context).textTheme.bodyLarge?.color,
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  void _showQuickCreateMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 10,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.grey.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(
                'Create New',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 20),
              _buildQuickCreateItem(
                context,
                icon: Icons.note_add,
                title: 'New Note',
                description: 'Create a blank note',
                onTap: () {
                  Navigator.pop(context);
                  // Show note creation dialog
                },
              ),
              const Divider(),
              _buildQuickCreateItem(
                context,
                icon: Icons.folder,
                title: 'New Notebook',
                description: 'Create a collection of notes',
                onTap: () {
                  Navigator.pop(context);
                  _showAddNotebookDialog(context);
                },
              ),
              const Divider(),
              _buildQuickCreateItem(
                context,
                icon: Icons.check_circle_outline,
                title: 'New Task',
                description: 'Add a to-do item',
                onTap: () {
                  Navigator.pop(context);
                  // Show task creation dialog
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildQuickCreateItem(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String description,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Theme.of(context).primaryColor.withOpacity(0.1),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Icon(
          icon,
          color: Theme.of(context).primaryColor,
        ),
      ),
      title: Text(
        title,
        style: Theme.of(context).textTheme.titleMedium,
      ),
      subtitle: Text(
        description,
        style: Theme.of(context).textTheme.bodySmall,
      ),
      onTap: onTap,
    );
  }

  void _showAddNotebookDialog(BuildContext context) {
    final _nameController = TextEditingController();
    final _descriptionController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Row(
          children: [
            Icon(Icons.folder_outlined, color: Theme.of(context).primaryColor), // Folder icon for notebook
            const SizedBox(width: 8),
            const Text('Add Notebook'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Name',
                prefixIcon: Icon(Icons.drive_file_rename_outline), // Rename icon for name field
              ),
              autofocus: true,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _descriptionController,
              decoration: const InputDecoration(
                labelText: 'Description',
                prefixIcon: Icon(Icons.description_outlined), // Description icon
              ),
              maxLines: 3,
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
              if (_nameController.text.isNotEmpty) {
                try {
                  final notebooksProvider = Provider.of<NotebooksProvider>(context, listen: false);
                  await notebooksProvider.createNotebook(
                    _nameController.text,
                    _descriptionController.text,
                  );
                  Navigator.of(ctx).pop();
                } catch (error) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Failed to create notebook')),
                  );
                }
              }
            },
            child: const Text('Create'),
            style: AppTheme.getSuccessButtonStyle(),
          ),
        ],
      ),
    );
  }
}
