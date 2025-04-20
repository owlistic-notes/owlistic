import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/theme_provider.dart';

class ThemeSwitcher extends StatelessWidget {
  final bool showIcon;
  final bool showLabel;
  
  const ThemeSwitcher({
    Key? key,
    this.showIcon = true,
    this.showLabel = true,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, _) {
        return IconButton(
          tooltip: themeProvider.isDarkMode 
            ? 'Switch to light theme' 
            : 'Switch to dark theme',
          onPressed: () => themeProvider.toggleThemeMode(),
          icon: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (showIcon)
                Icon(themeProvider.isDarkMode 
                  ? Icons.light_mode 
                  : Icons.dark_mode),
              if (showIcon && showLabel)
                const SizedBox(width: 8),
              if (showLabel)
                Text(themeProvider.isDarkMode ? 'Light Mode' : 'Dark Mode'),
            ],
          ),
        );
      },
    );
  }
}
