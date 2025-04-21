import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'note_editor_screen.dart';
import '../widgets/app_drawer.dart';
import '../widgets/card_container.dart';
import '../widgets/empty_state.dart';
import '../widgets/search_bar_widget.dart';
import '../providers/notes_provider.dart';
import '../providers/tasks_provider.dart';
import '../providers/notebooks_provider.dart';
import '../providers/websocket_provider.dart';
import '../providers/theme_provider.dart';
import '../providers/auth_provider.dart';
import '../utils/logger.dart';
import '../core/theme.dart';
import '../widgets/app_bar_common.dart';

class HomeScreen extends StatefulWidget {
  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final Logger _logger = Logger('HomeScreen');
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  bool _isInitialized = false;
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();

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
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _toggleSearch() {
    setState(() {
      _isSearching = !_isSearching;
      if (!_isSearching) {
        _searchController.clear();
      }
    });
  }

  void _handleSearch(String query) {
    // Implement search functionality
    _logger.info('Searching for: $query');
  }

  void _showThemeMenu(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    
    showMenu(
      context: context,
      position: RelativeRect.fromLTRB(MediaQuery.of(context).size.width, 0, 0, 0),
      items: [
        PopupMenuItem(
          value: ThemeMode.light,
          child: Row(
            children: [
              Icon(Icons.wb_sunny, 
                color: themeProvider.themeMode == ThemeMode.light 
                  ? Theme.of(context).primaryColor 
                  : null
              ),
              const SizedBox(width: 8),
              const Text('Light Mode'),
              if (themeProvider.themeMode == ThemeMode.light)
                Icon(Icons.check, color: Theme.of(context).primaryColor),
            ],
          ),
        ),
        PopupMenuItem(
          value: ThemeMode.dark,
          child: Row(
            children: [
              Icon(Icons.nightlight_round,
                color: themeProvider.themeMode == ThemeMode.dark 
                  ? Theme.of(context).primaryColor 
                  : null
              ),
              const SizedBox(width: 8),
              const Text('Dark Mode'),
              if (themeProvider.themeMode == ThemeMode.dark)
                Icon(Icons.check, color: Theme.of(context).primaryColor),
            ],
          ),
        ),
      ],
    ).then((value) {
      if (value != null) {
        themeProvider.setThemeMode(value);
      }
    });
  }

