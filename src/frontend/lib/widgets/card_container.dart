import 'package:flutter/material.dart';
import '../core/theme.dart';

class CardContainer extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final double elevation;
  final Color? color;
  final VoidCallback? onTap;
  final BorderRadius? borderRadius;
  final Widget? leading;
  final Widget? trailing;
  final String? title;
  final String? subtitle;
  final bool compact;

  const CardContainer({
    Key? key,
    required this.child,
    this.padding,
    this.elevation = 2,
    this.color,
    this.onTap,
    this.borderRadius,
    this.leading,
    this.trailing,
    this.title,
    this.subtitle,
    this.compact = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark; // Changed from context.isDarkMode
    final radius = borderRadius ?? BorderRadius.circular(12);
    final cardColor = color ?? theme.cardColor;

    final Widget cardContent = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title != null || subtitle != null || leading != null || trailing != null)
          Padding(
            padding: EdgeInsets.only(
              left: compact ? 12 : 16,
              right: compact ? 12 : 16,
              top: compact ? 12 : 16,
              bottom: compact ? 4 : 8,
            ),
            child: Row(
              children: [
                if (leading != null) ...[
                  leading!,
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (title != null)
                        Text(
                          title!,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      if (subtitle != null) ...[
                        if (title != null) const SizedBox(height: 2),
                        Text(
                          subtitle!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            // Fixed: Use theme's text color instead of missing method
                            color: isDark ? Colors.grey[400] : Colors.grey[600],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (trailing != null) trailing!,
              ],
            ),
          ),
        Padding(
          padding: padding ?? EdgeInsets.all(compact ? 12 : 16),
          child: child,
        ),
      ],
    );

    return Card(
      color: cardColor,
      elevation: elevation,
      shape: RoundedRectangleBorder(borderRadius: radius),
      clipBehavior: onTap != null ? Clip.antiAlias : Clip.none,
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      child: onTap != null
          ? InkWell(
              onTap: onTap,
              splashColor: theme.primaryColor.withOpacity(0.1),
              highlightColor: theme.primaryColor.withOpacity(0.05),
              child: cardContent,
            )
          : cardContent,
    );
  }
}
