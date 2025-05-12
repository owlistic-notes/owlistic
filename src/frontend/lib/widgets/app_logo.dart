import 'package:flutter/material.dart';

class AppLogo extends StatelessWidget {
  final double size;
  final bool useBackground;
  final EdgeInsetsGeometry padding;
  final bool forceTransparent;

  const AppLogo({
    Key? key, 
    this.size = 60.0,
    this.useBackground = false,
    this.padding = EdgeInsets.zero,
    this.forceTransparent = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Use transparent logo if in dark mode or if explicitly requested
    const String logoAsset = 'assets/logo/owlistic.png';
    final logoWidget = Image.asset(
      logoAsset,
      width: size,
      height: size,
    );

    if (!useBackground) {
      return Padding(
        padding: padding,
        child: logoWidget,
      );
    }

    // With circular background
    return Padding(
      padding: padding,
      child: Container(
        width: size + 20,
        height: size + 20,
        decoration: BoxDecoration(
          color: Theme.of(context).primaryColor.withOpacity(0.1),
          shape: BoxShape.circle,
        ),
        child: Center(child: logoWidget),
      ),
    );
  }
}