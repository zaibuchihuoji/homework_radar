/// 深浅色 × 样式自适应的颜色辅助。颜色一律来自当前 StylePalette
/// （tokens.dart，随样式与明暗双维变化），不要在这里新增色值。
library;

import 'package:flutter/material.dart';

import 'dashed_line.dart';
import '../services/stable_hash.dart';
import 'tokens.dart';

bool isDark(BuildContext c) => Theme.of(c).brightness == Brightness.dark;

bool isCleanStyle(BuildContext c) => _pal(c).clean;

StylePalette _pal(BuildContext c) => paletteOf(c);

Color bgColor(BuildContext c) => _pal(c).bg;

Color cardColor(BuildContext c) => _pal(c).card;

/// 弹层（对话框/菜单/底部弹窗）底色：比卡片更实的读层面。
Color modalColor(BuildContext c) => _pal(c).modal;

Color cardBorderColor(BuildContext c) => _pal(c).cardBorder;

/// 卡片描边：无描边样式返回 null。
/// 不做逐边异色描边——Impeller 下「非均匀 Border + 圆角」会让
/// 未裁剪容器的内容子树整体不绘制（真机复现）。
Border? cardBorderOf(BuildContext c) {
  final pal = _pal(c);
  if (pal.cardBorder.a == 0) return null;
  return Border.all(
    color: pal.cardBorder,
    width: (pal.comic || pal.pixel) ? 2.0 : 1.0,
  );
}

/// 漫画对话框徽标：圆角气泡 + 左下一条小尾巴（谁在说话一目了然），
/// 勾线一体绘制——整条外轮廓（含尾巴）用同一条 Path 描出，无接缝。
/// 用作平台/状态徽标的底（hw_card），字与色点由调用方叠在 child 里。
class BubbleDecoration extends Decoration {
  const BubbleDecoration({
    required this.fillColor,
    required this.borderColor,
    this.radius = 8,
    this.borderWidth = 1.6,
  });

  final Color fillColor;
  final Color borderColor;
  final double radius;
  final double borderWidth;

  @override
  BoxPainter createBoxPainter([void Function()? onChanged]) =>
      _BubblePainter(this);
}

class _BubblePainter extends BoxPainter {
  _BubblePainter(this.d);

  final BubbleDecoration d;

  @override
  void paint(Canvas canvas, Offset offset, ImageConfiguration cfg) {
    final size = cfg.size;
    if (size == null || size.isEmpty) return;
    // 尾巴占用的底部空间由调用方以 padding 预留
    final rect = (offset & size).deflate(0);
    const tailH = 5.0;
    final tailX = rect.left + 9.0;
    final r = Radius.circular(d.radius);
    final path = Path()
      ..moveTo(rect.left, rect.top + d.radius)
      ..arcToPoint(Offset(rect.left + d.radius, rect.top), radius: r)
      ..lineTo(rect.right - d.radius, rect.top)
      ..arcToPoint(Offset(rect.right, rect.top + d.radius), radius: r)
      ..lineTo(rect.right, rect.bottom - d.radius)
      ..arcToPoint(Offset(rect.right - d.radius, rect.bottom), radius: r)
      ..lineTo(tailX + 9, rect.bottom)
      ..lineTo(tailX, rect.bottom + tailH)
      ..lineTo(rect.left + 3, rect.bottom)
      ..lineTo(rect.left + d.radius, rect.bottom)
      ..arcToPoint(Offset(rect.left, rect.bottom - d.radius), radius: r)
      ..close();
    canvas
      ..drawPath(path, Paint()..color = d.fillColor)
      ..drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = d.borderWidth
          ..strokeJoin = StrokeJoin.round
          ..color = d.borderColor,
      );
  }
}

