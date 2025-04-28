import '../models/user.dart';
import 'base_viewmodel.dart';

/// Interface for authentication functionality
abstract class AuthViewModel extends BaseViewModel {
  /// Authentication state
  bool get isLoggedIn;
  
  /// Current user information
  User? get currentUser;
  String? get token;
  
  // Auth state stream for router navigation
  Stream<bool> get authStateChanges;

  /// Log in a user
  Future<bool> login(String email, String password, bool rememberMe);
  
  /// Register a new user
  Future<bool> register(String email, String password);
  
  /// Log out the current user
  Future<void> logout();
  
  /// Check if a token is valid
  bool isTokenValid(String token);
}
