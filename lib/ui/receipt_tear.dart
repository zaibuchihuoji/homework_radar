/// 小票的「撕下」动画：长按菜单选「撕掉这张小票」后播放——撕口从
/// 右下角出现，斜着往左上角慢慢推进，失了支撑的纸身绕左上角下垂、
/// 远端渐隐，最后行高收拢、回调 onTorn 由调用方移除条目。
/// 只在小票主题下使用；该主题下作业卡不走滑动删除（Dismissible），
/// 删除入口在长按菜单。
library;

import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

class ReceiptTearOut extends StatefulWidget {
  const ReceiptTearOut({
    super.key,
    required this.seed,
    required this.child,
    this.onTorn,
  });

  /// 撕线锯齿的随机种子（同一条作业恒定）
  final int seed;
  final Widget child;

  /// 撕完并收拢后回调（此时卡片已不可见、行高为 0），调用方在此移除条目
  final VoidCallback? onTorn;

  @override
  State<ReceiptTearOut> createState() => ReceiptTearOutState();
}

class ReceiptTearOutState extends State<ReceiptTearOut>
    with SingleTickerProviderStateMixin {
  // 0~0.78 撕纸（斜撕口推进），0.8~1 行高收拢（卡已不可见，只为平滑闭合空隙）
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..addStatusListener((s) {
      if (s == AnimationStatus.completed) widget.onTorn?.call();
    });

  late final Animation<double> _tearT = CurvedAnimation(
    parent: _ctrl,
    curve: const Interval(0, 0.78, curve: Curves.easeInOut),
  );
  late final Animation<double> _sizeT = Tween(begin: 1.0, end: 0.0).animate(
    CurvedAnimation(
      parent: _ctrl,
      curve: const Interval(0.8, 1.0, curve: Curves.easeIn),
    ),
  );

  bool _playing = false;

  void play(DismissDirection direction) {
    if (_playing) return;
    _playing = true;
    _ctrl.forward(from: 0);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizeTransition(
      sizeFactor: _sizeT,
      child: AnimatedBuilder(
        animation: _ctrl,
        child: widget.child,
        builder: (context, child) {
          final raw = _ctrl.value;
          final t = _tearT.value;
          if (raw == 0) return child!;
          // 撕程结束（0.78）后卡必须保持不可见直到收拢——
          // 直接还 child 会闪回一帧完整的卡
          if (raw >= 0.78) return const SizedBox.shrink();
          return ClipPath(
            clipper: _CornerTearClipper(progress: t, seed: widget.seed),
            child: Opacity(
              // 尾段渐隐，撕线扫到左上角时纸已不见
              opacity:
                  raw > 0.55 ? (1 - (raw - 0.55) / 0.23).clamp(0.0, 1.0) : 1.0,
              child: Transform.translate(
                offset: Offset(t * 20, t * t * 130),
                child: Transform.rotate(
                  angle: t * 0.14,
                  alignment: Alignment.topLeft,
                  child: child,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// 斜角撕线裁剪：consumed = {x + y > c}（右下角区），c 从 w+h（空）降到
/// 0（全撕），撕口是带确定性锯齿的 45° 斜线；保留区 = 线的左上侧。
/// 全保留时下界放到 rect 外 8px——小票装饰本身的锯齿底边伸出矩形，
/// 不能被裁平。
class _CornerTearClipper extends CustomClipper<Path> {
  const _CornerTearClipper({required this.progress, required this.seed});

  final double progress;
  final int seed;

  @override
  Path getClip(Size size) {
    final w = size.width;
    final h = size.height + 8; // 含装饰撕边的外廓
    if (progress <= 0) return Path()..addRect(Rect.fromLTWH(0, 0, w, h));
    if (progress >= 1) return Path();
    final c = lerpDouble(w + h, 0, progress)!;

    // 撕口直线 x+y=c 与矩形边界的两个交点：
    // 右/上侧端点（可见区沿顶边或右边走到它），左/下侧端点（沿底边或左边回来）
    final Offset topPt;
    if (c >= w) {
      topPt = Offset(w, c - w);
    } else {
      topPt = Offset(c, 0);
    }
    final Offset bottomPt;
    if (c >= h) {
      bottomPt = Offset(c - h, h);
    } else {
      bottomPt = Offset(0, c);
    }

    final path = Path()..moveTo(0, 0);
    if (c >= w) path.lineTo(w, 0); // 先走到右上角再下来
    path.lineTo(topPt.dx, topPt.dy);

    // 撕口锯齿：沿线段细分，垂直方向抖动（种子确定性）
    final seg = bottomPt - topPt;
    final len = seg.distance;
    final n = math.max(4, (len / 16).ceil());
    final normal = Offset(-seg.dy, seg.dx) / (len <= 0 ? 1 : len);
    var hh = seed & 0x7FFFFFFF;
    path.lineTo(topPt.dx, topPt.dy);
    for (var i = 1; i < n; i++) {
      hh = (hh * 1103515245 + 12345) & 0x7FFFFFFF;
      final amp = ((hh >> 8) % 9 - 4).toDouble(); // -4~4px
      final p = i / n;
      final base = topPt + seg * p;
      path.lineTo(base.dx + normal.dx * amp, base.dy + normal.dy * amp);
    }
    path.lineTo(bottomPt.dx, bottomPt.dy);

    if (c >= h) {
      path.lineTo(0, h);
    }
    path.close();
    return path;
  }

  @override
  bool shouldReclip(_CornerTearClipper old) => old.progress != progress;
}
