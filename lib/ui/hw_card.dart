/// 作业卡片公共构建逻辑，首页与日历页共用。
/// 视觉规格见 ui/tokens.dart（白卡 + 双层淡阴影，无描边，强调色只做点缀）。
library;

import 'package:flutter/material.dart';

import '../models/homework.dart';
import '../services/stable_hash.dart';
import '../services/storage.dart';
import 'adaptive.dart';
import 'dashed_line.dart';
import 'tokens.dart';

const kPrimary = Tokens.brand;

const avatarPalette = Tokens.coursePalette;

bool hwIsDone(HomeworkItem hw) =>
    hw.status == HwStatus.done || hw.status == HwStatus.submitted;

bool hwIsOverdue(HomeworkItem hw) => !hwIsDone(hw) && hw.isOverdue;

Color hwStatusColor(HomeworkItem hw) =>
    hwIsDone(hw) ? Tokens.brand : Tokens.danger;

/// 倒计时的分级紧迫色：全红会让「5小时后」与「2天后」同权，
/// 红色通胀 = 没有东西是紧急的。梯度：
/// 已截止 红 / <6h 红加粗+实心闹钟 / <24h 橙 / <72h 琥珀 / 其余 灰。
(Color, FontWeight, IconData) hwDueTone(
  HomeworkItem hw, {
  bool dark = false,
}) {
  if (hwIsDone(hw)) {
    return (
      dark ? Tokens.brandDark : Tokens.brand,
      FontWeight.w600,
      Icons.schedule_rounded,
    );
  }
  final d = hw.dueAt;
  if (d == null) {
    return (
      dark ? Tokens.ink3Dark : Tokens.ink3,
      FontWeight.w500,
      Icons.schedule_rounded,
    );
  }
  if (hwIsOverdue(hw)) {
    return (
      dark ? Tokens.dangerDark : Tokens.danger,
      FontWeight.w600,
      Icons.schedule_rounded,
    );
  }
  final minutes = d.difference(DateTime.now()).inMinutes;
  if (minutes < 60 * 6) {
    return (
      dark ? Tokens.dangerDark : Tokens.danger,
      FontWeight.w700,
      Icons.alarm_rounded,
    );
  }
  if (minutes < 60 * 24) {
    return (
      dark ? Tokens.warnDark : Tokens.warn,
      FontWeight.w700,
      Icons.schedule_rounded,
    );
  }
  if (minutes < 60 * 72) {
    return (
      dark ? Tokens.amberDark : Tokens.amber,
      FontWeight.w600,
      Icons.schedule_rounded,
    );
  }
  return (
    dark ? Tokens.ink2Dark : Tokens.ink2,
    FontWeight.w500,
    Icons.schedule_rounded,
  );
}

String hwStatusLabel(HomeworkItem hw) {
  if (hwIsOverdue(hw)) return '已截止';
  return switch (hw.status) {
    HwStatus.todo => '未完成',
    HwStatus.submitted => '已提交',
    HwStatus.done => '已完成',
    HwStatus.unknown => '未知',
  };
}

/// 作业卡头像色：读用户长按课程自选的颜色——此前漏传 override，
/// 自选色在首页与日历页的卡片上完全不生效。
Color avatarColorFor(String course) => Tokens.avatarSoftColor(
      course,
      override: Storage.courseColors()[course],
    );

/// 平台识别点色：取自账号页各平台渐变的首色，两处一致。
Color platformDotColor(PlatformKind p) => switch (p) {
      PlatformKind.chaoxing => const Color(0xFF6366F1),
      PlatformKind.mooc => const Color(0xFFF43F5E),
      PlatformKind.zhihuishu => const Color(0xFF16A34A),
      PlatformKind.xuetangx => const Color(0xFF0EA5E9),
      PlatformKind.yuketang => const Color(0xFF8B5CF6),
      PlatformKind.manual => const Color(0xFF9CA3AF),
    };

