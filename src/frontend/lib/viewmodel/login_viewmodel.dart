import 'package:flutter/material.dart';
import 'package:owlistic/models/user.dart';
import 'base_viewmodel.dart';

/// Interface for login functionality
abstract class LoginViewModel extends BaseViewModel {
  /// Login with email and password
  Future<bool> login(String email, String password, bool rememberMe);
  
  /// Get user email if it was previously saved
  Future<String?> getSavedEmail();
  
  /// Save email for future logins
  Future<void> saveEmail(String email);
  
  /// Clear saved email
  Future<void> clearSavedEmail();
  
  /// Check if a login attempt is in progress
  bool get isLoggingIn;
  
  /// Auth state properties - needed for router redirects
  bool get isLoggedIn;
  Future<User?> get currentUser;
  Stream<bool> get authStateChanges;
  
  /// Navigation methods
  void navigateToRegister(BuildContext context);
  
  /// Navigate after successful login - allows screens to navigate properly
  void navigateAfterSuccessfulLogin(BuildContext context);
  
  /// Handle successful login - perform any additional actions needed
  void onLoginSuccess(BuildContext context);
  
  /// Save server URL
  Future<void> saveServerUrl(String url);
  
  /// Get server URL
  String? getServerUrl();
}
