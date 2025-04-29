import 'package:flutter/material.dart';
import '../models/user.dart';
import 'base_viewmodel.dart';

/// Interface for user registration functionality
abstract class RegisterViewModel extends BaseViewModel {
  /// Register a new user
  Future<bool> register(String email, String password);
  
  /// Check if a registration attempt is in progress
  bool get isRegistering;
  
  /// Auth state properties - needed for router redirects
  bool get isLoggedIn;
  Future<User?> get currentUser;
  Stream<bool> get authStateChanges;
  
  /// Navigation helper to login screen
  void navigateToLogin(BuildContext context);
  
  /// Navigate after successful registration - allows screens to navigate properly
  void navigateAfterSuccessfulRegistration(BuildContext context);
  
  /// Handle successful registration - perform any additional actions needed
  void onRegistrationSuccess(BuildContext context);
  
  /// Validate email format
  bool isValidEmail(String email);
  
  /// Validate password strength
  bool isValidPassword(String password);
  
  /// Check if passwords match
  bool doPasswordsMatch(String password, String confirmPassword);
}