Widget buildHwCard(
  BuildContext context,
  HomeworkItem hw, {
  bool showCourse = true,
  bool platformPill = false,
  VoidCallback? onTap,
  VoidCallback? onLongPress,
}) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final pal = paletteOf(context);
  final ink = pal.ink;
  final ink2 = pal.ink2;
  final ink3 = pal.ink3;
  final done = hwIsDone(hw);
  final overdue = hwIsOverdue(hw);
  final tone = hwDueTone(hw, dark: isDark);
  final course = hw.course.trim().isEmpty ? '课程' : hw.course.trim();
  final color = avatarColorFor(course);
  final firstChar = String.fromCharCode(course.runes.first).toUpperCase();

  // 状态徽标：品牌/红色各自的 10% 淡底 + 同色字，不再用实色块
  final (pillBg, pillFg) = done
      ? (Tokens.brand.withValues(alpha: 0.10), Tokens.brand)
      : overdue
          ? (Tokens.danger.withValues(alpha: 0.10), Tokens.danger)
          : (pal.hairline, ink2);

  // 卡面随样式走：漫画 = 不透明粉彩分镜底（alphaBlend 调和，半透明会
  // 跟硬投影混成脏块）+ 黑粗勾线，框内保持清爽不加装饰（2026-10-05
  // 用户拍板）；蓝图 = 白/深蓝线稿卡 + 四角制图角标（blueprintTicks），
  // 无阴影；水墨 = 浓淡墨渐变 + 笔锋圆角，无描边（inkWashFill）；
  // 其余 = 样式卡面 + 各自的阴影/描边策略。暖纸叠加外框内缝线。
  final comic = pal.comic;
  final Decoration? decoration = inkWashFill(context, pal.radius) ??
      (pal.pixel
          // 像素：卡面由 decoration 出硬投影，勾线交给 pixelFrame 窗框
          ? BoxDecoration(
              color: pal.card,
              boxShadow: [
                BoxShadow(
                  color: pal.cardBorder.withValues(alpha: 0.9),
                  blurRadius: 0,
                  offset: const Offset(3, 3),
                ),
              ],
            )
          : pal.receipt
              // 小票：整卡是一张热敏收据（撕纸底边 + 平移硬投影）
              ? receiptTear(context)
              : pal.editorial
                  // 杂志：去盒化——无框无影的版块，规则线画在前景
                  ? BoxDecoration(color: pal.card)
                  : BoxDecoration(
                      color: comic
                          ? Color.alphaBlend(
                              color.withValues(alpha: isDark ? 0.30 : 0.26),
                              pal.card)
                          : pal.card,
                      borderRadius: BorderRadius.circular(pal.radius),
                      border: comic
                          ? Border.all(color: pal.cardBorder, width: 2.0)
                          : cardBorderOf(context),
                      boxShadow: pal.shadow,
                    ));

  // 已截止是既成事实而非行动项：整卡内容退场（降不透明度），红字保留
  return GestureDetector(
    onTap: onTap,
    onLongPress: onLongPress,
    // 手账：整卡 ±0.23° 微旋——拼贴在活页纸上的便签不会贴得笔直
    child: Transform.rotate(
      angle: pal.journal
          ? (stableHash(hw.id).abs() % 2 == 0 ? 0.004 : -0.004)
          : 0,
      child: JellyPress(
      enabled: comic || pal.pixel,
      child: Opacity(
        opacity: overdue ? 0.72 : 1.0,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
      Container(
        padding: EdgeInsets.fromLTRB(14, 14, 14, pal.receipt ? 17 : 13),
        decoration: decoration,
        foregroundDecoration: paperInnerRing(context, pal.radius) ??
            morandiCream(context, pal.radius) ??
            pixelFrame(context, pal.radius) ??
            editorialRules(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  // 水墨：头像是一滴墨（正圆浓淡晕染 + 焦墨字），
                  // 课程色不上墨黑卡面，课程身份靠字符本身。
                  // 漫画：头像是一枚贴纸icon——白底方贴 + 课程色描边。
                  decoration: pal.inkWash
                      ? BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(
                            colors: [
                              (isDark ? Colors.white : Colors.black)
                                  .withValues(alpha: isDark ? 0.20 : 0.15),
                              (isDark ? Colors.white : Colors.black)
                                  .withValues(alpha: isDark ? 0.05 : 0.03),
                            ],
                          ),
                        )
                      : comic
                          ? BoxDecoration(
                              color: isDark
                                  ? const Color(0xFF2E1E26)
                                  : Colors.white,
                              borderRadius: BorderRadius.circular(13),
                              border: Border.all(color: color, width: 2),
                            )
                          : pal.morandi
                              ? BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: color.withValues(
                                      alpha: isDark ? 0.18 : 0.10),
                                )
                              : pal.editorial
                                  // 杂志：首字下沉——无底块，大字压一道红下划线
                                  ? BoxDecoration(
                                      border: Border(
                                        bottom: BorderSide(
                                            color: pal.accent, width: 3),
                                      ),
                                    )
                                  : BoxDecoration(
                                      color: color.withValues(
                                          alpha: isDark ? 0.22 : 0.10),
                                      borderRadius:
                                          BorderRadius.circular(10),
                                    ),
                  child: Text(
                    firstChar,
                    style: serifTitle(
                      context,
                      TextStyle(
                          color: pal.inkWash
                              ? pal.ink
                              : pal.editorial
                                  ? pal.ink
                                  : color,
                          fontSize: pal.editorial ? 23 : 16,
                          height: pal.editorial ? 1.1 : null,
                          fontWeight: pal.editorial
                              ? FontWeight.w900
                              : FontWeight.w700),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (showCourse) ...[
                        Row(
                          children: [
                            // 杂志：瑞士红小方块做项目符号——印刷品的肌肉记忆
                            if (pal.editorial)
                              Container(
                                width: 7,
                                height: 7,
                                color: pal.accent,
                                margin: const EdgeInsets.only(right: 6),
                              ),
                            Expanded(
                              child: Text(course,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      fontSize: 11.5,
                                      // 杂志：课程名是图注（kicker），拉字距
                                      letterSpacing:
                                          pal.editorial ? 1.5 : null,
                                      fontFamily: pal.terminal || pal.receipt
                                          ? 'monospace'
                                          : null,
                                      color: ink3)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                      ],
                      Text(
                        hw.title.isEmpty ? '（无标题）' : hw.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: serifTitle(
                          context,
                          TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: ink,
                            height: 1.3,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (platformPill)
                  _platformPill(hw.platform, isDark,
                      stamp: pal.paper,
                      ink: pal.inkWash,
                      sticker: pal.comic,
                      outline: pal.cardBorder)
                else
                  _statusPill(hw, pillBg, pillFg,
                      stamp: pal.paper,
                      seal: pal.inkWash,
                      sticker: pal.comic,
                      outline: pal.cardBorder,
                      terminal: pal.terminal,
                      editorial: pal.editorial,
                      journal: pal.journal,
                      receipt: pal.receipt),
              ],
            ),
            if (hw.note != null && hw.note!.trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.sticky_note_2_outlined,
                      size: 13,
                      color: pal.inkWash ? ink2 : const Color(0xFFB45309)),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(hw.note!.trim(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 12,
                            color: pal.inkWash ? ink2 : const Color(0xFFB45309))),
                  ),
                ],
              ),
            ],
            // 小票：内容区与金额区之间是一道打印虚线（收据的分区线）
            if (pal.receipt) ...[
              const SizedBox(height: 10),
              DashedLine(
                color: ink.withValues(alpha: isDark ? 0.35 : 0.30),
                thickness: 1,
              ),
              const SizedBox(height: 9),
            ] else
              const SizedBox(height: 11),
            Row(
              children: [
                Icon(tone.$3, size: 15, color: tone.$1),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                      pal.terminal
                          ? '[${hw.countdownText}]'
                          : hw.countdownText,
                      // 像素：倒计时是 HUD 读数；小票/终端：等宽打印读数
                      style: monoText(
                        context,
                        TextStyle(
                            fontSize: 12.5,
                            fontWeight: tone.$2,
                            color: tone.$1,
                            fontFamily:
                                pal.pixel ? 'monospace' : null),
                      )),
                ),
                // 平台徽标挂在右上时，「手动添加」不再重复出现在底部
                if (!(platformPill && hw.platform == PlatformKind.manual))
                  if (hw.platform == PlatformKind.manual)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: pal.hairline,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text('手动添加',
                          style: TextStyle(fontSize: 10, color: ink2)),
                    )
                  else if (hw.score != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: pal.accent.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '${HomeworkItem.scoreText(hw.score)} 分',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: pal.accent),
                      ),
                    ),
              ],
            ),
            // 小票的落款：条形码 + NO. 编号——收据的身份区，同作业恒定
            if (pal.receipt) ...[
              const SizedBox(height: 9),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 16,
                      child: CustomPaint(
                        painter: ReceiptBarcodePainter(
                          color: ink.withValues(alpha: isDark ? 0.75 : 0.82),
                          seed: stableHash(hw.id),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'NO.${stableHash(hw.id).abs() % 9000 + 1000}',
                    style: monoText(
                      context,
                      TextStyle(
                          fontSize: 9.5,
                          letterSpacing: 1.2,
                          fontWeight: FontWeight.w600,
                          color: ink2),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
        // 手账：和纸胶带贴在卡顶（stableHash 定色定角，同一作业恒定）
        if (pal.journal)
          Positioned(
            top: -7,
            left: 16.0 + (stableHash(hw.id).abs() % 56),
            child: journalTape(context, hw.id),
          ),
        // 莫兰迪：右下角挂一枚「色票」——莫兰迪的代名词就是那些颜色，
        // 每门课按名字固定一张自己的色票（Pantone 式：色块 + 编号），
        // 半溢出卡外，像夹在画册页边的取色卡
        if (pal.morandi)
          Positioned(
            right: -4,
            bottom: -5,
            child: Container(
              width: 34,
              padding: const EdgeInsets.all(2.5),
              decoration: BoxDecoration(
                color: pal.modal,
                borderRadius: BorderRadius.circular(3),
                border: Border.all(
                  color: pal.hairline,
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.10),
                    blurRadius: 3,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Container(
                    height: 15,
                    decoration: BoxDecoration(
                      color: Color.alphaBlend(
                          color.withValues(alpha: 0.6), pal.card),
                      borderRadius: BorderRadius.circular(1.5),
                    ),
                  ),
                  const SizedBox(height: 1.5),
                  Text(
                    'M-${stableHash(course).abs() % 900 + 100}',
                    style: TextStyle(
                      fontSize: 7,
                      height: 1.1,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.3,
                      color: ink2,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      ),
      ),
    ),
  );
}

Widget _statusPill(HomeworkItem hw, Color bg, Color fg,
    {bool stamp = false,
    bool seal = false,
    bool sticker = false,
    Color? outline,
    bool terminal = false,
    bool editorial = false,
    bool journal = false,
    bool receipt = false}) {
  // 终端的徽标是"读数"：方括号状态字，等宽，无底块——终端不打装饰
  if (terminal) {
    return Text('[${hwStatusLabel(hw)}]',
        style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            fontFamily: 'monospace',
            letterSpacing: 0.5,
            color: fg));
  }
  // 杂志的徽标是"图例"：一个实色小方块 + 加宽字距的状态词，无底块
  if (editorial) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 6, height: 6, color: fg),
        const SizedBox(width: 6),
        Text(hwStatusLabel(hw),
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.5,
                color: fg)),
      ],
    );
  }
  // 手账的徽标是"图章"：双线框、微旋——盖在便签上的收讫章
  if (journal) {
    return Transform.rotate(
      angle: -0.05,
      child: Container(
        padding: const EdgeInsets.all(2.2),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: fg.withValues(alpha: 0.75), width: 1.1),
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(2.5),
            border:
                Border.all(color: fg.withValues(alpha: 0.45), width: 0.8),
            color: fg.withValues(alpha: 0.05),
          ),
          child: Text(hwStatusLabel(hw),
              style: const TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1)),
        ),
      ),
    );
  }
  // 小票的徽标是"打印标签"：方角细框 + 等宽字
  if (receipt) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(2),
        border: Border.all(color: fg.withValues(alpha: 0.6), width: 1.1),
      ),
      child: Text(hwStatusLabel(hw),
          style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              fontFamily: 'monospace',
              letterSpacing: 0.5,
              color: fg)),
    );
  }
  // 水墨的徽标是"朱印"：终态（完成/截止）盖实心方章、微微斜钤，
  // 未完成用淡墨虚章。印章语义：落章即定局。
  if (seal) {
    final filled = hwIsDone(hw) || hwIsOverdue(hw);
    return Transform.rotate(
      angle: -0.03,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: filled ? fg : fg.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(4),
          border: filled
              ? null
              : Border.all(color: fg.withValues(alpha: 0.5), width: 1.1),
        ),
        child: Text(hwStatusLabel(hw),
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
                color: filled ? Colors.white : fg)),
      ),
    );
  }
  // 漫画的徽标是"对话框"：气泡带尾巴（谁在说话一目了然），微斜着贴。
  if (sticker && outline != null) {
    return Transform.rotate(
      angle: -0.02,
      child: Container(
        // 底部多留 4px 给气泡尾巴，避免贴到下一行
        padding: const EdgeInsets.fromLTRB(9, 4, 9, 8),
        decoration: BubbleDecoration(
          fillColor: bg,
          borderColor: outline,
        ),
        child: Text(hwStatusLabel(hw),
            style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.w800, color: fg)),
      ),
    );
  }
  // 暖纸的徽标是"章"：不灌色块，描一圈状态色墨线 + 微染色底，方角。
  if (stamp) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: fg.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: fg.withValues(alpha: 0.5), width: 1.2),
      ),
      child: Text(hwStatusLabel(hw),
          style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
              color: fg)),
    );
  }
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
    child: Text(hwStatusLabel(hw),
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: fg)),
  );
}

