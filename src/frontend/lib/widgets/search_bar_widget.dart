import 'package:flutter/material.dart';

class SearchBarWidget extends StatelessWidget {
  final TextEditingController controller;
  final Function(String) onChanged;
  final VoidCallback onClear;
  final String hintText;
  
  const SearchBarWidget({
    Key? key,
    required this.controller,
    required this.onChanged,
    required this.onClear,
    this.hintText = 'Search...',
  }) : super(key: key);
  
  @override
  Widget build(BuildContext context) {
    // Get theme colors for better adaptation to light/dark mode
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    // Use appropriate colors based on the theme
    final textColor = Colors.white;
    final hintColor = textColor.withOpacity(0.7);
    
    return Container(
      height: 40,
      alignment: Alignment.center,
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        autofocus: true,
        style: TextStyle(
          color: textColor,
          fontSize: 16,
        ),
        decoration: InputDecoration(
          hintText: hintText,
          hintStyle: TextStyle(color: hintColor),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 8),
          isDense: true,
          prefixIcon: Icon(Icons.search, color: textColor),
          suffixIcon: IconButton(
            icon: Icon(Icons.clear, color: textColor),
            onPressed: () {
              controller.clear();
              onClear();
            },
            iconSize: 20, // Slightly smaller icon for better appearance
            splashRadius: 20, // Smaller splash for better UX
          ),
        ),
        cursorColor: textColor, // Set cursor color to match text
      ),
    );
  }
}