/// 莫兰迪奶霜面：卡片顶部一层柔和的奶白光泽（像奶油表面的反光），
/// 与漫画的硬边高光、玻璃的强受光都不同——莫兰迪要的是雾面奶油的柔。
/// 叠在前景（foregroundDecoration），非莫兰迪返回 null。
BoxDecoration? morandiCream(BuildContext c, double radius) {
  final pal = _pal(c);
  if (!pal.morandi) return null;
  return BoxDecoration(
    borderRadius: BorderRadius.circular(radius),
    gradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        Colors.white.withValues(alpha: isDark(c) ? 0.06 : 0.5),
        Colors.white.withValues(alpha: 0),
      ],
      stops: const [0.0, 0.3],
    ),
  );
}

/// 像素窗框：阶梯锯齿直角 + 复古游戏窗口双边框（外粗内细），
/// 自带阶梯形硬投影。线全是直的、角全是台阶的——像素风的骨架。
/// 叠在前景（foregroundDecoration），非像素返回 null。
Decoration? pixelFrame(BuildContext c, double radius) {
  final pal = _pal(c);
  if (!pal.pixel) return null;
  return PixelFrameDecoration(lineColor: pal.cardBorder);
}

class PixelFrameDecoration extends Decoration {
  const PixelFrameDecoration({required this.lineColor});

  final Color lineColor;

  // 阶梯角外轮廓：s 为单阶尺寸，四角各两级台阶
  static Path steppedPath(Rect rect, double s) {
    final l = rect.left, t = rect.top, r = rect.right, b = rect.bottom;
    return Path()
      ..moveTo(l, t + 2 * s)
      ..lineTo(l + s, t + 2 * s)
      ..lineTo(l + s, t + s)
      ..lineTo(l + 2 * s, t + s)
      ..lineTo(l + 2 * s, t)
      ..lineTo(r - 2 * s, t)
      ..lineTo(r - 2 * s, t + s)
      ..lineTo(r - s, t + s)
      ..lineTo(r - s, t + 2 * s)
      ..lineTo(r, t + 2 * s)
      ..lineTo(r, b - 2 * s)
      ..lineTo(r - s, b - 2 * s)
      ..lineTo(r - s, b - s)
      ..lineTo(r - 2 * s, b - s)
      ..lineTo(r - 2 * s, b)
      ..lineTo(l + 2 * s, b)
      ..lineTo(l + 2 * s, b - s)
      ..lineTo(l + s, b - s)
      ..lineTo(l + s, b)
      ..lineTo(l, b)
      ..close();
  }

  @override
  Path getClipPath(Rect rect, TextDirection textDirection) =>
      steppedPath(rect, 3);

  @override
  BoxPainter createBoxPainter([void Function()? onChanged]) =>
      _PixelFramePainter(this);
}

class _PixelFramePainter extends BoxPainter {
  _PixelFramePainter(this.d);

  final PixelFrameDecoration d;

  @override
  void paint(Canvas canvas, Offset offset, ImageConfiguration cfg) {
    final size = cfg.size;
    if (size == null || size.isEmpty) return;
    final rect = offset & size;
    final path = PixelFrameDecoration.steppedPath(rect, 3);
    // 前景层画在 child 之后：只能描线，不能灌填充/投影
    //（2026-10-05 复现：不透明填充会把整卡内容盖没）
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..color = d.lineColor,
    );
    // 复古窗口内线：缩进 4px 的细边
    final inner = PixelFrameDecoration.steppedPath(rect.deflate(4.5), 2);
    canvas.drawPath(
      inner,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.1
        ..color = d.lineColor.withValues(alpha: 0.45),
    );
  }
}

/// 小票撕纸卡面：整张卡是一个热敏收据——底边锯齿（齿尖朝下）+
/// 平移复制的硬投影。齿尖伸出矩形 5px，调用方在卡底多留 5px 内边距。
/// 叠在 decoration（背景位），getClipPath 一并给出（Impeller 教训：
/// 自定义装饰必须自带裁剪路径，否则配 Clip 时内容子树整体消失）。
Decoration? receiptTear(BuildContext c) {
  final pal = _pal(c);
  if (!pal.receipt) return null;
  return ReceiptTearDecoration(
    fill: pal.card,
    shadow: pal.shadow.isEmpty ? null : pal.shadow.first.color,
  );
}

class ReceiptTearDecoration extends Decoration {
  const ReceiptTearDecoration({required this.fill, this.shadow});

