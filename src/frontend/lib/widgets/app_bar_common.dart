import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/theme_provider.dart';
import 'search_bar_widget.dart';

class AppBarCommon extends StatefulWidget implements PreferredSizeWidget {
  final String title;
  final VoidCallback? onMenuPressed;
  final VoidCallback? onBackPressed;
  final bool showBackButton;
  final List<Widget> additionalActions;
  final bool automaticallyImplyLeading;
  final Widget? customTitle;

  const AppBarCommon({
    Key? key,
    this.title = 'ThinkStack',
    this.onMenuPressed,
    this.onBackPressed,
    this.showBackButton = true,
    this.additionalActions = const [],
    this.automaticallyImplyLeading = true,
    this.customTitle,
  }) : super(key: key);

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  _AppBarCommonState createState() => _AppBarCommonState();
}

class _AppBarCommonState extends State<AppBarCommon> {
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();

  void _toggleSearch() {
    setState(() {
      _isSearching = !_isSearching;
      if (!_isSearching) {
        _searchController.clear();
      }
    });
  }

  void _handleSearch(String query) {
    // Implement search functionality
    print('Searching for: $query');
  }

  void _showThemeMenu(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    
    showMenu(
      context: context,
      position: RelativeRect.fromLTRB(MediaQuery.of(context).size.width, 0, 0, 0),
      items: [
        PopupMenuItem(
          value: ThemeMode.light,
          child: Row(
            children: [
              Icon(Icons.wb_sunny, 
                color: themeProvider.themeMode == ThemeMode.light 
                  ? Theme.of(context).primaryColor 
                  : null
              ),
              const SizedBox(width: 8),
              const Text('Light Mode'),
              if (themeProvider.themeMode == ThemeMode.light)
                Icon(Icons.check, color: Theme.of(context).primaryColor),
            ],
          ),
        ),
        PopupMenuItem(
          value: ThemeMode.dark,
          child: Row(
            children: [
              Icon(Icons.nightlight_round,
                color: themeProvider.themeMode == ThemeMode.dark 
                  ? Theme.of(context).primaryColor 
                  : null
              ),
              const SizedBox(width: 8),
              const Text('Dark Mode'),
              if (themeProvider.themeMode == ThemeMode.dark)
                Icon(Icons.check, color: Theme.of(context).primaryColor),
            ],
          ),
        ),
      ],
    ).then((value) {
      if (value != null) {
        themeProvider.setThemeMode(value);
      }
    });
  }

  void _showNotificationsMenu(BuildContext context) {
    showMenu(
      context: context,
      position: RelativeRect.fromLTRB(MediaQuery.of(context).size.width, 0, 0, 0),
      items: [
        const PopupMenuItem(
          enabled: false,
          child: ListTile(
            title: Text('Notifications', style: TextStyle(fontWeight: FontWeight.bold)),
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
    showMenu<dynamic>(
      context: context,
      position: RelativeRect.fromLTRB(MediaQuery.of(context).size.width, 0, 0, 0),
      items: <PopupMenuEntry<dynamic>>[
        PopupMenuItem<String>(
          value: 'profile_header',
          child: ListTile(
            leading: CircleAvatar(
              child: const Icon(Icons.person),
              backgroundColor: Theme.of(context).primaryColor.withOpacity(0.1),
            ),
            title: const Text('John Doe'),
            subtitle: const Text('john.doe@example.com'),
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
        const PopupMenuItem<String>(
          value: 'admin',
          child: ListTile(
            leading: Icon(Icons.admin_panel_settings),
            title: Text('Admin Panel'),
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
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);

    return AppBar(
      title: _isSearching 
        ? SearchBarWidget(
            controller: _searchController,
            onChanged: _handleSearch,
            onClear: _toggleSearch,
          )
        : widget.customTitle ?? Text(widget.title),
      automaticallyImplyLeading: false, // Disable default leading widget
      titleSpacing: 0, // Use zero spacing to maximize available space
      leading: _buildLeadingSection(),
      actions: [
        // Search icon/button
        IconButton(
          icon: Icon(_isSearching ? Icons.close : Icons.search),
          onPressed: _toggleSearch,
          tooltip: 'Search',
        ),
        
        // Notifications button
        IconButton(
          icon: const Icon(Icons.notifications_outlined),
          onPressed: () => _showNotificationsMenu(context),
          tooltip: 'Notifications',
        ),
        
        // Theme toggle button
        IconButton(
          icon: Icon(
            themeProvider.themeMode == ThemeMode.light 
              ? Icons.wb_sunny
              : Icons.nightlight_round
          ),
          onPressed: () => _showThemeMenu(context),
          tooltip: 'Change Theme',
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
  
  Widget? _buildLeadingSection() {
    // Build a properly constrained leading section
    if (widget.onMenuPressed != null && widget.showBackButton) {
      // Both menu and back button - use a tight layout
      return Container(
        width: kToolbarHeight * 1.5, // Space for 1.5 buttons
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            // Menu button with smaller padding
            Container(
              width: kToolbarHeight * 0.75,
              child: IconButton(
                icon: const Icon(Icons.menu),
                onPressed: widget.onMenuPressed,
                tooltip: 'Menu',
                padding: EdgeInsets.zero,
                constraints: BoxConstraints(), // Remove constraints
                iconSize: 22, // Slightly smaller icon
              ),
            ),
            // Back button with smaller padding
            Container(
              width: kToolbarHeight * 0.75,
              child: IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: widget.onBackPressed ?? () => Navigator.of(context).pop(),
                tooltip: 'Back',
                padding: EdgeInsets.zero,
                constraints: BoxConstraints(), // Remove constraints
                iconSize: 22, // Slightly smaller icon
              ),
            ),
          ],
        ),
      );
    } else if (widget.onMenuPressed != null) {
      // Only menu button
      return IconButton(
        icon: const Icon(Icons.menu),
        onPressed: widget.onMenuPressed,
        tooltip: 'Menu',
      );
    } else if (widget.showBackButton) {
      // Only back button
      return IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: widget.onBackPressed ?? () => Navigator.of(context).pop(),
        tooltip: 'Back',
      );
    } else {
      // No leading widget
      return null;
    }
  }
}
