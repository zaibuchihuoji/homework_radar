/// 日历视图：月历标记有截止的日期，点选日期查看当天作业。
library;

import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:table_calendar/table_calendar.dart';
import 'dart:async';

import '../app_state.dart';
import '../models/homework.dart';
import '../ui/adaptive.dart';
import '../ui/hw_card.dart';
import '../ui/ink_wash.dart';
import '../ui/style_background.dart';
import '../ui/tokens.dart';
import 'detail_page.dart';

class CalendarPage extends StatefulWidget {
  const CalendarPage({super.key, required this.state});

  final AppState state;

  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  DateTime _selected = DateTime.now();
  bool _localeReady = false;
  Timer? _clock;

  @override
  void initState() {
    super.initState();
    initializeDateFormatting('zh_CN', null).then((_) {
      if (mounted) setState(() => _localeReady = true);
    });
    // 已截止/倒计时文案按 build 时刻算死，跨过截止点不翻转——定时重建
    _clock = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  Map<DateTime, List<HomeworkItem>> get _events {
    final map = <DateTime, List<HomeworkItem>>{};
    for (final hw in widget.state.homework) {
      final d = hw.dueAt;
      if (d == null) continue;
      final key = DateTime(d.year, d.month, d.day);
      map.putIfAbsent(key, () => []).add(hw);
    }
    return map;
  }

  @override
  Widget build(BuildContext context) {
    final events = _events;
    final dayKey = DateTime(_selected.year, _selected.month, _selected.day);
    final dayItems = (events[dayKey] ?? const <HomeworkItem>[])
        .toList()
      ..sort((a, b) => a.dueAt!.compareTo(b.dueAt!));

    return StyleBackground(
        // 玻璃样式下透明化 Scaffold，露出渐变磨砂底衬
        child: Scaffold(
      backgroundColor: scaffoldBgOf(context),
      appBar: AppBar(title: appBarTitle(context, '作业日历')),
      body: !_localeReady
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              children: [
                Container(
                  decoration: inkWashFill(context, 18) ??
                      (isPixelStyle(context)
                          ? BoxDecoration(color: cardColor(context))
                          : isReceiptStyle(context)
                              ? receiptTear(context)
                              : isEditorialStyle(context)
                                  ? BoxDecoration(color: cardColor(context))
                                  : BoxDecoration(
                                      color: cardColor(context),
                                      borderRadius:
                                          BorderRadius.circular(18),
                                      border: cardBorderOf(context),
                                    )),
                  foregroundDecoration: isPixelStyle(context)
                      ? pixelFrame(context, 18)
                      : paperInnerRing(context, 18) ??
                          morandiCream(context, 18) ??
                          editorialRules(context),
                  clipBehavior: Clip.antiAlias,
                  child: TableCalendar<HomeworkItem>(
                    firstDay: DateTime.now().subtract(const Duration(days: 120)),
                    lastDay: DateTime.now().add(const Duration(days: 400)),
                    focusedDay: _selected,
                    selectedDayPredicate: (day) =>
                        isSameDay(day, _selected),
                    locale: 'zh_CN',
                    eventLoader: (day) =>
                        events[DateTime(day.year, day.month, day.day)] ?? const [],
                    onDaySelected: (selected, focused) {
                      setState(() => _selected = selected);
                    },
                    // 跟踪翻页：不回写 focusedDay 的话，任何外部重建都会
                    // 把日历弹回 _selected 所在月份
                    onPageChanged: (focused) {
                      setState(() => _selected = focused);
                    },
                    headerStyle: HeaderStyle(
                      formatButtonVisible: false,
                      titleCentered: true,
                      // 小票：月份抬头是打印读数（等宽 + 拉字距）
                      titleTextStyle: monoText(
                        context,
                        const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w700),
                      ),
                    ),
                    calendarStyle: CalendarStyle(
                      todayDecoration: BoxDecoration(
                        color: accentColor(context).withValues(alpha: 0.18),
                        shape: BoxShape.circle,
                      ),
                      // 小票：选中日是一枚盖下去的红章（方印），不是圆圈
                      selectedDecoration: isReceiptStyle(context)
                          ? BoxDecoration(
                              color: accentColor(context),
                              borderRadius: BorderRadius.circular(2),
                            )
                          : BoxDecoration(
                              color: accentColor(context),
                              shape: BoxShape.circle,
                            ),
                      outsideDaysVisible: false,
                    ),
                    calendarBuilders: CalendarBuilders(
                      // 标记点颜色 = 当天作业状态：全完成绿、还没到期的橙、
                      // 当天/已过还有未完成的红——哪天有事没办一眼可见
                      markerBuilder: (context, day, events) {
                        if (events.isEmpty) return null;
                        final items = events.cast<HomeworkItem>();
                        final now = DateTime.now();
                        final today = DateTime(now.year, now.month, now.day);
                        final day0 = DateTime(day.year, day.month, day.day);
                        // 标记点颜色 = 当天作业状态：全完成绿、还没到期的橙、
                        // 当天/已过还有未完成的红。水墨下收进墨朱二色：
                        // 已办=淡墨点，未到=朱砂，已过期未办=赤红。
                        final color = isInkStyle(context)
                            ? (items.every(hwIsDone)
                                ? textSecondary(context).withValues(alpha: 0.55)
                                : day0.isAfter(today)
                                    ? accentColor(context)
                                    : Tokens.danger)
                            : items.every(hwIsDone)
                                ? accentColor(context)
                                : day0.isAfter(today)
                                    ? const Color(0xFFEA580C)
                                    : Tokens.danger;
                        return Positioned(
                          left: 0,
                          right: 0,
                          bottom: 4,
                          child: Center(
                            child: Container(
                              width: 6,
                              height: 6,
                              // 小票：标记点是打印方点
                              decoration: isReceiptStyle(context)
                                  ? BoxDecoration(
                                      color: color,
                                      borderRadius:
                                          BorderRadius.circular(1))
                                  : BoxDecoration(
                                      color: color,
                                      shape: BoxShape.circle,
                                    ),
                            ),
                          ),
                        );
                      },
                    ),
                    availableGestures: AvailableGestures.horizontalSwipe,
                  ),
                ),
                const SizedBox(height: 14),
                // 水墨：日期行前一枚顿笔墨点，与首页段头同一语言
                Row(
                  children: [
                    if (isInkStyle(context)) ...[
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: textPrimary(context).withValues(alpha: 0.78),
                        ),
                      ),
                      const SizedBox(width: 7),
                    ],
                    Text(
                      '${_selected.month}月${_selected.day}日 · ${dayItems.isEmpty ? '没有截止' : '${dayItems.length} 项截止'}',
                      style: monoText(
                        context,
                        TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: textSecondary(context)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (dayItems.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    child: Center(
                      // 水墨：空态是一小幅远山 +「闲」印落款，不上彩色 emoji
                      child: isInkStyle(context)
                          ? Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const SizedBox(
                                  width: 240,
                                  height: 72,
                                  child: InkMountains(height: 72),
                                ),
                                const SizedBox(height: 10),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text('这一天没有作业截止',
                                        style: TextStyle(
                                            fontSize: 13,
                                            color: textFaint(context))),
                                    const SizedBox(width: 7),
                                    const InkSealChip(glyph: '闲'),
                                  ],
                                ),
                              ],
                            )
                          : isReceiptStyle(context)
                              // 小票：空态是一道「本日无账」的打印分区
                              ? Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    SizedBox(
                                      width: 190,
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Container(
                                              height: 1,
                                              color: textPrimary(context)
                                                  .withValues(alpha: 0.30)),
                                          const SizedBox(height: 2),
                                          Container(
                                              height: 1,
                                              color: textPrimary(context)
                                                  .withValues(alpha: 0.30)),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 9),
                                    Text('这一天没有作业截止',
                                        style: monoText(
                                          context,
                                          TextStyle(
                                              fontSize: 12.5,
                                              letterSpacing: 1.5,
                                              color: textFaint(context)),
                                        )),
                                    const SizedBox(height: 9),
                                    SizedBox(
                                      width: 190,
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Container(
                                              height: 1,
                                              color: textPrimary(context)
                                                  .withValues(alpha: 0.30)),
                                          const SizedBox(height: 2),
                                          Container(
                                              height: 1,
                                              color: textPrimary(context)
                                                  .withValues(alpha: 0.30)),
                                        ],
                                      ),
                                    ),
                                  ],
                                )
                              : Text('这一天没有作业截止 🎉',
                                  style: TextStyle(
                                      fontSize: 13, color: textFaint(context))),
                    ),
                  )
                else
                  ...dayItems.map(
                    (hw) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: buildHwCard(
                        context,
                        hw,
                        onTap: () => Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => HomeworkDetailPage(homeworkId: hw.id),
                        )),
                      ),
                    ),
                  ),
              ],
            ),
    ),
    );
  }
}
