import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/theme_provider.dart';

class ThemeSwitcher extends StatelessWidget {
  const ThemeSwitcher({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, _) {
        final isDarkMode = themeProvider.isDarkMode;
        
        return IconButton(
          icon: Icon(
            isDarkMode ? Icons.wb_sunny : Icons.nightlight_round,
            color: Theme.of(context).appBarTheme.iconTheme?.color,
          ),
          tooltip: isDarkMode ? 'Light Mode' : 'Dark Mode',
          onPressed: () {
            themeProvider.toggleTheme();
          },
        );
      },
    );
  }
}
