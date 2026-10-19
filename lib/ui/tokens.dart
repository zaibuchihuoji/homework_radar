/// 设计 token —— 全局唯一来源（白净极简·日历感）。
/// 页面里禁止散落写死颜色，一律引用这里。
library;

import 'package:flutter/material.dart';

import '../services/stable_hash.dart';

/// 界面样式 = 底色/卡片质感/圆角/描边阴影策略/强调色的整体组合，
/// 与深浅模式正交叠加。晴黄是默认主题，清夏保留原绿色配色。
enum ThemeStyle {
  clean,
  morandi,
  pixel,
  amoled,
  paper,
  comic,
  receipt,
  editorial,
  terminal,
  journal,
  green,
}

extension ThemeStyleX on ThemeStyle {
  String get label => switch (this) {
    ThemeStyle.clean => '晴黄',
    ThemeStyle.green => '清夏',
    ThemeStyle.morandi => '莫兰迪',
    ThemeStyle.pixel => '像素',
    ThemeStyle.amoled => '墨黑',
    ThemeStyle.paper => '暖纸',
    ThemeStyle.comic => '漫画',
    ThemeStyle.receipt => '小票',
    ThemeStyle.editorial => '杂志',
    ThemeStyle.terminal => '终端',
    ThemeStyle.journal => '手账',
  };
}

ThemeStyle themeStyleFromName(String? name) {
  // 旧版持久化键迁移：candy→漫画、glass/blueprint/chalk→莫兰迪
  // （2026-10-05 三轮更名），读旧备份/旧偏好时映射到现存主题
  if (name == 'candy') return ThemeStyle.comic;
  if (name == 'glass' || name == 'blueprint' || name == 'chalk') {
    return ThemeStyle.morandi;
  }
  return ThemeStyle.values.where((s) => s.name == name).firstOrNull ??
      ThemeStyle.clean;
}

/// 一个样式在给定明暗下的完整取色。页面运行时经 paletteOf(context) 取；
/// 设置页缩略图经 stylePalette(style, brightness) 直接取。
class StylePalette extends ThemeExtension<StylePalette> {
  const StylePalette({
    required this.bg,
    required this.card,
    required this.cardBorder,
    required this.shadow,
    required this.radius,
    required this.accent,
    required this.onAccent,
    required this.ink,
    required this.ink2,
    required this.ink3,
    required this.hairline,
    required this.modal,
    this.clean = false,
    this.sunny = false,
    this.actionFill,
    this.morandi = false,
    this.pixel = false,
    this.comic = false,
    this.paper = false,
    this.receipt = false,
    this.editorial = false,
    this.terminal = false,
    this.journal = false,
    this.cardWash,
    this.inkWash = false,
  });

  final Color bg;
  final Color card;
  final Color cardBorder;
  final List<BoxShadow> shadow;
  final double radius;

  /// 品牌强调色（只允许出现在：今天、选中态、当前时刻指示线、主按钮、徽标）。
  final Color accent;

  /// 强调色上的文字/图标色。深色侧的亮强调（如 #34D399）配白字对比不足，
  /// 必须用深色字。
  final Color onAccent;
  final Color ink;
  final Color ink2;
  final Color ink3;
  final Color hairline;

  /// 弹层（对话框/菜单/底部弹窗）专用底色——比卡片更实的读层面。
  final Color modal;

  final bool clean;
  final bool sunny;

  /// Bright brand yellow belongs on filled surfaces. Text keeps a readable ink.
  final Color? actionFill;
  Color get accentFill => actionFill ?? accent;

  final bool morandi;
  final bool pixel;
  final bool comic;
  final bool paper;
  final bool receipt;
  final bool editorial;
  final bool terminal;
  final bool journal;

  /// 该样式是否有自绘底衬（StyleBackground 里的专属画布）。
  /// 有的话页面 Scaffold 必须透明，否则底衬被不透明底色整个盖住
  /// （2026-10-05 复盘：莫兰迪色雾/像素点阵因此从未上过屏）。
  bool get hasThemedBg =>
      morandi || pixel || receipt || terminal || journal || editorial;

