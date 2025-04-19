import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/logger.dart';

class ThemeProvider with ChangeNotifier {
  final Logger _logger = Logger('ThemeProvider');
  ThemeMode _themeMode = ThemeMode.system;
  static const String _themeModeKey = 'theme_mode';

  ThemeMode get themeMode => _themeMode;

  ThemeProvider() {
    _loadThemePreference();
  }

  // Load saved theme preference
  Future<void> _loadThemePreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedThemeMode = prefs.getString(_themeModeKey);
      if (savedThemeMode != null) {
        _themeMode = _parseThemeMode(savedThemeMode);
        notifyListeners();
      }
    } catch (e) {
      _logger.error('Failed to load theme preference', e);
    }
  }

  // Save theme preference
  Future<void> _saveThemePreference(ThemeMode mode) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_themeModeKey, mode.toString());
    } catch (e) {
      _logger.error('Failed to save theme preference', e);
    }
  }

  // Set theme mode
  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    await _saveThemePreference(mode);
    notifyListeners();
  }

  // Toggle between light, dark and system
  Future<void> toggleThemeMode() async {
    switch (_themeMode) {
      case ThemeMode.light:
        await setThemeMode(ThemeMode.dark);
        break;
      case ThemeMode.dark:
        await setThemeMode(ThemeMode.system);
        break;
      case ThemeMode.system:
        await setThemeMode(ThemeMode.light);
        break;
    }
  }

  // Parse theme mode from string
  ThemeMode _parseThemeMode(String value) {
    if (value == 'ThemeMode.dark') return ThemeMode.dark;
    if (value == 'ThemeMode.light') return ThemeMode.light;
    return ThemeMode.system;
  }

  // Get theme mode name for display
  String getThemeModeName() {
    switch (_themeMode) {
      case ThemeMode.light:
        return 'Light';
      case ThemeMode.dark:
        return 'Dark';
      case ThemeMode.system:
        return 'System';
    }
  }

  // Get theme mode icon
  IconData getThemeModeIcon() {
    switch (_themeMode) {
      case ThemeMode.light:
        return Icons.wb_sunny;
      case ThemeMode.dark:
        return Icons.nightlight_round;
      case ThemeMode.system:
        return Icons.brightness_auto;
    }
  }
}