  final Color fill;
  final Color? shadow;

  static Path tearPath(Rect rect, double tw, double th) {
    final p = Path()
      ..moveTo(rect.left, rect.top)
      ..lineTo(rect.right, rect.top)
      ..lineTo(rect.right, rect.bottom);
    var x = rect.right;
    while (x - tw >= rect.left) {
      p.lineTo(x - tw / 2, rect.bottom + th);
      x -= tw;
      p.lineTo(x, rect.bottom);
    }
    p.lineTo(rect.left, rect.bottom);
    p.close();
    return p;
  }

  @override
  Path getClipPath(Rect rect, TextDirection textDirection) =>
      tearPath(rect, 11, 5);

  @override
  BoxPainter createBoxPainter([void Function()? onChanged]) =>
      _ReceiptTearPainter(this);
}

class _ReceiptTearPainter extends BoxPainter {
  _ReceiptTearPainter(this.d);

  final ReceiptTearDecoration d;

  @override
  void paint(Canvas canvas, Offset offset, ImageConfiguration cfg) {
    final size = cfg.size;
    if (size == null || size.isEmpty) return;
    final rect = offset & size;
    final path = ReceiptTearDecoration.tearPath(rect, 11, 5);
    final shadow = d.shadow;
    if (shadow != null && shadow.a > 0) {
      canvas.drawPath(
        path.shift(const Offset(0, 2.5)),
        Paint()..color = shadow,
      );
    }
    canvas.drawPath(path, Paint()..color = d.fill);
  }
}

/// 杂志版块规则线：卡片去盒化——上下两条印刷规则线（上粗下细），
/// 无阴影无描边框，排版密度就是它的装饰。叠在前景，只描线不灌色。
Decoration? editorialRules(BuildContext c) {
  final pal = _pal(c);
  if (!pal.editorial) return null;
  return EditorialRulesDecoration(rule: pal.cardBorder, hairline: pal.hairline);
}

class EditorialRulesDecoration extends Decoration {
  const EditorialRulesDecoration({required this.rule, required this.hairline});

  final Color rule;
  final Color hairline;

  @override
  BoxPainter createBoxPainter([void Function()? onChanged]) =>
      _EditorialRulesPainter(this);
}

class _EditorialRulesPainter extends BoxPainter {
  _EditorialRulesPainter(this.d);

  final EditorialRulesDecoration d;

  @override
  void paint(Canvas canvas, Offset offset, ImageConfiguration cfg) {
    final size = cfg.size;
    if (size == null || size.isEmpty) return;
    final rect = offset & size;
    final rp = Paint()..color = d.rule;
    // Oxford 双线：粗线压顶，隔 2px 一道细线——报纸版块的经典记号
    canvas.drawRect(Rect.fromLTWH(rect.left, rect.top, rect.width, 2.2), rp);
    canvas.drawRect(
      Rect.fromLTWH(rect.left, rect.top + 4.2, rect.width, 1),
      rp,
    );
    canvas.drawRect(
      Rect.fromLTWH(rect.left, rect.bottom - 1, rect.width, 1),
      Paint()..color = d.rule.withValues(alpha: 0.35),
    );
  }
}

/// 手账和纸胶带：贴在卡片顶角、微微出斜的半透明胶带条。
/// 返回现成的 Container（含定色定角），调用方包 Positioned 定位。
/// 颜色/角度由 [seed]（作业标识）经 stableHash 决定——同一作业恒定。
Widget journalTape(BuildContext c, String seed, {double width = 62}) {
  const tapes = <Color>[
    Color(0xFFE8B4B8), // 灰粉
    Color(0xFFA8C0D8), // 灰蓝
    Color(0xFFE8D5A3), // 灰黄
    Color(0xFFB5C9A8), // 灰绿
    Color(0xFFE0B394), // 灰橙
    Color(0xFFF0EAD8), // 奶白
  ];
  final h = stableHash(seed);
  final color = tapes[h % tapes.length];
  final angle = ((h >> 3) % 2 == 0 ? 1 : -1) * (0.05 + (h % 5) * 0.014);
  return Transform.rotate(
    angle: angle,
    child: Container(
      width: width,
      height: 17,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            color.withValues(alpha: 0.78),
            color.withValues(alpha: 0.60),
            color.withValues(alpha: 0.78),
          ],
        ),
      ),
    ),
  );
}