  void _showNotificationsMenu(BuildContext context) {
    showMenu(
      context: context,
      position: RelativeRect.fromLTRB(MediaQuery.of(context).size.width, 0, 0, 0),
      items: [
        const PopupMenuItem(
          enabled: false,
          child: ListTile(
            title: Text('Notifications', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ),
        const PopupMenuItem(
          child: ListTile(
            leading: Icon(Icons.notifications_active),
            title: Text('Welcome to ThinkStack!'),
            subtitle: Text('Get started by creating your first notebook'),
          ),
        ),
        const PopupMenuItem(
          child: ListTile(
            leading: Icon(Icons.update),
            title: Text('App updated to latest version'),
            subtitle: Text('See what\'s new'),
          ),
        ),
        PopupMenuItem(
          child: Center(
            child: TextButton(
              child: const Text('View All Notifications'),
              onPressed: () {
                Navigator.pop(context);
                // Navigate to notifications page
              },
            ),
          ),
        ),
      ],
    );
  }

  void _showProfileMenu(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    
    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(MediaQuery.of(context).size.width, 0, 0, 0),
      items: <PopupMenuEntry<String>>[
        PopupMenuItem<String>(
          value: 'profile_header',
          child: ListTile(
            leading: CircleAvatar(
              child: const Icon(Icons.person),
              backgroundColor: Theme.of(context).primaryColor.withOpacity(0.1),
            ),
            title: Text(authProvider.currentUser?.email?.split('@')[0] ?? 'User'),
            subtitle: Text(authProvider.currentUser?.email ?? 'No email'),
          ),
        ),
        const PopupMenuItem<String>(
          value: 'profile',
          child: ListTile(
            leading: Icon(Icons.person),
            title: Text('My Profile'),
          ),
        ),
        const PopupMenuItem<String>(
          value: 'settings',
          child: ListTile(
            leading: Icon(Icons.settings),
            title: Text('Settings'),
          ),
        ),
        const PopupMenuItem<String>(
          value: 'admin',
          child: ListTile(
            leading: Icon(Icons.admin_panel_settings),
            title: Text('Admin Panel'),
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem<String>(
          value: 'logout',
          child: const ListTile(
            leading: Icon(Icons.logout),
            title: Text('Logout'),
          ),
          onTap: () async {
            // Wait a moment for the menu to close
            await Future.delayed(Duration.zero);
            if (context.mounted) {
              await authProvider.logout();
              // Navigation will be handled by GoRouter
            }
          },
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    
    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBarCommon(
        onMenuPressed: () => _scaffoldKey.currentState?.openDrawer(),
        showBackButton: false, // Home screen doesn't need back button
        title: 'ThinkStack', // Set explicit title for home screen
      ),
      drawer: const AppDrawer(),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildWelcomeCard(context, authProvider),
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

  Widget _buildWelcomeCard(BuildContext context, AuthProvider authProvider) {
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
              children: [
                Text(
                  'Welcome back${authProvider.currentUser != null ? ', ${authProvider.currentUser!.email.split('@')[0]}' : ''}!',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
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
    return Consumer<NotebooksProvider>(
      builder: (ctx, notebooksProvider, _) {
        if (notebooksProvider.isLoading) {
          return const SizedBox(
            height: 160,
            child: Center(child: CircularProgressIndicator()),
          );
        }

        final notebooks = notebooksProvider.notebooks.take(5).toList();
        
        if (notebooks.isEmpty) {
          // Return EmptyState without fixed height constraint
          return EmptyState(
            title: 'No notebooks yet',
            message: 'Create your first notebook to organize your notes.',
            icon: Icons.folder_outlined,
            onAction: () => _showAddNotebookDialog(context),
            actionLabel: 'Create Notebook',
          );
        }

        // Use fixed height only when showing notebooks
        return SizedBox(
          height: 160,
          child: ListView.builder(
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
          ),
        );
      },
    );
  }

  Widget _buildRecentNotes() {
    return Consumer<NotesProvider>(
      builder: (ctx, notesProvider, _) {
        if (notesProvider.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }

        if (notesProvider.recentNotes.isEmpty) {
          // Check if notebooks exist before showing the create note button
          final notebooksProvider = Provider.of<NotebooksProvider>(context, listen: false);
          final hasNotebooks = notebooksProvider.notebooks.isNotEmpty;
          
          return EmptyState(
            title: 'No notes yet',
            message: hasNotebooks 
                ? 'Create your first note to get started.' 
                : 'Create a notebook first, then add notes to it.',
            icon: Icons.note_outlined,
            onAction: () => hasNotebooks 
                ? _showAddNoteDialog(context)
                : _showAddNotebookDialog(context, showNoteDialogAfter: true),
            actionLabel: hasNotebooks ? 'Create Note' : 'Create Notebook',
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
                // Navigate to the note editor screen
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => NoteEditorScreen(note: note),
                  ),
                );
              },
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
            onAction: () => _showAddTaskDialog(context),
            actionLabel: 'Create Task',
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
      isScrollControlled: true,
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Container(
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
              crossAxisAlignment: CrossAxisAlignment.stretch,
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
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                _buildQuickCreateItem(
                  context,
                  icon: Icons.note_add,
                  title: 'New Note',
                  description: 'Create a blank note',
                  onTap: () {
                    Navigator.pop(context);
                    // Show notebook selector and note creation dialog
                    _showAddNoteDialog(context);
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
                    _showAddTaskDialog(context);
                  },
                ),
                const SizedBox(height: 8),
              ],
            ),
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

  void _showAddNoteDialog(BuildContext context) {
    final _titleController = TextEditingController();
    String? selectedNotebookId;

    // Get notebooks provider to check if notebooks exist
    final notebooksProvider = Provider.of<NotebooksProvider>(context, listen: false);
    // If no notebooks exist, show notebook creation dialog first
    if (notebooksProvider.notebooks.isEmpty) {
      _showAddNotebookDialog(context, showNoteDialogAfter: true);
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.note_add_outlined, color: Theme.of(context).primaryColor),
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
            // Add notebook dropdown
            Consumer<NotebooksProvider>(
              builder: (context, notebooksProvider, _) {
                final notebooks = notebooksProvider.notebooks;
                
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
              },
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _titleController,
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
              if (_titleController.text.isNotEmpty && selectedNotebookId != null) {
                try {
                  final notebooksProvider = Provider.of<NotebooksProvider>(context, listen: false);
                  await notebooksProvider.addNoteToNotebook(
                    selectedNotebookId!,
                    _titleController.text,
                  );
                  Navigator.of(ctx).pop();
                } catch (error) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Failed to create note')),
                  );
                }
              }
            },
            style: AppTheme.getSuccessButtonStyle(),
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  void _showAddTaskDialog(BuildContext context) {
    final _titleController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.add_task, color: Theme.of(context).primaryColor),
            const SizedBox(width: 8),
            const Text('Add Task'),
          ],
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        content: TextField(
          controller: _titleController,
          decoration: const InputDecoration(
            labelText: 'Task Title',
            prefixIcon: Icon(Icons.title),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (_titleController.text.isNotEmpty) {
                try {
                  final tasksProvider = Provider.of<TasksProvider>(context, listen: false);
                  await tasksProvider.createTask(_titleController.text, '');
                  Navigator.of(ctx).pop();
                } catch (error) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Failed to create task')),
                  );
                }
              }
            },
            style: AppTheme.getSuccessButtonStyle(),
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  void _showAddNotebookDialog(BuildContext context, {bool showNoteDialogAfter = false}) {
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
                  // If showNoteDialogAfter is true, show the note dialog after notebook creation
                  if (showNoteDialogAfter) {
                    // Add a short delay to allow the notebooks list to update
                    Future.delayed(Duration(milliseconds: 300), () {
                      _showAddNoteDialog(context);
                    });
                  }
                } catch (error) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Failed to create notebook')),
                  );
                }
              }
            },
            style: AppTheme.getSuccessButtonStyle(),
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }
}
