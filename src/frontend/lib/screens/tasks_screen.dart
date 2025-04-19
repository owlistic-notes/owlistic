import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../widgets/app_drawer.dart';
import '../widgets/card_container.dart';
import '../widgets/empty_state.dart';
import '../providers/notes_provider.dart';
import '../providers/tasks_provider.dart';
import '../models/task.dart';
import '../core/theme.dart';
import '../widgets/app_bar_common.dart';

class TasksScreen extends StatefulWidget {
  @override
  _TasksScreenState createState() => _TasksScreenState();
}

class _TasksScreenState extends State<TasksScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  
  @override
  void initState() {
    super.initState();
    
    // Use post-frame callback instead of microtask
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<TasksProvider>(context, listen: false).fetchTasks();
      Provider.of<NotesProvider>(context, listen: false).fetchNotes();
    });
  }

  void _showAddTaskDialog() {
    final _titleController = TextEditingController();
    String? selectedNoteId;

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
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Note selector dropdown would go here
            const SizedBox(height: 16),
            TextField(
              controller: _titleController,
              decoration: const InputDecoration(
                labelText: 'Task Title',
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
              if (_titleController.text.isNotEmpty) {
                try {
                  final tasksProvider = Provider.of<TasksProvider>(context, listen: false);
                  await tasksProvider.createTask(_titleController.text, selectedNoteId ?? '');
                  Navigator.of(ctx).pop();
                } catch (error) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Failed to create task')),
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
                  final tasksProvider = Provider.of<TasksProvider>(context, listen: false);
                  await tasksProvider.updateTaskTitle(task.id, _titleController.text);
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
                final tasksProvider = Provider.of<TasksProvider>(context, listen: false);
                await tasksProvider.deleteTask(task.id);
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
        onMenuPressed: () => _scaffoldKey.currentState?.openDrawer(),
        onBackPressed: () {
          if (Navigator.canPop(context)) {
            Navigator.of(context).pop();
          }
        },
      ),
      drawer: const AppDrawer(),
      body: Consumer<TasksProvider>(
        builder: (ctx, tasksProvider, _) {
          if (tasksProvider.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          
          if (tasksProvider.tasks.isEmpty) {
            return EmptyState(
              title: 'No tasks yet',
              message: 'Create your first task to stay organized',
              icon: Icons.assignment_outlined,
              onAction: _showAddTaskDialog,
              actionLabel: 'Create Task',
            );
          }
          
          return RefreshIndicator(
            onRefresh: () => tasksProvider.fetchTasks(),
            color: Theme.of(context).primaryColor,
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              itemCount: tasksProvider.tasks.length,
              itemBuilder: (context, index) {
                final task = tasksProvider.tasks[index];
                return CardContainer(
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
}
