import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/theme.dart';
import '../utils/logger.dart';

class ThemeProvider with ChangeNotifier {
  final Logger _logger = Logger('ThemeProvider');
  bool _isDarkMode = false;
  bool _isInitialized = false;
  
  ThemeProvider() {
    _loadThemePreference();
  }
  
  // Getters
  bool get isDarkMode => _isDarkMode;
  ThemeData get theme => _isDarkMode ? AppTheme.darkTheme : AppTheme.lightTheme;
  ThemeMode get themeMode => _isDarkMode ? ThemeMode.dark : ThemeMode.light;
  
  // Load theme preference from shared preferences
  Future<void> _loadThemePreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _isDarkMode = prefs.getBool('isDarkMode') ?? false;
      _isInitialized = true;
      notifyListeners();
      _logger.info('Theme loaded: ${_isDarkMode ? 'dark' : 'light'}');
    } catch (e) {
      _logger.error('Error loading theme preference', e);
      _isInitialized = true;
      notifyListeners();
    }
  }
  
  // Toggle theme between light and dark
  Future<void> toggleTheme() async {
    _isDarkMode = !_isDarkMode;
    notifyListeners();
    
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('isDarkMode', _isDarkMode);
      _logger.info('Theme changed to: ${_isDarkMode ? 'dark' : 'light'}');
    } catch (e) {
      _logger.error('Error saving theme preference', e);
    }
  }
  
  // For compatibility with drawer code
  void toggleThemeMode() {
    toggleTheme();
  }
  
  // Set specific theme mode
  Future<void> setThemeMode(ThemeMode mode) async {
    final newDarkMode = mode == ThemeMode.dark;
    if (_isDarkMode == newDarkMode) return;
    
    _isDarkMode = newDarkMode;
    notifyListeners();
    
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('isDarkMode', _isDarkMode);
      _logger.info('Theme set to: ${_isDarkMode ? 'dark' : 'light'}');
    } catch (e) {
      _logger.error('Error saving theme preference', e);
    }
  }
  
  // Set specific theme
  Future<void> setTheme(bool darkMode) async {
    if (_isDarkMode == darkMode) return;
    
    _isDarkMode = darkMode;
    notifyListeners();
    
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('isDarkMode', _isDarkMode);
      _logger.info('Theme set to: ${_isDarkMode ? 'dark' : 'light'}');
    } catch (e) {
      _logger.error('Error saving theme preference', e);
    }
  }

  
}
