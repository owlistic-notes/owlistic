import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:owlistic/viewmodel/login_viewmodel.dart';
import 'package:owlistic/utils/logger.dart';
import 'package:owlistic/widgets/app_logo.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({Key? key}) : super(key: key);
  
  @override
  _LoginScreenState createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final Logger _logger = Logger('LoginScreen');
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _serverUrlController = TextEditingController();
  bool _isPasswordVisible = false;
  bool _rememberMe = true;
  
  @override
  void initState() {
    super.initState();
    
    // Activate the LoginViewModel
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<LoginViewModel>().activate();
      _loadSavedEmail();
      _loadServerUrl();
    });
  }
  
  Future<void> _loadSavedEmail() async {
    final savedEmail = await context.read<LoginViewModel>().getSavedEmail();
    if (savedEmail != null && savedEmail.isNotEmpty) {
      _emailController.text = savedEmail;
    }
  }
  
  Future<void> _loadServerUrl() async {
    final serverUrl = context.read<LoginViewModel>().getServerUrl();
    if (serverUrl != null && serverUrl.isNotEmpty) {
      _serverUrlController.text = serverUrl;
    } else {
      // Default server URL if none is set
      _serverUrlController.text = 'http://localhost:8080';
    }
  }

  Future<void> _saveServerUrl() async {
    final url = _serverUrlController.text.trim();
    if (url.isNotEmpty) {
      await context.read<LoginViewModel>().saveServerUrl(url);
      _logger.info('Server URL saved: $url');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Server URL updated'))
        );
      }
    }
  }
  
  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _serverUrlController.dispose();
    // Deactivate the LoginViewModel
    context.read<LoginViewModel>().deactivate();
    super.dispose();
  }

  Future<void> _login() async {
    // Save server URL first
    await _saveServerUrl();
    
    if (_formKey.currentState!.validate()) {
      try {
        final loginViewModel = context.read<LoginViewModel>();
        
        final success = await loginViewModel.login(
          _emailController.text.trim(), 
          _passwordController.text,
          _rememberMe
        );
        
        if (success) {
          // Use the new navigation method after successful login
          if (mounted) {
            loginViewModel.onLoginSuccess(context);
          }
        } else if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(loginViewModel.errorMessage ?? 'Login failed'),
              backgroundColor: Colors.red,
            ),
          );
        }
      } catch (e) {
        _logger.error('Error during login', e);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Login error: ${e.toString()}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = MediaQuery.of(context).size;
    
    // Watch the LoginViewModel to react to changes
    final loginViewModel = context.watch<LoginViewModel>();
    final isLoading = loginViewModel.isLoading;
    
    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: Center(
        child: SingleChildScrollView(
          child: Center(
            child: Container(
              constraints: const BoxConstraints(
                maxWidth: 400,
                minHeight: 500,
              ),
              width: size.width * 0.85,
              margin: const EdgeInsets.symmetric(vertical: 24.0),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.08),
                    blurRadius: 20,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.all(32.0),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Replace icon with custom logo
                      const AppLogo(size: 80),
                      const SizedBox(height: 16),
                      
                      // App title
                      Text(
                        'Owlistic',
                        style: theme.textTheme.headlineMedium!.copyWith(
                          color: theme.primaryColor,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      
                      // Subtitle
                      Text(
                        'Welcome back',
                        style: theme.textTheme.titleMedium,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 32),
                      
                      // Server URL field
                      TextFormField(
                        controller: _serverUrlController,
                        decoration: InputDecoration(
                          labelText: 'Server URL',
                          hintText: 'http://localhost:8080',
                          prefixIcon: const Icon(Icons.cloud),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please enter server URL';
                          }
                          // Basic URL validation - should start with http:// or https://
                          if (!value.startsWith('http://') && !value.startsWith('https://')) {
                            return 'URL should start with http:// or https://';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      
                      // Email field
                      TextFormField(
                        controller: _emailController,
                        decoration: InputDecoration(
                          labelText: 'Email',
                          hintText: 'Enter your email',
                          prefixIcon: const Icon(Icons.email),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        keyboardType: TextInputType.emailAddress,
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please enter your email';
                          }
                          // Simple email validation
                          if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(value)) {
                            return 'Please enter a valid email';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      
                      // Password field
                      TextFormField(
                        controller: _passwordController,
                        obscureText: !_isPasswordVisible,
                        decoration: InputDecoration(
                          labelText: 'Password',
                          hintText: 'Enter your password',
                          prefixIcon: const Icon(Icons.lock),
                          suffixIcon: IconButton(
                            icon: Icon(_isPasswordVisible ? Icons.visibility_off : Icons.visibility),
                            onPressed: () {
                              setState(() {
                                _isPasswordVisible = !_isPasswordVisible;
                              });
                            },
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please enter your password';
                          }
                          return null;
                        },
                      ),
                      
                      // Remember me checkbox
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Remember me'),
                        value: _rememberMe,
                        onChanged: (value) {
                          setState(() {
                            _rememberMe = value ?? false;
                          });
                        },
                        controlAffinity: ListTileControlAffinity.leading,
                      ),
                      
                      const SizedBox(height: 24),
                      
                      // Login button - shows loading state from ViewModel
                      ElevatedButton(
                        onPressed: isLoading ? null : _login,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: theme.primaryColor,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: isLoading 
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text('Log in', style: TextStyle(fontSize: 16)),
                      ),
                      
                      const SizedBox(height: 16),
                      
                      // Register link
                      TextButton(
                        onPressed: () {
                          loginViewModel.navigateToRegister(context);
                        },
                        child: const Text('Don\'t have an account? Register now'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
