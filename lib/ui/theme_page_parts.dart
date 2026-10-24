import 'package:flutter/material.dart';

import '../services/stable_hash.dart';
import 'adaptive.dart';
import 'activity_icon.dart';
import 'dashed_line.dart';
import 'ink_wash.dart';
import 'tokens.dart';

/// Presentation only: page state and actions remain with each page.
class ThemePageHeader extends StatelessWidget {
  const ThemePageHeader({
    super.key,
    required this.title,
    required this.kicker,
    required this.summary,
    required this.icon,
    this.compact = false,
  });
  final String title, kicker, summary;
  final IconData icon;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final p = paletteOf(context);
    Text text(
      String value,
      double size, {
      Color? color,
      FontWeight weight = FontWeight.w500,
    }) => Text(
      value,
      style: TextStyle(
        fontSize: size,
        fontWeight: weight,
        height: 1.35,
        color: color ?? p.ink,
        fontFamily: p.terminal || p.pixel || p.receipt
            ? 'monospace'
            : p.paper || p.journal
            ? 'serif'
            : null,
      ),
    );
    final heading = text(
      title,
      compact
          ? 19
          : p.editorial
          ? 28
          : 23,
      weight: FontWeight.w800,
    );
    final note = text(summary, 12, color: p.ink2);
    final cap = text(kicker, 9, color: p.ink2, weight: FontWeight.w700);
    if (compact) {
      Widget compactBody;
      if (p.pixel || p.terminal) {
        compactBody = ThemePanel(
          label: kicker,
          icon: icon,
          seed: kicker,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          child: note,
        );
      } else if (p.receipt) {
        compactBody = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(child: cap),
            const SizedBox(height: 6),
            Center(child: note),
            const SizedBox(height: 8),
            DashedLine(color: p.ink2),
          ],
        );
      } else if (p.editorial || p.inkWash) {
        compactBody = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(icon, color: p.accent, size: 18),
                const SizedBox(width: 8),
                Expanded(child: cap),
              ],
            ),
            const SizedBox(height: 5),
            note,
            const SizedBox(height: 8),
            if (p.inkWash)
              BrushLine(color: p.ink2.withValues(alpha: 0.4))
            else
              Container(height: 2, color: p.ink),
          ],
        );
      } else {
        compactBody = ThemePanel(
          seed: kicker,
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              ThemePreferenceIcon(icon: icon),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [cap, const SizedBox(height: 4), note],
                ),
              ),
            ],
          ),
        );
      }
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: compactBody,
      );
    }
    Widget lines(
      List<Widget> children, {
      CrossAxisAlignment align = CrossAxisAlignment.start,
    }) => Column(
      crossAxisAlignment: align,
      mainAxisSize: MainAxisSize.min,
      children: children,
    );
    Widget content;
    if (p.editorial) {
      content = lines([
        cap,
        const SizedBox(height: 5),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 5,
              height: compact ? 28 : 36,
              margin: const EdgeInsets.only(right: 10, top: 3),
              color: p.accent,
            ),
            Expanded(child: heading),
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Icon(icon, size: 24, color: p.ink),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(height: 3, color: p.ink),
        const SizedBox(height: 7),
        note,
      ]);
    } else if (p.receipt) {
      content = lines([
        cap,
        const SizedBox(height: 4),
        heading,
        const SizedBox(height: 7),
        DashedLine(color: p.ink2),
        const SizedBox(height: 7),
        note,
      ], align: CrossAxisAlignment.center);
      content = Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
        color: p.card,
        child: content,
      );
    } else if (p.inkWash) {
      content = lines([
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: lines([cap, const SizedBox(height: 5), heading])),
            const Padding(
              padding: EdgeInsets.only(top: 10),
              child: InkSealChip(glyph: '记', size: 22),
            ),
          ],
        ),
        const SizedBox(height: 6),
        BrushLine(color: p.ink.withValues(alpha: 0.45), thickness: 2),
        const SizedBox(height: 7),
        note,
      ]);
    } else if (p.paper) {
      content = ThemePanel(
        seed: kicker,
        padding: const EdgeInsets.all(16),
        child: lines([
          cap,
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(icon, color: p.accent, size: 22),
              const SizedBox(width: 9),
              Expanded(child: heading),
            ],
          ),
          const SizedBox(height: 9),
          DashedLine(color: p.cardBorder),
          const SizedBox(height: 7),
          note,
        ]),
      );
    } else if (p.journal) {
      content = Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(14, 16, 12, 12),
              decoration: BoxDecoration(
                color: p.card,
                border: Border(left: BorderSide(color: p.accent, width: 2)),
              ),
              child: lines([
                cap,
                const SizedBox(height: 5),
                heading,
                const SizedBox(height: 5),
                note,
              ]),
            ),
            Positioned(
              top: -8,
              left: 18,
              child: ExcludeSemantics(
                child: journalTape(context, kicker, width: 70),
              ),
            ),
          ],
        ),
      );
    } else if (p.morandi) {
      content = Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: p.card.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(24),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: p.accentFill.withValues(alpha: 0.12),
              ),
              child: Icon(icon, color: p.accent, size: 25),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: lines([
                cap,
                const SizedBox(height: 3),
                heading,
                const SizedBox(height: 7),
                note,
              ]),
            ),
          ],
        ),
      );
    } else if (p.comic) {
      content = ThemePanel(
        seed: kicker,
        padding: const EdgeInsets.all(14),
        child: lines([
          Row(
            children: [
              Expanded(child: heading),
              const SizedBox(width: 8),
              Icon(icon, color: p.ink, size: 27),
            ],
          ),
          const SizedBox(height: 5),
          cap,
          const SizedBox(height: 9),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BubbleDecoration(
              fillColor: p.card,
              borderColor: p.cardBorder,
              radius: 8,
            ),
            child: note,
          ),
        ]),
      );
    } else if (p.pixel || p.terminal) {
      content = ThemePanel(
        label: kicker,
        icon: icon,
        seed: kicker,
        padding: const EdgeInsets.all(13),
        child: lines([
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              text(
                p.pixel ? '+ ' : '> ',
                22,
                color: p.accent,
                weight: FontWeight.w800,
              ),
              Expanded(child: heading),
            ],
          ),
          const SizedBox(height: 8),
          note,
        ]),
      );
    } else {
      content = lines([heading, const SizedBox(height: 5), note]);
    }
    return Padding(
      padding: EdgeInsets.only(bottom: compact ? 10 : 16),
      child: content,
    );
  }
}

