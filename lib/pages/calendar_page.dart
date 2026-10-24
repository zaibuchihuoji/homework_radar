/// 日历视图：月历标记有截止的日期，点选日期查看当天作业。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:table_calendar/table_calendar.dart';

import '../app_state.dart';
import '../models/homework.dart';
import '../ui/adaptive.dart';
import '../ui/dashed_line.dart';
import '../ui/hw_card.dart';
import '../ui/ink_wash.dart';
import '../ui/style_background.dart';
import '../ui/theme_page_parts.dart';
import '../ui/tokens.dart';
import '../ui/focus_parts.dart';
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
    // 倒计时和截止状态需要随时间刷新；翻页状态同时保留。
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
      map.putIfAbsent(DateTime(d.year, d.month, d.day), () => []).add(hw);
    }
    return map;
  }

  @override
  Widget build(BuildContext context) {
    final p = paletteOf(context);
    final events = _events;
    final dayKey = DateTime(_selected.year, _selected.month, _selected.day);
    final dayItems = (events[dayKey] ?? const <HomeworkItem>[]).toList()
      ..sort((a, b) => a.dueAt!.compareTo(b.dueAt!));
    final monthDays = events.entries.where(
      (e) => e.key.year == _selected.year && e.key.month == _selected.month,
    );
    final monthCount = monthDays.fold<int>(0, (sum, e) => sum + e.value.length);
    final dayTitle =
        '${_selected.month}月${_selected.day}日 · ${dayItems.isEmpty ? '没有截止' : '${dayItems.length} 项截止'}';
    final calendar = TableCalendar<HomeworkItem>(
      headerVisible: !p.sunny,
      firstDay: DateTime.now().subtract(const Duration(days: 120)),
      lastDay: DateTime.now().add(const Duration(days: 400)),
      focusedDay: _selected,
      selectedDayPredicate: (day) => isSameDay(day, _selected),
      locale: 'zh_CN',
      eventLoader: (day) =>
          events[DateTime(day.year, day.month, day.day)] ?? const [],
      onDaySelected: (selected, focused) =>
          setState(() => _selected = selected),
      // 翻页也回写 focusedDay，防止时钟/外部重建时跳回旧月份。
      onPageChanged: (focused) => setState(() => _selected = focused),
      rowHeight: p.sunny
          ? 48
          : p.clean
          ? 52
          : 48,
      daysOfWeekHeight: p.clean ? 20 : 34,
      headerStyle: HeaderStyle(
        formatButtonVisible: false,
        titleCentered: true,
        leftChevronIcon: const Tooltip(
          message: '上个月',
          child: Icon(Icons.chevron_left),
        ),
        rightChevronIcon: const Tooltip(
          message: '下个月',
          child: Icon(Icons.chevron_right),
        ),
        titleTextStyle: monoText(
          context,
          const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
        headerPadding: EdgeInsets.symmetric(vertical: p.clean ? 8 : 12),
        leftChevronMargin: EdgeInsets.zero,
        rightChevronMargin: EdgeInsets.zero,
      ),
      calendarStyle: CalendarStyle(
        todayDecoration: BoxDecoration(
          color: p.accentFill.withValues(alpha: 0.18),
          shape: BoxShape.circle,
        ),
        selectedDecoration: BoxDecoration(
          color: p.accentFill,
          shape: BoxShape.circle,
        ),
        selectedTextStyle: TextStyle(color: p.onAccent),
        outsideDaysVisible: false,
      ),
      calendarBuilders: CalendarBuilders<HomeworkItem>(
        headerTitleBuilder: p.clean ? null : _monthHeading,
        dowBuilder: p.clean ? null : _weekday,
        defaultBuilder: p.clean ? null : (c, day, focused) => _day(c, day),
        todayBuilder: p.clean
            ? null
            : (c, day, focused) => _day(c, day, today: true),
        selectedBuilder: p.clean
            ? null
            : (c, day, focused) => _day(c, day, selected: true),
        markerBuilder: _markers,
      ),
      availableGestures: AvailableGestures.horizontalSwipe,
    );

    if (p.sunny) {
      return _focusCalendar(
        context,
        calendar,
        dayItems,
        monthCount,
        monthDays.length,
      );
    }
    return StyleBackground(
      child: Scaffold(
        backgroundColor: scaffoldBgOf(context),
        appBar: AppBar(title: appBarTitle(context, '作业日历')),
        body: !_localeReady
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                children: [
                  if (!p.clean) ...[
                    ThemePageHeader(
                      compact: true,
                      title: '作业日历',
                      kicker: 'CALENDAR',
                      icon: Icons.calendar_month_outlined,
                      summary: '本月 $monthCount 项截止 · ${monthDays.length} 天有安排',
                    ),
                  ],
                  if (p.sunny)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        '本月 $monthCount 项截止',
                        style: TextStyle(fontSize: 12, color: p.ink2),
                      ),
                    ),
                  if (p.clean)
                    Container(
                      decoration: BoxDecoration(
                        color: cardColor(context),
                        borderRadius: BorderRadius.circular(18),
                        border: p.sunny ? null : cardBorderOf(context),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: calendar,
                    )
                  else
                    ThemePanel(
                      seed: 'calendar-month',
                      padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
                      child: calendar,
                    ),
                  const SizedBox(height: 14),
                  if (p.clean)
                    Text(
                      dayTitle,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: textSecondary(context),
                      ),
                    )
                  else ...[
                    ThemeSectionHeading(
                      title: '当日安排',
                      detail: '${dayItems.length} 项截止',
                    ),
                    const SizedBox(height: 8),
                    _agendaDate(context, dayTitle),
                  ],
                  const SizedBox(height: 8),
                  if (dayItems.isEmpty)
                    _emptyDay(context)
                  else
                    ...dayItems.map(
                      (hw) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: buildHwCard(
                          context,
                          hw,
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) =>
                                  HomeworkDetailPage(homeworkId: hw.id),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
      ),
    );
  }

  void _moveMonth(int delta) {
    final first = DateUtils.dateOnly(
      DateTime.now().subtract(const Duration(days: 120)),
    );
    final last = DateUtils.dateOnly(
      DateTime.now().add(const Duration(days: 400)),
    );
    var target = DateTime(_selected.year, _selected.month + delta, 1);
    if (target.isBefore(first)) target = first;
    if (target.isAfter(last)) target = last;
    setState(() => _selected = target);
  }

  Widget _focusCalendar(
    BuildContext context,
    Widget calendar,
    List<HomeworkItem> items,
    int monthCount,
    int days,
  ) {
    final p = paletteOf(context);
    final first = DateTime.now().subtract(const Duration(days: 120));
    final last = DateTime.now().add(const Duration(days: 400));
    final selectedMonth = DateTime(_selected.year, _selected.month);
    return StyleBackground(
      child: Scaffold(
        backgroundColor: scaffoldBgOf(context),
        appBar: AppBar(
          title: appBarTitle(context, '作业日历'),
          actions: [
            TextButton(
              onPressed: () => setState(() => _selected = DateTime.now()),
              child: const Tooltip(message: '返回今天', child: Text('今天')),
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: !_localeReady
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${_selected.year}年',
                              style: TextStyle(fontSize: 12, color: p.ink2),
                            ),
                            Text(
                              '${_selected.month}月',
                              style: TextStyle(
                                fontSize: 32,
                                height: 1.4,
                                fontWeight: FontWeight.w600,
                                color: p.ink,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: '上个月',
                        onPressed:
                            selectedMonth.isAfter(
                              DateTime(first.year, first.month),
                            )
                            ? () => _moveMonth(-1)
                            : null,
                        icon: const Icon(Icons.chevron_left_rounded),
                      ),
                      IconButton(
                        tooltip: '下个月',
                        onPressed:
                            selectedMonth.isBefore(
                              DateTime(last.year, last.month),
                            )
                            ? () => _moveMonth(1)
                            : null,
                        icon: const Icon(Icons.chevron_right_rounded),
                      ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Row(
                      children: [
                        Text(
                          '$monthCount 项截止',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: p.ink,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Text(
                          '$days 天有安排',
                          style: TextStyle(fontSize: 12, color: p.ink2),
                        ),
                      ],
                    ),
                  ),
                  calendar,
                  const SizedBox(height: 20),
                  FocusSummary(
                    eyebrow: DateUtils.isSameDay(_selected, DateTime.now())
                        ? '今天'
                        : '所选日期',
                    title: '${_selected.month}月${_selected.day}日',
                    detail: '${items.length} 项截止',
                    trailing: Icon(
                      Icons.event_note_outlined,
                      color: p.onAccent,
                      size: 26,
                    ),
                  ),
                  if (items.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 28),
                      child: Text(
                        '这一天没有截止作业',
                        style: TextStyle(fontSize: 15, color: p.ink2),
                      ),
                    )
                  else ...[
                    const FocusSectionTitle('截止安排'),
                    for (final hw in items)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: buildHwCard(
                          context,
                          hw,
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) =>
                                  HomeworkDetailPage(homeworkId: hw.id),
                            ),
                          ),
                        ),
                      ),
                  ],
                ],
              ),
      ),
    );
  }

  Widget _monthHeading(BuildContext context, DateTime date) {
    final p = paletteOf(context);
    final month = date.month.toString().padLeft(2, '0');
    final year = '${date.year}';
    final title = p.pixel
        ? '$year / $month'
        : p.terminal
        ? '[$year.$month]'
        : p.receipt
        ? '$year · $month'
        : '${date.month}月';
    final font = p.pixel || p.terminal || p.receipt
        ? 'monospace'
        : p.paper || p.inkWash || p.journal
        ? 'serif'
        : null;
    final text = Text(
      title,
      style: TextStyle(
        fontFamily: font,
        fontSize: p.editorial
            ? 36
            : p.inkWash
            ? 27
            : 21,
        fontWeight: p.editorial || p.comic ? FontWeight.w900 : FontWeight.w700,
        color: p.ink,
        letterSpacing: p.paper || p.inkWash
            ? 3
            : p.receipt
            ? 2
            : 0,
      ),
    );
    Widget heading = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!p.pixel && !p.terminal && !p.receipt)
          Text(
            p.journal ? '$year / MONTHLY' : year,
            style: TextStyle(
              fontSize: 10,
              fontFamily: font,
              color: p.ink2,
              letterSpacing: 2,
            ),
          ),
        FittedBox(fit: BoxFit.scaleDown, child: text),
        if (p.paper || p.receipt) ...[
          const SizedBox(height: 6),
          DashedLine(color: p.ink3),
        ],
        if (p.inkWash) const BrushLine(),
        if (p.editorial) Container(height: 3, color: p.ink),
        if (p.morandi)
          Padding(
            padding: const EdgeInsets.only(top: 5),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final color in [p.accent, p.ink3, p.hairline])
                  Container(
                    width: 18,
                    height: 5,
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
    if (p.comic) {
      heading = Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BubbleDecoration(
          fillColor: p.accentFill.withValues(alpha: 0.14),
          borderColor: p.ink,
          borderWidth: 2,
        ),
        child: heading,
      );
    }
    if (p.pixel || p.terminal) {
      heading = Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: p.ink, width: p.pixel ? 3 : 1),
          ),
        ),
        child: heading,
      );
    }
    if (p.journal) {
      heading = Container(
        padding: const EdgeInsets.all(5),
        decoration: BoxDecoration(
          color: p.accentFill.withValues(alpha: 0.08),
          border: Border(bottom: BorderSide(color: p.accent)),
        ),
        child: heading,
      );
    }
    return heading;
  }

  Widget _weekday(BuildContext context, DateTime date) {
    final p = paletteOf(context);
    const names = ['一', '二', '三', '四', '五', '六', '日'];
    final label = names[date.weekday - 1];
    return Container(
      alignment: Alignment.center,
      margin: const EdgeInsets.symmetric(horizontal: 2),
      decoration: BoxDecoration(
        color: p.morandi || p.comic
            ? p.accentFill.withValues(alpha: 0.09)
            : null,
        borderRadius: p.morandi
            ? BorderRadius.circular(10)
            : p.comic
            ? BorderRadius.circular(5)
            : null,
        border: p.paper || p.editorial || p.journal || p.terminal
            ? Border(
                bottom: BorderSide(
                  color: p.journal
                      ? p.accentFill.withValues(alpha: 0.4)
                      : p.hairline,
                ),
              )
            : null,
      ),
      child: Text(
        p.terminal
            ? '[$label]'
            : p.pixel
            ? '·$label·'
            : p.inkWash
            ? label
            : p.receipt
            ? label
            : '周$label',
        style: TextStyle(
          fontSize: p.terminal || p.pixel ? 10 : 11,
          color: p.ink2,
          fontFamily: p.pixel || p.terminal || p.receipt
              ? 'monospace'
              : p.paper || p.inkWash || p.journal
              ? 'serif'
              : null,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _day(
    BuildContext context,
    DateTime date, {
    bool today = false,
    bool selected = false,
  }) {
    final p = paletteOf(context);
    final highlighted = today || selected;
    final soft = p.paper || p.editorial || p.journal;
    final fill = selected
        ? (soft ? p.accentFill.withValues(alpha: 0.10) : p.accentFill)
        : today
        ? p.accentFill.withValues(alpha: 0.10)
        : Colors.transparent;
    final textColor = selected && !soft
        ? p.onAccent
        : highlighted
        ? p.accent
        : p.ink;
    final radius = p.morandi
        ? 13.0
        : p.comic
        ? 10.0
        : p.inkWash
        ? 3.0
        : 0.0;
    Decoration decoration = BoxDecoration(
      color: fill,
      shape: p.journal ? BoxShape.circle : BoxShape.rectangle,
      borderRadius: p.journal ? null : BorderRadius.circular(radius),
      border: highlighted
          ? Border.all(
              color: p.comic ? p.ink : p.accent,
              width: p.comic
                  ? 2
                  : p.inkWash
                  ? 1.5
                  : 1,
            )
          : null,
    );
    if (p.pixel && highlighted) {
      decoration = PixelFrameDecoration(lineColor: p.accent);
    }
    if (p.terminal && highlighted) decoration = BoxDecoration(color: fill);
    return Center(
      child: Container(
        width: 34,
        height: 36,
        alignment: Alignment.center,
        decoration: decoration,
        child: p.pixel && highlighted
            ? Container(
                alignment: Alignment.center,
                margin: const EdgeInsets.all(4),
                color: fill,
                child: Text(
                  '${date.day}',
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 14,
                    color: textColor,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              )
            : FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  p.terminal && highlighted ? '[${date.day}]' : '${date.day}',
                  style: TextStyle(
                    fontSize: p.terminal
                        ? 12
                        : p.editorial
                        ? 18
                        : 14,
                    color: textColor,
                    fontFamily: p.pixel || p.receipt || p.terminal
                        ? 'monospace'
                        : p.paper || p.inkWash || p.journal
                        ? 'serif'
                        : null,
                    fontWeight: highlighted || p.editorial
                        ? FontWeight.w800
                        : FontWeight.w500,
                    decoration: p.paper && highlighted
                        ? TextDecoration.underline
                        : null,
                  ),
                ),
              ),
      ),
    );
  }

  Widget? _markers(
    BuildContext context,
    DateTime day,
    List<HomeworkItem> items,
  ) {
    if (items.isEmpty) return null;
    final p = paletteOf(context);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day0 = DateTime(day.year, day.month, day.day);
    // 保留原有状态语义：完成为主题强调色（水墨淡墨）、未来橙色、到期红色。
    final color = p.inkWash
        ? items.every(hwIsDone)
              ? p.ink2.withValues(alpha: 0.55)
              : day0.isAfter(today)
              ? p.accent
              : Tokens.danger
        : items.every(hwIsDone)
        ? p.accent
        : day0.isAfter(today)
        ? const Color(0xFFEA580C)
        : Tokens.danger;
    final square = p.pixel || p.receipt || p.terminal;
    final line = p.editorial || p.journal || p.paper;
    return Positioned(
      left: 0,
      right: 0,
      bottom: 3,
      child: Center(
        child: Semantics(
          label: '${day.month}月${day.day}日 ${items.length}项截止',
          child: Container(
            width: line
                ? 16
                : p.comic
                ? 8
                : 6,
            height: line
                ? 3
                : p.comic
                ? 8
                : 6,
            decoration: BoxDecoration(
              color: color,
              shape: square || line ? BoxShape.rectangle : BoxShape.circle,
              border: p.comic ? Border.all(color: p.ink, width: 1) : null,
            ),
          ),
        ),
      ),
    );
  }

  Widget _agendaDate(BuildContext context, String title) {
    final p = paletteOf(context);
    return ThemePanel(
      seed: 'calendar-agenda',
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (p.inkWash)
            const Padding(
              padding: EdgeInsets.only(right: 10),
              child: InkSealChip(glyph: '日'),
            )
          else if (p.editorial || p.journal) ...[
            Text(
              _selected.day.toString().padLeft(2, '0'),
              style: TextStyle(
                fontSize: p.editorial ? 36 : 28,
                fontWeight: FontWeight.w900,
                fontFamily: p.journal ? 'serif' : null,
                color: p.ink,
              ),
            ),
            const SizedBox(width: 12),
          ] else ...[
            Icon(
              p.pixel
                  ? Icons.event_note
                  : p.receipt
                  ? Icons.receipt_long
                  : p.terminal
                  ? Icons.chevron_right
                  : Icons.today_outlined,
              color: p.ink2,
              size: 20,
            ),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Text(
              p.terminal ? '> $title' : title,
              style: serifTitle(
                context,
                monoText(
                  context,
                  TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: p.ink,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyDay(BuildContext context) {
    final p = paletteOf(context);
    final message = Text(
      p.clean ? '这一天没有作业截止 🎉' : '这一天没有作业截止',
      style: TextStyle(fontSize: 13, color: p.ink3),
      textAlign: TextAlign.center,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Center(
        child: p.inkWash
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(
                    width: 240,
                    height: 72,
                    child: InkMountains(height: 72),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    alignment: WrapAlignment.center,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 7,
                    children: [
                      message,
                      const InkSealChip(glyph: '闲'),
                    ],
                  ),
                ],
              )
            : p.receipt
            ? Column(
                children: [
                  const DashedLine(),
                  const SizedBox(height: 12),
                  message,
                  const SizedBox(height: 12),
                  const DashedLine(),
                ],
              )
            : message,
      ),
    );
  }
}
