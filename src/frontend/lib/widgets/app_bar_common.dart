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
  final Widget? titleEditAction; // New parameter for edit action next to title

  const AppBarCommon({
    Key? key,
    this.title = 'ThinkStack',
    this.onMenuPressed,
    this.onBackPressed,
    this.showBackButton = true,
    this.additionalActions = const [],
    this.automaticallyImplyLeading = true,
    this.customTitle,
    this.titleEditAction, // Add new parameter
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
    
    // Check if we're in the note editor screen
    final isNoteEditor = ModalRoute.of(context)?.settings.name?.contains('note_editor') == true || 
                        _isInNoteEditorScreen(context);

    return AppBar(
      title: _isSearching && !isNoteEditor
        ? SearchBarWidget(
            controller: _searchController,
            onChanged: _handleSearch,
            onClear: _toggleSearch,
          )
        : widget.customTitle ?? Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(child: Text(widget.title)),
              if (widget.titleEditAction != null)
                widget.titleEditAction!,
            ],
          ),
      titleSpacing: widget.onMenuPressed != null || widget.showBackButton ? 8.0 : 16.0,
      automaticallyImplyLeading: false,
      leading: Container(
        margin: const EdgeInsets.only(left: 8.0),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Menu button (hamburger) - always shown if provided
            if (widget.onMenuPressed != null)
              IconButton(
                icon: const Icon(Icons.menu),
                onPressed: widget.onMenuPressed,
                tooltip: 'Menu',
                padding: const EdgeInsets.all(8.0),
              ),
            
            // Back button - only shown if showBackButton is true
            if (widget.showBackButton)
              IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: widget.onBackPressed ?? () {
                  // Fix navigation by checking mounted state
                  if (Navigator.canPop(context)) {
                    Navigator.of(context).pop();
                  }
                },
                tooltip: 'Back',
                padding: const EdgeInsets.all(8.0),
              ),
          ],
        ),
      ),
      leadingWidth: _calculateLeadingWidth(),
      actions: [
        // Hide search icon in Note Editor screen
        if (!isNoteEditor)
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
  
  // Helper method to check if we're in the note editor screen
  bool _isInNoteEditorScreen(BuildContext context) {
    // Check the current route for NoteEditorScreen
    final currentRoute = ModalRoute.of(context);
    if (currentRoute != null) {
      // Check route settings 
      final settings = currentRoute.settings;
      
      // Check route name
      if (settings.name?.contains('note_editor') == true) {
        return true;
      }
      
      // Check route builder arguments
      if (settings.arguments is Map) {
        final args = settings.arguments as Map;
        if (args.containsKey('isNoteEditor') && args['isNoteEditor'] == true) {
          return true;
        }
      }
      
      // Check if current route is MaterialPageRoute with NoteEditorScreen
      if (currentRoute is MaterialPageRoute) {
        return currentRoute.builder.toString().contains('NoteEditorScreen');
      }
    }
    
    return false;
  }
  
  // Calculate appropriate leading width based on visible buttons
  double _calculateLeadingWidth() {
    double width = 8.0;  // Initial left margin
    
    // Add width for menu button if present
    if (widget.onMenuPressed != null) {
      width += 48.0;  // Standard IconButton width with padding
    }
    
    // Add width for back button if visible
    if (widget.showBackButton) {
      width += 48.0;  // Standard IconButton width with padding
    }
    
    return width;
  }
}