class ThemeSectionHeading extends StatelessWidget {
  const ThemeSectionHeading({
    super.key,
    required this.title,
    this.index = 1,
    this.detail,
  });
  final String title;
  final int index;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final p = paletteOf(context);
    final text = Text(
      p.terminal ? '> $title/' : title,
      style: TextStyle(
        color: p.ink,
        fontSize: p.editorial ? 17 : 14,
        fontWeight: FontWeight.w700,
        fontFamily: p.terminal || p.receipt || p.pixel
            ? 'monospace'
            : p.paper || p.journal
            ? 'serif'
            : null,
      ),
    );
    Widget lead = const SizedBox();
    if (p.editorial) {
      lead = Padding(
        padding: const EdgeInsets.only(right: 10),
        child: Text(
          index.toString().padLeft(2, '0'),
          style: TextStyle(
            fontSize: 27,
            height: 1,
            fontWeight: FontWeight.w900,
            color: p.accent,
          ),
        ),
      );
    } else if (p.pixel) {
      lead = Padding(
        padding: const EdgeInsets.only(right: 7),
        child: Icon(Icons.chevron_right, size: 19, color: p.accent),
      );
    } else if (p.morandi || p.inkWash || p.paper) {
      lead = Container(
        width: p.paper ? 12 : 7,
        height: p.paper ? 3 : 7,
        margin: const EdgeInsets.only(right: 8),
        decoration: BoxDecoration(
          color: p.accent,
          shape: p.inkWash || p.morandi ? BoxShape.circle : BoxShape.rectangle,
        ),
      );
    }
    Widget heading = Row(
      children: [
        lead,
        Expanded(child: text),
        if (detail != null) ...[
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              detail!,
              textAlign: TextAlign.end,
              style: TextStyle(
                fontSize: 11,
                color: p.ink2,
                fontFamily: p.terminal || p.receipt ? 'monospace' : null,
              ),
            ),
          ),
        ],
      ],
    );
    if (p.pixel || p.comic) {
      heading = Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: p.pixel ? p.ink : p.card,
          borderRadius: BorderRadius.circular(p.comic ? 8 : 0),
          border: p.comic ? Border.all(color: p.cardBorder, width: 1.5) : null,
        ),
        child: DefaultTextStyle.merge(
          style: TextStyle(color: p.pixel ? p.card : p.ink),
          child: p.pixel
              ? Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: p.card,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    if (detail != null)
                      Text(
                        detail!,
                        style: TextStyle(color: p.card, fontSize: 11),
                      ),
                  ],
                )
              : heading,
        ),
      );
    } else if (p.receipt || p.editorial) {
      heading = Column(
        children: [
          heading,
          const SizedBox(height: 7),
          if (p.receipt)
            DashedLine(color: p.ink2)
          else
            Container(height: 2, color: p.ink),
        ],
      );
    } else if (p.journal) {
      heading = Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            top: -5,
            left: 4,
            child: ExcludeSemantics(
              child: journalTape(context, title, width: 64),
            ),
          ),
          heading,
        ],
      );
    } else if (p.inkWash) {
      heading = Column(
        children: [
          heading,
          const SizedBox(height: 6),
          BrushLine(color: p.ink2.withValues(alpha: 0.4)),
        ],
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 16, 2, 10),
      child: heading,
    );
  }
}

