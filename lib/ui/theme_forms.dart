import 'package:flutter/material.dart';

import 'tokens.dart';

StylePalette _formPalette(BuildContext context) =>
    Theme.of(context).extension<StylePalette>() ??
    stylePalette(ThemeStyle.clean, Theme.of(context).brightness);

/// Shared presentation for app-owned forms and routes, never their state.
ShapeBorder themeModalShape(StylePalette p) => p.clean || p.clay
    ? RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: p.clay
            ? BorderSide(color: p.cardBorder, width: .7)
            : BorderSide.none,
      )
    : _ModalBorder(p);

class _ModalBorder extends ShapeBorder {
  const _ModalBorder(this.p);
  final StylePalette p;
  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.all(
    p.pixel
        ? 3
        : p.comic
        ? 2
        : 1,
  );
  @override
  ShapeBorder scale(double t) => this;
  @override
  Path getOuterPath(Rect r, {TextDirection? textDirection}) {
    if (p.pixel) {
      const s = 6.0;
      return Path()
        ..moveTo(r.left + s, r.top)
        ..lineTo(r.right - s, r.top)
        ..lineTo(r.right - s, r.top + s)
        ..lineTo(r.right, r.top + s)
        ..lineTo(r.right, r.bottom - s)
        ..lineTo(r.right - s, r.bottom - s)
        ..lineTo(r.right - s, r.bottom)
        ..lineTo(r.left + s, r.bottom)
        ..lineTo(r.left + s, r.bottom - s)
        ..lineTo(r.left, r.bottom - s)
        ..lineTo(r.left, r.top + s)
        ..lineTo(r.left + s, r.top + s)
        ..close();
    }
    if (p.receipt) {
      final path = Path()
        ..moveTo(r.left, r.top)
        ..lineTo(r.right, r.top)
        ..lineTo(r.right, r.bottom - 4);
      final count = (r.width / 10).ceil();
      final step = r.width / count;
      for (var i = 0; i < count; i++) {
        path
          ..lineTo(r.right - (i + 0.5) * step, r.bottom)
          ..lineTo(r.right - (i + 1) * step, r.bottom - 4);
      }
      return path
        ..lineTo(r.left, r.top)
        ..close();
    }
    final radius = p.morandi
        ? 24.0
        : p.comic
        ? 16.0
        : p.paper
        ? 8.0
        : p.journal
        ? 6.0
        : p.inkWash
        ? 14.0
        : 1.0;
    final corners = p.inkWash
        ? const BorderRadius.only(
            topLeft: Radius.circular(24),
            topRight: Radius.circular(4),
            bottomRight: Radius.circular(24),
            bottomLeft: Radius.circular(4),
          )
        : BorderRadius.circular(radius);
    return Path()..addRRect(corners.toRRect(r));
  }

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      getOuterPath(rect.deflate(2), textDirection: textDirection);
  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    final ink = p.pixel || p.comic || p.editorial ? p.ink : p.cardBorder;
    final pen = Paint()
      ..color = ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = p.comic || p.pixel ? 2 : 1;
    canvas.drawPath(getOuterPath(rect.deflate(1)), pen);
    if (p.pixel || p.terminal) {
      canvas.drawPath(
        getOuterPath(rect.deflate(4)),
        pen
          ..strokeWidth = 0.7
          ..color = ink.withValues(alpha: .5),
      );
    }
    if (p.paper) {
      final path = Path()
        ..addRRect(
          RRect.fromRectAndRadius(rect.deflate(5), const Radius.circular(4)),
        );
      pen
        ..color = p.cardBorder
        ..strokeWidth = 0.7;
      for (final metric in path.computeMetrics()) {
        for (double d = 0; d < metric.length; d += 8) {
          canvas.drawPath(
            metric.extractPath(d, (d + 4).clamp(0, metric.length)),
            pen,
          );
        }
      }
    }
    if (p.editorial) {
      pen
        ..color = p.ink
        ..strokeWidth = 1;
      canvas.drawLine(
        rect.topLeft + const Offset(0, 5),
        rect.topRight + const Offset(0, 5),
        pen,
      );
      canvas.drawLine(
        rect.bottomLeft - const Offset(0, 5),
        rect.bottomRight - const Offset(0, 5),
        pen,
      );
      canvas.drawRect(
        Rect.fromLTWH(rect.left, rect.top + 12, 3, 24),
        Paint()..color = p.accent,
      );
    }
    if (p.journal) {
      canvas.drawLine(
        rect.topLeft + const Offset(10, 8),
        rect.bottomLeft + const Offset(10, -8),
        pen..color = p.accentFill.withValues(alpha: .35),
      );
    }
  }
}

