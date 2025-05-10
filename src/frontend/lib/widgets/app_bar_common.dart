import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class AppBarCommon extends StatelessWidget implements PreferredSizeWidget {
  final String? title;
  final List<Widget>? actions;
  final Widget? leading;
  final bool showBackButton;
  final VoidCallback? onBackPressed;
  final VoidCallback? onMenuPressed;
  final double elevation;
  final bool centerTitle;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final bool showProfileButton;
  
  const AppBarCommon({
    Key? key,
    this.title,
    this.actions,
    this.leading,
    this.showBackButton = true,
    this.onBackPressed,
    this.onMenuPressed,
    this.elevation = 0,
    this.centerTitle = true,
    this.backgroundColor,
    this.foregroundColor,
    this.showProfileButton = true,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    Widget? leadingWidget = leading;
    
    // If leading is not provided and showBackButton is true, show back button
    if (leading == null) {
      if (showBackButton) {
        leadingWidget = IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: onBackPressed ?? () => Navigator.of(context).pop(),
        );
      } else if (onMenuPressed != null) {
        // Show menu button if onMenuPressed callback is provided
        leadingWidget = IconButton(
          icon: const Icon(Icons.menu),
          onPressed: onMenuPressed,
        );
      }
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
      title: title != null ? Text(title!) : null,
      centerTitle: centerTitle,
      elevation: elevation,
      backgroundColor: backgroundColor,
      foregroundColor: foregroundColor,
      leading: leadingWidget,
      actions: actionWidgets,
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}
