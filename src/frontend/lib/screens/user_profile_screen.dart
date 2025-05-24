import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:owlistic/viewmodel/user_profile_viewmodel.dart';
import 'package:owlistic/widgets/app_drawer.dart';
import 'package:owlistic/widgets/app_bar_common.dart';
import 'package:owlistic/widgets/theme_switcher.dart';
import 'package:owlistic/utils/logger.dart';

class UserProfileScreen extends StatefulWidget {
  const UserProfileScreen({Key? key}) : super(key: key);
  
  @override
  _UserProfileScreenState createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  final Logger _logger = Logger('UserProfileScreen');
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final _formKey = GlobalKey<FormState>();
  final _passwordFormKey = GlobalKey<FormState>();
  
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _displayNameController = TextEditingController();
  final TextEditingController _currentPasswordController = TextEditingController();
  final TextEditingController _newPasswordController = TextEditingController();
  final TextEditingController _confirmPasswordController = TextEditingController();
  
  bool _editMode = false;
  bool _passwordVisible = false;
  bool _isInitialized = false;
  late UserProfileViewModel _profileViewModel;
  
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    
    if (!_isInitialized) {
      _isInitialized = true;
      
      // Get ViewModel instance
      _profileViewModel = context.read<UserProfileViewModel>();
      
      // Activate the view model
      _profileViewModel.activate();
      
      _logger.info('UserProfileViewModel activated and screen initialized');
      
      // Load profile data after a short delay to avoid setState during build
      Future.microtask(() => _initializeData());
    } else {
      // Ensure provider is active when screen is visible again
      if (!_profileViewModel.isActive) {
        _profileViewModel.activate();
        Future.microtask(() => _initializeData());
        _logger.info('UserProfileViewModel re-activated');
      }
    }
  }
  
  Future<void> _initializeData() async {
    try {
      await _profileViewModel.loadUserProfile();
      if (mounted) {
        _populateFormFields();
      }
    } catch (e) {
      _logger.error('Error initializing user profile data', e);
    }
  }
  
  void _populateFormFields() {
    if (!mounted) return;
    
    final user = _profileViewModel.currentUser;
    if (user != null) {
      setState(() {
        _usernameController.text = user.username;
        _displayNameController.text = user.displayName;
      });
      _logger.debug('Form fields populated with user data');
    }
  }
  
  Future<void> _updateProfile() async {
    if (!_formKey.currentState!.validate()) return;
    
    final success = await _profileViewModel.updateUserProfile(
      username: _usernameController.text,
      displayName: _displayNameController.text,
    );
    
    if (success && mounted) {
      setState(() {
        _editMode = false;
      });
      _showSnackbar('Profile updated successfully');
    }
  }
  
  Future<void> _changePassword() async {
    if (!_passwordFormKey.currentState!.validate()) return;
    
    final success = await _profileViewModel.updatePassword(
      _currentPasswordController.text,
      _newPasswordController.text,
    );
    
    if (success && mounted) {
      _currentPasswordController.clear();
      _newPasswordController.clear();
      _confirmPasswordController.clear();
      _showSnackbar('Password updated successfully');
    }
  }
  
  Future<void> _confirmDeleteAccount() async {
    if (!mounted) return;
    
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Account'),
        content: const Text(
          'Are you sure you want to delete your account? This action cannot be undone.'
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    
    if (confirmed == true) {
      final success = await _profileViewModel.deleteAccount();
      
      if (success && mounted) {
        // Navigate to login screen after account deletion
        context.go('/login');
      }
    }
  }
  
  void _showSnackbar(String message) {
    if (!mounted) return;
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
  
  @override
  void dispose() {
    _usernameController.dispose();
    _displayNameController.dispose();
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    
    // Deactivate the view model
    _profileViewModel.deactivate();
    _logger.info('UserProfileScreen disposed and ViewModel deactivated');
    
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBarCommon(
        title: 'Profile',
        onBackPressed: () => context.go('/'),
        showBackButton: true,
        onMenuPressed: () => _scaffoldKey.currentState?.openDrawer(),
        actions: const [ThemeSwitcher()],
      ),
      drawer: const SidebarDrawer(),
      body: Consumer<UserProfileViewModel>(
        builder: (context, viewModel, _) {
          if (viewModel.isLoadingProfile) {
            return const Center(child: CircularProgressIndicator());
          }
          
          final user = viewModel.currentUser;
          
          if (user == null) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('Failed to load profile'),
                  if (viewModel.profileError != null)
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Text(
                        'Error: ${viewModel.profileError}',
                        style: TextStyle(color: theme.colorScheme.error),
                      ),
                    ),
                  ElevatedButton(
                    onPressed: _initializeData,
                    child: const Text('Retry'),
                  ),
                ],
              ),
            );
          }
          
          return RefreshIndicator(
            onRefresh: _initializeData,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Profile header with avatar
                  Center(
                    child: Column(
                      children: [
                        CircleAvatar(
                          radius: 50,
                          backgroundColor: theme.primaryColor,
                          child: Text(
                            user.displayName.isNotEmpty
                                ? user.displayName[0].toUpperCase()
                                : user.email[0].toUpperCase(),
                            style: theme.textTheme.displaySmall?.copyWith(
                              color: Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          user.email,
                          style: theme.textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        if (!_editMode)
                          ElevatedButton(
                            onPressed: () {
                              setState(() {
                                _editMode = true;
                              });
                            },
                            child: const Text('Edit Profile'),
                          ),
                      ],
                    ),
                  ),
                  
                  const Divider(height: 32),
                  
                  // Profile form
                  if (_editMode)
                    Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Edit Profile',
                            style: theme.textTheme.titleLarge,
                          ),
                          const SizedBox(height: 16),
                          
                          // Username field
                          TextFormField(
                            controller: _usernameController,
                            decoration: const InputDecoration(
                              labelText: 'Username',
                              border: OutlineInputBorder(),
                            ),
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Please enter a username';
                              }
                              if (!viewModel.validateUsername(value)) {
                                return 'Username must be at least 3 characters';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),
                          
                          // Display name field
                          TextFormField(
                            controller: _displayNameController,
                            decoration: const InputDecoration(
                              labelText: 'Display Name',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 16),
                          
                          // Error message
                          if (viewModel.profileError != null)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 16),
                              child: Text(
                                viewModel.profileError!,
                                style: TextStyle(color: theme.colorScheme.error),
                              ),
                            ),
                          
                          // Save/Cancel buttons
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              TextButton(
                                onPressed: () {
                                  setState(() {
                                    _editMode = false;
                                    _populateFormFields(); // Reset fields
                                  });
                                },
                                child: const Text('Cancel'),
                              ),
                              const SizedBox(width: 16),
                              ElevatedButton(
                                onPressed: viewModel.isUpdatingProfile
                                    ? null
                                    : _updateProfile,
                                child: viewModel.isUpdatingProfile
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Text('Save'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  
                  if (!_editMode) ...[
                    // User profile details
                    ListTile(
                      title: const Text('Username'),
                      subtitle: Text(user.username.isNotEmpty
                          ? user.username
                          : 'Not set'),
                    ),
                    ListTile(
                      title: const Text('Display Name'),
                      subtitle: Text(user.displayName.isNotEmpty
                          ? user.displayName
                          : 'Not set'),
                    ),
                    ListTile(
                      title: const Text('Email'),
                      subtitle: Text(user.email),
                    ),
                    ListTile(
                      title: const Text('Account Created'),
                      subtitle: Text(
                        '${user.createdAt.day}/${user.createdAt.month}/${user.createdAt.year}',
                      ),
                    ),
                  ],
                  
                  const Divider(height: 32),
                  
                  // Password change section
                  Text(
                    'Change Password',
                    style: theme.textTheme.titleLarge,
                  ),
                  const SizedBox(height: 16),
                  
                  Form(
                    key: _passwordFormKey,
                    child: Column(
                      children: [
                        // Current password
                        TextFormField(
                          controller: _currentPasswordController,
                          obscureText: !_passwordVisible,
                          decoration: InputDecoration(
                            labelText: 'Current Password',
                            border: const OutlineInputBorder(),
                            suffixIcon: IconButton(
                              icon: Icon(_passwordVisible
                                  ? Icons.visibility_off
                                  : Icons.visibility),
                              onPressed: () {
                                setState(() {
                                  _passwordVisible = !_passwordVisible;
                                });
                              },
                            ),
                          ),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Please enter your current password';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        
                        // New password
                        TextFormField(
                          controller: _newPasswordController,
                          obscureText: !_passwordVisible,
                          decoration: const InputDecoration(
                            labelText: 'New Password',
                            border: OutlineInputBorder(),
                          ),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Please enter a new password';
                            }
                            if (!viewModel.validatePassword(value)) {
                              return 'Password must be at least 6 characters';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        
                        // Confirm new password
                        TextFormField(
                          controller: _confirmPasswordController,
                          obscureText: !_passwordVisible,
                          decoration: const InputDecoration(
                            labelText: 'Confirm New Password',
                            border: OutlineInputBorder(),
                          ),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Please confirm your new password';
                            }
                            if (!viewModel.passwordsMatch(
                              _newPasswordController.text,
                              value,
                            )) {
                              return 'Passwords do not match';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        
                        // Error message
                        if (viewModel.passwordError != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: Text(
                              viewModel.passwordError!,
                              style: TextStyle(color: theme.colorScheme.error),
                            ),
                          ),
                        
                        // Update password button
                        ElevatedButton(
                          onPressed: viewModel.isUpdatingPassword
                              ? null
                              : _changePassword,
                          child: viewModel.isUpdatingPassword
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text('Update Password'),
                        ),
                      ],
                    ),
                  ),
                  
                  const Divider(height: 32),
                  
                  // Delete account button
                  Center(
                    child: TextButton(
                      onPressed: _confirmDeleteAccount,
                      style: TextButton.styleFrom(
                        foregroundColor: theme.colorScheme.error,
                      ),
                      child: const Text('Delete Account'),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
