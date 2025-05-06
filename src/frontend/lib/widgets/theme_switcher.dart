import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../viewmodel/theme_viewmodel.dart';

class ThemeSwitcher extends StatelessWidget {
  const ThemeSwitcher({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeViewModel>(
      builder: (context, themeViewModel, _) {
        final isDarkMode = themeViewModel.isDarkMode;
        
        return IconButton(
          icon: Icon(
            isDarkMode ? Icons.wb_sunny : Icons.nightlight_round,
            color: Theme.of(context).appBarTheme.iconTheme?.color,
          ),
          tooltip: isDarkMode ? 'Switch to Light Mode' : 'Switch to Dark Mode',
          onPressed: () {
            themeViewModel.toggleTheme();
          },
        );
      },
    );
  }
}
