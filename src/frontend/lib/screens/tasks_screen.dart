import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:owlistic/widgets/app_drawer.dart';
import 'package:owlistic/widgets/empty_state.dart';
import 'package:owlistic/viewmodel/tasks_viewmodel.dart';
import 'package:owlistic/models/task.dart';
import 'package:owlistic/core/theme.dart';
import 'package:owlistic/widgets/app_bar_common.dart';
import 'package:owlistic/utils/logger.dart';
import 'package:owlistic/widgets/theme_switcher.dart';

class TasksScreen extends StatefulWidget {
  const TasksScreen({super.key});

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

  void _showAddTaskDialog() {
    final titleController = TextEditingController();
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
                  controller: titleController,
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
                  if (titleController.text.isNotEmpty && selectedNoteId != null) {
                    try {
                      await _tasksViewModel.createTask(titleController.text, selectedNoteId!);
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
                style: AppTheme.getSuccessButtonStyle(),
                child: const Text('Create'),
              ),
            ],
          );
        }
      ),
    );
  }

  void _showEditTaskDialog(BuildContext context, Task task) {
    final titleController = TextEditingController(text: task.title);

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
          controller: titleController,
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
              if (titleController.text.isNotEmpty) {
                try {
                  await _tasksViewModel.updateTaskTitle(task.id, titleController.text);
                  Navigator.of(ctx).pop();
                } catch (error) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Failed to update task')),
                  );
                }
              }
            },
            style: AppTheme.getSuccessButtonStyle(),
            child: const Text('Save'),
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
      drawer: const SidebarDrawer(),
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
                return _buildTaskCard(context, task, tasksViewModel);
              },
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddTaskDialog,
        tooltip: 'Add Task',
        child: const Icon(Icons.add),
      ),
    );
  }
  
  Widget _buildTaskCard(BuildContext context, Task task, TasksViewModel tasksViewModel) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 8.0),
        leading: Transform.scale(
          scale: 1.2,
          child: Checkbox(
            value: task.isCompleted,
            shape: const CircleBorder(),
            checkColor: Colors.white,
            activeColor: Theme.of(context).primaryColor,
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
        title: Text(
          task.title,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w500,
            decoration: task.isCompleted ? TextDecoration.lineThrough : null,
            color: task.isCompleted ? Colors.grey : Theme.of(context).textTheme.bodyLarge?.color,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (task.description?.isNotEmpty == true)
              Padding(
                padding: const EdgeInsets.only(top: 2.0),
                child: Text(
                  task.description!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
                  ),
                ),
              ),
            const SizedBox(height: 4),
            // Placeholder for future task metadata (due date, etc.)
            Row(
              children: [
                Icon(Icons.calendar_today, size: 14, color: Theme.of(context).hintColor),
                const SizedBox(width: 4),
                // This will be replaced with actual due date when available
                Text(
                  'No due date',
                  style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor),
                ),
                const SizedBox(width: 12),
                // Placeholder for other metadata (priority, etc.)
                Icon(Icons.flag_outlined, size: 14, color: Theme.of(context).hintColor),
                const SizedBox(width: 4),
                Text(
                  'No priority',
                  style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor),
                ),
              ],
            ),
          ],
        ),
        trailing: PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert, size: 20),
          splashRadius: 20,
          onSelected: (value) {
            if (value == 'edit') {
              _showEditTaskDialog(context, task);
            } else if (value == 'delete') {
              _showDeleteConfirmation(context, task);
            }
          },
          itemBuilder: (BuildContext context) => [
            const PopupMenuItem<String>(
              value: 'edit',
              child: ListTile(
                leading: Icon(Icons.edit),
                title: Text('Edit Task'),
                contentPadding: EdgeInsets.zero,
                dense: true,
                visualDensity: VisualDensity.compact,
              ),
            ),
            const PopupMenuItem<String>(
              value: 'delete',
              child: ListTile(
                leading: Icon(Icons.delete_outline, color: Colors.red),
                title: Text('Delete Task', style: TextStyle(color: Colors.red)),
                contentPadding: EdgeInsets.zero,
                dense: true,
                visualDensity: VisualDensity.compact,
              ),
            ),
          ],
        ),
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
