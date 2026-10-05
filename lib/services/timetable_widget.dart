/// 今日课表桌面小组件的数据通道：把整周课程（含具体上下课时间与周次数组）
/// 写成结构化 JSON 给原生渲染，原生侧每次重绘按「今天」取列表、自己拼日期头
/// 和周次——这样跨天/跨周时（App 一直没开）系统 30 分钟一次的重绘也能自动
/// 换到正确的一天/一周；当前/已过的课由原生侧按时间实时判定。
library;

import 'dart:convert';

import 'package:home_widget/home_widget.dart';

import '../models/course.dart';
import 'section_times.dart';
import 'storage.dart';

class TimetableWidget {
  TimetableWidget._();

  /// 课表/学期校准/作息变化后调用：重写整周课程并刷新小组件。
  static Future<void> push(List<Course> courses) async {
    try {
      final now = DateTime.now();
      final start = Storage.semesterStart();
      final week = start == null ? null : Course.weekNumberOf(start, now);
      String hm(int m) =>
          '${m ~/ 60}:${(m % 60).toString().padLeft(2, '0')}';
      // 契约：表外节次 slotOf 返回 null → s/e 传空串，原生对空串只是
      // 不显示时间，无崩溃风险。此前钳到末节，13-16 节晚课会被标成
      // 21:45 上课误导用户。
      (String, String) slot(int section) {
        final s = SectionTimes.slotOf(section);
        if (s == null) return ('', '');
        return (hm(s.$1), hm(s.$2));
      }

      // 一周七天全量推送：每门课带上自己的周次数组（w）与开学日（start），
      // 原生按当前日期重算周次并过滤——不推送周次快照的话，App 超过一周
      // 没打开，小组件会一直显示旧周的「第N周」和旧周课程（单双周错课）。
      final days = <String, List<Map<String, Object>>>{};
      for (var d = 1; d <= 7; d++) {
        final dayCourses =
            courses.where((c) => c.weekday == d).toList()
              ..sort((a, b) => a.startSection.compareTo(b.startSection));
        days['$d'] = [
          for (final c in dayCourses)
            {
              's': slot(c.startSection).$1,
              'e': slot(c.endSection).$2,
              'n': c.name,
              'r': c.room,
              'w': c.weeks,
            },
        ];
      }

      await HomeWidget.saveWidgetData<String>(
          'tt_json',
          jsonEncode({
            // 兼容 v2 的字段：原生读到 w/start 就按当前周重算并过滤
            'week': week == null
                ? '周次未校准'
                : (week < 1 ? '未开学' : '第$week周'),
            'start': start?.millisecondsSinceEpoch,
            'days': days,
          }));
      await HomeWidget.updateWidget(androidName: 'TimetableWidgetProvider');
    } catch (_) {
      // 小组件更新失败不影响主流程
    }
  }
}
