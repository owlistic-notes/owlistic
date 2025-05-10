class User {
  final String id;
  final String email;
  final String username;
  final String displayName;
  final String profilePic;
  final Map<String, dynamic>? preferences;
  final DateTime createdAt;
  final DateTime updatedAt;
  
  User({
    required this.id,
    required this.email,
    this.username = '',
    this.displayName = '',
    this.profilePic = '',
    this.preferences,
    required this.createdAt,
    required this.updatedAt,
  });
  
  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] ?? '',
      email: json['email'] ?? '',
      username: json['username'] ?? '',
      displayName: json['display_name'] ?? '',
      profilePic: json['profile_pic'] ?? '',
      preferences: json['preferences'] != null 
          ? Map<String, dynamic>.from(json['preferences']) 
          : null,
      createdAt: json['created_at'] != null 
          ? DateTime.parse(json['created_at']) 
          : DateTime.now(),
      updatedAt: json['updated_at'] != null 
          ? DateTime.parse(json['updated_at']) 
          : DateTime.now(),
    );
  }
  
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'email': email,
      'username': username,
      'display_name': displayName,
      'profile_pic': profilePic,
      'preferences': preferences,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }
  
  User copyWith({
    String? id,
    String? email,
    String? username,
    String? displayName,
    String? profilePic,
    Map<String, dynamic>? preferences,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return User(
      id: id ?? this.id,
      email: email ?? this.email,
      username: username ?? this.username,
      displayName: displayName ?? this.displayName,
      profilePic: profilePic ?? this.profilePic,
      preferences: preferences ?? this.preferences,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

// UserProfile model for profile operations
class UserProfile {
  final String username;
  final String displayName;
  final String profilePic;
  final Map<String, dynamic>? preferences;
  
  UserProfile({
    this.username = '',
    this.displayName = '',
    this.profilePic = '',
    this.preferences,
  });
  
  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      username: json['username'] ?? '',
      displayName: json['display_name'] ?? '',
      profilePic: json['profile_pic'] ?? '',
      preferences: json['preferences'] != null 
          ? Map<String, dynamic>.from(json['preferences']) 
          : null,
    );
  }
  
  Map<String, dynamic> toJson() {
    final data = <String, dynamic>{};
    if (username.isNotEmpty) data['username'] = username;
    if (displayName.isNotEmpty) data['display_name'] = displayName;
    if (profilePic.isNotEmpty) data['profile_pic'] = profilePic;
    if (preferences != null) data['preferences'] = preferences;
    return data;
  }
  
  factory UserProfile.fromUser(User user) {
    return UserProfile(
      username: user.username,
      displayName: user.displayName,
      profilePic: user.profilePic,
      preferences: user.preferences,
    );
  }
}
