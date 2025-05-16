import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:owlistic/utils/logger.dart';

class ThemeService {
  final Logger _logger = Logger('ThemeService');
  static const String _themeKey = 'app_theme_mode';
  
  // Get theme mode from preferences
  Future<ThemeMode> getThemeMode() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final themeModeString = prefs.getString(_themeKey);
      
      if (themeModeString == null) {
        return ThemeMode.system;
      }
      
      switch (themeModeString) {
        case 'light':
          return ThemeMode.light;
        case 'dark':
          return ThemeMode.dark;
        default:
          return ThemeMode.system;
      }
    } catch (e) {
      _logger.error('Error getting theme mode', e);
      return ThemeMode.system;
    }
  }
  
  // Save theme mode preference
  Future<void> setThemeMode(ThemeMode mode) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      String themeModeString;
      
      switch (mode) {
        case ThemeMode.light:
          themeModeString = 'light';
          break;
        case ThemeMode.dark:
          themeModeString = 'dark';
          break;
        default:
          themeModeString = 'system';
      }
      
      await prefs.setString(_themeKey, themeModeString);
      _logger.debug('Theme mode set to: $themeModeString');
    } catch (e) {
      _logger.error('Error saving theme mode', e);
    }
  }
}
