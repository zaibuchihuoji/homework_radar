// 文本粘贴导入解析测试：块式 / 行内式 / URP 花括号 / 无法识别星期。
import 'package:flutter_test/flutter_test.dart';
import 'package:homework_radar/services/timetable_text_parser.dart';

void main() {
  test('块式：星期行 + 每行一个字段', () {
    const text = '''
星期一
高等数学
王一
1-16周
教A-301
星期三
大学英语
李四
1-16周(双)
外语楼402
''';
    final list = TimetableTextParser.parse(text);
    expect(list, hasLength(2));

    final math = list[0];
    expect(math.name, '高等数学');
    expect(math.teacher, '王一');
    expect(math.room, '教A-301');
    expect(math.weekday, 1);
    expect(math.weeks.length, 16);

    final eng = list[1];
    expect(eng.name, '大学英语');
    expect(eng.weekday, 3);
    expect(eng.weeks, [2, 4, 6, 8, 10, 12, 14, 16]);
  });

  test('行内式：一行一门课', () {
    const text = '''
周一 1-2节 高等数学 王一 1-16周 教A-301
周三 3-4节 大学英语 李四 1-16周 402
''';
    final list = TimetableTextParser.parse(text);
    expect(list, hasLength(2));

    final math = list.firstWhere((c) => c.name == '高等数学');
    expect(math.weekday, 1);
    expect(math.startSection, 1);
    expect(math.endSection, 2);
    expect(math.teacher, '王一');
    expect(math.room, '教A-301');
    expect(math.weeks.length, 16);

    final eng = list.firstWhere((c) => c.name == '大学英语');
    expect(eng.weekday, 3);
    expect(eng.startSection, 3);
    expect(eng.endSection, 4);
  });

  test('课名/教师名以「周X」开头不被当成星期前缀吞掉', () {
    // 「周一鸣」是常见教师名：周一后面跟的是汉字，不是空白/节次/数字。
    // 旧行为会把「周一鸣」整行当成星期切换，课程条目直接丢失。
    const text = '''
周易概论
王一
1-16周
星期一
高等数学
周一鸣
1-16周
教A-301
''';
    final list = TimetableTextParser.parse(text);
    expect(list, hasLength(2));
    // 块按出现顺序结算：周易概论块（无星期）在前
    final zhouyi = list[0];
    expect(zhouyi.name, '周易概论', reason: '「周易」开头的课名不能被当成星期');
    expect(zhouyi.weekday, 0, reason: '没有星期信息，交给预览页修正');
    final math = list[1];
    expect(math.name, '高等数学');
    expect(math.teacher, '周一鸣', reason: '教师名里的「周一鸣」不能被剥成星期前缀');
    expect(math.weekday, 1);
    expect(math.weeks.length, 16);
  });

  test('同一星期多门课：第二门在周次行处切开', () {
    const text = '''
星期二
数据结构
赵六
1-8周
教B-201
操作系统
钱七
9-16周
教B-201
''';
    final list = TimetableTextParser.parse(text);
    expect(list, hasLength(2));
    expect(list[0].name, '数据结构');
    expect(list[0].weeks.length, 8);
    expect(list[1].name, '操作系统');
    expect(list[1].teacher, '钱七');
    expect(list[1].weekday, 2);
  });

  test('无星期信息：weekday 为 0，交给预览页修正', () {
    const text = '高等数学\n王一\n1-16周\n教A-301\n';
    final list = TimetableTextParser.parse(text);
    expect(list, hasLength(1));
    expect(list.first.weekday, 0);
    expect(list.first.name, '高等数学');
    expect(list.first.weeks.length, 16);
  });

  test('URP 花括号复制文本', () {
    const text = '{大学英语IV;王一;01-16周;外语楼301}\n{大学物理;李四;1-16周;教1-101}';
    final list = TimetableTextParser.parse(text);
    expect(list, hasLength(2));
    expect(list[0].name, '大学英语IV');
    expect(list[0].room, '外语楼301');
    expect(list[1].teacher, '李四');
  });

  test('同一星期第二门课省略星期前缀：无前缀行按空白分词不整行丢弃', () {
    // 旧行为把无前缀行整行当课名入块，因无周次被静默丢弃，只剩一门课
    const text = '''
周一 1-2节 高等数学 王一 1-16周 教A-301
3-4节 大学物理 王二 2-17周 5-102
''';
    final list = TimetableTextParser.parse(text);
    expect(list, hasLength(2));

    final math = list.firstWhere((c) => c.name == '高等数学');
    expect(math.weekday, 1);
    expect(math.startSection, 1);
    expect(math.endSection, 2);

    final phys = list.firstWhere((c) => c.name == '大学物理');
    expect(phys.weekday, 1, reason: '省略前缀的行沿用当前星期');
    expect(phys.teacher, '王二');
    expect(phys.startSection, 3);
    expect(phys.endSection, 4);
    expect(phys.weeks.length, 16);
    expect(phys.room, '5-102');
  });

  test('网页复制的星期表头行整行跳过，不被当成课名/教师', () {
    // 旧行为只剥掉行首「星期一」，其余星期词进块：一门叫「星期二」、
    // 教师是「星期三,星期四…」的垃圾课把整页解析带偏
    const text = '''
星期一 星期二 星期三 星期四 星期五 星期六 星期日
高等数学 王一 1-16周 教A-301
''';
    final list = TimetableTextParser.parse(text);
    expect(list, hasLength(1));
    expect(list.first.name, '高等数学');
    // 表头行跳过后没有任何星期上下文：按解析器契约 weekday=0，
    // 由预览页人工指定星期
    expect(list.first.weekday, 0);
    expect(list.first.teacher, '王一');
  });

  test('表头行夹「节次/时间/上午」等列头词也整行跳过', () {
    const text = '''
节次 时间 上午 星期一 星期二 星期三 星期四 星期五
周二 3-4节 大学英语 李四 1-16周 外语楼201
''';
    final list = TimetableTextParser.parse(text);
    expect(list, hasLength(1));
    expect(list.first.name, '大学英语');
    expect(list.first.weekday, 2);
  });

  test('学期行提取：随解析结果返回且不污染课程', () {
    const text = '''
2025-2026学年第一学期
星期一
高等数学
王一
1-16周
教A-301
''';
    final parsed = TimetableTextParser.parseWithSemester(text);
    expect(parsed.semesterText, '2025-2026学年第一学期');
    expect(parsed.courses, hasLength(1));
    expect(parsed.courses.first.name, '高等数学');
    expect(parsed.courses.first.weekday, 1);
  });

  test('学期文本夹在行中间也能扫出，剩余内容照常解析', () {
    final parsed = TimetableTextParser.parseWithSemester(
        '课表 2025-2026学年第二学期\n周一 1-2节 高等数学 王一 1-16周 教A-301\n');
    expect(parsed.semesterText, '2025-2026学年第二学期');
    expect(parsed.courses, hasLength(1));
    expect(parsed.courses.first.name, '高等数学');
  });

  test('无学期文本时 semesterText 为空串', () {
    final parsed =
        TimetableTextParser.parseWithSemester('周一 1-2节 高数 王一 1-16周');
    expect(parsed.semesterText, '');
    expect(parsed.courses, hasLength(1));
  });

  test('垃圾文本不产出条目', () {
    expect(TimetableTextParser.parse('今天天气不错'), isEmpty);
    expect(TimetableTextParser.parse(''), isEmpty);
  });
}
