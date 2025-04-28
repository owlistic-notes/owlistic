import 'package:flutter/material.dart';
import 'base_viewmodel.dart';

/// Interface for theme management functionality
abstract class ThemeViewModel extends BaseViewModel {
  /// Dark mode state
  bool get isDarkMode;
  
  /// Get the current theme data
  ThemeData get theme;
  
  /// Get the theme mode
  ThemeMode get themeMode;
  
  /// Toggle between light and dark theme
  Future<void> toggleTheme();
  
  /// Set a specific theme mode
  Future<void> setThemeMode(ThemeMode mode);
  
  /// Set theme by dark mode value
  Future<void> setTheme(bool darkMode);
}