class ThemePanel extends StatelessWidget {
  const ThemePanel({
    super.key,
    required this.child,
    this.label,
    this.icon,
    this.padding = const EdgeInsets.all(16),
    this.seed = 'panel',
  });
  final Widget child;
  final String? label;
  final IconData? icon;
  final EdgeInsetsGeometry padding;
  final String seed;

  @override
  Widget build(BuildContext context) {
    final p = paletteOf(context);
    final radius = p.pixel || p.terminal || p.editorial || p.receipt
        ? 1.0
        : p.comic
        ? 15.0
        : p.morandi
        ? 24.0
        : p.journal
        ? 6.0
        : 12.0;
    final tint =
        Tokens.avatarSoftPalette[stableHash(seed).abs() %
            Tokens.avatarSoftPalette.length];
    final decoration =
        inkWashFill(context, radius) ??
        (p.receipt
            ? receiptTear(context)
            : BoxDecoration(
                color: p.comic
                    ? Color.alphaBlend(tint.withValues(alpha: 0.35), p.card)
                    : p.card,
                borderRadius: BorderRadius.circular(radius),
                border: p.editorial
                    ? null
                    : Border.all(color: p.cardBorder, width: p.comic ? 1.8 : 1),
                boxShadow: p.comic || p.pixel
                    ? [
                        BoxShadow(
                          color: p.cardBorder,
                          offset: const Offset(3, 3),
                        ),
                      ]
                    : p.morandi
                    ? p.shadow
                    : null,
              ));
    final chrome = (p.pixel || p.terminal) && label != null;
    Widget body = Container(
      decoration: decoration,
      foregroundDecoration: p.pixel
          ? pixelFrame(context, radius)
          : p.paper
          ? paperInnerRing(context, radius)
          : p.editorial
          ? editorialRules(context)
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (chrome)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
              color: p.ink,
              child: Row(
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 13, color: p.card),
                    const SizedBox(width: 7),
                  ],
                  Expanded(
                    child: Text(
                      label ?? (p.terminal ? '~/preferences' : 'OPTIONS'),
                      style: TextStyle(
                        color: p.card,
                        fontSize: 10,
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  ExcludeSemantics(
                    child: Text(
                      p.terminal ? '— □ ×' : '▪ ▪',
                      style: TextStyle(color: p.card, fontSize: 11),
                    ),
                  ),
                ],
              ),
            ),
          if (label != null && !chrome)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
              child: Text(
                label!,
                style: TextStyle(
                  color: p.ink2,
                  fontWeight: FontWeight.w700,
                  fontSize: 10,
                  fontFamily: p.receipt ? 'monospace' : null,
                ),
              ),
            ),
          Padding(padding: padding, child: child),
        ],
      ),
    );
    if (p.journal) {
      body = Padding(
        padding: const EdgeInsets.only(top: 7),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            body,
            Positioned(
              top: -7,
              right: 18,
              child: ExcludeSemantics(
                child: journalTape(context, seed, width: 56),
              ),
            ),
          ],
        ),
      );
    }
    return body;
  }
}

