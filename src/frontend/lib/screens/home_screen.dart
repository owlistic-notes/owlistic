import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:owlistic/utils/data_converter.dart';
import 'package:provider/provider.dart';
import 'package:owlistic/models/user.dart';
import 'package:owlistic/widgets/theme_switcher.dart';
import 'note_editor_screen.dart';
import 'package:owlistic/widgets/app_drawer.dart';
import 'package:owlistic/widgets/card_container.dart';
import 'package:owlistic/widgets/empty_state.dart';
import 'package:owlistic/viewmodel/home_viewmodel.dart';
import 'package:owlistic/utils/logger.dart';
import 'package:owlistic/widgets/app_bar_common.dart';
import 'package:owlistic/widgets/app_logo.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final Logger _logger = Logger('HomeScreen');
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    // Initialize our screen
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeViewModel();
    });
  }

  void _initializeViewModel() {
    // Activate just the HomeViewModel
    final homeViewModel = context.read<HomeViewModel>();
    homeViewModel.activate();
    
    // Initialize data
    _initializeData();
  }

  Future<void> _initializeData() async {
    final homeViewModel = context.read<HomeViewModel>();
    
    // Ensure WebSocket is connected
    await homeViewModel.ensureConnected();

    // Fetch data from HomeViewModel
    try {
      // Fetch notebooks first
      await homeViewModel.fetchRecentNotebooks();
      
      // Fetch recent notes
      await homeViewModel.fetchRecentNotes();
      
      // Fetch tasks
      await homeViewModel.fetchRecentTasks();
      
      // Mark as initialized
      setState(() {
        _isInitialized = true;
      });
    } catch (e) {
      _logger.error('Error loading initial data: $e');
    }
  }

  @override
  void dispose() {
    // Deactivate ViewModel when screen is disposed
    context.read<HomeViewModel>().deactivate();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBarCommon(
        onMenuPressed: () => _scaffoldKey.currentState?.openDrawer(),
        showBackButton: false, // Home screen doesn't need back button
        title: 'Owlistic', // Set explicit title for home screen
        actions: const [
          ThemeSwitcher(), // Add theme switcher to app bar
        ],
      ),
      drawer: const SidebarDrawer(),
      body: !_isInitialized
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _initializeData,
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildWelcomeCard(context),
                    _buildSectionHeader(context, 'Recent Notebooks', Icons.book_outlined),
                    _buildRecentNotebooks(),
                    _buildSectionHeader(context, 'Recent Notes', Icons.description_outlined),
                    _buildRecentNotes(),
                    _buildSectionHeader(context, 'Recent Tasks', Icons.task_outlined),
                    _buildRecentTasks(context),
                    const SizedBox(height: 80), // Space for FAB
                  ],
                ),
              ),
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showQuickCreateMenu(context),
        tooltip: 'Create New',
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildWelcomeCard(BuildContext context) {
    // Use FutureBuilder to handle async user data
    return FutureBuilder<User?>(
      future: context.read<HomeViewModel>().currentUser,
      builder: (context, snapshot) {
        final userName = snapshot.data?.displayName.isNotEmpty == true 
          ? snapshot.data!.displayName 
          : snapshot.data?.username;
        
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
                      'Welcome, $userName!',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Create notes, manage tasks, and stay organized.',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
              // Use transparent logo in welcome card
              const AppLogo(size: 60, forceTransparent: true),
            ],
          ),
        );
      }
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
    // Use HomeViewModel for notebooks data
    return Consumer<HomeViewModel>(
      builder: (ctx, homeViewModel, _) {
        if (homeViewModel.isLoading) {
          return const SizedBox(
            height: 160,
            child: Center(child: CircularProgressIndicator()),
          );
        }

        final notebooks = homeViewModel.recentNotebooks;

        if (notebooks.isEmpty) {
          return EmptyState(
            title: 'No notebooks yet',
            message: 'Create your first notebook to organize your notes.',
            icon: Icons.folder_outlined,
            onAction: () => _showAddNotebookDialog(context),
            actionLabel: 'Create Notebook',
          );
        }

        return SizedBox(
          height: 160,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            itemCount: notebooks.length,
            itemBuilder: (context, index) {
              final notebook = notebooks[index];
              // Get actual note count for this notebook
              final noteCount = homeViewModel.recentNotes
                  .where((note) => note.notebookId == notebook.id)
                  .length;
              
              return Container(
                width: 160,
                margin: const EdgeInsets.all(8),
                child: Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => context.go('/notebooks/${notebook.id}'),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          color: Theme.of(context).primaryColor.withOpacity(0.1),
                          height: 80,
                          width: double.infinity,
                          child: Icon(
                            Icons.book,
                            size: 40,
                            color: Theme.of(context).primaryColor,
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                notebook.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '$noteCount notes',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
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
    // Use HomeViewModel for notes data
    return Consumer<HomeViewModel>(
      builder: (ctx, homeViewModel, _) {
        if (homeViewModel.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }

        // Get recent notes from HomeViewModel
        if (homeViewModel.recentNotes.isEmpty) {
          // Check notebooks before showing create note button
          final hasNotebooks = homeViewModel.hasNotebooks;

          return EmptyState(
            title: 'No notes yet',
            message: hasNotebooks
                ? 'Create your first note to capture your thoughts.'
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
          itemCount: homeViewModel.recentNotes.take(3).length,
          itemBuilder: (context, index) {
            final note = homeViewModel.recentNotes[index];
            // Get notebook name if available
            final notebookName = _getNotebookName(note.notebookId);
            final lastEdited = note.updatedAt ?? note.createdAt;
            return CardContainer(
              child: ListTile(
                title: Text(
                  note.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  '${notebookName ?? 'Unknown notebook'} · ${DataConverter.formatDate(lastEdited)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                leading: const Icon(Icons.description),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => NoteEditorScreen(noteId: note.id),
                    ),
                  );
                },
              ),
            );
          },
        );
      },
    );
  }
  
  // Helper to get notebook name using HomeViewModel
  String? _getNotebookName(String notebookId) {
    final notebook = context.read<HomeViewModel>().getNotebook(notebookId);
    return notebook?.name;
  }

  Widget _buildRecentTasks(BuildContext context) {
    // Use HomeViewModel for tasks data
    return Consumer<HomeViewModel>(
      builder: (ctx, homeViewModel, _) {
        if (homeViewModel.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }

        if (homeViewModel.recentTasks.isEmpty) {
          return EmptyState(
            title: 'No tasks yet',
            message: 'Create tasks to stay organized and boost productivity.',
            icon: Icons.check_circle_outline,
            onAction: () => _showAddTaskDialog(context),
            actionLabel: 'Create Task',
          );
        }

        return CardContainer(
          padding: EdgeInsets.zero,
          child: ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: homeViewModel.recentTasks.length,
            separatorBuilder: (_, __) => const Divider(height: 1, indent: 56),
            itemBuilder: (context, index) {
              final task = homeViewModel.recentTasks[index];
              return ListTile(
                title: Text(
                  task.title,
                  style: TextStyle(
                    decoration: task.isCompleted
                        ? TextDecoration.lineThrough
                        : TextDecoration.none,
                  ),
                ),
                leading: Checkbox(
                  value: task.isCompleted,
                  onChanged: (value) {
                    // Use HomeViewModel to toggle completion
                    homeViewModel.toggleTaskCompletion(task.id, value ?? false);
                  },
                ),
                onTap: () {
                  // Use HomeViewModel to toggle completion
                  homeViewModel.toggleTaskCompletion(task.id, !task.isCompleted);
                },
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
              color: Theme.of(context).scaffoldBackgroundColor,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 10,
                  offset: const Offset(0, -5),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Create New',
                  style: Theme.of(context).textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                _buildQuickCreateItem(
                  context,
                  icon: Icons.book,
                  title: 'Notebook',
                  description: 'Create a new notebook to organize notes',
                  onTap: () {
                    Navigator.pop(context);
                    _showAddNotebookDialog(context);
                  },
                ),
                const Divider(),
                _buildQuickCreateItem(
                  context,
                  icon: Icons.description,
                  title: 'Note',
                  description: 'Create a new note to capture your thoughts',
                  onTap: () {
                    Navigator.pop(context);
                    _showAddNoteDialog(context);
                  },
                ),
                const Divider(),
                _buildQuickCreateItem(
                  context,
                  icon: Icons.check_circle,
                  title: 'Task',
                  description: 'Create a new task to track your to-dos',
                  onTap: () {
                    Navigator.pop(context);
                    _showAddTaskDialog(context);
                  },
                ),
                const SizedBox(height: 20),
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
    final titleController = TextEditingController();
    String? selectedNotebookId;

    // Use HomeViewModel for notebooks
    final homeViewModel = context.read<HomeViewModel>();
    final notebooks = homeViewModel.recentNotebooks;
    
    // If no notebooks exist, show notebook creation dialog first
    if (notebooks.isEmpty) {
      _showAddNotebookDialog(context, showNoteDialogAfter: true);
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.note_add, color: Theme.of(context).primaryColor),
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
            TextField(
              controller: titleController,
              decoration: const InputDecoration(
                labelText: 'Note Title',
                prefixIcon: Icon(Icons.title),
              ),
              autofocus: true,
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              decoration: const InputDecoration(
                labelText: 'Notebook',
                prefixIcon: Icon(Icons.book),
              ),
              items: notebooks.map((notebook) {
                return DropdownMenuItem(
                  value: notebook.id,
                  child: Text(notebook.name),
                );
              }).toList(),
              value: selectedNotebookId,
              hint: const Text('Select Notebook'),
              onChanged: (value) {
                selectedNotebookId = value;
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
            },
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (titleController.text.isNotEmpty && selectedNotebookId != null) {
                // Create note through HomeViewModel
                try {
                  final note = await homeViewModel.createNote(
                    titleController.text,
                    selectedNotebookId!,
                  );
                  
                  Navigator.pop(context);
                  
                  if (note != null) {
                    // Navigate to the new note
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => NoteEditorScreen(noteId: note.id),
                      ),
                    );
                  }
                } catch (e) {
                  _logger.error('Error creating note', e);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error creating note: ${e.toString()}')),
                  );
                  Navigator.pop(context);
                }
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  void _showAddTaskDialog(BuildContext context) {
    final titleController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.check_circle_outline, color: Theme.of(context).primaryColor),
            const SizedBox(width: 8),
            const Text('Add Task'),
          ],
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        content: TextField(
          controller: titleController,
          decoration: const InputDecoration(
            labelText: 'Task Title',
            prefixIcon: Icon(Icons.title),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
            },
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (titleController.text.isNotEmpty) {
                // Create task through HomeViewModel
                final homeViewModel = context.read<HomeViewModel>();
                try {
                  await homeViewModel.createTask(
                    titleController.text, homeViewModel.recentNotes.first.id
                  );
                  Navigator.pop(context);
                } catch (e) {
                  _logger.error('Error creating task', e);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error creating task: ${e.toString()}')),
                  );
                  Navigator.pop(context);
                }
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  void _showAddNotebookDialog(BuildContext context, {bool showNoteDialogAfter = false}) {
    final nameController = TextEditingController();
    final descriptionController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Row(
          children: [
            Icon(Icons.create_new_folder, color: Theme.of(context).primaryColor),
            const SizedBox(width: 8),
            const Text('Add Notebook'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: 'Notebook Name',
                prefixIcon: Icon(Icons.book),
              ),
              autofocus: true,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: descriptionController,
              decoration: const InputDecoration(
                labelText: 'Description (Optional)',
                prefixIcon: Icon(Icons.description),
              ),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
            },
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (nameController.text.isNotEmpty) {
                // Create notebook through HomeViewModel
                final homeViewModel = context.read<HomeViewModel>();
                try {
                  await homeViewModel.createNotebook(
                    nameController.text,
                    descriptionController.text,
                  );
                  
                  Navigator.pop(context);
                  
                  // Show note dialog after if requested
                  if (showNoteDialogAfter) {
                    Future.delayed(const Duration(milliseconds: 300), () {
                      _showAddNoteDialog(context);
                    });
                  }
                } catch (e) {
                  _logger.error('Error creating notebook', e);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error creating notebook: ${e.toString()}')),
                  );
                  Navigator.pop(context);
                }
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }
}
