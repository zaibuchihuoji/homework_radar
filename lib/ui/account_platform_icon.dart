import 'package:flutter/material.dart';

import 'tokens.dart';

/// Local vector marks: independent of network images and platform font glyphs.
class AccountPlatformIcon extends StatelessWidget {
  const AccountPlatformIcon({super.key, required this.index, this.size = 48});
  final int index;
  final double size;

  @override
  Widget build(BuildContext context) {
    final p = paletteOf(context);
    final mono = p.pixel || p.receipt || p.terminal || p.inkWash;
    final brand = const [
      Color(0xFFCF850E),
      Color(0xFF259351),
      Color(0xFFD65C57),
      Color(0xFF426DC5),
      Color(0xFF228FCA),
      Color(0xFF58699A),
    ][index - 1];
    final ink = mono ? p.ink : brand;
    final radius = p.pixel || p.receipt || p.terminal
        ? 3.0
        : p.paper || p.journal
        ? 9.0
        : size * .29;
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Color.alphaBlend(
            ink.withValues(alpha: mono ? .045 : .085),
            p.card,
          ),
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: ink.withValues(alpha: mono ? .22 : .12)),
        ),
        padding: EdgeInsets.all(size * .14),
        child: CustomPaint(painter: _PlatformMark(index, ink)),
      ),
    );
  }
}

class _PlatformMark extends CustomPainter {
  const _PlatformMark(this.index, this.ink);
  final int index;
  final Color ink;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 40, size.height / 40);
    final fill = Paint()..color = ink;
    final line = Paint()
      ..color = ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.7
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    switch (index) {
      case 1:
        // A compact cap, an open book and a separate tassel.
        canvas.drawPath(
          Path()
            ..moveTo(3, 14)
            ..lineTo(20, 6)
            ..lineTo(37, 14)
            ..lineTo(20, 22)
            ..close(),
          fill,
        );
        canvas.drawPath(
          Path()
            ..moveTo(10, 21)
            ..lineTo(10, 28)
            ..quadraticBezierTo(20, 34, 30, 28)
            ..lineTo(30, 21),
          line,
        );
        canvas.drawPath(
          Path()
            ..moveTo(36, 16)
            ..lineTo(36, 27),
          line..strokeWidth = 2,
        );
        canvas.drawCircle(const Offset(36, 29), 2, fill);
      case 2:
        // A folded M; the open bottom keeps the small mark clear.
        canvas.drawPath(
          Path()
            ..moveTo(5, 31)
            ..lineTo(5, 10)
            ..quadraticBezierTo(5, 6, 8, 8)
            ..lineTo(20, 21)
            ..lineTo(32, 8)
            ..quadraticBezierTo(35, 6, 35, 10)
            ..lineTo(35, 31),
          line..strokeWidth = 4.7,
        );
        canvas.drawLine(
          const Offset(15, 30),
          const Offset(25, 30),
          line..strokeWidth = 2.5,
        );
      case 3:
        canvas.drawPath(
          Path()
            ..moveTo(20, 33)
            ..lineTo(20, 18)
            ..moveTo(20, 25)
            ..lineTo(12, 19)
            ..moveTo(20, 27)
            ..lineTo(29, 20),
          line,
        );
        canvas.drawOval(const Rect.fromLTWH(15, 3, 10, 16), fill);
        canvas.save();
        canvas.rotate(-.5);
        canvas.drawOval(const Rect.fromLTWH(-2, 12, 11, 15), fill);
        canvas.restore();
        canvas.save();
        canvas.translate(29, 19);
        canvas.rotate(.6);
        canvas.drawOval(const Rect.fromLTWH(-5, -7, 10, 15), fill);
        canvas.restore();
        canvas.drawLine(
          const Offset(12, 35),
          const Offset(28, 35),
          line..strokeWidth = 2.2,
        );
      case 4:
        // Crossed study ribbons, with an independent spark.
        canvas.drawPath(
          Path()
            ..moveTo(8, 11)
            ..lineTo(16, 11)
            ..lineTo(32, 32)
            ..lineTo(24, 32)
            ..close(),
          fill,
        );
        canvas.drawPath(
          Path()
            ..moveTo(25, 11)
            ..lineTo(33, 11)
            ..lineTo(16, 32)
            ..lineTo(8, 32)
            ..close(),
          fill..color = ink.withValues(alpha: .6),
        );
        fill.color = ink;
        canvas.drawPath(
          Path()
            ..moveTo(28, 2)
            ..lineTo(30, 6)
            ..lineTo(34, 8)
            ..lineTo(30, 10)
            ..lineTo(28, 14)
            ..lineTo(26, 10)
            ..lineTo(22, 8)
            ..lineTo(26, 6)
            ..close(),
          fill,
        );
      case 5:
        canvas.drawPath(
          Path()
            ..moveTo(10, 25)
            ..cubicTo(0, 25, 1, 13, 10, 13)
            ..cubicTo(12, 1, 29, 3, 30, 14)
            ..cubicTo(39, 13, 40, 25, 30, 25)
            ..close(),
          line,
        );
        canvas.drawLine(const Offset(14, 30), const Offset(12, 35), line);
        canvas.drawLine(const Offset(24, 30), const Offset(22, 35), line);
        canvas.drawCircle(const Offset(25, 13), 2.4, fill);
      case 6:
        canvas.drawPath(
          Path()
            ..moveTo(4, 14)
            ..lineTo(20, 5)
            ..lineTo(36, 14)
            ..close(),
          fill,
        );
        for (final x in [10.0, 20.0, 30.0]) {
          canvas.drawLine(
            Offset(x, 19),
            Offset(x, 29),
            line..strokeWidth = 3.5,
          );
        }
        canvas.drawLine(
          const Offset(5, 34),
          const Offset(35, 34),
          line..strokeWidth = 3,
        );
        canvas.drawCircle(
          const Offset(20, 11),
          1.5,
          Paint()..color = Colors.white.withValues(alpha: .8),
        );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_PlatformMark old) => old.index != index || old.ink != ink;
}
