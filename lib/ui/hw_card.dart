/// 作业卡片公共构建逻辑，首页与日历页共用。
/// 视觉规格见 ui/tokens.dart（白卡 + 双层淡阴影，无描边，强调色只做点缀）。
library;

import 'package:flutter/material.dart';

import '../models/homework.dart';
import '../services/stable_hash.dart';
import '../services/storage.dart';
import 'adaptive.dart';
import 'dashed_line.dart';
import 'ink_wash.dart';
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
(Color, FontWeight, IconData) hwDueTone(HomeworkItem hw, {bool dark = false}) {
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
Color avatarColorFor(String course) =>
    Tokens.avatarSoftColor(course, override: Storage.courseColors()[course]);

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

  if (pal.clean) {
    // 日期信息只承担时间语义，完成状态单独显示；缺失日期保持中性。
    final dateColor = hw.dueAt == null || done ? ink2 : tone.$1;
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: pal.card,
          borderRadius: BorderRadius.circular(pal.radius),
          border: cardBorderOf(context),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (showCourse) ...[
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      course,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: ink2),
                    ),
                  ),
                ] else
                  const Spacer(),
                const SizedBox(width: 8),
                Text(
                  hw.platform.label,
                  style: TextStyle(fontSize: 10.5, color: ink3),
                ),
              ],
            ),
            const SizedBox(height: 7),
            Text(
              hw.title.isEmpty ? '（无标题）' : hw.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 16,
                height: 1.4,
                fontWeight: FontWeight.w600,
                color: ink,
              ),
            ),
            if (hw.note?.trim().isNotEmpty == true) ...[
              const SizedBox(height: 6),
              Text(
                hw.note!.trim(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: ink2),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Icon(
                    hw.dueAt == null || done ? Icons.schedule_rounded : tone.$3,
                    size: 14,
                    color: dateColor,
                  ),
                ),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    hw.countdownText,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.5,
                      color: dateColor,
                      fontWeight: done || hw.dueAt == null
                          ? FontWeight.w400
                          : tone.$2,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    hw.score == null
                        ? hwStatusLabel(hw)
                        : '${hwStatusLabel(hw)} · ${HomeworkItem.scoreText(hw.score)} 分',
                    textAlign: TextAlign.end,
                    style: TextStyle(
                      fontSize: 11,
                      height: 1.5,
                      color: overdue
                          ? (isDark ? Tokens.dangerDark : Tokens.danger)
                          : done
                          ? pal.accent
                          : ink2,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // 卡面随样式走：漫画 = 不透明粉彩分镜底（alphaBlend 调和，半透明会
  // 跟硬投影混成脏块）+ 黑粗勾线，框内保持清爽不加装饰（2026-10-05
  // 用户拍板）；蓝图 = 白/深蓝线稿卡 + 四角制图角标（blueprintTicks），
  // 无阴影；水墨 = 浓淡墨渐变 + 笔锋圆角，无描边（inkWashFill）；
  // 其余 = 样式卡面 + 各自的阴影/描边策略。暖纸叠加外框内缝线。
  final comic = pal.comic;
  final Decoration? decoration =
      inkWashFill(context, pal.radius) ??
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
                      pal.card,
                    )
                  : pal.card,
              borderRadius: BorderRadius.circular(pal.radius),
              border: comic
                  ? Border.all(color: pal.cardBorder, width: 2.0)
                  : cardBorderOf(context),
              boxShadow: pal.shadow,
            ));

  final mono = pal.pixel || pal.terminal || pal.receipt;
  final statusColor = done
      ? pal.accent
      : overdue
      ? tone.$1
      : ink2;
  final dateColor = hw.dueAt == null || done ? ink2 : tone.$1;
  final platform = pal.pixel || pal.terminal || pal.receipt || pal.editorial
      ? Text(
          hw.platform.label,
          style: TextStyle(
            fontSize: 10.5,
            fontFamily: mono ? 'monospace' : null,
            color: pal.pixel || pal.terminal ? pal.card : ink2,
          ),
        )
      : _platformPill(
          hw.platform,
          isDark,
          stamp: pal.paper,
          ink: pal.inkWash,
          sticker: pal.comic,
          outline: pal.cardBorder,
        );
  Widget heading = Row(
    children: [
      if (showCourse) ...[
        if (pal.editorial) ...[
          Container(width: 6, height: 6, color: pal.accent),
          const SizedBox(width: 6),
        ],
        if (pal.morandi) ...[
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
        ],
        Expanded(
          child: Text(
            course,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              fontWeight: pal.comic || pal.editorial
                  ? FontWeight.w700
                  : FontWeight.w400,
              fontFamily: mono
                  ? 'monospace'
                  : pal.paper
                  ? 'serif'
                  : null,
              color: pal.pixel || pal.terminal
                  ? pal.card
                  : pal.journal
                  ? pal.accent
                  : ink2,
              decoration: pal.journal ? TextDecoration.underline : null,
            ),
          ),
        ),
      ] else
        const Spacer(),
      const SizedBox(width: 8),
      platform,
    ],
  );
  if (pal.pixel || pal.terminal) {
    heading = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      color: pal.cardBorder,
      child: Row(
        children: [
          ExcludeSemantics(
            child: Text(
              pal.terminal ? '> ' : '+ ',
              style: TextStyle(
                color: pal.card,
                fontFamily: 'monospace',
                fontSize: 12,
              ),
            ),
          ),
          Expanded(child: heading),
        ],
      ),
    );
  } else if (pal.receipt) {
    heading = Column(
      children: [
        if (showCourse)
          Text(
            course,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
              color: ink2,
            ),
          ),
        const SizedBox(height: 3),
        platform,
      ],
    );
  }
  final content = Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      heading,
      SizedBox(height: pal.receipt ? 9 : 8),
      Text(
        hw.title.isEmpty ? '（无标题）' : hw.title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        textAlign: pal.receipt ? TextAlign.center : TextAlign.start,
        style: TextStyle(
          fontSize: pal.editorial
              ? 20
              : pal.comic || pal.inkWash
              ? 17
              : 16,
          height: pal.editorial ? 1.25 : 1.4,
          fontFamily: pal.paper
              ? 'serif'
              : mono
              ? 'monospace'
              : null,
          fontWeight: pal.comic || pal.editorial
              ? FontWeight.w800
              : FontWeight.w600,
          letterSpacing: pal.inkWash ? 1 : null,
          color: ink,
        ),
      ),
      if (pal.inkWash) ...[
        const SizedBox(height: 5),
        BrushLine(color: ink.withValues(alpha: 0.24), thickness: 1.4),
      ],
      if (hw.note?.trim().isNotEmpty == true) ...[
        const SizedBox(height: 7),
        Container(
          padding: pal.paper || pal.journal || pal.comic
              ? const EdgeInsets.symmetric(horizontal: 8, vertical: 6)
              : EdgeInsets.zero,
          decoration: pal.paper || pal.journal || pal.comic
              ? BoxDecoration(
                  color: pal.card.withValues(alpha: pal.comic ? 0.6 : 0.7),
                  borderRadius: BorderRadius.circular(pal.comic ? 6 : 2),
                )
              : null,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (pal.terminal) ...[
                Text(
                  '# ',
                  style: TextStyle(
                    color: ink2,
                    fontFamily: 'monospace',
                    fontSize: 12,
                  ),
                ),
              ],
              Expanded(
                child: Text(
                  hw.note!.trim(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: ink2,
                    height: 1.4,
                    fontFamily: pal.terminal || pal.receipt
                        ? 'monospace'
                        : null,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
      const SizedBox(height: 12),
      if (pal.receipt || pal.paper || pal.terminal) ...[
        DashedLine(color: ink2.withValues(alpha: 0.35)),
        const SizedBox(height: 9),
      ],
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 3,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Icon(
                    hw.dueAt == null || done ? Icons.schedule_rounded : tone.$3,
                    size: 14,
                    color: dateColor,
                  ),
                ),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    pal.terminal ? '[${hw.countdownText}]' : hw.countdownText,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.45,
                      fontWeight: hw.dueAt == null || done
                          ? FontWeight.w400
                          : tone.$2,
                      fontFamily: mono ? 'monospace' : null,
                      color: dateColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _statusPill(
                  hw,
                  statusColor.withValues(alpha: 0.08),
                  statusColor,
                  stamp: pal.paper,
                  seal: pal.inkWash,
                  sticker: pal.comic,
                  outline: pal.cardBorder,
                  terminal: pal.terminal,
                  editorial: pal.editorial,
                  journal: pal.journal,
                  receipt: pal.receipt,
                ),
                if (hw.score != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    '${HomeworkItem.scoreText(hw.score)} 分',
                    style: TextStyle(
                      fontSize: 11,
                      fontFamily: mono ? 'monospace' : null,
                      color: ink2,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
      if (pal.receipt) ...[
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 15,
                child: CustomPaint(
                  painter: ReceiptBarcodePainter(
                    color: ink.withValues(alpha: 0.8),
                    seed: stableHash(hw.id),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              'NO.${stableHash(hw.id).abs() % 9000 + 1000}',
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 10,
                color: ink2,
              ),
            ),
          ],
        ),
      ],
      if (pal.morandi) ...[
        const SizedBox(height: 9),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Container(
              width: 22,
              height: 8,
              decoration: BoxDecoration(
                color: Color.alphaBlend(
                  color.withValues(alpha: 0.65),
                  pal.card,
                ),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 5),
            Text(
              'M-${stableHash(course).abs() % 900 + 100}',
              style: TextStyle(fontSize: 9, color: ink2),
            ),
          ],
        ),
      ],
    ],
  );
  return GestureDetector(
    onTap: onTap,
    onLongPress: onLongPress,
    child: Transform.rotate(
      angle: pal.journal ? (stableHash(hw.id).isEven ? 0.004 : -0.004) : 0,
      child: JellyPress(
        enabled: comic || pal.pixel,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              padding: EdgeInsets.fromLTRB(
                pal.pixel ? 18 : 15,
                pal.journal ? 20 : 15,
                pal.pixel ? 18 : 15,
                pal.receipt ? 19 : 15,
              ),
              decoration: decoration,
              foregroundDecoration:
                  paperInnerRing(context, pal.radius) ??
                  morandiCream(context, pal.radius) ??
                  pixelFrame(context, pal.radius) ??
                  editorialRules(context),
              child: content,
            ),
            if (pal.journal)
              Positioned(
                top: -6,
                left: 22,
                child: journalTape(context, hw.id, width: 58),
              ),
          ],
        ),
      ),
    ),
  );
}