InputBorder themeFieldBorder(
  StylePalette p, {
  bool focused = false,
  bool error = false,
}) {
  final side = BorderSide(
    color: error
        ? Tokens.danger
        : focused
        ? p.accent
        : p.inkWash
        ? p.ink2
        : p.cardBorder,
    width: focused || p.comic || p.pixel ? 1.8 : 1,
  );
  if (p.receipt || p.editorial || p.journal || p.inkWash) {
    return UnderlineInputBorder(borderSide: side);
  }
  return OutlineInputBorder(
    borderRadius: BorderRadius.circular(
      p.clean || p.clay
          ? 12
          : p.morandi
          ? 18
          : p.comic
          ? 9
          : p.pixel || p.terminal
          ? 1
          : 5,
    ),
    borderSide: side,
  );
}

InputDecorationThemeData themedInputTheme(StylePalette p) =>
    InputDecorationThemeData(
      filled: true,
      fillColor: p.clean
          ? p.card
          : Color.alphaBlend(
              p.accentFill.withValues(alpha: p.comic ? .055 : .025),
              p.modal,
            ),
      labelStyle: TextStyle(
        color: p.ink2,
        fontSize: 13,
        fontFamily: p.terminal || p.receipt || p.pixel ? 'monospace' : null,
      ),
      floatingLabelStyle: TextStyle(
        color: p.accent,
        fontSize: 12,
        fontWeight: FontWeight.w700,
      ),
      hintStyle: TextStyle(color: p.ink2, fontSize: 12.5),
      helperStyle: TextStyle(color: p.ink2, fontSize: 11.5),
      errorStyle: const TextStyle(color: Tokens.danger, fontSize: 11.5),
      errorMaxLines: 3,
      helperMaxLines: 3,
      hintMaxLines: 2,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      border: themeFieldBorder(p),
      enabledBorder: themeFieldBorder(p),
      focusedBorder: themeFieldBorder(p, focused: true),
      errorBorder: themeFieldBorder(p, error: true),
      focusedErrorBorder: themeFieldBorder(p, error: true, focused: true),
      disabledBorder: themeFieldBorder(p),
      prefixIconColor: p.ink2,
      suffixIconColor: p.ink2,
    );

InputDecoration themedInputDecoration(
  BuildContext context, {
  String? labelText,
  String? hintText,
  String? helperText,
  String? errorText,
  Widget? suffixIcon,
  Widget? prefixIcon,
  bool isDense = true,
}) {
  final p = _formPalette(context);
  if (p.clean) {
    return InputDecoration(
      labelText: labelText,
      hintText: hintText,
      helperText: helperText,
      errorText: errorText,
      suffixIcon: suffixIcon,
      prefixIcon: prefixIcon,
      isDense: isDense,
      border: const OutlineInputBorder(),
      errorMaxLines: 3,
    );
  }
  return InputDecoration(
    labelText: labelText,
    hintText: hintText,
    helperText: helperText,
    errorText: errorText,
    suffixIcon: suffixIcon,
    prefixIcon: prefixIcon,
    isDense: isDense,
  ).applyDefaults(themedInputTheme(p));
}

