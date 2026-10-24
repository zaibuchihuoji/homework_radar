import 'package:flutter/material.dart';

import 'adaptive.dart';
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Semantics(
        label: '待完成 $pending 项，今天截止 $today 项',
        container: true,
        explicitChildNodes: true,
        child: SizedBox(
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
                  '待完成 $pending 项',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: p.ink,
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
                    color: today > 0
                        ? (isDark(context) ? Tokens.warnDark : Tokens.amber)
                        : p.ink2,
                  ),
                ),
              ),
            ],
          ),
        ),
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