  /// 水墨卡面的浓淡墨渐变（两色，左上→右下）；非水墨为 null。
  /// 水墨的层次手段是"墨阶"（浓淡渐变+墨晕阴影），不是描边。
  final List<Color>? cardWash;

  /// 墨黑水墨身份开关：笔锋圆角/朱印徽标/飞白分隔/落款小印都挂在这上面。
  final bool inkWash;

  @override
  StylePalette copyWith() => this;

  // 切样式/深浅由 MaterialApp 的 themeAnimation 驱动逐帧 lerp：
  // 颜色/阴影/圆角/墨阶渐变全程平滑，唯 morandi/pixel/comic/paper/inkWash 五个
  // 身份开关在过半时切换（布尔无中间态；与全局色彩渐变同步，不突兀）。
  @override
  StylePalette lerp(StylePalette? other, double t) {
    if (other == null) return this;
    List<Color>? lerpList(List<Color>? a, List<Color>? b) {
      if (a == null || b == null || a.length != b.length) {
        return t < 0.5 ? a : b;
      }
      return [for (var i = 0; i < a.length; i++) Color.lerp(a[i], b[i], t)!];
    }

    return StylePalette(
      bg: Color.lerp(bg, other.bg, t)!,
      card: Color.lerp(card, other.card, t)!,
      cardBorder: Color.lerp(cardBorder, other.cardBorder, t)!,
      shadow: BoxShadow.lerpList(shadow, other.shadow, t)!,
      radius: radius + (other.radius - radius) * t,
      accent: Color.lerp(accent, other.accent, t)!,
      actionFill: Color.lerp(accentFill, other.accentFill, t),
      onAccent: Color.lerp(onAccent, other.onAccent, t)!,
      ink: Color.lerp(ink, other.ink, t)!,
      ink2: Color.lerp(ink2, other.ink2, t)!,
      ink3: Color.lerp(ink3, other.ink3, t)!,
      hairline: Color.lerp(hairline, other.hairline, t)!,
      modal: Color.lerp(modal, other.modal, t)!,
      cardWash: lerpList(cardWash, other.cardWash),
      clean: t < 0.5 ? clean : other.clean,
      sunny: t < 0.5 ? sunny : other.sunny,
      morandi: t < 0.5 ? morandi : other.morandi,
      pixel: t < 0.5 ? pixel : other.pixel,
      comic: t < 0.5 ? comic : other.comic,
      paper: t < 0.5 ? paper : other.paper,
      receipt: t < 0.5 ? receipt : other.receipt,
      editorial: t < 0.5 ? editorial : other.editorial,
      terminal: t < 0.5 ? terminal : other.terminal,
      journal: t < 0.5 ? journal : other.journal,
      inkWash: t < 0.5 ? inkWash : other.inkWash,
    );
  }

  @override
  Object get type => StylePalette;
}

StylePalette paletteOf(BuildContext c) =>
    Theme.of(c).extension<StylePalette>()!;

