import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../providers/websocket_provider.dart';
import '../providers/theme_provider.dart';
import '../core/theme.dart';
import 'theme_switcher.dart';

class AppDrawer extends StatelessWidget {
  const AppDrawer({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDark = context.isDarkMode;

    return Drawer(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      elevation: 2,
      child: SafeArea(
        child: Column(
          children: [
            _buildHeader(context),
            const Divider(height: 1),
            _buildMenuItem(
              context,
              icon: Icons.home_outlined,
              title: 'Home',
              route: '/',
            ),
            _buildMenuItem(
              context,
              icon: Icons.book_outlined,
              title: 'Notebooks',
              route: '/notebooks',
            ),
            _buildMenuItem(
              context,
              icon: Icons.note_outlined,
              title: 'Notes',
              route: '/notes',
            ),
            _buildMenuItem(
              context,
              icon: Icons.task_outlined,
              title: 'Tasks',
              route: '/tasks',
            ),
            const Divider(height: 1),
            const SizedBox(height: 8),
            _buildSyncStatus(context),
            const Spacer(),
            _buildBottomActions(context),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: Theme.of(context).primaryColor,
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.auto_awesome,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'ThinkStack',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  'Your connected workspace',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white70,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMenuItem(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String route,
  }) {
    final isSelected = GoRouterState.of(context).matchedLocation == route;
    final theme = Theme.of(context);
    
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: isSelected ? theme.primaryColor.withOpacity(0.1) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
      ),
      child: ListTile(
        leading: Icon(
          icon,
          color: isSelected ? theme.primaryColor : theme.iconTheme.color,
        ),
        title: Text(
          title,
          style: TextStyle(
            fontSize: 15,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
            color: isSelected ? theme.primaryColor : theme.textTheme.bodyLarge?.color,
          ),
        ),
        dense: true,
        visualDensity: const VisualDensity(horizontal: -1, vertical: -1),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        onTap: () {
          context.go(route);
          Navigator.pop(context); // Close drawer
        },
      ),
    );
  }

  Widget _buildSyncStatus(BuildContext context) {
    final wsProvider = Provider.of<WebSocketProvider>(context);
    final statusColor = wsProvider.isConnected ? Colors.green : Colors.orange;
    final statusText = wsProvider.isConnected ? 'Connected' : 'Disconnected';
    
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: statusColor,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            statusText,
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).textTheme.bodySmall?.color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomActions(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Theme switcher
          const ThemeSwitcher(),
          
          // WebSocket reconnect
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () async {
              Navigator.pop(context);
              final wsProvider = Provider.of<WebSocketProvider>(context, listen: false);
              await wsProvider.reconnect();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    wsProvider.isConnected 
                      ? 'WebSocket reconnected!' 
                      : 'WebSocket reconnection failed'
                  ),
                ),
              );
            },
            tooltip: 'Reconnect WebSocket',
          ),
          
          // Help button
          IconButton(
            icon: const Icon(Icons.help_outline),
            onPressed: () {},
            tooltip: 'Help',
          ),
        ],
      ),
    );
  }
}
