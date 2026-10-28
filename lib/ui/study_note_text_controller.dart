import 'package:flutter/material.dart';

/// Renders saved inline marks while retaining ordinary editable plain text.
class StudyNoteTextController extends TextEditingController {
  StudyNoteTextController({super.text, List<dynamic> marks = const []})
    : _marks = List<dynamic>.of(marks);

  List<dynamic> _marks;

  void setMarks(List<dynamic> marks) {
    _marks = List<dynamic>.of(marks);
    notifyListeners();
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final boundaries = <int>{0, text.length};
    for (final raw in _marks) {
      if (raw is Map && raw['start'] is int && raw['end'] is int) {
        boundaries.add((raw['start'] as int).clamp(0, text.length));
        boundaries.add((raw['end'] as int).clamp(0, text.length));
      }
    }
    final composing = value.composing;
    if (withComposing && composing.isValid && !composing.isCollapsed) {
      boundaries.add(composing.start.clamp(0, text.length));
      boundaries.add(composing.end.clamp(0, text.length));
    }
    final positions = boundaries.toList()..sort();
    final spans = <InlineSpan>[];
    for (var i = 0; i + 1 < positions.length; i++) {
      final start = positions[i], end = positions[i + 1];
      if (start == end) continue;
      final active = <String>{};
      for (final raw in _marks) {
        if (raw is Map &&
            raw['start'] is int &&
            raw['end'] is int &&
            (raw['start'] as int) <= start &&
            (raw['end'] as int) >= end &&
            raw['type'] is String) {
          active.add(raw['type'] as String);
        }
      }
      final underlined =
          active.contains('underline') ||
          (withComposing &&
              composing.isValid &&
              composing.start <= start &&
              composing.end >= end);
      spans.add(
        TextSpan(
          text: text.substring(start, end),
          style: TextStyle(
            fontWeight: active.contains('bold') ? FontWeight.bold : null,
            fontStyle: active.contains('italic') ? FontStyle.italic : null,
            decoration: underlined ? TextDecoration.underline : null,
            backgroundColor: active.contains('highlight')
                ? const Color(0x66f2c94c)
                : null,
          ),
        ),
      );
    }
    return TextSpan(style: style, children: spans);
  }
}
