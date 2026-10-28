import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';

import '../models/homework.dart';
import 'hw_card.dart';
import 'tokens.dart';

/// A compact date filter; selecting a date never changes the stored homework.
class HomeworkDateBar extends StatefulWidget {
  const HomeworkDateBar({
    super.key,
    required this.homework,
    required this.selectedDate,
    required this.onDateSelected,
    required this.onOpenCalendar,
  });

  final List<HomeworkItem> homework;
  final DateTime? selectedDate;
  final ValueChanged<DateTime?> onDateSelected;
  final VoidCallback onOpenCalendar;

  @override
  State<HomeworkDateBar> createState() => _HomeworkDateBarState();
}

class _HomeworkDateBarState extends State<HomeworkDateBar> {
  DateTime _focused = DateTime.now();
  bool _expanded = false;

  @override
  void didUpdateWidget(covariant HomeworkDateBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedDate != oldWidget.selectedDate &&
        widget.selectedDate != null) {
      _focused = widget.selectedDate!;
    }
  }

  void _move(int direction) {
    final first = DateUtils.dateOnly(
      DateTime.now().subtract(const Duration(days: 120)),
    );
    final last = DateUtils.dateOnly(
      DateTime.now().add(const Duration(days: 400)),
    );
    final target = _expanded
        ? DateTime(_focused.year, _focused.month + direction, 1)
        : _focused.add(Duration(days: direction * 7));
    setState(
      () => _focused = target.isBefore(first)
          ? first
          : target.isAfter(last)
          ? last
          : target,
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = paletteOf(context);
    final events = <DateTime, List<HomeworkItem>>{};
    for (final item in widget.homework) {
      final due = item.dueAt;
      if (due != null) {
        events.putIfAbsent(DateUtils.dateOnly(due), () => []).add(item);
      }
    }
    final square = p.pixel || p.receipt || p.terminal || p.editorial;
    final first = DateUtils.dateOnly(
      DateTime.now().subtract(const Duration(days: 120)),
    );
    final last = DateUtils.dateOnly(
      DateTime.now().add(const Duration(days: 400)),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 2),
      child: Container(
        decoration: BoxDecoration(
          color: p.card,
          borderRadius: BorderRadius.circular(
            square
                ? 2
                : p.morandi
                ? 20
                : 12,
          ),
          border: Border.all(
            color: p.cardBorder,
            width: p.pixel || p.comic ? 1.5 : 1,
          ),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 2, 4, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${_focused.year}年${_focused.month}月',
                      style: TextStyle(
                        color: p.ink,
                        fontWeight: FontWeight.w700,
                        fontFamily: p.pixel || p.terminal || p.receipt
                            ? 'monospace'
                            : null,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: _expanded ? '上个月' : '上一周',
                    onPressed: _focused.isAfter(first) ? () => _move(-1) : null,
                    icon: const Icon(Icons.chevron_left_rounded),
                    visualDensity: VisualDensity.compact,
                  ),
                  IconButton(
                    tooltip: _expanded ? '下个月' : '下一周',
                    onPressed: _focused.isBefore(last) ? () => _move(1) : null,
                    icon: const Icon(Icons.chevron_right_rounded),
                    visualDensity: VisualDensity.compact,
                  ),
                  Tooltip(
                    message: '选择今天',
                    child: TextButton(
                      onPressed: () {
                        final today = DateUtils.dateOnly(DateTime.now());
                        setState(() => _focused = today);
                        widget.onDateSelected(today);
                      },
                      child: const Text('今天'),
                    ),
                  ),
                  IconButton(
                    tooltip: _expanded ? '收起月历' : '展开月历',
                    onPressed: () => setState(() => _expanded = !_expanded),
                    icon: Icon(
                      _expanded
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                    ),
                  ),
                ],
              ),
            ),
            AnimatedSize(
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: TableCalendar<HomeworkItem>(
                firstDay: first,
                lastDay: last,
                focusedDay: _focused,
                headerVisible: false,
                calendarFormat: _expanded
                    ? CalendarFormat.month
                    : CalendarFormat.week,
                startingDayOfWeek: StartingDayOfWeek.monday,
                rowHeight: MediaQuery.textScalerOf(context)
                    .scale(42)
                    .clamp(42.0, 72.0),
                daysOfWeekHeight: 24,
                availableGestures: AvailableGestures.horizontalSwipe,
                selectedDayPredicate: (day) =>
                    DateUtils.isSameDay(day, widget.selectedDate),
                onDaySelected: (day, focused) {
                  setState(() => _focused = focused);
                  widget.onDateSelected(DateUtils.dateOnly(day));
                },
                onPageChanged: (day) => setState(() => _focused = day),
                eventLoader: (day) =>
                    events[DateUtils.dateOnly(day)] ?? const [],
                calendarStyle: CalendarStyle(
                  outsideDaysVisible: false,
                  defaultTextStyle: TextStyle(color: p.ink),
                  weekendTextStyle: TextStyle(color: p.ink),
                  todayTextStyle: TextStyle(color: p.ink),
                  todayDecoration: BoxDecoration(
                    color: p.accentFill.withValues(alpha: .16),
                    shape: BoxShape.circle,
                  ),
                  selectedTextStyle: TextStyle(
                    color: p.onAccent,
                    fontWeight: FontWeight.w700,
                  ),
                  selectedDecoration: BoxDecoration(
                    color: p.accentFill,
                    shape: square ? BoxShape.rectangle : BoxShape.circle,
                    borderRadius: square ? BorderRadius.circular(2) : null,
                  ),
                ),
                calendarBuilders: CalendarBuilders<HomeworkItem>(
                  dowBuilder: (context, day) => Center(
                    child: Text(
                      const ['一', '二', '三', '四', '五', '六', '日'][day.weekday -
                          1],
                      style: TextStyle(color: p.ink2, fontSize: 11),
                    ),
                  ),
                  markerBuilder: (context, day, items) {
                    if (items.isEmpty) return null;
                    final done = items.every(hwIsDone);
                    final past = !DateUtils.dateOnly(day)
                        .isAfter(DateUtils.dateOnly(DateTime.now()));
                    final color = done
                        ? (p.inkWash ? p.ink2.withValues(alpha: .55) : p.accent)
                        : past
                        ? Tokens.danger
                        : (p.inkWash ? p.accent : const Color(0xFFEA580C));
                    final status = done
                        ? '全部完成'
                        : past
                        ? '未完成，今天及以前截止'
                        : '未完成，未来截止';
                    return Positioned(
                      bottom: 2,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: Semantics(
                          label:
                              '${day.month}月${day.day}日 ${items.length}项截止，$status',
                          child: Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: color,
                              shape: square
                                  ? BoxShape.rectangle
                                  : BoxShape.circle,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  TextButton(
                    onPressed: widget.selectedDate == null
                        ? null
                        : () => widget.onDateSelected(null),
                    child: const Text('全部作业'),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: widget.onOpenCalendar,
                    child: const Text('完整日历'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