StylePalette stylePalette(ThemeStyle style, Brightness brightness) {
  final dark = brightness == Brightness.dark;
  return switch (style) {
    // ---- 晴黄（默认）：暖白纸面、品牌黄操作面、深墨文字 ----
    ThemeStyle.clean =>
      dark
          ? const StylePalette(
              clean: true,
              sunny: true,
              actionFill: Color(0xFFFFE044),
              bg: Color(0xFF191812),
              card: Color(0xFF25231B),
              cardBorder: Color(0xFF3C382A),
              shadow: [],
              radius: 14,
              accent: Color(0xFFFFE044),
              onAccent: Color(0xFF151B2B),
              ink: Color(0xFFFFF9E9),
              ink2: Color(0xFFC1BAA6),
              ink3: Color(0xFFC1BAA6),
              hairline: Color(0xFF3C382A),
              modal: Color(0xFF25231B),
            )
          : const StylePalette(
              clean: true,
              sunny: true,
              actionFill: Color(0xFFFFE044),
              bg: Color(0xFFFFFBF0),
              card: Color(0xFFFFFFFF),
              cardBorder: Color(0xFFEAE4D3),
              shadow: [],
              radius: 14,
              accent: Color(0xFF65521C),
              onAccent: Color(0xFF151B2B),
              ink: Color(0xFF151B2B),
              ink2: Color(0xFF686254),
              ink3: Color(0xFF686254),
              hairline: Color(0xFFEAE4D3),
              modal: Color(0xFFFFFFFF),
            ),
    // ---- 清夏（保留的绿色主题）：暖白纸面、细描边，强调色只标记操作与状态 ----
    ThemeStyle.green =>
      dark
          ? const StylePalette(
              clean: true,
              bg: Color(0xFF101214),
              card: Color(0xFF1A1D21),
              cardBorder: Color(0xFF262C3A),
              shadow: [],
              radius: 14,
              accent: Color(0xFF34D399),
              onAccent: Color(0xFF0A3D24),
              ink: Color(0xFFF2F3F5),
              ink2: Color(0xFF9CA3AF),
              ink3: Color(0xFF9CA3AF),
              hairline: Color(0xFF272B30),
              modal: Color(0xFF1A1D21),
            )
          : const StylePalette(
              clean: true,
              bg: Color(0xFFF7F8F5),
              card: Color(0xFFFFFFFF),
              cardBorder: Color(0xFFE6EAE4),
              shadow: [],
              radius: 14,
              accent: Color(0xFF087F6D),
              onAccent: Colors.white,
              ink: Color(0xFF232C29),
              ink2: Color(0xFF66716C),
              ink3: Color(0xFF66716C),
              hairline: Color(0xFFE6EAE4),
              modal: Color(0xFFFFFFFF),
            ),
    // ---- 莫兰迪：低饱和奶油语言。结构语言（非颜色维度）：清夏骨架的
    // 暖灰版——超圆角 24、无描边、单层大模糊软阴影（雾面）、奶霜高光面、
    // 圆形图标座/圆形 FAB、燕麦底+
    // 奶白卡+奶咖 accent（#8C6A5D 白字约 4.8:1）。温柔高级，浅色为主。
    ThemeStyle.morandi =>
      dark
          ? const StylePalette(
              bg: Color(0xFF211E1B),
              card: Color(0xFF2A2622),
              cardBorder: Colors.transparent,
              shadow: [
                BoxShadow(
                  color: Color(0xFF151210),
                  blurRadius: 0,
                  offset: Offset(0, 4),
                ),
              ],
              radius: 24,
              accent: Color(0xFFC9AFA4),
              onAccent: Color(0xFF33241C),
              ink: Color(0xFFEFEAE4),
              ink2: Color(0xFFA89F96),
              ink3: Color(0xFFA89F96),
              hairline: Color(0xFF38332E),
              modal: Color(0xFF2A2622),
              morandi: true,
            )
          : const StylePalette(
              bg: Color(0xFFEFEAE3),
              card: Color(0xFFF7F4EF),
              cardBorder: Colors.transparent,
              // 厚奶糖：无模糊实色底边露出 4px，卡片有「厚度」
              shadow: [
                BoxShadow(
                  color: Color(0xFFD9CFC4),
                  blurRadius: 0,
                  offset: Offset(0, 4),
                ),
              ],
              radius: 24,
              accent: Color(0xFF8C6A5D),
              onAccent: Colors.white,
              ink: Color(0xFF4A4440),
              ink2: Color(0xFF756B63),
              ink3: Color(0xFF756B63),
              hairline: Color(0xFFE2DCD3),
              modal: Color(0xFFF7F4EF),
              morandi: true,
            ),
    // ---- 像素：8-bit 掌机语言。结构语言（非颜色维度）：直角 radius 0 +
    // 近黑描边 2px + 对角硬投影 (3,3) + HUD 等宽倒计时 + 按压感
    // （JellyPress）+ FC 蓝 accent（#2B5CC8 白字约 5:1，深色提亮）。
    ThemeStyle.pixel =>
      dark
          ? const StylePalette(
              bg: Color(0xFF10131C),
              card: Color(0xFF1B2030),
              cardBorder: Color(0xFFE8ECF4),
              shadow: [],
              radius: 0,
              accent: Color(0xFF5C7CFF),
              onAccent: Color(0xFF0A1330),
              ink: Color(0xFFEDF0F7),
              ink2: Color(0xFF9AA3B5),
              ink3: Color(0xFF9AA3B5),
              hairline: Color(0xFF2A3040),
              modal: Color(0xFF1B2030),
              pixel: true,
            )
          : const StylePalette(
              bg: Color(0xFFDDE3EA),
              card: Color(0xFFFFFFFF),
              cardBorder: Color(0xFF1B1F2A),
              shadow: [],
              radius: 0,
              accent: Color(0xFF2B5CC8),
              onAccent: Colors.white,
              ink: Color(0xFF1B1F2A),
              ink2: Color(0xFF5A6170),
              ink3: Color(0xFF5A6170),
              hairline: Color(0xFFC6CDD8),
              modal: Color(0xFFFFFFFF),
              pixel: true,
            ),
    // ---- 墨黑：水墨画语言。结构语言（非颜色维度）：无描边、层次全靠
    // "墨分五色"浓淡渐变（cardWash）；笔锋不对称圆角（左上/右下藏锋大圆、
    // 右上/左下收锋小角）；飞白笔触分隔线（BrushLine）；朱砂印章徽标
    // （方章实心、微旋）；标题旁落款小印。水墨的本体是黑白灰：
    // 浅色=白纸+淡墨洗卡+焦墨字，卡片头像平台徽标一律去彩；
    // 红只出现在印章——严禁暖调米黄（那是暖纸的领地，
    // 2026-10-05 用户两次实测撞车后的结论：彩字彩徽标不除，水墨感立不起来）。
    // 深色 accent 用朱磦（黑底提亮），浅色用印泥朱砂 #C3272B——
    // 必须是正红：发棕的砖红（原 #B03A2E）用户实测与暖纸琥珀棕撞车。 ----
    ThemeStyle.amoled =>
      dark
          ? const StylePalette(
              bg: Colors.black,
              card: Color(0xFF1E1B16),
              cardBorder: Colors.transparent,
              cardWash: [Color(0xFF302B23), Color(0xFF1B1915)],
              shadow: [],
              radius: 14,
              accent: Color(0xFFF0483C),
              onAccent: Color(0xFF2B0B06),
              ink: Color(0xFFEDEAE2),
              ink2: Color(0xFFA39D90),
              ink3: Color(0xFFA39D90),
              hairline: Color(0xFF2A2620),
              modal: Color(0xFF1E1B16),
              inkWash: true,
            )
          : const StylePalette(
              // 白纸黑墨：白底上浮淡墨洗卡片（与清夏的灰底白卡互为反相），
              // 画面本体黑白灰，彩色只允许出现在印章/语义色上。
              bg: Colors.white,
              card: Color(0xFFF7F7F2),
              cardBorder: Colors.transparent,
              cardWash: [Color(0xFFEFEFE7), Color(0xFFD9D9CC)],
              shadow: [
                BoxShadow(
                  color: Color(0x1A000000),
                  blurRadius: 18,
                  offset: Offset(0, 6),
                ),
              ],
              radius: 14,
              accent: Color(0xFFC3272B),
              onAccent: Colors.white,
              ink: Color(0xFF161613),
              ink2: Color(0xFF5B5B55),
              ink3: Color(0xFF5B5B55),
              hairline: Color(0xFFD6D6CE),
              modal: Color(0xFFF7F7F3),
              inkWash: true,
            ),
    // ---- 暖纸：信纸打印体。结构语言（非颜色维度）：衬线标题、章形徽标、
    // 虚线缝线分隔、外框内一圈缝线（paperInnerRing）、小圆角"印刷卡"、
    // 暖棕纸晕阴影。色板只做配套，不是暖纸的主角。 ----
    ThemeStyle.paper =>
      dark
          ? const StylePalette(
              bg: Color(0xFF17130D),
              card: Color(0xFF211B12),
              cardBorder: Color(0xFF4A3D28),
              shadow: [],
              radius: 10,
              accent: Color(0xFFFBBF24),
              onAccent: Color(0xFF4A2E04),
              ink: Color(0xFFF0EAE0),
              ink2: Color(0xFFA99C89),
              ink3: Color(0xFFA99C89),
              hairline: Color(0xFF322A1E),
              modal: Color(0xFF211B12),
              paper: true,
            )
          : const StylePalette(
              bg: Color(0xFFF6F1E7),
              card: Color(0xFFFFFCF5),
              cardBorder: Color(0xFFD9C8A7),
              shadow: [
                BoxShadow(
                  color: Color(0x1F906010),
                  blurRadius: 14,
                  offset: Offset(0, 4),
                ),
              ],
              radius: 10,
              accent: Color(0xFFB45309),
              onAccent: Colors.white,
              ink: Color(0xFF3B342A),
              ink2: Color(0xFF6F6452),
              ink3: Color(0xFF6F6452),
              hairline: Color(0xFFE7DCC7),
              modal: Color(0xFFFFFCF5),
              paper: true,
            ),
    // ---- 漫画：漫画分镜语言（原「糖果」更名，2026-10-05）。结构语言
    // （非颜色维度）：白纸黑粗线（2px 墨线描边，分镜勾线）+ 无模糊硬投影
    // （赛璐璐层次）+ 对话框式徽标（气泡带尾巴，BubbleDecoration）+
    // 按压果冻动效（JellyPress）+ 课程色粉彩整卡着色（分镜色块）。
    // 卡面内部保持素净——波点/糖霜等装饰已被用户逐一点名撤除。
    // 与其它四套的区分：清夏=无描边淡阴影、墨黑=纯灰阶无描边、
    // 暖纸=米纸缝线衬线、漫画=白底黑粗线+粉彩+气泡。深色反转：黑底白粗线。
    // 紫色系整体退场——2026-10-05 用户实测默认紫=浓重 AI 感；
    // accent 树莓草莓 #E11D48（白字 4.7:1）。----
    ThemeStyle.comic =>
      dark
          ? const StylePalette(
              bg: Color(0xFF131316),
              card: Color(0xFF1E1E23),
              // 反转勾线：黑底上的白粗线
              cardBorder: Color(0xFFF2F2F5),
              shadow: [
                BoxShadow(
                  color: Color(0xFF000000),
                  blurRadius: 0,
                  offset: Offset(0, 3),
                ),
              ],
              radius: 16,
              accent: Color(0xFFFF8FAF),
              onAccent: Color(0xFF47101F),
              ink: Color(0xFFF5F5F7),
              ink2: Color(0xFFB9BCC4),
              ink3: Color(0xFFB9BCC4),
              hairline: Color(0xFF33333A),
              modal: Color(0xFF1E1E23),
              comic: true,
            )
          : const StylePalette(
              bg: Color(0xFFFAFAF8),
              card: Color(0xFFFFFFFF),
              // 漫画勾线：真墨黑实线，粗细在 cardBorderOf 里按 comic 加到 2.0
              cardBorder: Color(0xFF17171A),
              shadow: [
                BoxShadow(
                  color: Color(0xFF17171A),
                  blurRadius: 0,
                  offset: Offset(0, 3),
                ),
              ],
              radius: 16,
              accent: Color(0xFFE11D48),
              onAccent: Colors.white,
              ink: Color(0xFF17171A),
              ink2: Color(0xFF5C5F66),
              ink3: Color(0xFF5C5F66),
              hairline: Color(0xFFECECEE),
              modal: Color(0xFFFFFFFF),
              comic: true,
            ),
    // ---- 小票：热敏收据语言。结构语言（非颜色维度）：锯齿撕纸底边
    // （ReceiptTear 装饰自绘，齿尖朝下）+ 卡内虚线分隔（小票的
    // 打印分区线）+ 底部条形码 + NO. 编号（stableHash 定值，同作业恒定）
    // + 全等宽票据字 + 逾期盖红章。热敏纸是灰白不是纯白——
    // 卡面 #FBF9F3 浮在柜台色 #E8E4DA 上。accent 是收讫章的印泥红。----
    ThemeStyle.receipt =>
      dark
          ? const StylePalette(
              bg: Color(0xFF171511),
              card: Color(0xFF211E18),
              cardBorder: Color(0xFF3B362B),
              shadow: [],
              radius: 0,
              accent: Color(0xFFE0765C),
              onAccent: Color(0xFF2E0F06),
              ink: Color(0xFFF0EBE1),
              ink2: Color(0xFFA69D8D),
              ink3: Color(0xFFA69D8D),
              hairline: Color(0xFF2E2A21),
              modal: Color(0xFF211E18),
              receipt: true,
            )
          : const StylePalette(
              bg: Color(0xFFE8E4DA),
              card: Color(0xFFFBF9F3),
              cardBorder: Color(0xFFD9D3C6),
              shadow: [
                BoxShadow(
                  color: Color(0x0F2A2416),
                  blurRadius: 7,
                  offset: Offset(0, 2),
                ),
              ],
              radius: 0,
              accent: Color(0xFFC2402A),
              onAccent: Colors.white,
              ink: Color(0xFF26231D),
              ink2: Color(0xFF6E675A),
              ink3: Color(0xFF6E675A),
              hairline: Color(0xFFE5E0D4),
              modal: Color(0xFFFBF9F3),
              receipt: true,
            ),
    // ---- 杂志：瑞士国际主义排版语言。结构语言（非颜色维度）：卡片去盒化
    // （无阴影无圆角，靠上下规则线分隔的版块）+ 首页巨大日期数字做主视觉
    // + 章节头 01/02 编号 + 瑞士红小方块做符号 + 纯平（shadow 空）。
    // 排版密度就是它的装饰，背景必须近纯色。accent 瑞士红 #E2231A。----
    ThemeStyle.editorial =>
      dark
          ? const StylePalette(
              bg: Color(0xFF121211),
              card: Color(0xFF1A1917),
              cardBorder: Color(0xFFECEBE6),
              shadow: [],
              radius: 0,
              accent: Color(0xFFFF5245),
              onAccent: Color(0xFF2B0503),
              ink: Color(0xFFF0EFEA),
              ink2: Color(0xFFA5A29A),
              ink3: Color(0xFFA5A29A),
              hairline: Color(0xFF2E2D2A),
              modal: Color(0xFF1A1917),
              editorial: true,
            )
          : const StylePalette(
              bg: Color(0xFFF4F2EC),
              card: Color(0xFFFAF8F2),
              cardBorder: Color(0xFF191919),
              shadow: [],
              radius: 0,
              accent: Color(0xFFE2231A),
              onAccent: Colors.white,
              ink: Color(0xFF161616),
              ink2: Color(0xFF59564F),
              ink3: Color(0xFF59564F),
              hairline: Color(0xFFDAD6CC),
              modal: Color(0xFFFAF8F2),
              editorial: true,
            ),
    // ---- 终端：文本模式控制台语言（与像素的"游戏机"拉开：细线 vs 粗块）。
    // 结构语言（非颜色维度）：1px 单线窗格框 + 2px 微圆角、全局等宽字、
    // 倒计时/状态一律方括号读数 [剩余3天]、章节头 ┌─ 制表线 + 伪命令行
    // 问候、CRT 扫描线背景。磷光绿只在 accent/读数上，底色是墨绿黑。----
    ThemeStyle.terminal =>
      dark
          ? const StylePalette(
              bg: Color(0xFF0A0E0A),
              card: Color(0xFF121A12),
              cardBorder: Color(0xFF2C4632),
              shadow: [],
              radius: 2,
              accent: Color(0xFF4ADE80),
              onAccent: Color(0xFF03180A),
              ink: Color(0xFFD4EAD8),
              ink2: Color(0xFF7EA183),
              ink3: Color(0xFF7EA183),
              hairline: Color(0xFF1C2A1E),
              modal: Color(0xFF121A12),
              terminal: true,
            )
          : const StylePalette(
              bg: Color(0xFFE0E4DB),
              card: Color(0xFFF3F5EE),
              cardBorder: Color(0xFF2F352E),
              shadow: [],
              radius: 2,
              accent: Color(0xFF1E7A3C),
              onAccent: Colors.white,
              ink: Color(0xFF1D221C),
              ink2: Color(0xFF575E54),
              ink3: Color(0xFF575E54),
              hairline: Color(0xFFC9CEC2),
              modal: Color(0xFFF3F5EE),
              terminal: true,
            ),
    // ---- 手账：活页手帐语言（与暖纸区分：暖纸=旧信纸缝线印刷体，
    // 手账=活页纸+贴纸胶带+邮戳）。结构语言（非颜色维度）：卡片顶角
    // 半透明和纸胶带（伸出卡外、stableHash 定色定角）、横格纸+装订孔
    // 背景、徽标双线框"图章"化、整卡微旋（±0.3° 手账拼贴感）。
    // accent 钢笔墨蓝——手账的本体是纸+胶带+墨水笔。----
    ThemeStyle.journal =>
      dark
          ? const StylePalette(
              bg: Color(0xFF211D16),
              card: Color(0xFF2B2620),
              cardBorder: Color(0xFF443C2F),
              shadow: [],
              radius: 8,
              accent: Color(0xFF92A9D6),
              onAccent: Color(0xFF0F1E3C),
              ink: Color(0xFFF0EAE0),
              ink2: Color(0xFFA89F8F),
              ink3: Color(0xFFA89F8F),
              hairline: Color(0xFF3A3429),
              modal: Color(0xFF2B2620),
              journal: true,
            )
          : const StylePalette(
              bg: Color(0xFFF5EDDE),
              card: Color(0xFFFFFDF6),
              cardBorder: Color(0xFFE2D6BE),
              shadow: [
                BoxShadow(
                  color: Color(0x14685436),
                  blurRadius: 9,
                  offset: Offset(0, 3),
                ),
              ],
              radius: 8,
              accent: Color(0xFF3F5E9E),
              onAccent: Colors.white,
              ink: Color(0xFF3A342A),
              ink2: Color(0xFF6D6457),
              ink3: Color(0xFF6D6457),
              hairline: Color(0xFFE9DFCB),
              modal: Color(0xFFFFFDF6),
              journal: true,
            ),
  };
}

