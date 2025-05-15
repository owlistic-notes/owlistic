import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:owlistic/viewmodel/theme_viewmodel.dart';

/// A widget that provides a button to toggle between light and dark themes
class ThemeSwitcher extends StatelessWidget {
  final double? size;
  final EdgeInsets padding;
  
  const ThemeSwitcher({
    Key? key,
    this.size,
    this.padding = const EdgeInsets.all(8.0),
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeViewModel>(
      builder: (context, themeViewModel, _) {
        return IconButton(
          padding: padding,
          icon: Icon(
            themeViewModel.isDarkMode 
              ? Icons.light_mode
              : Icons.nightlight_round,
            size: size,
          ),
          onPressed: () {
            themeViewModel.toggleTheme();
          },
          tooltip: themeViewModel.isDarkMode 
              ? 'Switch to Light Theme' 
              : 'Switch to Dark Theme',
        );
      },
    );
  }
}
