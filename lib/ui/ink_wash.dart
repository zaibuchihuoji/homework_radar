import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'adaptive.dart';
import 'tokens.dart';
import 'dashed_line.dart';

/// 水墨飞白分隔线：中段饱满、两端收锋，笔毛带干笔留白。
/// 与暖纸的虚线缝线、清夏的直线 Divider 构成三套分隔语言。
class BrushLine extends StatelessWidget {
  const BrushLine({super.key, this.color, this.thickness = 2.2});

  final Color? color;
  final double thickness;

  @override
  Widget build(BuildContext context) {
    final c = color ?? dividerColor(context);
    return SizedBox(
      width: double.infinity,
      height: 7,
      child: CustomPaint(
        painter: _BrushPainter(color: c, thickness: thickness),
      ),
    );
  }
}

class _BrushPainter extends CustomPainter {
  _BrushPainter({required this.color, required this.thickness});

  final Color color;
  final double thickness;

  @override
  void paint(Canvas canvas, Size size) {
    // 种子取宽度与笔宽，同尺寸每次绘制完全一致，避免逐帧抖动。
    final rnd = math.Random(size.width.toInt() * 31 + (thickness * 10).round());
    final midY = size.height / 2;
    const step = 2.5;
    final paint = Paint()..strokeCap = StrokeCap.round;
    for (double x = 0; x < size.width; x += step) {
      final t = x / size.width;
      final profile = math.sin(math.pi * t);
      final y = midY + math.sin(t * 9.2) * 0.5;
      final roll = rnd.nextDouble();
      final alpha = roll < 0.14 ? 0.08 : 0.55 + profile * 0.4;
      paint.color = color.withValues(alpha: alpha);
      paint.strokeWidth = thickness * (0.30 + 0.70 * profile);
      canvas.drawLine(Offset(x, y), Offset(x + step * 1.5, y), paint);
    }
  }

  @override
  bool shouldRepaint(_BrushPainter old) =>
      old.color != color || old.thickness != thickness;
}

/// AppBar 题字：水墨=衬线拉字距+落款小印（每页标题都钤一方印，
/// 全 app 统一的「题款」语言）；暖纸=衬线信纸体；其余样式常规标题。
/// 放在本文件而非 adaptive.dart，避免 adaptive ↔ ink_wash 循环 import。
Widget appBarTitle(BuildContext c, String text, {bool root = false}) {
  final pal = paletteOf(c);
  final base = TextStyle(
    fontSize: root
        ? (pal.clay ? 25 : 22)
        : pal.sunny || pal.clay
        ? 25
        : pal.editorial
        ? 19
        : 17,
    fontWeight: pal.comic || pal.editorial
        ? FontWeight.w800
        : pal.sunny
        ? FontWeight.w600
        : FontWeight.w700,
    fontFamily: pal.pixel || pal.receipt || pal.terminal
        ? 'monospace'
        : pal.journal
        ? 'serif'
        : null,
    color: textPrimary(c),
  );
  if (!isInkStyle(c)) {
    final title = Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: serifTitle(c, base),
    );
    if (pal.terminal || pal.pixel || pal.editorial || pal.morandi) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (pal.terminal)
            ExcludeSemantics(
              child: Text('> ', style: base.copyWith(color: pal.accent)),
            )
          else if (pal.pixel)
            Container(
              width: 9,
              height: 9,
              margin: const EdgeInsets.only(right: 8),
              color: pal.accent,
            )
          else if (pal.editorial)
            Container(
              width: 3,
              height: 20,
              margin: const EdgeInsets.only(right: 8),
              color: pal.accent,
            )
          else
            Container(
              width: 7,
              height: 7,
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                color: pal.accent.withValues(alpha: 0.6),
                shape: BoxShape.circle,
              ),
            ),
          Flexible(child: title),
        ],
      );
    }
    if (pal.comic) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: pal.card,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: pal.cardBorder, width: 1.5),
        ),
        child: title,
      );
    }
    if (pal.receipt || pal.paper) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          title,
          const SizedBox(height: 3),
          SizedBox(width: 90, child: DashedLine(color: pal.cardBorder)),
        ],
      );
    }
    if (pal.journal) {
      return Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(top: -5, left: 5, child: journalTape(c, text, width: 33)),
          Padding(padding: const EdgeInsets.only(top: 4), child: title),
        ],
      );
    }
    return title;
  }
  return Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Flexible(
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: inkTitle(c, serifTitle(c, base)),
        ),
      ),
      const SizedBox(width: 7),
      const InkSealChip(),
    ],
  );
}