class Tokens {
  Tokens._();

  // ---- 品牌强调色基准（清夏浅/深）。语义绿与平台识别色不变；
  // 界面强调色运行时一律 brandOf(context)/accentColor(context)。----
  static const brand = Color(0xFF059669);
  static const brandDark = Color(0xFF34D399);

  // ---- 语义色（逾期/危险），替换散落各页的写死红 ----
  static const danger = Color(0xFFDC2626);
  static const dangerDark = Color(0xFFFCA5A5);

  // ---- 紧迫度梯度色（倒计时 <24h 橙 / <72h 琥珀；深色侧提亮保对比）----
  static const warn = Color(0xFFEA580C);
  static const warnDark = Color(0xFFFB923C);
  static const amber = Color(0xFFB45309);
  static const amberDark = Color(0xFFFBBF24);

  // ---- 深色卡片描边（此前以 0xFF262C3A 字面量散落 4 页 5 处）----
  static const cardBorderDark = Color(0xFF262C3A);

  // ---- 浅色 ----
  static const bg = Color(0xFFF6F7F8);
  static const card = Color(0xFFFFFFFF);
  static const ink = Color(0xFF1A1D21);
  static const ink2 = Color(0xFF6B7280);
  // tertiary 文本：原 #9CA3AF 白底只有 2.6:1，可读性不达标；
  // 提到 #6B7280 后白卡 4.8:1、浅背景 4.5:1。与 ink2 同值——层级靠
  // 字号/字重区分，对比度优先。
  static const ink3 = Color(0xFF6B7280);
  static const hairline = Color(0xFFECEDEF);

