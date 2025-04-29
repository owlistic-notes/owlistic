import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../services/auth_service.dart';
import '../viewmodel/register_viewmodel.dart';
import '../models/user.dart';
import '../utils/logger.dart';

class RegisterProvider with ChangeNotifier implements RegisterViewModel {
  final Logger _logger = Logger('RegisterProvider');
  final AuthService _authService;
  
  // State
  bool _isLoading = false;
  bool _isActive = false;
  bool _isInitialized = false;
  String? _errorMessage;
  
  // Constructor with dependency injection
  RegisterProvider({required AuthService authService})
      : _authService = authService {
    _isInitialized = true;
  }
  
  // RegisterViewModel implementation
  @override
  Future<bool> register(String email, String password) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    
    try {
      final success = await _authService.register(email, password);
      
      // If registration succeeded, automatically log them in
      if (success) {
        await _authService.login(email, password);
      }
      
      _isLoading = false;
      notifyListeners();
      return success;
    } catch (e) {
      _logger.error('Registration error', e);
      _errorMessage = e.toString();
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }
  
  @override
  bool get isRegistering => _isLoading;
  
  // Auth state properties - delegated to AuthService
  @override
  bool get isLoggedIn => _authService.isLoggedIn;
  
  @override
  Future<User?> get currentUser async {
    try {
      final token = await _authService.getStoredToken();
      if (token != null) {
        return await _authService.getUserProfile();
      }
    } catch (e) {
      _logger.error('Error getting current user', e);
    }
    return null;
  }
  
  @override
  Stream<bool> get authStateChanges => _authService.authStateChanges;
  
  @override
  void navigateToLogin(BuildContext context) {
    context.go('/login');
  }
  
  // New navigation methods
  @override
  void navigateAfterSuccessfulRegistration(BuildContext context) {
    _logger.info('Navigating after successful registration');
    context.go('/'); // Navigate to home screen
  }
  
  @override
  void onRegistrationSuccess(BuildContext context) {
    _logger.info('Registration successful, performing post-registration actions');
    // Any additional actions needed after successful registration
    
    // Navigate to home screen
    navigateAfterSuccessfulRegistration(context);
  }
  
  @override
  bool isValidEmail(String email) {
    return RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(email);
  }
  
  @override
  bool isValidPassword(String password) {
    // Minimum 6 characters
    return password.length >= 6;
  }
  
  @override
  bool doPasswordsMatch(String password, String confirmPassword) {
    return password == confirmPassword;
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
    _logger.info('RegisterProvider activated');
    notifyListeners();
  }
  
  @override
  void deactivate() {
    _isActive = false;
    _logger.info('RegisterProvider deactivated');
    notifyListeners();
  }
  
  @override
  void resetState() {
    _errorMessage = null;
    notifyListeners();
  }
}
