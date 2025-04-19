import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../core/theme.dart';
import 'package:provider/provider.dart';
import '../providers/theme_provider.dart';

class AppDrawer extends StatelessWidget {
  const AppDrawer({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDarkMode;

    return Drawer(
      child: Column(
        children: [
          _buildHeader(context),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                _buildMenuItem(
                  context, 
                  title: 'Home', 
                  icon: Icons.home_outlined, 
                  route: '/',
                ),
                _buildMenuItem(
                  context, 
                  title: 'Notebooks', 
                  icon: Icons.folder_outlined, 
                  route: '/notebooks',
                ),
                _buildMenuItem(
                  context, 
                  title: 'Notes', 
                  icon: Icons.description_outlined, 
                  route: '/notes',
                ),
                _buildMenuItem(
                  context, 
                  title: 'Tasks', 
                  icon: Icons.check_circle_outline, 
                  route: '/tasks',
                ),
                const Divider(),
                _buildMenuItem(
                  context, 
                  title: 'Tags', 
                  icon: Icons.tag_outlined, 
                  route: '/tags',
                ),
                _buildMenuItem(
                  context, 
                  title: 'Archive', 
                  icon: Icons.archive_outlined, 
                  route: '/archive',
                ),
                _buildMenuItem(
                  context, 
                  title: 'Trash', 
                  icon: Icons.delete_outline, 
                  route: '/trash',
                ),
                const Divider(),
                _buildMenuItem(
                  context, 
                  title: 'Settings', 
                  icon: Icons.settings_outlined, 
                  route: '/settings',
                ),
                _buildMenuItem(
                  context, 
                  title: 'About', 
                  icon: Icons.info_outline, 
                  route: '/about',
                ),
              ],
            ),
          ),
          // Add theme toggle at the bottom
          _buildThemeToggle(context),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      height: 156, // Adjusted from 160px to 156px to fix overflow
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: Theme.of(context).primaryColor,
      ),
      alignment: Alignment.bottomLeft,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            backgroundColor: Colors.white.withOpacity(0.2),
            radius: 30, // Reduced from 32 to 30
            child: const Icon(
              Icons.person,
              size: 36, // Reduced from 40 to 36
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 10), // Reduced from 12 to 10
          const Text(
            'ThinkStack',
            style: TextStyle(
              color: Colors.white,
              fontSize: 22, // Reduced from 24 to 22
              fontWeight: FontWeight.bold,
            ),
          ),
          const Text(
            'Your knowledge stack',
            style: TextStyle(
              color: Colors.white70,
              fontWeight: FontWeight.w300,
              fontSize: 13, // Added explicit font size
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMenuItem(
    BuildContext context, {
    required String title,
    required IconData icon,
    required String route,
  }) {
    // Determine if this is the active route
    final isCurrent = GoRouterState.of(context).path == route;
    
    return ListTile(
      leading: Icon(
        icon,
        color: isCurrent 
          ? Theme.of(context).primaryColor 
          : null,
      ),
      title: Text(
        title,
        style: TextStyle(
          color: isCurrent 
            ? Theme.of(context).primaryColor 
            : null,
          fontWeight: isCurrent 
            ? FontWeight.bold 
            : null,
        ),
      ),
      selected: isCurrent,
      onTap: () {
        // Close drawer before navigation
        Navigator.pop(context);
        
        // Navigate to the selected route
        if (GoRouterState.of(context).path != route) {
          context.go(route);
        }
      },
    );
  }
  
  // New method to build the theme toggle at the bottom of the drawer
  Widget _buildThemeToggle(BuildContext context) {
    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, _) {
        final isDarkMode = themeProvider.themeMode == ThemeMode.dark;
        
        return Container(
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(
                color: Theme.of(context).dividerColor,
                width: 0.5,
              ),
            ),
          ),
          child: ListTile(
            leading: Icon(
              isDarkMode ? Icons.nightlight_round : Icons.wb_sunny,
            ),
            title: Text(
              isDarkMode ? 'Dark Mode' : 'Light Mode'
            ),
            trailing: Switch(
              value: isDarkMode,
              onChanged: (_) => themeProvider.toggleThemeMode(),
            ),
            onTap: () => themeProvider.toggleThemeMode(),
          ),
        );
      },
    );
  }
}
