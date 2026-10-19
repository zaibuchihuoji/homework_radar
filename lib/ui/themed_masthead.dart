import 'package:flutter/material.dart';

import 'dashed_line.dart';
import 'ink_wash.dart';
import 'tokens.dart';

/// Decorative mastheads share the same date and never replace a task action.
class ThemedMasthead extends StatelessWidget {
  const ThemedMasthead({super.key, required this.dateLine});
  final String dateLine;

  @override
  Widget build(BuildContext context) {
    final p = paletteOf(context);
    Text label(
      String value,
      double size, {
      Color? color,
      FontWeight weight = FontWeight.w400,
      String? font,
      double? spacing,
    }) => Text(
      value,
      style: TextStyle(
        fontSize: size,
        color: color ?? p.ink,
        fontWeight: weight,
        fontFamily: font,
        letterSpacing: spacing,
        height: 1.25,
      ),
    );
    final date = label(
      dateLine,
      p.clean ? 13 : 11.5,
      color: p.ink2,
      font: p.pixel || p.receipt || p.terminal ? 'monospace' : null,
    );
    Widget column(List<Widget> children) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
    if (p.editorial) {
      final now = DateTime.now();
      final issue = now.difference(DateTime(now.year)).inDays + 1;
      return column([
        label('作业通 / 第 $issue 期', 9, weight: FontWeight.w800, spacing: 1.1),
        const SizedBox(height: 3),
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            label(
              now.day.toString().padLeft(2, '0'),
              38,
              weight: FontWeight.w900,
              spacing: -1.5,
            ),
            const SizedBox(width: 9),
            column([
              Container(width: 7, height: 7, color: p.accent),
              const SizedBox(height: 5),
              label(
                '${now.month}月 · ${dateLine.split(' · ').last}',
                10.5,
                weight: FontWeight.w700,
              ),
            ]),
          ],
        ),
      ]);
    }
    if (p.terminal) {
      return column([
        label('student@radar ~', 10, color: p.ink2, font: 'monospace'),
        const SizedBox(height: 3),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            label(
              '> ',
              22,
              color: p.accent,
              font: 'monospace',
              weight: FontWeight.w800,
            ),
            label('作业通', 22, font: 'monospace', weight: FontWeight.w800),
            const SizedBox(width: 6),
            Container(width: 6, height: 16, color: p.accent),
          ],
        ),
        const SizedBox(height: 5),
        date,
      ]);
    }
    if (p.pixel) {
      return column([
        label(
          'STUDY QUEST',
          9,
          color: p.accent,
          weight: FontWeight.w800,
          font: 'monospace',
          spacing: 1,
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.sports_esports_rounded, size: 17, color: p.accent),
            const SizedBox(width: 6),
            label('作业通', 22, font: 'monospace', weight: FontWeight.w800),
          ],
        ),
        const SizedBox(height: 5),
        date,
      ]);
    }
    if (p.receipt) {
      return column([
        label(
          '作业通',
          23,
          font: 'monospace',
          spacing: 2,
          weight: FontWeight.w700,
        ),
        const SizedBox(height: 4),
        date,
        const SizedBox(height: 4),
        label('课业清单 · DAILY LIST', 9, color: p.ink2, font: 'monospace'),
      ]);
    }
    if (p.inkWash) {
      return column([
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            label('作业通', 24, weight: FontWeight.w600, spacing: 4),
            const SizedBox(width: 6),
            const InkSealChip(size: 13),
          ],
        ),
        SizedBox(
          width: 110,
          child: BrushLine(color: p.ink.withValues(alpha: 0.55), thickness: 2),
        ),
        const SizedBox(height: 3),
        date,
      ]);
    }
    if (p.paper) {
      return column([
        label('本日课业 / STUDY NOTES', 8.5, color: p.ink2, spacing: 0.6),
        const SizedBox(height: 4),
        label('作业通', 24, font: 'serif', weight: FontWeight.w600, spacing: 1),
        const SizedBox(height: 4),
        date,
      ]);
    }
    if (p.comic) {
      return column([
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            label('作业通', 24, weight: FontWeight.w900),
            const SizedBox(width: 7),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
              decoration: BoxDecoration(
                color: p.accent,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: p.cardBorder, width: 1.2),
              ),
              child: label(
                'TODAY',
                8,
                color: p.onAccent,
                weight: FontWeight.w900,
              ),
            ),
          ],
        ),
        const SizedBox(height: 5),
        date,
      ]);
    }
    if (p.journal) {
      return column([
        label('作业通', 24, font: 'serif', weight: FontWeight.w600, spacing: 2),
        SizedBox(
          width: 84,
          child: DashedLine(color: p.accentFill.withValues(alpha: 0.6)),
        ),
        const SizedBox(height: 4),
        date,
      ]);
    }
    if (p.morandi) {
      return column([
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            label('作业通', 24, weight: FontWeight.w600),
            const SizedBox(width: 9),
            for (final c in const [
              Color(0xFFC9AFA4),
              Color(0xFFA3B18A),
              Color(0xFFC9B8D8),
            ])
              Container(
                width: 6,
                height: 6,
                margin: const EdgeInsets.only(right: 3),
                decoration: BoxDecoration(color: c, shape: BoxShape.circle),
              ),
          ],
        ),
        const SizedBox(height: 5),
        date,
      ]);
    }
    if (p.sunny) {
      return column([
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            label('作业通', 23, weight: FontWeight.w700),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: p.accentFill,
                borderRadius: BorderRadius.circular(5),
              ),
              child: label(
                'TODAY',
                8,
                color: p.onAccent,
                weight: FontWeight.w800,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        date,
      ]);
    }
    return column([
      label('作业通', 23, weight: FontWeight.w700),
      const SizedBox(height: 4),
      date,
    ]);
  }
}
