import 'package:flutter/material.dart';
import 'package:owlistic/core/theme.dart';
import '../viewmodel/theme_viewmodel.dart';
import '../services/theme_service.dart';
import '../utils/logger.dart';

class ThemeProvider with ChangeNotifier implements ThemeViewModel {
  final Logger _logger = Logger('ThemeProvider');
  final ThemeService? themeService;
  
  // BaseViewModel properties
  bool _isLoading = false;
  bool _isActive = false;
  bool _isInitialized = false;
  String? _errorMessage;
  
  ThemeProvider({this.themeService});
  
  // Default to light mode instead of system
  ThemeMode _themeMode = ThemeMode.light;
  late ThemeData _theme = AppTheme.getThemeData(_themeMode);
  
  // Define consistent theme colors - same for both light and dark
  static final Color _primaryColor = Colors.blue.shade700;
  static final Color _accentColor = Colors.blue.shade400;
  
  @override
  ThemeMode get themeMode => _themeMode;
  
  @override
  ThemeData get theme => _theme;
  
  @override
  bool get isDarkMode => _themeMode == ThemeMode.dark;
  
  // BaseViewModel implementation
  @override
  bool get isLoading => _isLoading;
  
  @override
  bool get isActive => _isActive;
  
  @override
  bool get isInitialized => _isInitialized;
  
  @override
  String? get errorMessage => _errorMessage;
  
  @override
  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }
  
  @override
  void activate() {
    _isActive = true;
    notifyListeners();
  }
  
  @override
  void deactivate() {
    _isActive = false;
    notifyListeners();
  }
  
  @override
  void resetState() {
    // Reset to defaults
    _themeMode = ThemeMode.light;
    _updateTheme();
    notifyListeners();
  }
  
  // Initialize by loading saved preferences
  @override
  Future<void> initialize() async {
    if (themeService != null) {
      try {
        _isLoading = true;
        notifyListeners();
        
        final savedThemeMode = await themeService!.getThemeMode();
        _themeMode = savedThemeMode;
        _updateTheme();
        _logger.info('Theme initialized: $_themeMode');
        _isInitialized = true;
      } catch (e) {
        _logger.error('Error initializing theme', e);
        _errorMessage = 'Failed to load theme preferences';
        // Use default theme mode if there's an error
        _themeMode = ThemeMode.light;
        _updateTheme();
      } finally {
        _isLoading = false;
        notifyListeners();
      }
    } else {
      // No theme service, initialize with defaults
      _updateTheme();
      _isInitialized = true;
      notifyListeners();
    }
  }

  @override
  Future<void> setThemeMode(ThemeMode mode) async {
    // Only accept light or dark mode
    if (mode != ThemeMode.light && mode != ThemeMode.dark) {
      mode = ThemeMode.light;
    }
    
    _themeMode = mode;
    _updateTheme();
    
    try {
      await themeService?.setThemeMode(mode);
      _logger.info('Theme mode set: $mode');
    } catch (e) {
      _logger.error('Error saving theme mode', e);
      _errorMessage = 'Failed to save theme preferences';
    }
    
    notifyListeners();
  }
  
  @override
  Future<void> toggleTheme() async {
    final newMode = isDarkMode ? ThemeMode.light : ThemeMode.dark;
    await setThemeMode(newMode);
  }
  
  @override
  Future<void> setTheme(bool darkMode) async {
    final newMode = darkMode ? ThemeMode.dark : ThemeMode.light;
    await setThemeMode(newMode);
  }
  
  void _updateTheme() {
    if (_themeMode == ThemeMode.dark) {
      _theme = _createDarkTheme();
    } else {
      _theme = _createLightTheme();
    }
  }
  
  // Create a dark theme with blue accents
  ThemeData _createDarkTheme() {
    return ThemeData.dark().copyWith(
      primaryColor: _primaryColor,
      colorScheme: ColorScheme.dark(
        primary: _primaryColor,
        secondary: _accentColor,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: _primaryColor,
        foregroundColor: Colors.white,
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: _primaryColor,
      ),
    );
  }
  
  // Create a light theme with same blue accents but WHITE backgrounds
  ThemeData _createLightTheme() {
    return ThemeData.light().copyWith(
      primaryColor: _primaryColor,
      colorScheme: ColorScheme.light(
        primary: _primaryColor,
        secondary: _accentColor,
      ),
      scaffoldBackgroundColor: Colors.white,
      appBarTheme: AppBarTheme(
        backgroundColor: _primaryColor,
        foregroundColor: Colors.white,
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: _primaryColor,
      ),
    );
  }
}
