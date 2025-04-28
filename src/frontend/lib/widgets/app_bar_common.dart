import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:thinkstack/core/theme.dart';
import '../viewmodel/auth_viewmodel.dart';

class AppBarCommon extends StatefulWidget implements PreferredSizeWidget {
  final String title;
  final VoidCallback? onMenuPressed;
  final VoidCallback? onBackPressed;
  final bool showBackButton;
  final List<Widget> additionalActions;
  final bool automaticallyImplyLeading;
  final Widget? customTitle;
  final Widget? titleEditAction;

  const AppBarCommon({
    Key? key,
    this.title = 'ThinkStack',
    this.onMenuPressed,
    this.onBackPressed,
    this.showBackButton = true,
    this.additionalActions = const [],
    this.automaticallyImplyLeading = true,
    this.customTitle,
    this.titleEditAction,
  }) : super(key: key);

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  _AppBarCommonState createState() => _AppBarCommonState();
}

class _AppBarCommonState extends State<AppBarCommon> {
  void _showNotificationsMenu(BuildContext context) {
    showMenu(
      context: context,
      position: RelativeRect.fromLTRB(MediaQuery.of(context).size.width, 0, 0, 0),
      items: [
        const PopupMenuItem(
          enabled: false,
          child: ListTile(
            title: Text('Notifications',
                style: TextStyle(fontWeight: FontWeight.bold)),
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
    final authViewModel = context.read<AuthViewModel>();
    final user = authViewModel.currentUser;

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
            title: Text(user?.email?.split('@')[0] ?? 'User'),
            subtitle: Text(user?.email ?? 'user@example.com'),
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
        const PopupMenuDivider(),
        const PopupMenuItem<String>(
          value: 'logout',
          child: ListTile(
            leading: Icon(Icons.logout),
            title: Text('Logout'),
          ),
        ),
      ],
    ).then((value) async {
      if (value == 'logout') {
        // Show confirmation dialog before logout
        final confirm = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Logout'),
            content: const Text('Are you sure you want to logout?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: AppTheme.getDangerButtonStyle(),
                child: const Text('Logout'),
              ),
            ],
          ),
        );

        // If user confirmed, perform logout
        if (confirm == true && context.mounted) {
          await authViewModel.logout();
          // Navigation is handled by GoRouter redirect
        }
      }
      // Handle other menu options here
    });
  }

  @override
  Widget build(BuildContext context) {
    return AppBar(
      title: widget.customTitle ?? 
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(child: Text(widget.title)),
                  if (widget.titleEditAction != null) widget.titleEditAction!,
                ],
              ),
      titleSpacing: 8.0,
      automaticallyImplyLeading: false,
      leading: Container(
        margin: const EdgeInsets.only(left: 8.0),
        child: IconButton(
          icon: const Icon(Icons.menu),
          onPressed: widget.onMenuPressed,
          tooltip: 'Menu',
          padding: const EdgeInsets.all(8.0),
        ),
      ),
      actions: [
        // Notifications button
        IconButton(
          icon: const Icon(Icons.notifications_outlined),
          onPressed: () => _showNotificationsMenu(context),
          tooltip: 'Notifications',
        ),

        // Profile button
        IconButton(
          icon: const Icon(Icons.person_outline),
          onPressed: () => _showProfileMenu(context),
          tooltip: 'Profile',
        ),

        // Additional custom actions
        ...widget.additionalActions,
      ],
    );
  }
}