  // ---- 深色 ----
  static const bgDark = Color(0xFF101214);
  static const cardDark = Color(0xFF1A1D21);
  static const inkDark = Color(0xFFF2F3F5);
  static const ink2Dark = Color(0xFF9CA3AF);
  // 深色侧同步提亮（原 #6B7280 在深色卡上只有 3.5:1）：换到 #9CA3AF，
  // 深色卡 6.6:1、深色背景 7.4:1，与浅色侧一样满足 tertiary ≥4.5:1。
  static const ink3Dark = Color(0xFF9CA3AF);
  static const hairlineDark = Color(0xFF272B30);

  static Color brandOf(BuildContext c) => paletteOf(c).accent;

  /// 卡片层次手段随样式走：清夏=双层淡阴影，墨黑/暖纸/漫画=描边或色块（无阴影）。
  static List<BoxShadow> cardShadow(BuildContext c) => paletteOf(c).shadow;

  /// 有色按钮的"光源感"：贴身一圈稍亮 + 外围一大圈很淡，
  /// 像按钮在微微照亮周围；参数收敛，宁淡勿夸张。
  static List<BoxShadow> glow(Color accent, {bool dark = false}) => [
    BoxShadow(
      color: accent.withValues(alpha: dark ? 0.30 : 0.24),
      blurRadius: 14,
      offset: const Offset(0, 3),
    ),
    BoxShadow(
      color: accent.withValues(alpha: dark ? 0.16 : 0.10),
      blurRadius: 30,
      offset: const Offset(0, 6),
    ),
  ];

