import 'package:flutter/material.dart';

import '../../../../core/theme/app_tokens.dart';

class HighlightedText extends StatelessWidget {
  const HighlightedText({
    super.key,
    required this.text,
    required this.keyword,
    this.style,
    this.maxLines,
    this.overflow,
  });

  final String text;
  final String keyword;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow? overflow;

  @override
  Widget build(BuildContext context) {
    final kw = keyword.trim();
    if (kw.isEmpty) {
      return Text(text, style: style, maxLines: maxLines, overflow: overflow);
    }
    final spans = <TextSpan>[];
    final lowerText = text.toLowerCase();
    final lowerKw = kw.toLowerCase();
    var start = 0;
    while (true) {
      final idx = lowerText.indexOf(lowerKw, start);
      if (idx == -1) {
        spans.add(TextSpan(text: text.substring(start), style: style));
        break;
      }
      if (idx > start) {
        spans.add(TextSpan(text: text.substring(start, idx), style: style));
      }
      spans.add(
        TextSpan(
          text: text.substring(idx, idx + kw.length),
          style: (style ?? const TextStyle()).copyWith(
            color: AppColors.primary,
          ),
        ),
      );
      start = idx + kw.length;
    }
    return RichText(
      text: TextSpan(
        children: spans,
        style: style ?? DefaultTextStyle.of(context).style,
      ),
      maxLines: maxLines,
      overflow: overflow ?? TextOverflow.clip,
    );
  }
}
