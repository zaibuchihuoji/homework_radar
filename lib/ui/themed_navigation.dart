import 'package:flutter/material.dart';

import 'adaptive.dart';
import 'dashed_line.dart';
import 'ink_wash.dart';
import 'tokens.dart';

/// All themes reserve the same navigation area; each draws its own material.
class ThemedNavigationBar extends StatelessWidget {
  const ThemedNavigationBar({
    super.key,
    required this.selectedIndex,
    required this.onSelected,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;

  static const labels = ['作业', '课表', '日历', '账号', '设置'];
  static const icons = <(IconData, IconData)>[
    (Icons.assignment_outlined, Icons.assignment_rounded),
    (Icons.bento_outlined, Icons.bento_rounded),
    (Icons.calendar_month_outlined, Icons.calendar_month_rounded),
    (Icons.person_outline, Icons.person_rounded),
    (Icons.settings_outlined, Icons.settings_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    final pal = paletteOf(context);
    final indicatorExtent = pal.morandi || pal.paper || pal.terminal
        ? 38.0
        : 36.0;
    // Preserve each theme's existing row height, including its old frame inset.
    final iconArea = pal.comic
        ? 44.0
        : pal.terminal || pal.inkWash || pal.paper
        ? 42.0
        : 40.0;
    final verticalInset = (iconArea - indicatorExtent) / 2;
    final radius = pal.pixel || pal.receipt || pal.editorial
        ? 0.0
        : pal.terminal
        ? 2.0
        : pal.morandi
        ? indicatorExtent / 2
        : pal.paper
        ? 5.0
        : pal.comic
        ? 9.0
        : 12.0;
    final corners = pal.inkWash
        ? brushRadiusOf(context, 8)
        : pal.journal
        ? const BorderRadius.only(
            topLeft: Radius.circular(5),
            topRight: Radius.circular(10),
            bottomLeft: Radius.circular(10),
            bottomRight: Radius.circular(5),
          )
        : BorderRadius.circular(radius);
    final hasFrame =
        pal.comic ||
        pal.pixel ||
        pal.terminal ||
        pal.inkWash ||
        pal.paper ||
        pal.receipt ||
        pal.journal;
    return Material(
      color: pal.card,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (pal.inkWash)
            BrushLine(color: pal.ink.withValues(alpha: 0.25), thickness: 1.4)
          else if (pal.paper || pal.receipt || pal.journal)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: DashedLine(color: pal.cardBorder, thickness: 1),
            )
          else
            SizedBox(
              height: pal.editorial || pal.pixel ? 2 : 1,
              child: ColoredBox(
                color: pal.pixel || pal.editorial
                    ? pal.cardBorder
                    : pal.hairline,
                child: const SizedBox.expand(),
              ),
            ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(
                children: [
                  for (var i = 0; i < labels.length; i++)
                    Expanded(
                      child: Semantics(
                        button: true,
                        selected: i == selectedIndex,
                        label: '${labels[i]}标签页',
                        child: InkWell(
                          onTap: () => onSelected(i),
                          borderRadius: corners,
                          child: Padding(
                            padding: EdgeInsets.symmetric(
                              vertical: verticalInset,
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                AnimatedContainer(
                                  duration: const Duration(milliseconds: 180),
                                  width: indicatorExtent,
                                  height: indicatorExtent,
                                  alignment: Alignment.center,
                                  padding: EdgeInsets.zero,
                                  decoration: BoxDecoration(
                                    color: i != selectedIndex
                                        ? Colors.transparent
                                        : pal.editorial
                                        ? pal.ink
                                        : pal.sunny || pal.pixel || pal.inkWash
                                        ? pal.accentFill
                                        : pal.receipt
                                        ? Colors.transparent
                                        : pal.accentFill.withValues(
                                            alpha: pal.comic
                                                ? 0.15
                                                : pal.morandi
                                                ? 0.12
                                                : 0.09,
                                          ),
                                    gradient: i == selectedIndex && pal.morandi
                                        ? morandiCream(
                                            context,
                                            radius,
                                          )?.gradient
                                        : null,
                                    borderRadius: corners,
                                    border: i == selectedIndex && hasFrame
                                        ? Border.all(
                                            color: pal.comic || pal.pixel
                                                ? pal.cardBorder
                                                : pal.accentFill.withValues(
                                                    alpha: 0.6,
                                                  ),
                                            width: pal.comic || pal.pixel
                                                ? 2
                                                : 1,
                                          )
                                        : null,
                                    boxShadow:
                                        i == selectedIndex &&
                                            (pal.comic || pal.pixel)
                                        ? [
                                            BoxShadow(
                                              color: pal.cardBorder,
                                              offset: const Offset(2, 2),
                                            ),
                                          ]
                                        : i == selectedIndex &&
                                              pal.morandi &&
                                              pal.shadow.isNotEmpty
                                        ? [
                                            BoxShadow(
                                              color: pal.shadow.first.color,
                                              offset: const Offset(0, 2),
                                            ),
                                          ]
                                        : null,
                                  ),
                                  foregroundDecoration:
                                      i == selectedIndex && pal.paper
                                      ? paperInnerRing(context, radius)
                                      : null,
                                  child: Icon(
                                    i == selectedIndex
                                        ? icons[i].$2
                                        : icons[i].$1,
                                    size: 22,
                                    color: i != selectedIndex
                                        ? pal.ink2
                                        : pal.editorial
                                        ? pal.card
                                        : pal.pixel || pal.sunny || pal.inkWash
                                        ? pal.onAccent
                                        : pal.accent,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  labels[i],
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontFamily:
                                        pal.terminal || pal.receipt || pal.pixel
                                        ? 'monospace'
                                        : pal.paper
                                        ? 'serif'
                                        : null,
                                    fontWeight:
                                        i == selectedIndex ||
                                            pal.comic ||
                                            pal.editorial
                                        ? FontWeight.w700
                                        : FontWeight.w400,
                                    color: i == selectedIndex
                                        ? pal.accent
                                        : pal.ink2,
                                    decoration:
                                        i == selectedIndex &&
                                            (pal.receipt || pal.journal)
                                        ? TextDecoration.underline
                                        : null,
                                    decorationColor: pal.accent,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
