// 青果（KINGOSOFT）课表解析器测试。
// 样例按郑州轻工业大学「教学综合管理服务平台 → 教学安排 → 个人课表（二维表）」
// 的真实截图构造：格子行为「课程名/教师/周次[节次]/教室」，
// 左侧为上午/下午/晚上分组列 + 大节序号列（一~五，每个大节 = 2 小节）。
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:homework_radar/models/course.dart';
import 'package:homework_radar/services/timetable_parser.dart';

const _page = '''
<table>
<tr><th>星期一</th><th>星期二</th><th>星期三</th><th>星期四</th><th>星期五</th><th>星期六</th><th>星期日</th></tr>
<tr>
<td rowspan="2">上午</td><td>一</td>
<td>网络系统管理A<br>陆文静<br>1-5,8-19[1-2]<br>三教107</td>
<td>&nbsp;</td>
<td>计算机组成原理<br>胡伟华<br>1-5,8-10[1-2]<br>三教404</td>
<td>毛泽东思想概论<br>涂海燕<br>1-5,8,14双[1-2]<br>三教407<br>软件工程B<br>全雪松<br>1-5,8-15单[1-2]<br>三教407</td>
<td>画法设计与分析A<br>翁修焓<br>1-5,8-19[1-2]<br>三教109</td>
<td>&nbsp;</td><td>&nbsp;</td>
</tr>
<tr><td>二</td>
<td>软件工程A<br>宋卫卫<br>1-5,8-15[3-4]<br>三教409</td>
<td>计算机网络A<br>李世奇<br>黄连树<br>1-5,8-16[3-4]<br>二教815</td>
<td>形势与政策5<br>王淑敏<br>11-14[3-4]<br>三教103</td>
<td>&nbsp;</td>
<td>大学语文<br>边加强<br>1-5,8-10[3-4]<br>三教409</td>
<td>&nbsp;</td><td>&nbsp;</td>
</tr>
<tr>
<td rowspan="2">下午</td><td>三</td>
<td>数字图像处理导论<br>徐修如<br>1-5,8-15[5-6]<br>三教202</td>
<td>科技文献检索<br>兰张奇<br>1-5,8-10[5-6]<br>三教106</td>
<td>算法设计与分析A<br>苏牧<br>1-5,8-13双[5-6]<br>三教407<br>网络系统管理A<br>陆文静<br>1-5,8-13双[5-6]<br>三教407</td>
<td>&nbsp;</td>
<td>计算机组成原理<br>鲍军生<br>1-5,8-10[5-6]<br>三教404</td>
<td>&nbsp;</td><td>&nbsp;</td>
</tr>
<tr><td>四</td>
<td>&nbsp;</td>
<td>毛泽东思想概论<br>徐静娴<br>1-5,8,14[7-8]<br>三教405</td>
<td>&nbsp;</td><td>&nbsp;</td><td>&nbsp;</td><td>&nbsp;</td><td>&nbsp;</td>
</tr>
<tr>
<td>晚上</td><td>五</td>
<td>&nbsp;</td><td>&nbsp;</td><td>&nbsp;</td><td>&nbsp;</td><td>&nbsp;</td><td>&nbsp;</td><td>&nbsp;</td>
</tr>
</table>
''';

