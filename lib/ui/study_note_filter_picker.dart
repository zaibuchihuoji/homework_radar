import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'theme_forms.dart';
import 'tokens.dart';

/// The original anchored menu, with a quieter transition and selection mark.
class StudyNoteFilterMenu extends StatelessWidget {
  const StudyNoteFilterMenu({
    super.key,
    required this.label,
    required this.tooltip,
    required this.allLabel,
    required this.selected,
    required this.choices,
    required this.optionKeyPrefix,
    required this.onSelected,
  });

  final String label;
  final String tooltip;
  final String allLabel;
  final String? selected;
  final List<String> choices;
  final String optionKeyPrefix;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final p = paletteOf(context);
    final maxWidth = math.max(
      0.0,
      math.min(280.0, MediaQuery.sizeOf(context).width - 32),
    );
    final disableAnimations = MediaQuery.disableAnimationsOf(context);

    PopupMenuItem<String> item(String value, String text) {
      final active = value == (selected ?? '');
      return PopupMenuItem<String>(
        key: ValueKey('$optionKeyPrefix:$value'),
        value: value,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Semantics(
          selected: active,
          child: Row(
            children: [
              Expanded(
                child: Text(
                  text,
                  style: TextStyle(
                    color: p.ink,
                    fontSize: 14,
                    fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
              if (active) ...[
                const SizedBox(width: 12),
                Icon(Icons.check_rounded, size: 18, color: p.ink),
              ],
            ],
          ),
        ),
      );
    }

    return Theme(
      // Keep initialValue so long menus scroll to the current choice, while
      // replacing Flutter's full-width selection fill with a small checkmark.
      data: Theme.of(context).copyWith(highlightColor: Colors.transparent),
      child: PopupMenuButton<String>(
        tooltip: tooltip,
        initialValue: selected ?? '',
        position: PopupMenuPosition.under,
        offset: const Offset(0, 4),
        color: p.modal,
        surfaceTintColor: Colors.transparent,
        shape: themeModalShape(p),
        clipBehavior: Clip.antiAlias,
        elevation: 4,
        menuPadding: const EdgeInsets.symmetric(vertical: 6),
        constraints: BoxConstraints(
          minWidth: math.min(160.0, maxWidth),
          maxWidth: maxWidth,
        ),
        popUpAnimationStyle: disableAnimations
            ? AnimationStyle.noAnimation
            : const AnimationStyle(
                duration: Duration(milliseconds: 160),
                curve: Curves.easeOutCubic,
                reverseCurve: Curves.easeInCubic,
              ),
        onSelected: onSelected,
        itemBuilder: (_) => [
          item('', allLabel),
          for (final choice in choices) item(choice, choice),
        ],
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      ),
    );
  }
}
