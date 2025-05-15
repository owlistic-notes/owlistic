import '../models/user.dart';
import 'base_viewmodel.dart';

/// Interface for user profile management functionality
abstract class UserProfileViewModel extends BaseViewModel {
  // Current user data
  User? get currentUser;
  
  // Loading states for different operations
  bool get isLoadingProfile;
  bool get isUpdatingProfile;
  bool get isUpdatingPassword;
  
  // Error handling for profile actions
  String? get profileError;
  String? get passwordError;
  
  // Clear specific errors
  void clearProfileError();
  void clearPasswordError();
  
  // User profile operations
  Future<void> loadUserProfile();
  
  Future<bool> updateUserProfile({
    String? username,
    String? displayName,
    String? profilePic,
    Map<String, dynamic>? preferences,
  });
  
  Future<bool> updatePassword(String currentPassword, String newPassword);
  Future<bool> deleteAccount();
  
  // Validation methods
  bool validateUsername(String username);
  bool validatePassword(String password);
  bool passwordsMatch(String password, String confirmPassword);
  
  // State management
  @override
  void resetState();
}