void main() {
  test('青果二维表：课程数量', () {
    final list = TimetableParser.parseKingosoftTable(_page);
    // 周三上午格叠了 3 门课，周日下午格叠 2 门，其余 10 个格子各 1 门
    expect(list, hasLength(15));
  });

  test('单门课：教师/教室/周次/节次', () {
    final list = TimetableParser.parseKingosoftTable(_page);
    final net = list.firstWhere((c) => c.name == '网络系统管理A' && c.weekday == 1);
    expect(net.startSection, 1);
    expect(net.endSection, 2);
    expect(net.teacher, '陆文静');
    expect(net.room, '三教107');
    // 1-5,8-19 → 1-5 全部 + 8-19
    expect(
        net.weeks, [...List.generate(5, (i) => i + 1), ...List.generate(12, (i) => i + 8)]);
  });

  test('段级单双周：1-5,8,14双 与 1-5,8-15单', () {
    final list = TimetableParser.parseKingosoftTable(_page);
    final mao = list.firstWhere(
        (c) => c.name == '毛泽东思想概论' && c.teacher == '涂海燕');
    expect(mao.weeks, [1, 2, 3, 4, 5, 8, 14]);
    expect(mao.weekday, 4);
    expect(mao.startSection, 1);

    final seB = list.firstWhere((c) => c.name == '软件工程B');
    expect(seB.weeks, [1, 2, 3, 4, 5, 9, 11, 13, 15]);
    expect(seB.teacher, '全雪松');
  });

  test('同一格子叠多门课互不串行', () {
    final list = TimetableParser.parseKingosoftTable(_page);
    // 周三上午是独立的一格
    final wedMorning =
        list.where((c) => c.weekday == 3 && c.startSection == 1).toList();
    expect(wedMorning, hasLength(1));
    expect(wedMorning.first.name, '计算机组成原理');
    expect(wedMorning.first.teacher, '胡伟华');
    // 周四上午一格叠了两门课
    final thuMorning = list
        .where((c) => c.weekday == 4 && c.startSection == 1)
        .map((c) => c.name)
        .toList();
    expect(thuMorning, hasLength(2));
    expect(thuMorning, containsAll(['毛泽东思想概论', '软件工程B']));

    final wedAfternoon = list
        .where((c) => c.weekday == 3 && c.startSection == 5)
        .toList();
    expect(wedAfternoon, hasLength(2));
    // 两门课教室教师不串（都解析各自字段）
    final algo = wedAfternoon.firstWhere((c) => c.name == '算法设计与分析A');
    expect(algo.teacher, '苏牧');
    expect(algo.room, '三教407');
    expect(algo.weeks, [1, 2, 3, 4, 5, 8, 10, 12]);
    final net2 = wedAfternoon.firstWhere((c) => c.name == '网络系统管理A');
    expect(net2.teacher, '陆文静');
  });

  test('双教师、离散周次、独立节次', () {
    final list = TimetableParser.parseKingosoftTable(_page);
    final nw = list.firstWhere((c) => c.name == '计算机网络A' && c.weekday == 2);
    expect(nw.teacher, '李世奇,黄连树');
    expect(nw.room, '二教815');
    expect(nw.weeks.length, 5 + 9); // 1-5 + 8-16

    final situation = list.firstWhere((c) => c.name == '形势与政策5');
    expect(situation.weeks, [11, 12, 13, 14]);
    expect(situation.startSection, 3);
    expect(situation.endSection, 4);

    final comp = list.firstWhere((c) => c.name == '计算机组成原理' && c.weekday == 5);
    expect(comp.startSection, 5); // 下午第一大节 = 全天第 5-6 节
    expect(comp.endSection, 6);
  });

  test('周二下午第 7-8 节课不与上午混淆', () {
    final list = TimetableParser.parseKingosoftTable(_page);
    final mao2 = list
        .where((c) => c.name == '毛泽东思想概论' && c.weekday == 2)
        .toList();
    expect(mao2, hasLength(1));
    expect(mao2.first.startSection, 7);
    expect(mao2.first.endSection, 8);
    expect(mao2.first.teacher, '徐静娴');
  });

  test('extractJs 返回值解析（Android 双层 JSON 引号）', () {
    final inner = jsonEncode({
      'table': _page,
      'xh': '542407230336',
      'week': '',
      'sem': '2026-2027学年第一学期',
    });
    final outer = jsonEncode(inner);
    final parsed = TimetableParser.parseExtracted(outer);
    expect(parsed.xh, '542407230336');
    expect(parsed.semesterText, '2026-2027学年第一学期');
    expect(parsed.courses, hasLength(15));
  });

  test('周次文本：段级单双、全局括号单双、分段周字', () {
    expect(Course.parseWeeks('1-5,8,14双'), [1, 2, 3, 4, 5, 8, 14]);
    expect(Course.parseWeeks('1-5,8-15单'), [1, 2, 3, 4, 5, 9, 11, 13, 15]);
    expect(Course.parseWeeks('1-5,8-13双'), [1, 2, 3, 4, 5, 8, 10, 12]);
    expect(Course.parseWeeks('1-16周'), List.generate(16, (i) => i + 1));
    expect(Course.parseWeeks('3-16周(单)'), [3, 5, 7, 9, 11, 13, 15]);
    expect(Course.parseWeeks('1,3-5,8周'), [1, 3, 4, 5, 8]);
    expect(Course.parseWeeks('1-8周,9-16周'), List.generate(16, (i) => i + 1));
    expect(Course.parseWeeks('没写周次'), isEmpty);
    // 纯教室号（无有效周次数字段）不该解析出周次
    expect(Course.parseWeeks('三教107'), isEmpty);
  });

  test('周次推算与 JSON 往返不受影响', () {
    final start = DateTime(2026, 8, 31); // 周一
    expect(Course.weekNumberOf(start, DateTime(2026, 9, 29)), 5);
    final c = Course(
      id: 'x',
      name: '数据结构',
      teacher: '赵六',
      room: '三教407',
      weekday: 3,
      startSection: 5,
      endSection: 6,
      weeks: [1, 2, 3, 5],
    );
    final back = Course.fromJson(c.toJson());
    expect(back.weeks, c.weeks);
    expect(back.weeksText, '1-3,5周');
  });

  test('weeksText：全单/全双且无缺口时压缩，有缺口逐段列', () {
    Course mk(List<int> weeks) => Course(
          id: 'x',
          name: '课',
          weekday: 1,
          startSection: 1,
          endSection: 2,
          weeks: weeks,
        );
    // 全单无缺口 →「1-15(单)」（旧实现会列成 1,3,5,… 长串）
    expect(mk([1, 3, 5, 7, 9, 11, 13, 15]).weeksText, '1-15(单)');
    // 全双无缺口
    expect(mk([2, 4, 6, 8, 10, 12, 14, 16]).weeksText, '2-16(双)');
    // 全单但有缺口 → 不许压成区间（会暗示中间的单周也上课）
    expect(mk([1, 3, 9, 11]).weeksText, '1,3,9,11周');
    // 普通连续区间
    expect(mk(List.generate(16, (i) => i + 1)).weeksText, '1-16周');
    // 中间断一周
    expect(mk([1, 2, 3, 4, 6, 7, 8]).weeksText, '1-4,6-8周');
    // 单周次
    expect(mk([3]).weeksText, '3周');
  });
}