Widget _statusPill(
  HomeworkItem hw,
  Color bg,
  Color fg, {
  bool stamp = false,
  bool seal = false,
  bool sticker = false,
  Color? outline,
  bool terminal = false,
  bool editorial = false,
  bool journal = false,
  bool receipt = false,
}) {
  // 终端的徽标是"读数"：方括号状态字，等宽，无底块——终端不打装饰
  if (terminal) {
    return Text(
      '[${hwStatusLabel(hw)}]',
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        fontFamily: 'monospace',
        letterSpacing: 0.5,
        color: fg,
      ),
    );
  }
  // 杂志的徽标是"图例"：一个实色小方块 + 加宽字距的状态词，无底块
  if (editorial) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 6, height: 6, color: fg),
        const SizedBox(width: 6),
        Text(
          hwStatusLabel(hw),
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.5,
            color: fg,
          ),
        ),
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
            border: Border.all(color: fg.withValues(alpha: 0.45), width: 0.8),
            color: fg.withValues(alpha: 0.05),
          ),
          child: Text(
            hwStatusLabel(hw),
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 1,
              color: fg,
            ),
          ),
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
      child: Text(
        hwStatusLabel(hw),
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          fontFamily: 'monospace',
          letterSpacing: 0.5,
          color: fg,
        ),
      ),
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
        child: Text(
          hwStatusLabel(hw),
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
            color: filled ? Colors.white : fg,
          ),
        ),
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
        decoration: BubbleDecoration(fillColor: bg, borderColor: outline),
        child: Text(
          hwStatusLabel(hw),
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: fg,
          ),
        ),
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
      child: Text(
        hwStatusLabel(hw),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
          color: fg,
        ),
      ),
    );
  }
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      hwStatusLabel(hw),
      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: fg),
    ),
  );
}

/// 平台徽标：色点 + 平台名。单 tab 视图里「未完成」人尽皆知，
/// 真正缺的信息是「这笔欠在哪个平台」。暖纸下走方角章形；水墨下
/// 墨线方框 + 灰字，只留色点一点彩（画面主体必须黑白灰）。
Widget _platformPill(
  PlatformKind p,
  bool isDark, {
  bool stamp = false,
  bool ink = false,
  bool sticker = false,
  Color? outline,
}) {
  final color = p == PlatformKind.manual
      ? (isDark ? Tokens.ink2Dark : Tokens.ink2)
      : platformDotColor(p);
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
          Text(
            p.label,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              color: isDark
                  ? Colors.white.withValues(alpha: 0.78)
                  : Colors.black.withValues(alpha: 0.62),
            ),
          ),
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
            Text(
              p.label,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
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
          Text(
            p.label,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
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
        Text(
          p.label,
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    ),
  );
}
