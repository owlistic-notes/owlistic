import 'dart:convert';
import 'package:owlistic/models/user.dart';
import 'base_service.dart';
import 'package:owlistic/utils/logger.dart';

class UserService extends BaseService {
  final Logger _logger = Logger('UserService');

  // Get user by ID - this is the primary method that should be used
  Future<User> getUserById(String id) async {
    try {
      final response = await authenticatedGet('/api/v1/users/$id');
      
      if (response.statusCode == 200) {
        return User.fromJson(json.decode(response.body));
      } else {
        _logger.error('Failed to fetch user: ${response.statusCode}, ${response.body}');
        throw Exception('Failed to fetch user: ${response.body}');
      }
    } catch (e) {
      _logger.error('Error fetching user by ID', e);
      rethrow;
    }
  }
  
  // Update user profile
  Future<User> updateUserProfile(String userId, UserProfile profile) async {
    try {
      final response = await authenticatedPut(
        '/api/v1/users/$userId',
        profile.toJson(),
      );
      
      if (response.statusCode == 200) {
        _logger.info('User profile updated successfully');
        return User.fromJson(json.decode(response.body));
      } else {
        _logger.error('Failed to update profile: ${response.statusCode}, ${response.body}');
        throw Exception('Failed to update profile: ${response.body}');
      }
    } catch (e) {
      _logger.error('Error updating user profile', e);
      rethrow;
    }
  }
  
  // Update password
  Future<bool> updatePassword(String userId, String currentPassword, String newPassword) async {
    try {
      final response = await authenticatedPut(
        '/api/v1/users/$userId/password',
        {
          'current_password': currentPassword,
          'new_password': newPassword,
        },
      );
      
      if (response.statusCode == 200) {
        _logger.info('Password updated successfully');
        return true;
      } else {
        _logger.error('Failed to update password: ${response.statusCode}, ${response.body}');
        throw Exception('Failed to update password: ${response.body}');
      }
    } catch (e) {
      _logger.error('Error updating password', e);
      rethrow;
    }
  }
  
  // Delete user account
  Future<bool> deleteUserAccount(String userId) async {
    try {
      final response = await authenticatedDelete('/api/v1/users/$userId');
      
      if (response.statusCode == 204) {
        _logger.info('User account deleted successfully');
        return true;
      } else {
        _logger.error('Failed to delete account: ${response.statusCode}, ${response.body}');
        throw Exception('Failed to delete account: ${response.body}');
      }
    } catch (e) {
      _logger.error('Error deleting account', e);
      rethrow;
    }
  }
}
