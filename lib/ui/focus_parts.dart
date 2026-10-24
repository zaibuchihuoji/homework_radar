import 'package:flutter/material.dart';

import 'adaptive.dart';
import 'tokens.dart';

/// Presentation primitives for the selected sunny workbench. No stored state.
class FocusSummary extends StatelessWidget {
  const FocusSummary({
    super.key,
    required this.eyebrow,
    required this.title,
    this.detail,
    this.trailing,
    this.child,
    this.yellow = true,
  });
  final String eyebrow, title;
  final String? detail;
  final Widget? trailing, child;
  final bool yellow;
  @override
  Widget build(BuildContext context) {
    final p = paletteOf(context);
    final ink = yellow ? p.onAccent : p.ink;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: yellow ? p.accentFill : p.ink.withValues(alpha: .035),
        borderRadius: BorderRadius.circular(12),
      ),
      child: DefaultTextStyle.merge(
        style: TextStyle(color: ink),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        eyebrow,
                        style: TextStyle(fontSize: 12, height: 1.5, color: ink),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w600,
                          height: 1.3,
                          color: ink,
                        ),
                      ),
                    ],
                  ),
                ),
                if (trailing != null) ...[const SizedBox(width: 12), trailing!],
              ],
            ),
            if (detail != null) ...[
              const SizedBox(height: 10),
              Text(
                detail!,
                style: TextStyle(fontSize: 13, height: 1.6, color: ink),
              ),
            ],
            if (child != null) ...[const SizedBox(height: 14), child!],
          ],
        ),
      ),
    );
  }
}

class FocusSectionTitle extends StatelessWidget {
  const FocusSectionTitle(this.title, {super.key, this.detail, this.action});
  final String title;
  final String? detail;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 24, bottom: 12),
    child: Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: textPrimary(context),
            ),
          ),
        ),
        if (detail != null)
          Text(
            detail!,
            style: TextStyle(fontSize: 12, color: textSecondary(context)),
          ),
        ?action,
      ],
    ),
  );
}

class FocusViewSwitch extends StatelessWidget {
  const FocusViewSwitch({
    super.key,
    required this.labels,
    required this.selected,
    required this.onChanged,
  });
  final List<String> labels;
  final int selected;
  final ValueChanged<int> onChanged;
  @override
  Widget build(BuildContext context) {
    final p = paletteOf(context);
    return Row(
      children: [
        for (var i = 0; i < labels.length; i++)
          Expanded(
            child: Semantics(
              selected: i == selected,
              button: true,
              child: InkWell(
                onTap: () => onChanged(i),
                child: Container(
                  constraints: const BoxConstraints(minHeight: 48),
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: i == selected ? p.accentFill : p.hairline,
                        width: i == selected ? 3 : .5,
                      ),
                    ),
                  ),
                  child: Text(
                    labels[i],
                    style: TextStyle(
                      fontSize: 14,
                      color: i == selected ? p.ink : p.ink2,
                      fontWeight: i == selected
                          ? FontWeight.w600
                          : FontWeight.w400,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
