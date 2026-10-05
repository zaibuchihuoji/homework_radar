/// 页面底衬：莫兰迪样式是「奶油画布」——燕麦底上三团低饱和色雾
/// （灰粉/灰绿/奶白）朦胧相融，这是莫兰迪的灵魂：几个温柔的颜色
/// 在一起；像素样式铺 LCD 点阵；小票铺热敏纸纹；终端铺 CRT 扫描线；
/// 手账铺横格纸+装订孔；杂志走纯平（排版密度就是装饰，背景必须素）；
/// 其余样式原样透传。由各标签页在自身 Scaffold 外包裹，弹层不经过这里。
///
/// 配套约束：带底衬的样式 Scaffold 必须 transparent（scaffoldBgOf），
/// 否则不透明底色把底衬整个盖住——莫兰迪色雾/像素点阵曾因此从未上屏。
///
/// 不用 BackdropFilter：Impeller 下与日历页的 ClipRect/PageView 组合
/// 会把整个页面内容一起糊掉（真机复现），且每帧多一次全屏 saveLayer。
library;

import 'package:flutter/material.dart';

import 'adaptive.dart';
import 'tokens.dart';

class StyleBackground extends StatelessWidget {
  const StyleBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final pal = paletteOf(context);
    if (pal.morandi) {
      final dark = isDark(context);
      // (颜色, 半径, 位置) —— 位置铺满整屏，色团彼此交叠才有「融」的感觉
      final blobs = dark
          ? const [
              (Color(0xFF4A3B33), 190.0, Offset(0.18, 0.22)),
              (Color(0xFF39443B), 210.0, Offset(0.85, 0.45)),
              (Color(0xFF4E4841), 170.0, Offset(0.40, 0.88)),
            ]
          : const [
              (Color(0xFFE3C8BC), 190.0, Offset(0.18, 0.22)),
              (Color(0xFFC9D2BC), 210.0, Offset(0.85, 0.45)),
              (Color(0xFFFBF7F0), 170.0, Offset(0.40, 0.88)),
            ];
      return Stack(
        children: [
          Positioned.fill(child: ColoredBox(color: pal.bg)),
          for (final (color, radius, pos) in blobs)
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment(pos.dx * 2 - 1, pos.dy * 2 - 1),
                    radius: radius / 400,
                    colors: [
                      color.withValues(alpha: dark ? 0.55 : 0.85),
                      color.withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
            ),
          child,
        ],
      );
    }
    if (pal.pixel) {
      // 像素屏：点阵背景（LCD 像素格），内容浮在「屏幕」上
      final dark = Theme.of(context).brightness == Brightness.dark;
      return Stack(
        children: [
          Positioned.fill(child: ColoredBox(color: pal.bg)),
          Positioned.fill(
            child: CustomPaint(
              painter: _DotMatrixPainter(
                color: dark
                    ? Colors.white.withValues(alpha: 0.05)
                    : Colors.black.withValues(alpha: 0.06),
              ),
            ),
          ),
          child,
        ],
      );
    }
    if (pal.editorial) {
      // 杂志：纯纸面 + 左缘一道通天「书脊」——装订边把整页锚在纸面上
      return Stack(
        children: [
          Positioned.fill(child: ColoredBox(color: pal.bg)),
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: 5,
            child: ColoredBox(color: pal.cardBorder),
          ),
          child,
        ],
      );
    }
    if (pal.receipt) {
      // 柜台上的热敏纸：极淡的横向纸纹（打印介质自己的肌理）
      final dark = Theme.of(context).brightness == Brightness.dark;
      return Stack(
        children: [
          Positioned.fill(child: ColoredBox(color: pal.bg)),
          Positioned.fill(
            child: CustomPaint(
              painter: _GrainPainter(
                color: dark
                    ? Colors.white.withValues(alpha: 0.03)
                    : Colors.black.withValues(alpha: 0.035),
              ),
            ),
          ),
          child,
        ],
      );
    }
    if (pal.terminal) {
      // CRT 扫描线：文本模式的介质感，淡到不抢读
      final dark = Theme.of(context).brightness == Brightness.dark;
      return Stack(
        children: [
          Positioned.fill(child: ColoredBox(color: pal.bg)),
          Positioned.fill(
            child: CustomPaint(
              painter: _ScanlinePainter(
                color: dark
                    ? Colors.white.withValues(alpha: 0.035)
                    : Colors.black.withValues(alpha: 0.045),
              ),
            ),
          ),
          child,
        ],
      );
    }
    if (pal.journal) {
      // 活页本摊开：横格纸 + 左侧装订孔 + 页边线
      final dark = Theme.of(context).brightness == Brightness.dark;
      return Stack(
        children: [
          Positioned.fill(child: ColoredBox(color: pal.bg)),
          Positioned.fill(
            child: CustomPaint(
              painter: _RuledPaperPainter(dark: dark, pal: pal),
            ),
          ),
          child,
        ],
      );
    }
    return child;
  }
}

/// 点阵：12px 一格的像素点，确定性绘制
class _DotMatrixPainter extends CustomPainter {
  const _DotMatrixPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    for (double y = 6; y < size.height; y += 12) {
      for (double x = 6; x < size.width; x += 12) {
        canvas.drawCircle(Offset(x, y), 1.0, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DotMatrixPainter old) => old.color != color;
}

/// 热敏纸纹：4px 间距的极淡横线，粗细交替模拟打印介质
class _GrainPainter extends CustomPainter {
  const _GrainPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    var i = 0;
    for (double y = 2; y < size.height; y += 4) {
      paint.strokeWidth = i.isEven ? 1.0 : 0.6;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
      i++;
    }
  }

  @override
  bool shouldRepaint(_GrainPainter old) => old.color != color;
}

/// CRT 扫描线：3px 一道 1px 细线
class _ScanlinePainter extends CustomPainter {
  const _ScanlinePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    for (double y = 1.5; y < size.height; y += 3) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(_ScanlinePainter old) => old.color != color;
}

/// 活页横格纸：26px 间距横格 + 左侧 34px 处页边竖线 + 沿边装订孔
class _RuledPaperPainter extends CustomPainter {
  const _RuledPaperPainter({required this.dark, required this.pal});

  final bool dark;
  final StylePalette pal;

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = dark
          ? const Color(0xFF4A5A6A).withValues(alpha: 0.20)
          : const Color(0xFF8FA8C0).withValues(alpha: 0.28)
      ..strokeWidth = 1;
    for (double y = 44; y < size.height; y += 26) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
    }
    // 页边线：红色竖线是笔记本的肌肉记忆
    canvas.drawLine(
      const Offset(34, 0),
      Offset(34, size.height),
      Paint()
        ..color = (dark ? const Color(0xFFB0554A) : const Color(0xFFD07A6A))
            .withValues(alpha: 0.30)
        ..strokeWidth = 1.2,
    );
    // 装订孔：沿左缘均布，孔是「打穿」的——填底色再描一圈暗环
    final holeY = size.height / 5;
    for (var i = 0; i < 5; i++) {
      final center = Offset(17, holeY * i + holeY / 2);
      canvas.drawCircle(center, 5.5, Paint()..color = pal.bg);
      canvas.drawCircle(
        center,
        5.5,
        Paint()
          ..color = (dark ? Colors.black : const Color(0xFF8A7A5A))
              .withValues(alpha: 0.35)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2,
      );
    }
  }

  @override
  bool shouldRepaint(_RuledPaperPainter old) =>
      old.dark != dark || old.pal != pal;
}
