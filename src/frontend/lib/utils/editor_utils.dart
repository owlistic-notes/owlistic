import 'package:flutter/material.dart';
import 'package:super_editor/super_editor.dart';
import 'document_builder.dart';

/// Helper class with utility functions for editor integration
class EditorUtils {
  /// Creates a text style based on attributions
  static TextStyle buildTextStyle(Set<Attribution> attributions, BuildContext context) {
    TextStyle style = TextStyle(
      color: Theme.of(context).textTheme.bodyMedium?.color ?? Colors.black,
      fontSize: 16,
    );
    
    for (final attribution in attributions) {
      if (attribution == const NamedAttribution('bold')) {
        style = style.copyWith(fontWeight: FontWeight.bold);
      } else if (attribution == const NamedAttribution('italic')) {
        style = style.copyWith(fontStyle: FontStyle.italic);
      } else if (attribution == const NamedAttribution('underline')) {
        style = style.copyWith(decoration: TextDecoration.underline);
      } else if (attribution == const NamedAttribution('strikethrough')) {
        style = style.copyWith(decoration: TextDecoration.lineThrough);
      } else if (attribution is LinkAttribution) {
        style = style.copyWith(
          color: Colors.blue,
          decoration: TextDecoration.underline,
        );
      } else if (attribution is ColorAttribution) {
        style = style.copyWith(color: attribution.color);
      }
    }
    return style;
  }
  
  /// Determines the appropriate node type based on block type
  static String getNodeTypeFromBlock(String blockType) {
    switch (blockType) {
      case 'heading':
        return 'heading';
      case 'checklist':
        return 'task';
      case 'code':
        return 'code';
      case 'text':
      default:
        return 'paragraph';
    }
  }
  
  /// Creates a customized stylesheet for the editor
  static Stylesheet createCustomStylesheet(BuildContext context) {
    final defaultTextColor = Theme.of(context).textTheme.bodyMedium?.color ?? Colors.black;
    
    return Stylesheet(
      rules: [
        StyleRule(
          const BlockSelector("paragraph"),
          (doc, node) => {
            Styles.textStyle: TextStyle(
              color: defaultTextColor,
              fontSize: 16,
              height: 1.5,
            ),
            Styles.padding: const CascadingPadding.only(top: 8, bottom: 8),
          },
        ),
        StyleRule(
          const BlockSelector("heading"),
          (doc, node) => {
            Styles.textStyle: TextStyle(
              color: defaultTextColor,
              fontSize: 24,
              fontWeight: FontWeight.bold,
              height: 1.4,
            ),
            Styles.padding: const CascadingPadding.only(top: 16, bottom: 8),
          },
        ),
        StyleRule(
          const BlockSelector("code"),
          (doc, node) => {
            Styles.textStyle: TextStyle(
              color: defaultTextColor,
              fontSize: 14, 
              fontFamily: 'monospace',
              height: 1.5,
            ),
            Styles.padding: const CascadingPadding.only(top: 8, bottom: 8, left: 16),
            Styles.backgroundColor: Colors.grey.withOpacity(0.1),
          },
        ),
        taskStyles,
      ],
      inlineTextStyler: (Set<Attribution> attributions, TextStyle baseStyle) {
        return buildTextStyle(attributions, context);
      },
    );
  }
}
