// 离线回放：用真机截图的 ML Kit 识别块数据调 TimetableOcrParser。
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:homework_radar/services/timetable_ocr.dart';

void main() {
  test('真实截图识别块回放', () {
    final blocks = (jsonDecode(
                File('test/ocr_elements_real.json').readAsStringSync()) as List)
        .map((j) => OcrBlock(
              text: (j['t'] as String),
              left: (j['l'] as num).toDouble(),
              top: (j['tp'] as num).toDouble(),
              width: (j['w'] as num).toDouble(),
              height: (j['h'] as num).toDouble(),
            ))
        .toList();
    final courses = TimetableOcrParser.parse(blocks);
    // 有断言的回归网：解析器改坏布局重建时这里必须失败
    expect(courses, isNotEmpty, reason: '真实截图回放应至少解析出课程');
    // 周次行被 OCR 漏读的格子允许产出「周次未知」条目（预览页预关勾选、
    // 人工补），但其余字段仍须全部合法
    final weekless = courses.where((c) => c.weeks.isEmpty).toList();
    expect(weekless.length, lessThan(courses.length),
        reason: '全部课程都缺周次说明周次解析整体坏了');
    for (final c in courses) {
      expect(c.name, isNotEmpty, reason: '课程名不能为空');
      expect(c.weekday, inInclusiveRange(1, 7), reason: '${c.name} 星期越界');
      // 解析器契约允许到 16 节（晚课），断言不该比契约更窄
      expect(c.startSection, inInclusiveRange(1, 16), reason: '${c.name} 起始节次越界');
      expect(c.endSection, inInclusiveRange(c.startSection, 16),
          reason: '${c.name} 结束节次越界');
      for (final w in c.weeks) {
        expect(w, inInclusiveRange(1, 30), reason: '${c.name} 周次越界');
      }
    }
  });
}
