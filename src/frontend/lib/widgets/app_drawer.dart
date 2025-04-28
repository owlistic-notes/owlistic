import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../core/theme.dart';
import '../viewmodel/auth_viewmodel.dart'; // Use the interface instead of the implementation
import '../utils/logger.dart';

class AppDrawer extends StatelessWidget {
  const AppDrawer({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final logger = Logger('AppDrawer');
    
    // Use AuthViewModel interface instead of concrete AuthProvider class
    final authViewModel = context.watch<AuthViewModel>();
    final user = authViewModel.currentUser;
    
    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: <Widget>[
          UserAccountsDrawerHeader(
            accountName: Text(user?.email?.split('@')[0] ?? 'User'),
            accountEmail: Text(user?.email ?? 'No Email'),
            currentAccountPicture: CircleAvatar(
              backgroundColor: Theme.of(context).colorScheme.secondary,
              child: Text(
                (user?.email?.isEmpty ?? true) ? 'U' : user!.email[0].toUpperCase(),
                style: const TextStyle(fontSize: 24.0),
              ),
            ),
            decoration: BoxDecoration(
              color: Theme.of(context).primaryColor,
            ),
          ),
          ListTile(
            leading: const Icon(Icons.home),
            title: const Text('Home'),
            onTap: () {
              context.go('/');
            },
          ),
          ListTile(
            leading: const Icon(Icons.folder),
            title: const Text('Notebooks'),
            onTap: () {
              logger.debug('Navigating to notebooks');
              Navigator.pop(context); // Close drawer
              context.go('/notebooks');
            },
          ),
          ListTile(
            leading: const Icon(Icons.note),
            title: const Text('Notes'),
            onTap: () {
              logger.debug('Navigating to notes');
              Navigator.pop(context); // Close drawer
              context.go('/notes');
            },
          ),
          ListTile(
            leading: const Icon(Icons.check_circle_outline),
            title: const Text('Tasks'),
            onTap: () {
              logger.debug('Navigating to tasks');
              Navigator.pop(context); // Close drawer
              context.go('/tasks');
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.delete_outline),
            title: const Text('Trash'),
            onTap: () {
              logger.debug('Navigating to trash');
              Navigator.pop(context); // Close drawer
              context.go('/trash');
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.settings),
            title: const Text('Settings'),
            onTap: () {
              logger.debug('Navigating to settings');
              Navigator.pop(context); // Close drawer
              // TODO: Navigate to settings
            },
          ),
          ListTile(
            leading: const Icon(Icons.logout),
            title: const Text('Logout'),
            onTap: () => _showLogoutConfirmation(context),
          ),
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
              
              // Use the AuthViewModel for logout
              final authViewModel = Provider.of<AuthViewModel>(context, listen: false);
              await authViewModel.logout();
              
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