  /// 课程强调色 12 色（白卡左色条 / 课程详情点缀 / 课程卡整块铺色）。
  /// 白字对比度全部 ≥4.5:1：铺色卡上的白字（11px 加粗）此前在 600 档
  /// 上实测只有 3.1-3.8，看不清，故统一提到 700 档。
  /// 琥珀位用 yellow700 #A16207 而非 amber700 #B45309——后者已是末位
  /// 既有色，撞色会让两门课的默认色无法区分（色板必须 12 色互异）。
  static const coursePalette = <Color>[
    Color(0xFF2563EB),
    Color(0xFF047857), // emerald700（原 600 #059669，白字 3.77 不达标）
    Color(0xFFA16207), // yellow700（原 amber600 #D97706；amber700 已被末位占用）
    Color(0xFFDC2626),
    Color(0xFF7C3AED),
    Color(0xFF0E7490), // cyan700（原 600 #0891B2）
    Color(0xFFDB2777),
    Color(0xFF4D7C0F), // lime700（原 600 #65A30D）
    Color(0xFFC2410C), // orange700（原 600 #EA580C）
    Color(0xFF4F46E5),
    Color(0xFF0F766E), // teal700（原 600 #0D9488）
    Color(0xFFB45309), // amber700（原值，白字 4.55 达标，保留）
  ];

