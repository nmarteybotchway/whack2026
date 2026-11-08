import 'package:flutter/painting.dart';

/// Splits [text] into plain and bold spans, consuming `**bold**` markers.
/// Unpaired markers are left as literal text.
List<TextSpan> messageSpans(String text) {
  final parts = text.split('**');
  // An even part count means the last marker is unpaired.
  final unpaired = parts.length.isEven;
  final spans = <TextSpan>[];
  for (var i = 0; i < parts.length; i++) {
    final bold = i.isOdd && !(unpaired && i == parts.length - 1);
    spans.add(
      TextSpan(
        text: bold || !(unpaired && i == parts.length - 1)
            ? parts[i]
            : '**${parts[i]}',
        style: bold ? const TextStyle(fontWeight: FontWeight.w700) : null,
      ),
    );
  }
  return spans;
}