/// 收据条形码：线性条码的形（宽窄条交替），不做可扫编码——
/// 种子取稳定哈希，同一对象的「码」恒定。小票作业卡与账号凭单共用。
class ReceiptBarcodePainter extends CustomPainter {
  const ReceiptBarcodePainter({required this.color, required this.seed});

  final Color color;
  final int seed;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = color;
    var h = seed & 0x7FFFFFFF;
    var x = 0.0;
    while (x < size.width - 1) {
      h = (h * 1103515245 + 12345) & 0x7FFFFFFF;
      final w = 1.0 + (h % 3);
      final gap = 1.0 + ((h >> 8) % 3);
      canvas.drawRect(Rect.fromLTWH(x, 0, w, size.height), p);
      x += w + gap;
    }
  }

  @override
  bool shouldRepaint(ReceiptBarcodePainter old) =>
      old.color != color || old.seed != seed;
}

/// 暖纸信纸感：卡片外框内缩 5px 再描一圈虚线细框（缝线）；非暖纸返回 null。
/// 叠在前景（foregroundDecoration），不挤内容内边距。
Decoration? paperInnerRing(BuildContext c, double outerRadius) {
  final pal = _pal(c);
  if (!pal.paper) return null;
  return StitchDecoration(radius: outerRadius, color: pal.cardBorder);
}

double cardRadius(BuildContext c) => _pal(c).radius;

Color textPrimary(BuildContext c) => _pal(c).ink;

Color textSecondary(BuildContext c) => _pal(c).ink2;

Color textFaint(BuildContext c) => _pal(c).ink3;

Color dividerColor(BuildContext c) => _pal(c).hairline;

Color chipBorder(BuildContext c) => _pal(c).hairline;

/// 界面强调色（随样式变化）；语义绿/平台识别色不走这里。
Color accentColor(BuildContext c) => _pal(c).accent;

/// 强调色上的文字色（深色侧亮强调必须配深字）。
Color onAccentColor(BuildContext c) => _pal(c).onAccent;

bool isPixelStyle(BuildContext c) => _pal(c).pixel;

bool isMorandiStyle(BuildContext c) => _pal(c).morandi;

bool isComicStyle(BuildContext c) => _pal(c).comic;

bool isPaperStyle(BuildContext c) => _pal(c).paper;

bool isReceiptStyle(BuildContext c) => _pal(c).receipt;

bool isEditorialStyle(BuildContext c) => _pal(c).editorial;

bool isTerminalStyle(BuildContext c) => _pal(c).terminal;

bool isJournalStyle(BuildContext c) => _pal(c).journal;

/// 页面 Scaffold 背景色：带自绘底衬的样式必须透明——底衬画在
/// StyleBackground 里、Scaffold 之后，不透明底色会把色雾/点阵/
/// 扫描线整个盖住（2026-10-05 复盘：莫兰迪/像素的背景从未上过屏）。
Color scaffoldBgOf(BuildContext c) =>
    _pal(c).hasThemedBg ? Colors.transparent : bgColor(c);

/// 票据读数感：小票/终端的数字与状态用等宽字（对齐像打印读数）。
TextStyle monoText(BuildContext c, TextStyle base) {
  final pal = _pal(c);
  if (!pal.receipt && !pal.terminal) return base;
  return base.copyWith(fontFamily: 'monospace');
}

bool isInkStyle(BuildContext c) => _pal(c).inkWash;

/// 水墨笔锋圆角：左上/右下藏锋大圆、右上/左下收锋小角（对角呼应，
/// 像一笔落在纸上）。其余样式为普通均匀圆角。
BorderRadius brushRadiusOf(BuildContext c, double radius) {
  if (!_pal(c).inkWash) return BorderRadius.circular(radius);
  return BorderRadius.only(
    topLeft: Radius.circular(radius + 6),
    topRight: Radius.circular(radius * 0.35),
    bottomRight: Radius.circular(radius + 6),
    bottomLeft: Radius.circular(radius * 0.35),
  );
}

