import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';

/// Highlight one localized substring inside a localized text string.
Widget highlightText(
  BuildContext context, {
  required String key,
  required String highlightKey,
  TextStyle? style,
  TextStyle? highlightStyle,
}) {
  final text = tr(key);
  final highlight = tr(highlightKey);

  final parts = text.split(highlight);

  return RichText(
    text: TextSpan(
      style: style ?? Theme.of(context).textTheme.bodyMedium,
      children: [
        TextSpan(text: parts[0]),
        TextSpan(
          text: highlight,
          style: highlightStyle ?? const TextStyle(fontWeight: FontWeight.bold),
        ),
        if (parts.length > 1) TextSpan(text: parts[1]),
      ],
    ),
  );
}
