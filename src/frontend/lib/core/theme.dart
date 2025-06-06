import 'package:flutter/material.dart';

/// App theme definition inspired by Evernote
class AppTheme {
  // Color constants
  static const primaryColor = Colors.blue;
  static const accentColor = Colors.blueAccent;
  static const dangerColor = Colors.red;
  static const warningColor = Colors.orange;
  static const successColor = Colors.green;
  static const selectionLight = Color(0xFFACCEF7);
  static const selectionDark = Color.fromARGB(255, 247, 172, 233);
  static const backgroundLight = Colors.white;
  static const backgroundDark = Color(0xFF121212);
  static const cardLight = Colors.white;
  static const cardDark = Color(0xFF1E1E1E);
  
  // Light theme definition
  static final ThemeData lightTheme = ThemeData(
    primarySwatch: Colors.blue,
    brightness: Brightness.light,
    scaffoldBackgroundColor: const Color(0xFFF5F5F5),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.white,
      foregroundColor: Colors.black87,
      elevation: 1,
      iconTheme: IconThemeData(color: Colors.grey[800]),
    ),
    cardTheme: const CardThemeData(
      color: cardLight,
      elevation: 2,
      shadowColor: Colors.black26,
    ),
    iconTheme: const IconThemeData(color: Colors.black54),
    textTheme: const TextTheme(
      bodyLarge: TextStyle(color: Colors.black87),
      bodyMedium: TextStyle(color: Colors.black87),
      bodySmall: TextStyle(color: Colors.black54),
    ),
    textSelectionTheme: const TextSelectionThemeData(
      cursorColor: accentColor,
      selectionColor: selectionLight
    ),
    checkboxTheme: const CheckboxThemeData(
      shape: CircleBorder(),
    ),
    dividerTheme: DividerThemeData(
      color: Colors.grey[300],
      thickness: 1,
    ),
    colorScheme: const ColorScheme.light(
      primary: primaryColor,
      secondary: accentColor,
      error: dangerColor,
      surface: cardLight,
    ),
    useMaterial3: true,
  );

  // Dark theme definition  
  static final ThemeData darkTheme = ThemeData(
    primarySwatch: Colors.blue,
    primaryColor: primaryColor,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: backgroundDark,
    appBarTheme: const AppBarTheme(
      backgroundColor: Color(0xFF1E1E1E),
      foregroundColor: Colors.white,
      elevation: 0,
      iconTheme: IconThemeData(color: Colors.white70),
    ),
    cardTheme: const CardThemeData(
      color: cardDark,
      elevation: 4,
      shadowColor: Colors.black45,
    ),
    iconTheme: const IconThemeData(color: Colors.white70),
    textTheme: const TextTheme(
      bodyLarge: TextStyle(color: Colors.white),
      bodyMedium: TextStyle(color: Colors.white),
      bodySmall: TextStyle(color: Colors.white70),
    ),
    textSelectionTheme: const TextSelectionThemeData(
      cursorColor: accentColor,
      selectionColor: selectionDark,
    ),
    checkboxTheme: const CheckboxThemeData(
      shape: CircleBorder(),
    ),
    dividerTheme: const DividerThemeData(
      color: Colors.white24,
      thickness: 1,
    ),
    colorScheme: const ColorScheme.dark(
      primary: primaryColor,
      secondary: accentColor,
      error: dangerColor,
      surface: cardDark,
    ),
    useMaterial3: true,
  );

  // Get theme data based on mode
  static ThemeData getThemeData(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.dark:
        return darkTheme;
      case ThemeMode.light:
        return lightTheme;
      default:
        return lightTheme;
    }
  }

  // Button styles
  static ButtonStyle getPrimaryButtonStyle() {
    return ElevatedButton.styleFrom(
      backgroundColor: primaryColor,
      foregroundColor: Colors.white,
    );
  }
  
  static ButtonStyle getSuccessButtonStyle() {
    return ElevatedButton.styleFrom(
      backgroundColor: successColor,
      foregroundColor: Colors.white,
    );
  }
  
  static ButtonStyle getDangerButtonStyle() {
    return ElevatedButton.styleFrom(
      backgroundColor: dangerColor,
      foregroundColor: Colors.white,
    );
  }
}
