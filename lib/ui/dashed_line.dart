import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'adaptive.dart';

/// 虚线（缝线）分隔线：暖纸样式的分隔语言，其余样式继续用 Divider。
class DashedLine extends StatelessWidget {
  const DashedLine({super.key, this.color, this.thickness = 1});

  final Color? color;
  final double thickness;

  @override
  Widget build(BuildContext context) {
    final c = color ?? dividerColor(context);
    return SizedBox(
      width: double.infinity,
      height: thickness,
      child: CustomPaint(
        painter: _DashedPainter(color: c, thickness: thickness),
      ),
    );
  }
}

class _DashedPainter extends CustomPainter {
  _DashedPainter({required this.color, required this.thickness});

  final Color color;
  final double thickness;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = thickness
      ..strokeCap = StrokeCap.round;
    const dash = 4.0;
    const gap = 3.5;
    for (double x = 0; x < size.width; x += dash + gap) {
      canvas.drawLine(Offset(x, size.height / 2),
          Offset(math.min(x + dash, size.width), size.height / 2), paint);
    }
  }

  @override
  bool shouldRepaint(_DashedPainter old) =>
      old.color != color || old.thickness != thickness;
}

/// 暖纸缝线：卡片外框内缩一圈虚线细框，像本子的缝线。
/// BoxDecoration 的 Border 画不了虚线，自绘。
class StitchDecoration extends Decoration {
  const StitchDecoration({required this.radius, required this.color});

  final double radius;
  final Color color;

  @override
  BoxPainter createBoxPainter([void Function()? onChanged]) =>
      _StitchPainter(this);
}

class _StitchPainter extends BoxPainter {
  _StitchPainter(this.decoration);

  final StitchDecoration decoration;

  @override
  void paint(Canvas canvas, Offset offset, ImageConfiguration configuration) {
    final size = configuration.size;
    if (size == null || size.isEmpty) return;
    final rrect = RRect.fromRectAndRadius(
      (offset & size).deflate(5),
      Radius.circular(math.max(0, decoration.radius - 5)),
    );
    final paint = Paint()
      ..color = decoration.color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final path = Path()..addRRect(rrect);
    const dash = 4.0;
    const gap = 3.0;
    for (final metric in path.computeMetrics()) {
      for (double d = 0; d < metric.length; d += dash + gap) {
        canvas.drawPath(
          metric.extractPath(d, math.min(d + dash, metric.length)),
          paint,
        );
      }
    }
  }
}