/// 平台徽标：色点 + 平台名。单 tab 视图里「未完成」人尽皆知，
/// 真正缺的信息是「这笔欠在哪个平台」。暖纸下走方角章形；水墨下
/// 墨线方框 + 灰字，只留色点一点彩（画面主体必须黑白灰）。
Widget _platformPill(PlatformKind p, bool isDark,
    {bool stamp = false,
    bool ink = false,
    bool sticker = false,
    Color? outline}) {
  final color = platformDotColor(p);
  if (ink) {
    final line = (isDark ? Colors.white : Colors.black).withValues(alpha: 0.32);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: line, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 4),
          Text(p.label,
              style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white.withValues(alpha: 0.78) : Colors.black.withValues(alpha: 0.62))),
        ],
      ),
    );
  }
  // 漫画的平台徽标是"姓名贴纸"：白底小方贴 + 剪影描边 + 硬投影 + 色点。
  if (sticker && outline != null) {
    return Transform.rotate(
      angle: -0.02,
      child: Container(
        // 底部多留 4px 给气泡尾巴，避免贴到下一行
        padding: const EdgeInsets.fromLTRB(9, 4, 9, 8),
        decoration: BubbleDecoration(
          fillColor: isDark ? const Color(0xFF1E1E23) : Colors.white,
          borderColor: outline,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 4),
            Text(p.label,
                style: TextStyle(
                    fontSize: 10.5, fontWeight: FontWeight.w800, color: color)),
          ],
        ),
      ),
    );
  }
  if (stamp) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.45), width: 1.2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 4),
          Text(p.label,
              style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  color: color)),
        ],
      ),
    );
  }
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: isDark ? 0.16 : 0.09),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(p.label,
            style: TextStyle(
                fontSize: 10.5, fontWeight: FontWeight.w600, color: color)),
      ],
    ),
  );
}
