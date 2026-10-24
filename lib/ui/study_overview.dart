import 'package:flutter/material.dart';

import 'adaptive.dart';
import 'dashed_line.dart';
import 'ink_wash.dart';
import 'tokens.dart';

class StudyOverview extends StatelessWidget {
  const StudyOverview({
    super.key,
    required this.pending,
    required this.today,
    this.onTodayTap,
    this.onPendingTap,
    this.todaySelected = false,
  });
  final int pending;
  final int today;
  final VoidCallback? onTodayTap, onPendingTap;
  final bool todaySelected;

  @override
  Widget build(BuildContext context) {
    final p = paletteOf(context);
    final square = p.pixel || p.terminal || p.receipt || p.editorial;
    final mono = p.pixel || p.terminal || p.receipt;
    final radius = square
        ? 2.0
        : p.morandi
        ? 16.0
        : p.paper || p.journal
        ? 5.0
        : 10.0;
    final line = p.comic || p.pixel || p.terminal ? p.cardBorder : p.hairline;
    final plain = p.clean || p.inkWash || p.editorial || p.receipt;
    final content = SizedBox(
      width: double.infinity,
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        spacing: 12,
        runSpacing: 6,
        children: [
          _action(
            context,
            onPendingTap,
            false,
            Text(
              '${p.terminal ? '> ' : ''}待完成 $pending 项',
              style: TextStyle(
                fontSize: 13,
                fontWeight: p.comic ? FontWeight.w800 : FontWeight.w600,
                color: p.terminal ? p.card : p.ink,
                fontFamily: mono
                    ? 'monospace'
                    : p.paper
                    ? 'serif'
                    : null,
              ),
            ),
          ),
          _action(
            context,
            onTodayTap,
            todaySelected,
            Text(
              '今天截止 $today 项',
              style: TextStyle(
                fontSize: 13,
                fontFamily: mono ? 'monospace' : null,
                color: p.terminal
                    ? (today > 0 ? Tokens.warnDark : p.card)
                    : today > 0
                    ? (isDark(context) ? Tokens.warnDark : Tokens.amber)
                    : p.ink2,
              ),
            ),
          ),
        ],
      ),
    );
    Widget panel = Container(
      padding: plain
          ? EdgeInsets.zero
          : const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: plain
          ? null
          : BoxDecoration(
              color: p.terminal ? p.cardBorder : p.card,
              borderRadius: BorderRadius.circular(radius),
              border: p.morandi
                  ? null
                  : Border.all(
                      color: line,
                      width: p.comic || p.pixel ? 1.5 : 1,
                    ),
              boxShadow: p.comic || p.pixel
                  ? [BoxShadow(color: p.cardBorder, offset: const Offset(2, 2))]
                  : null,
            ),
      foregroundDecoration: p.paper ? paperInnerRing(context, radius) : null,
      child: content,
    );
    if (p.inkWash || p.receipt || p.editorial) {
      panel = Column(
        children: [
          panel,
          const SizedBox(height: 7),
          if (p.inkWash)
            BrushLine(color: p.ink.withValues(alpha: 0.35), thickness: 1.5)
          else if (p.receipt)
            DashedLine(color: p.ink2.withValues(alpha: 0.55))
          else
            SizedBox(
              height: 2,
              child: ColoredBox(color: p.ink, child: const SizedBox.expand()),
            ),
        ],
      );
    }
    if (p.journal) {
      panel = Stack(
        clipBehavior: Clip.none,
        children: [
          panel,
          Positioned(
            top: -6,
            left: 16,
            child: journalTape(context, 'overview', width: 42),
          ),
        ],
      );
    }
    return Padding(
      padding: p.clean
          ? const EdgeInsets.symmetric(horizontal: 12)
          : const EdgeInsets.fromLTRB(20, 10, 20, 2),
      child: Semantics(
        label: '待完成 $pending 项，今天截止 $today 项',
        container: true,
        explicitChildNodes: true,
        child: panel,
      ),
    );
  }

  Widget _action(
    BuildContext context,
    VoidCallback? onTap,
    bool selected,
    Widget text,
  ) {
    if (onTap == null) return text;
    final p = paletteOf(context);
    return Semantics(
      selected: selected,
      child: TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          minimumSize: const Size(48, 44),
          foregroundColor: p.terminal ? p.card : p.ink,
          backgroundColor: selected ? p.accent.withValues(alpha: .12) : null,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(p.pixel || p.terminal ? 2 : 10),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            text,
            if (onTap == onTodayTap) ...[
              const SizedBox(width: 4),
              Icon(
                selected ? Icons.close_rounded : Icons.chevron_right_rounded,
                size: 15,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
