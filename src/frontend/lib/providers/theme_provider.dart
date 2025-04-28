import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/theme.dart';
import '../utils/logger.dart';
import '../viewmodel/theme_viewmodel.dart';

class ThemeProvider with ChangeNotifier implements ThemeViewModel {
  final Logger _logger = Logger('ThemeProvider');
  bool _isDarkMode = false;
  bool _isInitialized = false;
  bool _isLoading = false;
  bool _isActive = false;
  String? _errorMessage;
  
  ThemeProvider() {
    _loadThemePreference();
  }
  
  // BaseViewModel implementation
  @override
  bool get isLoading => _isLoading;
  
  @override
  bool get isInitialized => _isInitialized;
  
  @override
  bool get isActive => _isActive;
  
  @override
  String? get errorMessage => _errorMessage;
  
  @override
  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }
  
  // ThemePresenter implementation
  @override
  bool get isDarkMode => _isDarkMode;
  
  @override
  ThemeData get theme => _isDarkMode ? AppTheme.darkTheme : AppTheme.lightTheme;
  
  @override
  ThemeMode get themeMode => _isDarkMode ? ThemeMode.dark : ThemeMode.light;
  
  // Load theme preference from shared preferences
  Future<void> _loadThemePreference() async {
    _isLoading = true;
    
    try {
      final prefs = await SharedPreferences.getInstance();
      _isDarkMode = prefs.getBool('isDarkMode') ?? false;
      _isLoading = false;
      _isInitialized = true;  // Set initialized to true after successful loading
      _logger.info('Theme loaded: ${_isDarkMode ? 'dark' : 'light'}');
      notifyListeners();
    } catch (e) {
      _logger.error('Error loading theme preference', e);
      _isLoading = false;
      _errorMessage = e.toString();
      notifyListeners();
    }
  }
  
  // Toggle theme between light and dark
  @override
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
  @override
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
  @override
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
  
  // BasePresenter implementation
  @override
  void activate() {
    _logger.info('ThemeProvider activated');
    _isActive = true;
    notifyListeners();
  }
  
  @override
  void deactivate() {
    _logger.info('ThemeProvider deactivated');
    _isActive = false;
    notifyListeners();
  }
  
  @override
  void resetState() {
    // Nothing to reset for themes as it's a user preference
  }
}
