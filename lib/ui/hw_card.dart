/// 作业卡片公共构建逻辑，首页与日历页共用。
/// 视觉规格见 ui/tokens.dart（白卡 + 双层淡阴影，无描边，强调色只做点缀）。
library;

import 'package:flutter/material.dart';

import '../models/homework.dart';
import '../services/storage.dart';
import 'tokens.dart';
import 'focus_parts.dart';

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
}) => GestureDetector(
  onTap: onTap,
  onLongPress: onLongPress,
  child: buildFocusHomeworkRow(context, hw, showCourse: showCourse),
);

Widget buildFocusHomeworkRow(
  BuildContext context,
  HomeworkItem hw, {
  bool priority = false,
  bool showCourse = true,
}) {
  final p = paletteOf(context);
  final ink = priority ? p.onAccent : p.ink;
  final secondary = priority ? p.onAccent.withValues(alpha: .78) : p.ink2;
  final due = hw.dueAt;
  final overdue = hwIsOverdue(hw);
  final time = due == null ? '截止时间待确认' : HomeworkItem.formatDueTime(due);
  final compactTime = due == null
      ? ''
      : '${due.hour.toString().padLeft(2, '0')}:${due.minute.toString().padLeft(2, '0')}';
  final large = MediaQuery.textScalerOf(context).scale(15) > 19;
  final metadata = Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (showCourse) ...[
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: avatarColorFor(hw.course),
              shape: BoxShape.circle,
            ),
          ),
        ),
        const SizedBox(width: 7),
      ],
      Expanded(
        child: Text(
          showCourse ? (hw.course.isEmpty ? '未指定课程' : hw.course) : '',
          style: TextStyle(fontSize: 12, color: secondary),
        ),
      ),
      const SizedBox(width: 8),
      Text(
        hw.platform.label,
        textAlign: TextAlign.end,
        style: TextStyle(fontSize: 11, color: secondary),
      ),
    ],
  );
  final title = Text(
    hw.title.isEmpty ? '（无标题）' : hw.title,
    style: TextStyle(
      fontSize: 16,
      height: 1.4,
      fontWeight: FontWeight.w600,
      color: ink,
    ),
  );
  final deadline = Column(
    crossAxisAlignment: CrossAxisAlignment.end,
    children: [
      Text(
        compactTime,
        style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: ink),
      ),
      Text(
        overdue ? '已截止' : '今天',
        style: TextStyle(
          fontSize: 11,
          color: overdue ? Theme.of(context).colorScheme.error : secondary,
        ),
      ),
    ],
  );
  final content = Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      metadata,
      const SizedBox(height: 8),
      if (priority && !large)
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(child: title),
            const SizedBox(width: 12),
            deadline,
          ],
        )
      else
        title,
      if (priority && large) ...[const SizedBox(height: 7), deadline],
      if (!priority && hw.note?.trim().isNotEmpty == true) ...[
        const SizedBox(height: 6),
        Text(
          hw.note!.trim(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 12, color: secondary),
        ),
      ],
      if (!priority) ...[
        const SizedBox(height: 10),
        Wrap(
          spacing: 12,
          runSpacing: 4,
          children: [
            Text(
              time,
              style: TextStyle(
                fontSize: 12,
                color: overdue
                    ? Theme.of(context).colorScheme.error
                    : secondary,
              ),
            ),
            Text(
              hwStatusLabel(hw),
              style: TextStyle(
                fontSize: 11,
                color: overdue
                    ? Theme.of(context).colorScheme.error
                    : secondary,
              ),
            ),
          ],
        ),
      ],
      if (hw.score != null)
        Text(
          '${HomeworkItem.scoreText(hw.score)} 分',
          style: TextStyle(fontSize: 11, color: secondary),
        ),
    ],
  );
  return priority
      ? Padding(padding: const EdgeInsets.all(15), child: content)
      : WorkbenchPanel(seed: hw.id, child: content);
}