  /// 按课程名取课程色；[override] 为用户自选的色板下标。
  /// 哈希用自定义 stableHash 而非 String.hashCode——后者官方契约
  /// 「不保证跨程序执行一致」，引擎一旦换实现全部默认色会整体洗牌。
  static Color courseColor(String courseName, {int? override}) =>
      coursePalette[(override ?? stableHash(courseName)) %
          coursePalette.length];

  /// 作业卡头像/组头专用的低饱和调和色板（8 色冷谱为主 + 双暖锚点 + 中性）。
  /// 只做「10% 同色淡底 + 同色深字」，不整块铺色，与品牌绿同框不打架；
  /// [coursePalette] 仍服务课表格子铺色（白字 ≥4.5:1），两套互不干扰。
  static const avatarSoftPalette = <Color>[
    Color(0xFF0F766E), // teal700
    Color(0xFF0369A1), // sky700
    Color(0xFF4F46E5), // indigo600
    Color(0xFF7C3AED), // violet600
    Color(0xFFBE123C), // rose700
    Color(0xFFB45309), // amber700
    Color(0xFF475569), // slate600
    Color(0xFF0E7490), // cyan700
  ];

  /// 头像用色哈希；override 是用户在课程编辑里选的 coursePalette 下标，
  /// 这里取模兼容到 8 色板（保留「用户选过色 = 与别的课区分」的意图）。
  static Color avatarSoftColor(String courseName, {int? override}) =>
      avatarSoftPalette[(override ?? stableHash(courseName)) %
          avatarSoftPalette.length];
}
