import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// App theme definition inspired by Evernote
class AppTheme {
  // Main colors
  static const Color primaryColor = Color(0xFF67b0f0);
  static const Color dangerColor = Color(0xFFf06767);
  static const Color successColor = Color(0xFF93d385);
  
  // Light mode colors
  static const Color lightBackgroundColor = Color(0xFFF8F8F8);
  static const Color lightCardColor = Colors.white;
  static const Color lightTextPrimaryColor = Color(0xFF2E3C42);
  static const Color lightTextSecondaryColor = Color(0xFF757575);
  static const Color lightDividerColor = Color(0xFFEEEEEE);
  
  // Dark mode colors
  static const Color darkBackgroundColor = Color(0xFF1A1A1A);
  static const Color darkCardColor = Color(0xFF2D2D2D);
  static const Color darkTextPrimaryColor = Color(0xFFF4F4F4);
  static const Color darkTextSecondaryColor = Color(0xFFBBBBBB);
  static const Color darkDividerColor = Color(0xFF444444);

  // Get the appropriate color based on theme mode
  static Color getBackgroundColor(bool isDarkMode) => isDarkMode ? darkBackgroundColor : lightBackgroundColor;
  static Color getCardColor(bool isDarkMode) => isDarkMode ? darkCardColor : lightCardColor;
  static Color getTextPrimaryColor(bool isDarkMode) => isDarkMode ? darkTextPrimaryColor : lightTextPrimaryColor;
  static Color getTextSecondaryColor(bool isDarkMode) => isDarkMode ? darkTextSecondaryColor : lightTextSecondaryColor;
  static Color getDividerColor(bool isDarkMode) => isDarkMode ? darkDividerColor : lightDividerColor;

  // Create MaterialColor from a single Color
  static MaterialColor createMaterialColor(Color color) {
    List<double> strengths = [.05, .1, .2, .3, .4, .5, .6, .7, .8, .9];
    Map<int, Color> swatch = {};
    final int r = color.red, g = color.green, b = color.blue;

    for (var strength in strengths) {
      final ds = 0.5 - strength;
      swatch[(strength * 1000).round()] = Color.fromRGBO(
        r + ((ds < 0 ? r : (255 - r)) * ds).round(),
        g + ((ds < 0 ? g : (255 - g)) * ds).round(),
        b + ((ds < 0 ? b : (255 - b)) * ds).round(),
        1,
      );
    }
    return MaterialColor(color.value, swatch);
  }

  // Get theme data based on mode
  static ThemeData getThemeData(ThemeMode mode) {
    final brightness = _getBrightness(mode);
    final isDark = brightness == Brightness.dark;
    
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      primaryColor: primaryColor,
      primarySwatch: createMaterialColor(primaryColor),
      scaffoldBackgroundColor: getBackgroundColor(isDark),
      cardColor: getCardColor(isDark),
      dividerColor: getDividerColor(isDark),
      
      // Appbar theme
      appBarTheme: AppBarTheme(
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: primaryColor,
          statusBarIconBrightness: Brightness.light,
          statusBarBrightness: Brightness.dark,
        ),
      ),
      
      // Card theme with subtle shadow
      cardTheme: CardTheme(
        color: getCardColor(isDark),
        elevation: 2,
        shadowColor: isDark ? Colors.black38 : Colors.black12,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      ),
      
