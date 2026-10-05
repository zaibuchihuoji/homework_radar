// 通用课表网格解析器测试：正方 / 强智 / URP 常见格子写法。
// 样式依据各系统公开页面格式构造；真机样本到位后应补真实回归样本。
import 'package:flutter_test/flutter_test.dart';
import 'package:homework_radar/services/timetable_parser.dart';

void main() {
  // 正方（ZFSoft）个人课表：周次行不带节次括号，行头「1,2」节次区间
  const zfPage = '''
<table>
<tr><th>节次</th><th>星期一</th><th>星期二</th><th>星期三</th><th>星期四</th><th>星期五</th></tr>
<tr><td>1,2</td>
<td>大学英语Ⅳ<br>王强<br>1-16周<br>教C-403</td>
<td>高等数学AⅠ<br>李明<br>1-16周(单)<br>教B-201</td>
<td>&nbsp;</td><td>数据结构<br>赵六<br>2-17周<br>实C-110</td><td>&nbsp;</td></tr>
<tr><td>3,4</td>
<td>&nbsp;</td>
<td>大学物理<br>钱七<br>1-16周<br>教A-101</td>
<td>体育Ⅲ<br>孙八老师<br>3-18周<br>操场</td>
<td>&nbsp;</td><td>&nbsp;</td></tr>
</table>
''';

  test('正方格式：周次行不带括号也能解析', () {
    final list = TimetableParser.parseTimetableGrid(zfPage);
    expect(list, hasLength(5));

    final eng = list.firstWhere((c) => c.name == '大学英语Ⅳ');
    expect(eng.weekday, 1);
    expect(eng.startSection, 1);
    expect(eng.endSection, 2);
    expect(eng.teacher, '王强');
    expect(eng.room, '教C-403');
    expect(eng.weeks, List.generate(16, (i) => i + 1));

    final math = list.firstWhere((c) => c.name == '高等数学AⅠ');
    expect(math.weeks, [1, 3, 5, 7, 9, 11, 13, 15]);

    final pe = list.firstWhere((c) => c.name == '体育Ⅲ');
    expect(pe.teacher, '孙八老师');
    expect(pe.room, '操场');
    expect(pe.weekday, 3);
    expect(pe.startSection, 3);
  });

  // 强智（QiangZhi）：格子「课程名/周次/教室/教师」顺序，纯数字教室
  const qzPage = '''
<table>
<tr><th>星期一</th><th>星期二</th><th>星期三</th><th>星期四</th><th>星期五</th><th>星期六</th><th>星期日</th></tr>
<tr><td>操作系统<br>1-16周<br>3106<br>张老师</td>
<td>&nbsp;</td>
<td>编译原理<br>第1-8周,11-16周<br>4208<br>李老师</td>
<td>&nbsp;</td><td>&nbsp;</td><td>&nbsp;</td><td>&nbsp;</td></tr>
</table>
''';

  test('强智格式：纯数字教室与「第1-8周,11-16周」', () {
    final list = TimetableParser.parseTimetableGrid(qzPage);
    final os = list.firstWhere((c) => c.name == '操作系统');
    expect(os.weekday, 1);
    expect(os.room, '3106');
    expect(os.teacher, '张老师');
    expect(os.weeks.length, 16);

    final compiler = list.firstWhere((c) => c.name == '编译原理');
    expect(compiler.weeks,
        [...List.generate(8, (i) => i + 1), ...List.generate(6, (i) => i + 11)]);
    expect(compiler.weekday, 3);
  });

  // URP：花括号字段格子
  const urpPage = '''
<table>
<tr><th>星期一</th><th>星期二</th><th>星期三</th><th>星期四</th><th>星期五</th><th>星期六</th><th>星期日</th></tr>
<tr><td>{大学英语IV;王一;01-16周;外语楼301}</td>
<td>&nbsp;</td><td>&nbsp;</td><td>&nbsp;</td><td>&nbsp;</td><td>&nbsp;</td><td>&nbsp;</td></tr>
</table>
''';

  test('URP 花括号格子', () {
    final list = TimetableParser.parseTimetableGrid(urpPage);
    expect(list, hasLength(1));
    final c = list.first;
    expect(c.name, '大学英语IV');
    expect(c.teacher, '王一');
    expect(c.room, '外语楼301');
    expect(c.weeks, List.generate(16, (i) => i + 1));
  });

  test('表头「周一…周日」写法', () {
    const page = '''
<table>
<tr><th>周一</th><th>周二</th><th>周三</th><th>周四</th><th>周五</th><th>周六</th><th>周日</th></tr>
<tr><td>概率论<br>王九<br>1-16周<br>教1-101</td>
<td>&nbsp;</td><td>&nbsp;</td><td>&nbsp;</td><td>&nbsp;</td><td>&nbsp;</td><td>&nbsp;</td></tr>
</table>
''';
    final list = TimetableParser.parseTimetableGrid(page);
    expect(list, hasLength(1));
    expect(list.first.weekday, 1);
    expect(list.first.room, '教1-101');
  });

  test('行头「第3-4节」区间写法', () {
    const page = '''
<table>
<tr><th>星期一</th><th>星期二</th><th>星期三</th><th>星期四</th><th>星期五</th><th>星期六</th><th>星期日</th></tr>
<tr><td>第3-4节</td><td>人工智能导论<br>1-16周<br>教2-202</td>
<td>&nbsp;</td><td>&nbsp;</td><td>&nbsp;</td><td>&nbsp;</td><td>&nbsp;</td></tr>
</table>
''';
    final list = TimetableParser.parseTimetableGrid(page);
    expect(list, hasLength(1));
    expect(list.first.startSection, 3);
    expect(list.first.endSection, 4);
    expect(list.first.weekday, 1);
  });

  test('parseWeekLine：常见周次/节次行', () {
    // 青果括号式
    final a = TimetableParser.parseWeekLine('1-5,8-19[1-2]');
    expect(a!.$1, [...List.generate(5, (i) => i + 1), ...List.generate(12, (i) => i + 8)]);
    expect(a.$2, (1, 2));
    // 正方式
    expect(TimetableParser.parseWeekLine('1-16周')!.$1.length, 16);
    expect(TimetableParser.parseWeekLine('第1-16周')!.$1.length, 16);
    expect(TimetableParser.parseWeekLine('1-16周(单)')!.$1, [1, 3, 5, 7, 9, 11, 13, 15]);
    // 段中单双（青果）：「1-5双」只作用于所在段（双 = 偶数周）
    final seg = TimetableParser.parseWeekLine('1-5双,8-16周');
    expect(seg, isNotNull, reason: '段中单双不应被周次表达式校验拒绝');
    expect(seg!.$1, [2, 4, 8, 9, 10, 11, 12, 13, 14, 15, 16]);
    // 周次+节次同行
    final b = TimetableParser.parseWeekLine('1-16周 第1-2节');
    expect(b!.$1.length, 16);
    expect(b.$2, (1, 2));
    // 纯节次行
    expect(TimetableParser.parseWeekLine('第3-4节')!.$2, (3, 4));
    // 非周次行不误判
    expect(TimetableParser.parseWeekLine('形势与政策5'), isNull);
    expect(TimetableParser.parseWeekLine('三教107'), isNull);
    expect(TimetableParser.parseWeekLine('高等数学'), isNull);
  });

  test('parseCellLines：纯节次行不改写已完结条目，而是开新条目', () {
    // 块式文本：「3-4节」出现在高数块完结（已带周次）之后，属于下一门课；
    // 旧行为会把高数错标 3-4 节、大学物理退化成兜底 1-1
    final es = TimetableParser.parseCellLines(
        '高等数学\n王一\n1-16周\n3-301\n3-4节\n大学物理\n李二\n1-16周\n5-302');
    expect(es, hasLength(2));
    expect(es[0].name, '高等数学');
    expect(es[0].start, 0, reason: '「3-4节」不应改写上一门课的节次');
    expect(es[1].name, '大学物理');
    expect(es[1].start, 3, reason: '纯节次行应作为新条目的节次');
    expect(es[1].end, 4);
    expect(es[1].room, '5-302');
  });

  test('parseCellLines：空格分隔的多教师名', () {
    // 真实青果页写法（test/fixtures/zf_kingosoft_real.html）：
    // 「李建春 黄道颖」旧正则不认，整行被静默丢弃成无教师
    final es = TimetableParser.parseCellLines(
        '计算机网络A\n李建春 黄道颖\n1-5,8-16[3-4]\n一教楼815');
    expect(es, hasLength(1));
    expect(es.first.name, '计算机网络A');
    expect(es.first.teacher, '李建春 黄道颖');

    // 教师放在块尾（条目已完结）的写法同样要认成教师
    final tail = TimetableParser.parseCellLines(
        '计算机网络A\n1-5,8-16[3-4]\n一教楼815\n李建春 黄道颖');
    expect(tail, hasLength(1));
    expect(tail.first.teacher, '李建春 黄道颖');
  });

  test('parseCellLines：完结条目后的 2-3 字短课名不被吞进教师字段', () {
    // 「体育」在大学化学块完结后出现：应开新条目，而不是追加进教师字段
    //（吞掉的话紧跟的教室行会变成幽灵课名条目）
    final es = TimetableParser.parseCellLines(
        '大学化学\n李四\n1-16周\n化楼101\n体育\n王五\n3-18周\n操场');
    expect(es, hasLength(2));
    expect(es[0].name, '大学化学');
    expect(es[0].teacher, '李四', reason: '「体育」不应被追加进上一门课的教师');
    expect(es[1].name, '体育');
    expect(es[1].teacher, '王五');
    expect(es[1].room, '操场');

    // 带后缀的教师名放在块尾（强智式）仍认教师，不受短课名判定影响
    final qz = TimetableParser.parseCellLines('操作系统\n1-16周\n3106\n张老师');
    expect(qz, hasLength(1));
    expect(qz.first.teacher, '张老师');
  });

  test('parseCellLines：混入的纯星期词不成为课名或教师', () {
    final es =
        TimetableParser.parseCellLines('星期一\n高等数学\n王一\n1-16周\n3-301');
    expect(es, hasLength(1));
    expect(es.first.name, '高等数学', reason: '「星期一」不应顶替课名');
    expect(es.first.teacher, '王一', reason: '「高等数学」不应被当成教师');
    expect(es.first.room, '3-301');

    final es2 = TimetableParser.parseCellLines('周一\n大学英语\n李四\n1-16周\n402');
    expect(es2, hasLength(1));
    expect(es2.first.name, '大学英语');
  });

  test('跨行/跨列格：rowspan 续行不错位、跨行课程不重复', () {
    // 周一连堂课 rowspan=2 占住「1,2」和「3,4」两个行带的周一列：
    // 旧实现下第二行的星期列会整体左移（物理课被当成周一、体育被当成周二）
    const page = '''
<table>
<tr><th>节次</th><th>星期一</th><th>星期二</th><th>星期三</th><th>星期四</th><th>星期五</th></tr>
<tr><td>1,2</td>
<td rowspan="2">连堂研讨<br>周老师<br>1-16周<br>教C-101</td>
<td>高等数学<br>李明<br>1-16周<br>教B-201</td>
<td>&nbsp;</td><td>&nbsp;</td><td>&nbsp;</td></tr>
<tr><td>3,4</td>
<td>大学物理<br>钱七<br>1-16周<br>教A-101</td>
<td>体育Ⅲ<br>孙八<br>3-18周<br>操场</td>
<td>&nbsp;</td><td>&nbsp;</td></tr>
</table>
''';
    final list = TimetableParser.parseTimetableGrid(page);

    final seminar = list.where((c) => c.name == '连堂研讨').toList();
    expect(seminar, hasLength(1), reason: '跨行课程只在其起始行解析一次');
    expect(seminar.first.weekday, 1);
    expect(seminar.first.startSection, 1);
    // 夹具自述该课 rowspan=2 占「1,2」+「3,4」两个行带：结束节次要延伸到
    // 第二带行头（3,4）的结束节次，断言 2 会把连堂 3-4 节的排课钉死丢失
    expect(seminar.first.endSection, 4);

    // 第二行（3,4 节）：周一列被上方跨行格占住，后续课程各归各位
    final phys = list.firstWhere((c) => c.name == '大学物理');
    expect(phys.weekday, 2, reason: '第二行不能因上一行的 rowspan 缺位而整体左移');
    expect(phys.startSection, 3);
    final pe = list.firstWhere((c) => c.name == '体育Ⅲ');
    expect(pe.weekday, 3);
    expect(pe.startSection, 3);
    expect(list.where((c) => c.name == '高等数学'), hasLength(1));
  });

  test('colspan 格占位不挤错后续列', () {
    // 表头前的「节次」列用 colspan=2（一些强智模板这么写）
    const page = '''
<table>
<tr><th colspan="2">节次</th><th>星期一</th><th>星期二</th><th>星期三</th><th>星期四</th><th>星期五</th></tr>
<tr><td colspan="2">1,2</td>
<td>大学英语<br>王强<br>1-16周<br>教C-403</td>
<td>&nbsp;</td><td>&nbsp;</td><td>&nbsp;</td><td>&nbsp;</td></tr>
</table>
''';
    final list = TimetableParser.parseTimetableGrid(page);
    expect(list, hasLength(1));
    expect(list.first.name, '大学英语');
    expect(list.first.weekday, 1);
    expect(list.first.startSection, 1);
  });

  test('rowspan 连堂：跨带行头解析不出时按每带 2 节兜底延伸', () {
    // 无行头表（强智式）：连堂实验 rowspan=2，第二带没有行头可查，
    // 结束节次按 start + 2×2 - 1 = 4 兜底，不能截成 1-2
    const page = '''
<table>
<tr><th>星期一</th><th>星期二</th><th>星期三</th><th>星期四</th><th>星期五</th></tr>
<tr><td rowspan="2">连堂实验<br>周老师<br>1-16周<br>实C-110</td>
<td>&nbsp;</td><td>&nbsp;</td><td>&nbsp;</td><td>&nbsp;</td></tr>
<tr><td>网络安全<br>钱七<br>1-16周<br>实C-111</td>
<td>&nbsp;</td><td>&nbsp;</td><td>&nbsp;</td></tr>
</table>
''';
    final list = TimetableParser.parseTimetableGrid(page);
    final lab = list.firstWhere((c) => c.name == '连堂实验');
    expect(lab.weekday, 1);
    expect(lab.startSection, 1);
    expect(lab.endSection, 4, reason: '跨带行头不可得时按 start+2n-1 延伸到第 4 节');
    // 第二行首列被上方跨行格占住：网络安全左移会错归周一
    final net = list.firstWhere((c) => c.name == '网络安全');
    expect(net.weekday, 2);
    expect(net.startSection, 3);
    expect(net.endSection, 4);
  });

  test('colspan+rowspan 复合格：下一行每列都注册跨行占位', () {
    // 复合格 colspan=2 rowspan=2 占周一、周二：只注册首列占位的话，
    // 课程D/课程E 会左移进被跨的列、归错星期
    const page = '''
<table>
<tr><th>节次</th><th>星期一</th><th>星期二</th><th>星期三</th><th>星期四</th><th>星期五</th></tr>
<tr><td>1,2</td>
<td colspan="2" rowspan="2">复合课<br>周老师<br>1-16周<br>教A-101</td>
<td>课程C<br>李明<br>1-16周<br>教B-201</td>
<td>&nbsp;</td><td>&nbsp;</td></tr>
<tr><td>3,4</td>
<td>课程D<br>钱七<br>1-16周<br>教C-301</td>
<td>课程E<br>孙八<br>1-16周<br>教D-401</td>
<td>&nbsp;</td></tr>
</table>
''';
    final list = TimetableParser.parseTimetableGrid(page);
    final courseC = list.firstWhere((c) => c.name == '课程C');
    expect(courseC.weekday, 3, reason: '第一行课程不受复合格影响');
    final courseD = list.firstWhere((c) => c.name == '课程D');
    expect(courseD.weekday, 3, reason: '课程D 不能左移进被复合格跨住的周二列');
    expect(courseD.startSection, 3);
    final courseE = list.firstWhere((c) => c.name == '课程E');
    expect(courseE.weekday, 4);
  });

  test('行头单节「第3节」「3节」不按大节号烧成 5-6 节', () {
    String mkPage(String head) => '''
<table>
<tr><th>节次</th><th>星期一</th><th>星期二</th><th>星期三</th><th>星期四</th><th>星期五</th></tr>
<tr><td>$head</td><td>单节课<br>李明<br>1-16周<br>教B-201</td>
<td>&nbsp;</td><td>&nbsp;</td><td>&nbsp;</td><td>&nbsp;</td></tr>
</table>
''';
    // 带节字的单节行头 → (3,3)
    for (final head in const ['第3节', '3节']) {
      final list = TimetableParser.parseTimetableGrid(mkPage(head));
      expect(list, hasLength(1), reason: '行头「$head」应能解析');
      expect(list.first.startSection, 3, reason: '行头「$head」起始节次应为 3');
      expect(list.first.endSection, 3, reason: '行头「$head」不应按大节号 3 烧成 5-6 节');
    }
    // 裸数字行头没有「节」字，仍按大节号 3 → 5-6 节（既有行为）
    final bigList = TimetableParser.parseTimetableGrid(mkPage('3'));
    expect(bigList, hasLength(1));
    expect(bigList.first.startSection, 5);
    expect(bigList.first.endSection, 6);
  });
}
