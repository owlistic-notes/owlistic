import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/auth_service.dart';
import '../viewmodel/login_viewmodel.dart';
import '../models/user.dart';
import '../utils/logger.dart';

class LoginProvider with ChangeNotifier implements LoginViewModel {
  final Logger _logger = Logger('LoginProvider');
  final AuthService _authService;
  
  // State
  bool _isLoading = false;
  bool _isActive = false; // For lifecycle management
  bool _isInitialized = false;
  String? _errorMessage;
  
  // Constructor with dependency injection
  LoginProvider({required AuthService authService}) 
      : _authService = authService {
    _isInitialized = true;
  }
  
  // LoginViewModel implementation
  @override
  Future<bool> login(String email, String password, bool rememberMe) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    
    try {
      _logger.info('Attempting login for user: $email');
      
      if (rememberMe) {
        await saveEmail(email);
      }
      
      // Make sure auth service is initialized
      await _authService.initialize();
      
      // Call auth service to perform login
      final response = await _authService.login(email, password);
      final success = response['success'] == true;
      
      if (success) {
        _logger.info('Login successful for user: $email');
      } else {
        _errorMessage = "Authentication failed";
        _logger.error('Login unsuccessful: Authentication failed');
      }
      
      _isLoading = false;
      notifyListeners();
      
      return success;
    } catch (e) {
      _logger.error('Login error', e);
      _errorMessage = e.toString();
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }
  
  @override
  Future<String?> getSavedEmail() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('last_login_email');
    } catch (e) {
      _logger.error('Error getting saved email', e);
      return null;
    }
  }
  
  @override
  Future<void> saveEmail(String email) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('last_login_email', email);
    } catch (e) {
      _logger.error('Error saving email', e);
    }
  }
  
  @override
  Future<void> clearSavedEmail() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('last_login_email');
    } catch (e) {
      _logger.error('Error clearing saved email', e);
    }
  }
  
  @override
  bool get isLoggingIn => _isLoading;
  
  @override
  bool get isLoggedIn => _authService.isLoggedIn;
  
  @override
  Future<User?> get currentUser async {
    try {
      return await _authService.getUserProfile();
    } catch (e) {
      _logger.error('Error getting current user', e);
      return null;
    }
  }
  
  @override
  Stream<bool> get authStateChanges => _authService.authStateChanges;
  
  @override
  void navigateToRegister(BuildContext context) {
    context.go('/register');
  }
  
  @override
  void navigateAfterSuccessfulLogin(BuildContext context) {
    _logger.info('Navigating after successful login');
    context.go('/'); // Navigate to home screen
  }
  
  @override
  void onLoginSuccess(BuildContext context) {
    _logger.info('Login successful, performing post-login actions');
    // Navigate to home screen
    navigateAfterSuccessfulLogin(context);
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
  
  @override
  void activate() {
    _isActive = true;
    _logger.info('LoginProvider activated');
    notifyListeners();
  }
  
  @override
  void deactivate() {
    _isActive = false;
    _logger.info('LoginProvider deactivated');
    notifyListeners();
  }
  
  @override
  void resetState() {
    _errorMessage = null;
    notifyListeners();
  }
}