/// 落款小印：水墨风格的标题旁一枚朱砂方印（画完成后钤印的落款）。
/// 只在水墨样式下由调用方决定是否出现，组件本身不做样式判断。
class InkSealChip extends StatelessWidget {
  const InkSealChip({super.key, this.glyph = '墨', this.size = 16});

  final String glyph;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: accentColor(context),
        borderRadius: BorderRadius.circular(size * 0.16),
      ),
      child: Text(
        glyph,
        style: TextStyle(
          color: onAccentColor(context),
          fontSize: size * 0.6,
          fontWeight: FontWeight.w700,
          fontFamily: 'serif',
          height: 1.0,
        ),
      ),
    );
  }
}

/// 远山淡墨：三层山影（远淡近浓）+ 两三只飞鸟，水墨的「平远」构图。
/// 山体自山脊向下渐隐入雾（留白），只用墨色——深色模式换白墨。
/// 纯装饰，IgnorePointer 不挡手。
class InkMountains extends StatelessWidget {
  const InkMountains({super.key, this.height = 150});

  final double height;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return IgnorePointer(
      child: CustomPaint(
        size: Size(double.infinity, height),
        painter: _MountainsPainter(ink: dark ? Colors.white : Colors.black),
      ),
    );
  }
}

class _MountainsPainter extends CustomPainter {
  _MountainsPainter({required this.ink});

  final Color ink;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    // 三层山：远山最高最淡，近山最矮最浓；(x, y) 都是相对宽高的 0~1。
    _layer(
      canvas,
      const [
        (0.00, 0.46),
        (0.16, 0.14),
        (0.33, 0.46),
        (0.52, 0.08),
        (0.70, 0.42),
        (0.88, 0.20),
        (1.00, 0.46),
      ],
      0.10,
      w,
      h,
    );
    _layer(
      canvas,
      const [
        (0.00, 0.62),
        (0.13, 0.42),
        (0.31, 0.66),
        (0.49, 0.36),
        (0.67, 0.62),
        (0.83, 0.48),
        (1.00, 0.68),
      ],
      0.15,
      w,
      h,
    );
    _layer(
      canvas,
      const [
        (0.00, 0.82),
        (0.21, 0.64),
        (0.41, 0.86),
        (0.63, 0.60),
        (0.85, 0.80),
        (1.00, 0.70),
      ],
      0.21,
      w,
      h,
    );
    _bird(canvas, Offset(w * 0.78, h * 0.16), 7, 0.42);
    _bird(canvas, Offset(w * 0.87, h * 0.10), 5, 0.36);
    _bird(canvas, Offset(w * 0.70, h * 0.26), 4.5, 0.30);
  }

  void _layer(
    Canvas canvas,
    List<(double, double)> pts,
    double alpha,
    double w,
    double h,
  ) {
    final path = Path()..moveTo(0, pts.first.$2 * h);
    for (var i = 1; i < pts.length; i++) {
      final px = pts[i - 1].$1 * w, py = pts[i - 1].$2 * h;
      final x = pts[i].$1 * w, y = pts[i].$2 * h;
      // 控制点取 (中点, 前点高度)：出笔水平、峰顶圆浑，山谷自然收拢
      path.quadraticBezierTo((px + x) / 2, py, x, y);
    }
    path
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    final paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          ink.withValues(alpha: alpha),
          ink.withValues(alpha: alpha * 0.10),
        ],
      ).createShader(Rect.fromLTWH(0, 0, w, h));
    canvas.drawPath(path, paint);
  }

  void _bird(Canvas canvas, Offset c, double s, double alpha) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round
      ..color = ink.withValues(alpha: alpha);
    final path = Path()
      ..moveTo(c.dx - s, c.dy)
      ..quadraticBezierTo(c.dx - s * 0.45, c.dy - s * 0.6, c.dx, c.dy)
      ..quadraticBezierTo(c.dx + s * 0.45, c.dy - s * 0.6, c.dx + s, c.dy);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_MountainsPainter old) => old.ink != ink;
}
