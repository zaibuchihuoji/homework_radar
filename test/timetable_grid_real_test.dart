// 真实抓取页回归：郑州轻工业大学金智青果实拍页（rowspan 组列 + colspan 表头）。
// 曾因行尾补齐 bug 把 rowspan 开头行撑宽到 40 列导致整行丢失（上午/下午课全没）。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:homework_radar/models/course.dart';
import 'package:homework_radar/services/timetable_parser.dart';

void main() {
  test('真实青果页：rowspan 开头行的上午/下午课程不丢', () {
    final raw = File('test/fixtures/zf_kingosoft_real.html').readAsStringSync();
    final list = TimetableParser.parseTimetableGrid(raw);

    Course first(String name, int wd) =>
        list.firstWhere((c) => c.name == name && c.weekday == wd);

    // row1（上午 1-2 节）——曾整行丢失
    final netA = first('网络系统管理A', 1);
    expect(netA.startSection, 1);
    expect(netA.endSection, 2);
    expect(netA.weeks,
        [...List.generate(5, (i) => i + 1), ...List.generate(6, (i) => i + 8)]);
    expect(first('计算机组成原理', 3).startSection, 1);
    final mao = first('毛泽东思想和中国特色社会主义理论体系概论', 4);
    expect(mao.startSection, 1);
    // 同格双课（周四 1-2 节：毛概 + 单周软件工程A）
    final thu = list.where((c) => c.weekday == 4 && c.startSection == 1).toList();
    expect(thu.map((c) => c.name),
        containsAll(['毛泽东思想和中国特色社会主义理论体系概论', '软件工程A']));

    // row3（下午 5-6 节）——曾整行丢失
    final dig = first('数字图像处理导论', 1);
    expect(dig.startSection, 5);
    expect(dig.endSection, 6);
    expect(first('科技文献检索', 2).startSection, 5);
    // 同格双课（周三 5-6 节：双周算法 + 单周网A）
    final wed = list.where((c) => c.weekday == 3 && c.startSection == 5).toList();
    expect(wed, hasLength(2));

    // row2/row4 原本就能解出的课不受影响
    expect(first('软件工程A', 1).startSection, 3);
    expect(first('毛泽东思想和中国特色社会主义理论体系概论', 2).startSection, 7);
  });
}
