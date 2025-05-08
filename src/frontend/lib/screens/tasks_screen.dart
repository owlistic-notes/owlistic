import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../widgets/app_drawer.dart';
import '../widgets/card_container.dart';
import '../widgets/empty_state.dart';
import '../viewmodel/tasks_viewmodel.dart';
import '../models/task.dart';
import '../core/theme.dart';
import '../widgets/app_bar_common.dart';
import '../utils/logger.dart';
import '../widgets/theme_switcher.dart';

class TasksScreen extends StatefulWidget {
  @override
  _TasksScreenState createState() => _TasksScreenState();
}

class _TasksScreenState extends State<TasksScreen> {
  final Logger _logger = Logger('TasksScreen');
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  bool _isInitialized = false;

  // ViewModel
  late TasksViewModel _tasksViewModel;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    if (!_isInitialized) {
      _isInitialized = true;

      // Get ViewModel
      _tasksViewModel = context.read<TasksViewModel>();

      // Initialize data
      _initializeData();
    }
  }

  Future<void> _initializeData() async {
    try {
      _tasksViewModel.activate();
      await _tasksViewModel.fetchTasks();
    } catch (e) {
      _logger.error('Error initializing TasksScreen', e);
    }
  }

  Future<void> _refreshTasks() async {
    if (!mounted) return;
    
    try {
      await _tasksViewModel.fetchTasks();
    } catch (e) {
      _logger.error('Error refreshing tasks', e);
    }
  }

  void _showAddTaskDialog() {
    final _titleController = TextEditingController();
    String? selectedNoteId;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) {
          final availableNotes = _tasksViewModel.availableNotes;
          
          return AlertDialog(
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
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: _titleController,
                  decoration: const InputDecoration(
                    labelText: 'Task Title',
                    prefixIcon: Icon(Icons.title),
                  ),
                  autofocus: true,
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  decoration: const InputDecoration(
                    labelText: 'Select Note',
                    prefixIcon: Icon(Icons.book),
                  ),
                  value: selectedNoteId,
                  items: [
                    if (availableNotes.isEmpty)
                      const DropdownMenuItem(
                        value: '',
                        child: Text('No notes available'),
                      ),
                    ...availableNotes.map(
                      (note) => DropdownMenuItem(
                        value: note.id,
                        child: Text(note.title),
                      ),
                    ),
                  ],
                  onChanged: (value) {
                    setState(() {
                      selectedNoteId = value;
                    });
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
                  if (_titleController.text.isNotEmpty && selectedNoteId != null) {
                    try {
                      await _tasksViewModel.createTask(_titleController.text, selectedNoteId!);
                      Navigator.of(ctx).pop();
                    } catch (error) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Failed to create task')),
                      );
                    }
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Please enter a title and select a note')),
                    );
                  }
                },
                child: const Text('Create'),
                style: AppTheme.getSuccessButtonStyle(),
              ),
            ],
          );
        }
      ),
    );
  }

  void _showEditTaskDialog(BuildContext context, Task task) {
    final _titleController = TextEditingController(text: task.title);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.edit_note, color: Theme.of(context).primaryColor),
            const SizedBox(width: 8),
            const Text('Edit Task'),
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
                  await _tasksViewModel.updateTaskTitle(task.id, _titleController.text);
                  Navigator.of(ctx).pop();
                } catch (error) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Failed to update task')),
                  );
                }
              }
            },
            child: const Text('Save'),
            style: AppTheme.getSuccessButtonStyle(),
          ),
        ],
      ),
    );
  }

  void _showDeleteConfirmation(BuildContext context, Task task) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Task'),
        content: Text('Are you sure you want to delete "${task.title}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              try {
                await _tasksViewModel.deleteTask(task.id);
              } catch (error) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Failed to delete task')),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBarCommon(
        title: 'Tasks',
        showBackButton: false,
        onMenuPressed: () => _scaffoldKey.currentState?.openDrawer(),
        actions: const [ThemeSwitcher()],
        onBackPressed: () {
          if (Navigator.canPop(context)) {
            Navigator.of(context).pop();
          }
        },
      ),
      drawer: const AppDrawer(),
      body: Consumer<TasksViewModel>(
        builder: (ctx, tasksViewModel, _) {
          if (tasksViewModel.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          
          if (tasksViewModel.tasks.isEmpty) {
            return EmptyState(
              title: 'No tasks yet',
              message: 'Create your first task to stay organized',
              icon: Icons.task_outlined,
              onAction: _showAddTaskDialog,
              actionLabel: 'Create Task',
            );
          }
          
          return RefreshIndicator(
            onRefresh: () => tasksViewModel.fetchTasks(),
            color: Theme.of(context).primaryColor,
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              itemCount: tasksViewModel.tasks.length,
              itemBuilder: (context, index) {
                final task = tasksViewModel.tasks[index];
                return CardContainer(
                  leading: Transform.scale(
                    scale: 1.2,
                    child: Checkbox(
                      value: task.isCompleted,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                      onChanged: (bool? value) async {
                        try {
                          await tasksViewModel.toggleTaskCompletion(
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
                  title: task.title,
                  subtitle: task.description,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit),
                        onPressed: () => _showEditTaskDialog(context, task),
                      ),
                      IconButton(
                        icon: Icon(
                          Icons.delete_outline,
                          color: AppTheme.dangerColor,
                        ),
                        onPressed: () => _showDeleteConfirmation(context, task),
                      ),
                    ],
                  ),
                  child: task.description != null && task.description!.isNotEmpty
                      ? Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            task.description!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        )
                      : const SizedBox.shrink(),
                );
              },
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddTaskDialog,
        child: const Icon(Icons.add),
        tooltip: 'Add Task',
      ),
    );
  }

  @override
  void dispose() {
    if (_isInitialized) {
      _tasksViewModel.deactivate();
    }
    super.dispose();
  }
}
