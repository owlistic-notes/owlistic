import 'package:flutter/material.dart';

class CardContainer extends StatelessWidget {
  final Widget? child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Widget? trailing;
  final Widget? leading;
  final String? title;
  final String? subtitle;
  final EdgeInsetsGeometry? padding;
  
  const CardContainer({
    Key? key,
    this.child,
    this.onTap,
    this.onLongPress,
    this.trailing,
    this.leading,
    this.title,
    this.subtitle,
    this.padding,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: padding ?? const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (title != null || subtitle != null || leading != null || trailing != null)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: leading,
                  title: title != null 
                      ? Text(
                          title!,
                          style: Theme.of(context).textTheme.titleMedium,
                          overflow: TextOverflow.ellipsis,
                        ) 
                      : null,
                  subtitle: subtitle != null 
                      ? Text(
                          subtitle!,
                          style: Theme.of(context).textTheme.bodySmall,
                        ) 
                      : null,
                  trailing: trailing,
                ),
              if (child != null) child!,
            ],
          ),
        ),
      ),
    );
  }
}