class ThemePreferenceIcon extends StatelessWidget {
  const ThemePreferenceIcon({
    super.key,
    required this.icon,
    this.spinning = false,
  });
  final IconData icon;
  final bool spinning;
  @override
  Widget build(BuildContext context) {
    final p = paletteOf(context);
    if (p.clean || p.receipt || p.inkWash) {
      return ActivityIcon(icon, active: spinning, size: 21, color: p.accent);
    }
    return Container(
      padding: const EdgeInsets.all(7),
      decoration: BoxDecoration(
        color: p.editorial || p.terminal
            ? p.ink
            : p.accentFill.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(
          p.pixel || p.editorial || p.terminal
              ? 1
              : p.journal
              ? 4
              : p.comic
              ? 9
              : 16,
        ),
        border: p.pixel || p.comic || p.journal
            ? Border.all(
                color: p.comic ? p.cardBorder : p.accent,
                width: p.comic ? 1.4 : 1,
              )
            : null,
      ),
      child: ActivityIcon(
        icon,
        active: spinning,
        size: 18,
        color: p.editorial || p.terminal ? p.card : p.accent,
      ),
    );
  }
}

class ThemePreferenceToggle extends StatelessWidget {
  const ThemePreferenceToggle({
    super.key,
    required this.value,
    required this.onChanged,
  });
  final bool value;
  final ValueChanged<bool> onChanged;
  @override
  Widget build(BuildContext context) {
    final p = paletteOf(context);
    if (p.morandi || p.comic || p.clean) {
      return Switch(
        value: value,
        onChanged: onChanged,
        activeTrackColor: p.accentFill,
        activeThumbColor: p.onAccent,
        trackOutlineColor: WidgetStatePropertyAll(
          p.comic ? p.cardBorder : p.hairline,
        ),
        trackOutlineWidth: WidgetStatePropertyAll(p.comic ? 2 : 1),
      );
    }
    if (p.paper || p.receipt || p.journal) {
      return Checkbox(
        value: value,
        onChanged: (v) => onChanged(v ?? false),
        activeColor: p.accentFill,
        checkColor: p.onAccent,
        side: BorderSide(color: p.ink2, width: p.journal ? 1.5 : 1),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(p.journal ? 3 : 0),
        ),
      );
    }
    return Semantics(
      toggled: value,
      child: TextButton(
        style: TextButton.styleFrom(
          minimumSize: const Size(56, 48),
          padding: const EdgeInsets.symmetric(horizontal: 7),
          foregroundColor: value ? p.onAccent : p.ink2,
          backgroundColor: value ? p.accentFill : p.card,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(p.inkWash ? 4 : 0),
            side: BorderSide(
              color: value ? p.accent : p.cardBorder,
              width: p.pixel ? 1.5 : 1,
            ),
          ),
        ),
        onPressed: () => onChanged(!value),
        child: Text(
          p.terminal
              ? (value ? '[ON]' : '[OFF]')
              : p.pixel
              ? (value ? 'ON' : 'OFF')
              : value
              ? '开'
              : '关',
          style: TextStyle(
            fontSize: 12,
            fontFamily: p.pixel || p.terminal ? 'monospace' : null,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
