import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../core/theme.dart';
import '../viewmodel/home_viewmodel.dart';
import '../utils/logger.dart';

class AppDrawer extends StatelessWidget {
  const AppDrawer({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final logger = Logger('AppDrawer');
    
    // Use HomeViewModel interface instead of concrete AuthProvider class
    final homeViewModel = context.watch<HomeViewModel>();
    final user = homeViewModel.currentUser;
    
    return Drawer(
      child: Column(
        children: [
          // Drawer header with app logo/name
          DrawerHeader(
            decoration: BoxDecoration(
              color: Theme.of(context).primaryColor,
            ),
            child: Center(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.psychology,
                    size: 36,
                    color: Colors.white,
                  ),
                  SizedBox(width: 12),
                  Text(
                    'ThinkStack',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Drawer items
          ListTile(
            leading: const Icon(Icons.home),
            title: const Text('Home'),
            onTap: () {
              Navigator.pop(context);
              GoRouter.of(context).go('/');
            },
          ),
          ListTile(
            leading: const Icon(Icons.book),
            title: const Text('Notebooks'),
            onTap: () {
              Navigator.pop(context);
              GoRouter.of(context).go('/notebooks');
            },
          ),
          ListTile(
            leading: const Icon(Icons.description),
            title: const Text('Notes'),
            onTap: () {
              Navigator.pop(context);
              GoRouter.of(context).go('/notes');
            },
          ),
          ListTile(
            leading: const Icon(Icons.task),
            title: const Text('Tasks'),
            onTap: () {
              Navigator.pop(context);
              GoRouter.of(context).go('/tasks');
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete),
            title: const Text('Trash'),
            onTap: () {
              Navigator.pop(context);
              GoRouter.of(context).go('/trash');
            },
          ),
          Divider(),
          ListTile(
            leading: const Icon(Icons.settings),
            title: const Text('Settings'),
            onTap: () {
              Navigator.pop(context);
              GoRouter.of(context).go('/settings');
            },
          ),
          const Spacer(),
          Divider(),
          ListTile(
            leading: const Icon(Icons.logout),
            title: const Text('Logout'),
            onTap: () async {
              Navigator.pop(context);
              // Use HomeViewModel for logout
              await context.read<HomeViewModel>().logout();
            },
          ),
          SizedBox(height: 16),
        ],
      ),
    );
  }

  void _navigateTo(BuildContext context, String route) {
    Navigator.pop(context); // Close the drawer first
    if (GoRouterState.of(context).matchedLocation != route) {
      context.go(route);
    }
  }

  void _showLogoutConfirmation(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to log out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx); // Close dialog
              Navigator.pop(context); // Close drawer
              
              // Use the HomeViewModel for logout
              await context.read<HomeViewModel>().logout();
              
              // Navigation will be handled by GoRouter redirect
            },
            style: AppTheme.getDangerButtonStyle(),
            child: const Text('Logout'),
          ),
        ],
      ),
    );
  }
}
