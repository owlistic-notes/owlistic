import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class AppBarCommon extends StatelessWidget implements PreferredSizeWidget {
  final String? title;
  final List<Widget>? actions;
  final bool showBackButton;
  final VoidCallback? onBackPressed;
  final VoidCallback? onMenuPressed;
  final double elevation;
  final bool centerTitle;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final bool showProfileButton;
  final bool showUndoRedoButtons;

  const AppBarCommon({
    Key? key,
    this.title,
    this.actions,
    this.showBackButton = true,
    this.onBackPressed,
    this.onMenuPressed,
    this.elevation = 0,
    this.centerTitle = true,
    this.backgroundColor,
    this.foregroundColor,
    this.showProfileButton = true,
    this.showUndoRedoButtons = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    List<Widget>? leadingWidgets = [];
    
    if (onMenuPressed != null) {
      // Show menu button if onMenuPressed callback is provided
      leadingWidgets.add(IconButton(
        icon: const Icon(Icons.menu),
        onPressed: onMenuPressed,
      ));
    }
    
    if (showBackButton) {
      leadingWidgets.add(IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: onBackPressed ?? () => Navigator.of(context).pop(),
      ));
    } 
    
    // Create a copy of the actions list to modify if needed
    List<Widget>? actionWidgets = actions != null ? List<Widget>.from(actions!) : [];

    // Add profile button to actions if showProfileButton is true
    if (showProfileButton) {
      actionWidgets.add(
        IconButton(
          icon: const Icon(Icons.account_circle),
          tooltip: 'Profile',
          onPressed: () {
            // Navigate to profile page
            context.go('/profile');
          },
        ),
      );
    }
    
    return AppBar(
      leading: Builder(builder: (context) => Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: leadingWidgets,
        ),
      ),
      actions: actionWidgets,
      title: title != null ? Text(title!) : null,
      centerTitle: centerTitle,
      elevation: elevation,
      backgroundColor: backgroundColor,
      foregroundColor: foregroundColor,
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}
