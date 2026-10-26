/// Pure course reminder planning. Unknown weeks/times never become guesses.
library;

import 'dart:convert';

import '../models/course.dart';
import 'stable_hash.dart';

class ClassReminderTarget {
  const ClassReminderTarget(this.courseId, this.lessonMs);
  final String courseId;
  final int lessonMs;
  static const prefix = 'class-reminder:';
  static ClassReminderTarget? parse(String? payload) {
    if (payload == null || !payload.startsWith(prefix)) return null;
    try {
      final j = jsonDecode(payload.substring(prefix.length));
      if (j is! Map || j['course'] is! String || j['lesson'] is! int) {
        return null;
      }
      return ClassReminderTarget(j['course'] as String, j['lesson'] as int);
    } catch (_) {
      return null;
    }
  }
}

class ClassReminderEntry {
  const ClassReminderEntry({
    required this.id,
    required this.course,
    required this.fire,
    required this.lesson,
    required this.minutes,
  });
  final int id, minutes;
  final Course course;
  final DateTime fire, lesson;
  ClassReminderEntry at(DateTime time) => ClassReminderEntry(
    id: id,
    course: course,
    fire: time,
    lesson: lesson,
    minutes: minutes,
  );
  String get title => '$minutes分钟后上课：${course.name}';
  String get body =>
      '${lesson.hour.toString().padLeft(2, '0')}:${lesson.minute.toString().padLeft(2, '0')} 开始 · 第${course.startSection}节${course.room.isEmpty ? '' : ' · ${course.room}'}';
  // Include content and lead time: changed/deleted schedules cannot preserve a
  // stale pending alarm just because the stable course ID stayed the same.
  String get payload =>
      '${ClassReminderTarget.prefix}${jsonEncode({'course': course.id, 'lesson': lesson.millisecondsSinceEpoch, 'minutes': minutes, 'name': course.name, 'room': course.room, 'section': course.startSection})}';
}

class ClassReminderPlan {
  const ClassReminderPlan(this.entries, this.issue);
  final List<ClassReminderEntry> entries;
  final String? issue;

  static ClassReminderPlan build({
    required List<Course> courses,
    required DateTime? semesterStart,
    required DateTime now,
    required bool enabled,
    required int minutes,
    required List<(int, int)> slots,
  }) {
    if (!enabled) return const ClassReminderPlan([], '上课提醒已关闭');
    if (semesterStart == null) {
      return const ClassReminderPlan([], '请先在课表页设置开学日期');
    }
    final entries = <ClassReminderEntry>[];
    final unknown = <String>{};
    final used = <int>{0x7fffffff}; // reserved for the delayed diagnostic
    for (var d = 0; d < 56; d++) {
      final day = DateTime(now.year, now.month, now.day + d);
      final week = Course.weekNumberOf(semesterStart, day);
      if (week < 1) continue;
      for (final c in courses) {
        if (c.weeks.isEmpty || c.sectionsProvisional) {
          unknown.add(c.id);
          continue;
        }
        if (c.weekday != day.weekday || !c.inWeek(week)) continue;
        final index = c.startSection - 1;
        if (index < 0 || index >= slots.length) {
          unknown.add(c.id);
          continue;
        }
        final start = slots[index].$1;
        if (start < 0 || start >= 1440) {
          unknown.add(c.id);
          continue;
        }
        final lesson = DateTime(
          day.year,
          day.month,
          day.day,
          start ~/ 60,
          start % 60,
        );
        if (!lesson.isAfter(now)) continue;
        var id =
            0x40000000 |
            (stableHash('${c.id}#${day.year}-${day.month}-${day.day}') &
                0x3fffffff);
        while (!used.add(id)) {
          id = 0x40000000 | ((id + 1) & 0x3fffffff);
        }
        entries.add(
          ClassReminderEntry(
            id: id,
            course: c,
            fire: lesson.subtract(Duration(minutes: minutes)),
            lesson: lesson,
            minutes: minutes,
          ),
        );
      }
    }
    entries.sort((a, b) {
      final order = a.fire.compareTo(b.fire);
      return order == 0 ? a.id.compareTo(b.id) : order;
    });
    return ClassReminderPlan(
      entries,
      unknown.isEmpty ? null : '${unknown.length} 门课的周次或作息不完整，尚未安排提醒',
    );
  }
}
