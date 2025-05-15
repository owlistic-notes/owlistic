import 'dart:async';
import 'package:flutter/material.dart';
import 'dart:convert';
import '../models/user.dart';
import '../services/user_service.dart';
import '../services/auth_service.dart';
import '../services/app_state_service.dart';
import '../utils/logger.dart';
import '../viewmodel/user_profile_viewmodel.dart';

class UserProfileProvider with ChangeNotifier implements UserProfileViewModel {
  final Logger _logger = Logger('UserProfileProvider');
  final UserService _userService;
  final AuthService _authService;
  
  // Services
  final AppStateService _appStateService = AppStateService();
  StreamSubscription? _resetSubscription;
  
  // State variables
  User? _currentUser;
  bool _isActive = false;
  bool _isInitialized = false;
  bool _isLoadingProfile = false;
  bool _isUpdatingProfile = false;
  bool _isUpdatingPassword = false;
  String? _errorMessage;
  String? _profileError;
  String? _passwordError;
  
  // Constructor with dependency injection
  UserProfileProvider({
    required UserService userService,
    required AuthService authService,
  }) : _userService = userService,
       _authService = authService {
    // Listen for app reset events
    _resetSubscription = _appStateService.onResetState.listen((_) {
      resetState();
    });
    
    _isInitialized = true;
  }
  
  // BaseViewModel implementation
  @override
  bool get isLoading => _isLoadingProfile;
  
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
  
  // UserProfileViewModel implementation
  @override
  User? get currentUser => _currentUser;
  
  @override
  bool get isLoadingProfile => _isLoadingProfile;
  
  @override
  bool get isUpdatingProfile => _isUpdatingProfile;
  
  @override
  bool get isUpdatingPassword => _isUpdatingPassword;
  
  @override
  String? get profileError => _profileError;
  
  @override
  String? get passwordError => _passwordError;
  
  @override
  void clearProfileError() {
    _profileError = null;
    notifyListeners();
  }
  
  @override
  void clearPasswordError() {
    _passwordError = null;
    notifyListeners();
  }
  
  @override
  Future<void> loadUserProfile() async {
    if (!_isActive) {
      return;
    }
    
    _isLoadingProfile = true;
    _profileError = null;
    notifyListeners();
    
    try {
      final userId = await _authService.getCurrentUserId();
      if (userId == null) {
        throw Exception('No authenticated user');
      }
      
      final user = await _userService.getUserById(userId);
      _currentUser = user;
    } catch (e) {
      _profileError = _extractErrorMessage(e.toString());
    } finally {
      _isLoadingProfile = false;
      notifyListeners();
    }
  }
  
  // Helper method to extract clean error messages
  String _extractErrorMessage(String errorString) {
    // Try to extract JSON error message if present
    final jsonPattern = RegExp(r'({.*})');
    final match = jsonPattern.firstMatch(errorString);
    
    if (match != null) {
      try {
        final jsonStr = match.group(1);
        if (jsonStr != null) {
          final errorMap = json.decode(jsonStr);
          if (errorMap.containsKey('error')) {
            return errorMap['error'];
          }
        }
      } catch (_) {
        // If JSON parsing fails, continue to fallback
      }
    }
    
    // If not in JSON format, try to extract from standard error message
    final errorPattern = RegExp(r'[Ee]rror: (.+)');
    final errorMatch = errorPattern.firstMatch(errorString);
    if (errorMatch != null && errorMatch.groupCount >= 1) {
      return errorMatch.group(1) ?? errorString;
    }
    
    // Fallback to removing common prefixes
    String cleanError = errorString;
    final prefixes = [
      'Failed to load profile:', 
      'Failed to fetch user:', 
      'Error:'
    ];
    
    for (final prefix in prefixes) {
      cleanError = cleanError.replaceAll(prefix, '').trim();
    }
    
    return cleanError;
  }
  
  @override
  Future<bool> updateUserProfile({
    String? username,
    String? displayName,
    String? profilePic,
    Map<String, dynamic>? preferences,
  }) async {
    if (!_isActive || _currentUser == null) {
      return false;
    }
    
    _isUpdatingProfile = true;
    _profileError = null;
    notifyListeners();
    
    try {
      final profile = UserProfile(
        username: username ?? _currentUser!.username,
        displayName: displayName ?? _currentUser!.displayName,
        profilePic: profilePic ?? _currentUser!.profilePic,
        preferences: preferences ?? _currentUser!.preferences,
      );
      
      final updatedUser = await _userService.updateUserProfile(_currentUser!.id, profile);
      _currentUser = updatedUser;
      return true;
    } catch (e) {
      _profileError = _extractErrorMessage(e.toString());
      return false;
    } finally {
      _isUpdatingProfile = false;
      notifyListeners();
    }
  }
  
  @override
  Future<bool> updatePassword(String currentPassword, String newPassword) async {
    if (!_isActive || _currentUser == null) {
      return false;
    }
    
    _isUpdatingPassword = true;
    _passwordError = null;
    notifyListeners();
    
    try {
      final success = await _userService.updatePassword(
        _currentUser!.id, 
        currentPassword, 
        newPassword
      );
      
      return success;
    } catch (e) {
      _passwordError = _extractErrorMessage(e.toString());
      return false;
    } finally {
      _isUpdatingPassword = false;
      notifyListeners();
    }
  }
  
  @override
  Future<bool> deleteAccount() async {
    if (!_isActive || _currentUser == null) {
      return false;
    }
    
    try {
      final success = await _userService.deleteUserAccount(_currentUser!.id);
      
      if (success) {
        await _authService.logout();
        resetState();
      }
      
      return success;
    } catch (e) {
      _errorMessage = _extractErrorMessage(e.toString());
      notifyListeners();
      return false;
    }
  }
  
  @override
  bool validateUsername(String username) {
    return username.length >= 3;
  }
  
  @override
  bool validatePassword(String password) {
    return password.length >= 6;
  }
  
  @override
  bool passwordsMatch(String password, String confirmPassword) {
    return password == confirmPassword;
  }
  
  // State lifecycle management
  @override
  void activate() {
    if (_isActive) return;
    
    _isActive = true;
    loadUserProfile(); // Load profile when activated
  }
  
  @override
  void deactivate() {
    if (!_isActive) return;
    
    _isActive = false;
  }
  
  @override
  void resetState() {
    _currentUser = null;
    _profileError = null;
    _passwordError = null;
    _errorMessage = null;
    notifyListeners();
  }
  
  @override
  void dispose() {
    _resetSubscription?.cancel();
    super.dispose();
  }
}