/// A single decorated child: constraints propagate to scrollable dialogs/sheets.
class ThemeModalSurface extends StatelessWidget {
  const ThemeModalSurface({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final p = _formPalette(context);
    if (p.clean) return child;
    return DecoratedBox(
      decoration: ShapeDecoration(color: p.modal, shape: themeModalShape(p)),
      child: child,
    );
  }
}

class ThemedDialog extends StatelessWidget {
  const ThemedDialog({
    super.key,
    required this.child,
    this.backgroundColor,
    this.shape,
    this.insetPadding,
  });
  final Widget child;
  final Color? backgroundColor;
  final ShapeBorder? shape;
  final EdgeInsets? insetPadding;
  @override
  Widget build(BuildContext context) {
    final p = _formPalette(context);
    return Dialog(
      backgroundColor: p.clean ? backgroundColor : p.modal,
      surfaceTintColor: Colors.transparent,
      shape: p.clean ? (shape ?? themeModalShape(p)) : themeModalShape(p),
      clipBehavior: p.clean ? Clip.none : Clip.antiAlias,
      insetPadding:
          insetPadding ??
          const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: child,
    );
  }
}

/// Keep AlertDialog's intrinsic sizing, scrolling, actions and route semantics.
class ThemedAlertDialog extends StatelessWidget {
  const ThemedAlertDialog({
    super.key,
    this.title,
    this.content,
    this.actions,
    this.icon,
    this.backgroundColor,
    this.shape,
    this.contentPadding,
    this.titlePadding,
    this.actionsPadding,
    this.actionsAlignment,
    this.scrollable = false,
    this.insetPadding,
  });
  final Widget? title, content, icon;
  final List<Widget>? actions;
  final Color? backgroundColor;
  final ShapeBorder? shape;
  final EdgeInsetsGeometry? contentPadding, titlePadding, actionsPadding;
  final MainAxisAlignment? actionsAlignment;
  final bool scrollable;
  final EdgeInsets? insetPadding;
  @override
  Widget build(BuildContext context) {
    final p = _formPalette(context);
    return AlertDialog(
      title: p.clean || title == null || title is ThemeEditorHeading
          ? title
          : _ModalHeading(
              title: title!,
              kicker: 'CONFIRM / OPTIONS',
              icon: icon,
            ),
      icon: icon,
      content: content,
      actions: actions,
      backgroundColor: p.clean ? backgroundColor : p.modal,
      surfaceTintColor: Colors.transparent,
      shape: p.clean ? (shape ?? themeModalShape(p)) : themeModalShape(p),
      titlePadding: titlePadding ?? const EdgeInsets.fromLTRB(24, 24, 24, 4),
      contentPadding:
          contentPadding ?? const EdgeInsets.fromLTRB(24, 16, 24, 20),
      actionsPadding:
          actionsPadding ?? const EdgeInsets.fromLTRB(16, 0, 16, 14),
      actionsAlignment: actionsAlignment,
      insetPadding:
          insetPadding ??
          const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      scrollable: scrollable,
    );
  }
}

class ThemeEditorHeading extends StatelessWidget {
  const ThemeEditorHeading({
    super.key,
    required this.title,
    required this.kicker,
    this.icon,
    this.summary,
  });
  final String title, kicker;
  final IconData? icon;
  final String? summary;
  @override
  Widget build(BuildContext context) => _ModalHeading(
    title: Text(title),
    kicker: kicker,
    icon: icon == null ? null : Icon(icon),
    summary: summary,
  );
}

class _ModalHeading extends StatelessWidget {
  const _ModalHeading({
    required this.title,
    required this.kicker,
    this.icon,
    this.summary,
  });
  final Widget title;
  final String kicker;
  final Widget? icon;
  final String? summary;
  @override
  Widget build(BuildContext context) {
    final p = _formPalette(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DefaultTextStyle.merge(
          style: TextStyle(
            fontSize: 20,
            fontFamily: p.clay ? 'StudySerif' : null,
            fontWeight: p.clay
                ? FontWeight.w400
                : p.comic
                ? FontWeight.w800
                : FontWeight.w600,
            height: 1.35,
            color: p.ink,
          ),
          child: title,
        ),
        if (summary != null) ...[
          const SizedBox(height: 10),
          Text(
            summary!,
            style: TextStyle(fontSize: 13, height: 1.5, color: p.ink2),
          ),
        ],
      ],
    );
  }
}

class ThemeFieldGroup extends StatelessWidget {
  const ThemeFieldGroup({
    super.key,
    required this.title,
    required this.child,
    this.index = 1,
  });
  final String title;
  final Widget child;
  final int index;
  @override
  Widget build(BuildContext context) {
    final p = _formPalette(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 9),
          child: Row(
            children: [
              if (p.editorial) ...[
                Text(
                  index.toString().padLeft(2, '0'),
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: p.accent,
                  ),
                ),
                const SizedBox(width: 8),
              ],
              if (p.terminal || p.pixel)
                Text(
                  p.terminal ? '> ' : '+ ',
                  style: TextStyle(
                    fontFamily: 'monospace',
                    color: p.accent,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: p.ink2,
                    fontFamily: p.paper || p.journal
                        ? 'serif'
                        : p.terminal || p.receipt
                        ? 'monospace'
                        : null,
                  ),
                ),
              ),
            ],
          ),
        ),
        child,
      ],
    );
  }
}