/// 水墨卡面：浓淡墨渐变（色值来自调色板 cardWash）+ 墨晕阴影，无描边——
/// 水墨的层次手段是墨阶，不是线。非水墨返回 null，由调用处原逻辑兜底。
BoxDecoration? inkWashFill(BuildContext c, double radius) {
  final pal = _pal(c);
  final wash = pal.cardWash;
  if (!pal.inkWash || wash == null) return null;
  return BoxDecoration(
    borderRadius: brushRadiusOf(c, radius),
    gradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: wash,
    ),
    boxShadow: pal.shadow,
  );
}

/// 暖纸印刷感：标题类文字换衬线体（系统缺中文衬线时自动回退黑体）。
/// 只用于标题/徽标类大字，正文与小字保持黑体保证可读性。
TextStyle serifTitle(BuildContext c, TextStyle base) {
  if (_pal(c).clay) {
    return base.copyWith(
      fontFamily: 'StudySerif',
      fontWeight: FontWeight.w400,
      letterSpacing: 0,
    );
  }
  if (!_pal(c).paper) return base;
  return base.copyWith(fontFamily: 'serif', letterSpacing: 0.3);
}

/// 水墨题字感：大标题拉开字距，像卷轴上的题款。只用于大字标题。
TextStyle inkTitle(BuildContext c, TextStyle base) {
  if (!_pal(c).inkWash) return base;
  return base.copyWith(letterSpacing: 5);
}

/// 主按钮/悬浮按钮的落影语言随样式走：漫画=贴纸硬投影（无模糊的实色
/// 偏移影，撕贴纸的立体感）；水墨=淡墨影（印章不发光）；黑板=图钉投影
/// 像素=对角硬投影（按键立体感）；莫兰迪=雾面软影；其余=品牌光晕。
List<BoxShadow> primaryButtonShadow(BuildContext c) {
  final pal = _pal(c);
  if (pal.clean || pal.clay) return const [];
  if (pal.comic) {
    return [
      BoxShadow(
        color: isDark(c) ? const Color(0xFF0B0716) : pal.cardBorder,
        blurRadius: 0,
        offset: const Offset(0, 3),
      ),
    ];
  }
  if (pal.inkWash) {
    return [
      BoxShadow(
        color: Colors.black.withValues(alpha: isDark(c) ? 0 : 0.16),
        blurRadius: 14,
        offset: const Offset(0, 4),
      ),
    ];
  }
  if (pal.morandi) {
    return [
      BoxShadow(
        color: Colors.black.withValues(alpha: isDark(c) ? 0.30 : 0.12),
        blurRadius: 14,
        offset: const Offset(0, 4),
      ),
    ];
  }
  if (pal.pixel) {
    return [
      BoxShadow(
        color: pal.cardBorder,
        blurRadius: 0,
        offset: const Offset(3, 3),
      ),
    ];
  }
  return Tokens.glow(pal.accent, dark: isDark(c));
}

/// 漫画贴纸的按压感：按下轻微压扁，松手弹性回弹（果冻）。
/// 非漫画样式原样返回 child，零开销。
class JellyPress extends StatefulWidget {
  const JellyPress({super.key, required this.child, this.enabled = true});

  final Widget child;
  final bool enabled;

  @override
  State<JellyPress> createState() => _JellyPressState();
}

class _JellyPressState extends State<JellyPress> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    return Listener(
      onPointerDown: (_) => setState(() => _down = true),
      onPointerUp: (_) => setState(() => _down = false),
      onPointerCancel: (_) => setState(() => _down = false),
      child: AnimatedScale(
        scale: _down ? 0.955 : 1.0,
        duration: Duration(milliseconds: _down ? 90 : 280),
        curve: _down ? Curves.easeOut : Curves.elasticOut,
        child: widget.child,
      ),
    );
  }
}