      // List tile theme
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        iconColor: primaryColor,
      ),
      
      // Elevated button theme
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryColor,
          foregroundColor: Colors.white,
          elevation: 2,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      
      // Text button theme
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primaryColor,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      
      // Input decoration theme
      inputDecorationTheme: InputDecorationTheme(
        fillColor: getCardColor(isDark),
        filled: true,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: getDividerColor(isDark)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: getDividerColor(isDark)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: primaryColor, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        labelStyle: TextStyle(color: getTextSecondaryColor(isDark)),
      ),
      
      // Icon theme
      iconTheme: IconThemeData(
        color: getTextSecondaryColor(isDark),
      ),
      
      // Checkbox theme
      checkboxTheme: CheckboxThemeData(
        fillColor: MaterialStateProperty.resolveWith((states) {
          if (states.contains(MaterialState.selected)) {
            return primaryColor;
          }
          return isDark ? darkTextSecondaryColor.withOpacity(0.3) : null;
        }),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
      ),
      
      // Floating action button theme
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      
      // Dialog theme
      dialogTheme: DialogTheme(
        backgroundColor: getCardColor(isDark),
        elevation: 8,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        titleTextStyle: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: getTextPrimaryColor(isDark),
        ),
      ),
      
      // Text theme
      textTheme: TextTheme(
        headlineLarge: TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.bold,
          color: getTextPrimaryColor(isDark),
        ),
        headlineMedium: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w600,
          color: getTextPrimaryColor(isDark),
        ),
        headlineSmall: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: getTextPrimaryColor(isDark),
        ),
        titleLarge: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: getTextPrimaryColor(isDark),
        ),
        titleMedium: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w500,
          color: getTextPrimaryColor(isDark),
        ),
        bodyLarge: TextStyle(
          fontSize: 16,
          color: getTextPrimaryColor(isDark),
        ),
        bodyMedium: TextStyle(
          fontSize: 14,
          color: getTextPrimaryColor(isDark),
        ),
        labelLarge: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w500,
          color: primaryColor,
        ),
      ),
      
      // Color scheme
      colorScheme: ColorScheme(
        brightness: brightness,
        primary: primaryColor,
        onPrimary: Colors.white,
        secondary: primaryColor.withOpacity(0.7),
        onSecondary: Colors.white,
        error: dangerColor,
        onError: Colors.white,
        background: getBackgroundColor(isDark),
        onBackground: getTextPrimaryColor(isDark),
        surface: getCardColor(isDark),
        onSurface: getTextPrimaryColor(isDark),
      ),
      
      // Bottom sheet theme
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: getCardColor(isDark),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
      ),
      
      // Switch theme
      switchTheme: SwitchThemeData(
        thumbColor: MaterialStateProperty.resolveWith((states) {
          if (states.contains(MaterialState.selected)) {
            return primaryColor;
          }
          return null;
        }),
        trackColor: MaterialStateProperty.resolveWith((states) {
          if (states.contains(MaterialState.selected)) {
            return primaryColor.withOpacity(0.5);
          }
          return null;
        }),
      ),
      
      // Snackbar theme
      snackBarTheme: SnackBarThemeData(
        backgroundColor: isDark ? darkCardColor : lightTextPrimaryColor,
        contentTextStyle: TextStyle(color: isDark ? darkTextPrimaryColor : Colors.white),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      
      // Tooltip theme
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: isDark ? darkCardColor.withOpacity(0.9) : lightTextPrimaryColor.withOpacity(0.9),
          borderRadius: BorderRadius.circular(4),
        ),
        textStyle: TextStyle(color: isDark ? darkTextPrimaryColor : Colors.white),
      ),
    );
  }

  // Get brightness based on theme mode
  static Brightness _getBrightness(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.dark:
        return Brightness.dark;
      case ThemeMode.light:
        return Brightness.light;
      case ThemeMode.system:
        return WidgetsBinding.instance.window.platformBrightness;
    }
  }
  
  // Special button styles for action buttons
  static ButtonStyle getDangerButtonStyle() {
    return ElevatedButton.styleFrom(
      backgroundColor: dangerColor,
      foregroundColor: Colors.white,
    );
  }
  
  static ButtonStyle getSuccessButtonStyle() {
    return ElevatedButton.styleFrom(
      backgroundColor: successColor,
      foregroundColor: Colors.white,
    );
  }
  
  // Icon styles for action buttons
  static IconThemeData getDangerIconTheme() {
    return const IconThemeData(
      color: dangerColor,
    );
  }
  
  static IconThemeData getSuccessIconTheme() {
    return const IconThemeData(
      color: successColor,
    );
  }
}

/// Extension methods for easy theme access
extension ThemeExtension on BuildContext {
  ThemeData get theme => Theme.of(this);
  bool get isDarkMode => Theme.of(this).brightness == Brightness.dark;
  Color get primaryColor => Theme.of(this).primaryColor;
  TextTheme get textTheme => Theme.of(this).textTheme;
  ColorScheme get colorScheme => Theme.of(this).colorScheme;
}
