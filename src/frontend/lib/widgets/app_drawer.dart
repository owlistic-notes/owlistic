import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/theme_provider.dart';

class AppDrawer extends StatelessWidget {
  const AppDrawer({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final email = authProvider.currentUser?.email ?? '';
    final username = email.isNotEmpty ? email.split('@').first : 'User';

    return Drawer(
      child: Column(
        children: [
          UserAccountsDrawerHeader(
            accountName: Text(username),
            accountEmail: Text(email),
            currentAccountPicture: CircleAvatar(
              backgroundColor: Theme.of(context).brightness == Brightness.dark
                  ? Colors.white24
                  : Theme.of(context).primaryColor.withOpacity(0.2),
              child: const Icon(Icons.person, size: 40),
            ),
            decoration: BoxDecoration(
              color: Theme.of(context).primaryColor,
            ),
          ),
          _buildNavItem(
            context,
            icon: Icons.home,
            title: 'Home',
            route: '/',
          ),
          _buildNavItem(
            context,
            icon: Icons.folder,
            title: 'Notebooks',
            route: '/notebooks',
          ),
          _buildNavItem(
            context,
            icon: Icons.description,
            title: 'Notes',
            route: '/notes',
          ),
          _buildNavItem(
            context,
            icon: Icons.check_circle_outline,
            title: 'Tasks',
            route: '/tasks',
          ),
          _buildNavItem(
            context,
            icon: Icons.delete_outline,
            title: 'Trash',
            route: '/trash',
          ),
          const Divider(),
          _buildThemeSwitcher(context),
          const Spacer(),
          _buildLogoutButton(context, authProvider),
        ],
      ),
    );
  }

  Widget _buildNavItem(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String route,
  }) {
    final currentRoute = GoRouterState.of(context).matchedLocation;
    final isActive = currentRoute.startsWith(route) && 
                    (route != '/' || currentRoute == '/');

    return ListTile(
      leading: Icon(
        icon,
        color: isActive ? Theme.of(context).primaryColor : null,
      ),
      title: Text(
        title,
        style: TextStyle(
          color: isActive ? Theme.of(context).primaryColor : null,
          fontWeight: isActive ? FontWeight.bold : null,
        ),
      ),
      onTap: () {
        Navigator.pop(context); // Close drawer
        if (currentRoute != route) {
          context.go(route);
        }
      },
    );
  }

  Widget _buildThemeSwitcher(BuildContext context) {
    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, _) {
        final isDarkMode = themeProvider.isDarkMode;
        return ListTile(
          leading: Icon(
            isDarkMode ? Icons.nightlight_round : Icons.wb_sunny,
          ),
          title: Text('${isDarkMode ? 'Dark' : 'Light'} Mode'),
          trailing: Switch(
            value: isDarkMode,
            activeColor: Theme.of(context).primaryColor,
            onChanged: (value) => themeProvider.setTheme(value),
          ),
        );
      },
    );
  }

  Widget _buildLogoutButton(BuildContext context, AuthProvider authProvider) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: ElevatedButton.icon(
        onPressed: () async {
          Navigator.pop(context); // Close drawer
          try {
            await authProvider.logout();
          } catch (e) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Error logging out')),
            );
          }
        },
        icon: const Icon(Icons.logout),
        label: const Text('Logout'),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.red,
          foregroundColor: Colors.white,
          minimumSize: const Size(double.infinity, 48),
        ),
      ),
    );
  }
}
