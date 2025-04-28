import 'package:flutter/material.dart';

/// Base ViewModel interface that all ViewModels must implement
/// In MVVM, ViewModels expose state that Views observe and react to
abstract class BaseViewModel with ChangeNotifier {
  /// Indicates if the ViewModel is currently loading data
  bool get isLoading;
  
  /// Indicates if the ViewModel has been initialized
  bool get isInitialized;
  
  /// Indicates if the ViewModel is currently active
  bool get isActive;
  
  /// Current error message, if any
  String? get errorMessage;
  
  /// Clear current error message
  void clearError();
  
  /// Activate the ViewModel when its view becomes visible
  /// This is used to manage resources and subscriptions
  void activate();
  
  /// Deactivate the ViewModel when its view is no longer visible
  /// This is used to release resources and pause subscriptions
  void deactivate();
  
  /// Reset internal state
  /// Used when logging out or clearing application state
  void resetState();
}
