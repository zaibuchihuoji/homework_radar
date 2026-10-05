// 截图 OCR 布局重建测试：喂坐标块（模拟 ML Kit 行级结果），不依赖真机。
import 'package:flutter_test/flutter_test.dart';
import 'package:homework_radar/services/timetable_ocr.dart';

OcrBlock blk(String text, double cx, double cy, {double w = 60, double h = 18}) =>
    OcrBlock(text: text, left: cx - w / 2, top: cy - h / 2, width: w, height: h);

/// 7 列表头 + 表尺 1..4（表尺 y=100,200,300,400，行带间距 100）。
List<OcrBlock> grid() => [
      for (var d = 0; d < 7; d++) blk('星期${'一二三四五六日'[d]}', 120.0 + d * 120, 40),
      for (var n = 1; n <= 4; n++) blk('$n', 40, 100.0 + (n - 1) * 100, w: 20),
    ];

void main() {
  // 7 列课表：列锚点 x = 120, 240, ..., 840；表尺在 x = 40
  test('网格截图：表头分列 + 表尺定节次 + 单元格聚类', () {
    final blocks = [
      ...grid(),
      // 周一第 1 节格子（3 行文本，行距 20 < 阈值 → 同格）
      blk('高等数学', 120, 100),
      blk('王一', 120, 120),
      blk('1-16周', 120, 140),
      blk('教A-301', 120, 160),
      // 周三另一格（y 远 → 新格）
      blk('大学英语', 360, 100),
      blk('李四', 360, 120),
      blk('2-8周', 360, 140),
      // 时间轴文本（应被剔除）
      blk('08:00', 40, 90, w: 40),
    ];

    final list = TimetableOcrParser.parse(blocks);
    expect(list, hasLength(2));

    final math = list.firstWhere((c) => c.name == '高等数学');
    expect(math.weekday, 1);
    expect(math.teacher, '王一');
    expect(math.room, '教A-301');
    expect(math.weeks.length, 16);
    // 表尺 y=100 → 第 1 行 → 大节 1 → 第 1-2 节
    expect(math.startSection, 1);
    expect(math.endSection, 2);

    final eng = list.firstWhere((c) => c.name == '大学英语');
    expect(eng.weekday, 3);
    expect(eng.weeks, [2, 3, 4, 5, 6, 7, 8]);
    expect(eng.startSection, 1);
  });

  test('同列相邻两格不并组：带1/带2 各自成组、各自节次', () {
    final blocks = [
      ...grid(),
      // 周一列上下两格：格 A 文字落在带 1（y 100~160，格底行与带 2
      // 等距、按行带滞后仍归带 1），格 B 落在带 2
      blk('高等数学', 120, 100),
      blk('王一', 120, 120),
      blk('1-16周', 120, 140),
      blk('教A-301', 120, 160),
      blk('大学英语', 120, 200),
      blk('李四', 120, 220),
      blk('2-8周', 120, 240),
    ];
    final list = TimetableOcrParser.parse(blocks);
    expect(list, hasLength(2), reason: '同列相邻两格此前必然并成一组');

    final math = list.firstWhere((c) => c.name == '高等数学');
    expect(math.weekday, 1);
    expect(math.teacher, '王一');
    expect(math.room, '教A-301');
    expect(math.weeks.length, 16);
    expect(math.startSection, 1);
    expect(math.endSection, 2);

    final eng = list.firstWhere((c) => c.name == '大学英语');
    expect(eng.weekday, 1);
    expect(eng.teacher, '李四');
    expect(eng.weeks, [2, 3, 4, 5, 6, 7, 8]);
    expect(eng.startSection, 3);
    expect(eng.endSection, 4);
  });

  test('rowspan 连堂：跨两个行带的组写 首带起始~末带结束（1-4 节）', () {
    final blocks = [
      ...grid(),
      // 一个连堂格跨带 1-2：文字行距 30 < 半个行带（35），组不切断
      blk('数据结构', 120, 100),
      blk('王五', 120, 130),
      blk('1-16周', 120, 160),
      blk('教B-201', 120, 190),
    ];
    final list = TimetableOcrParser.parse(blocks);
    expect(list, hasLength(1));
    final c = list.single;
    expect(c.name, '数据结构');
    expect(c.teacher, '王五');
    expect(c.room, '教B-201');
    expect(c.weeks.length, 16);
    // 组内行带 {1,2} → 节次 1~4，而不是组中心最近带的单带 2 节
    expect(c.startSection, 1);
    expect(c.endSection, 4);
  });

  test('无表尺 9 组：节次兜底钳回 1..16 不越界', () {
    final blocks = [
      for (var d = 0; d < 7; d++) blk('星期${'一二三四五六日'[d]}', 120.0 + d * 120, 40),
      // 无表尺块：周一列 9 个单行格，行距 40 > 聚格阈值 → 9 组
      for (var i = 1; i <= 9; i++) blk('课程$i', 120, 100.0 + (i - 1) * 40),
    ];
    final list = TimetableOcrParser.parse(blocks);
    expect(list, hasLength(9));
    for (final c in list) {
      expect(c.startSection, inInclusiveRange(1, 16), reason: '${c.name} 越界');
      expect(c.endSection, inInclusiveRange(c.startSection, 16),
          reason: '${c.name} 越界');
    }
    // 第 9 组此前按 gi*2+1 算出 17-18 流出解析器
    final last = list.firstWhere((c) => c.name == '课程9');
    expect(last.startSection, 16);
    expect(last.endSection, 16);
    final first = list.firstWhere((c) => c.name == '课程1');
    expect(first.startSection, 1);
    expect(first.endSection, 2);
  });

  test('pitch 稳健：漏 2 个分散表头出现 2× 差值时列距不翻倍', () {
    // 漏识别星期三、星期五：相邻锚点差 = [p, 2p, 2p, p]，
    // 旧实现取排序后上中位恰得 2p → pitch 翻倍、表尺列被误排除
    final blocks = [
      blk('星期一', 120, 40),
      blk('星期二', 240, 40),
      blk('星期四', 480, 40),
      blk('星期六', 720, 40),
      blk('星期日', 840, 40),
      for (var n = 1; n <= 4; n++) blk('$n', 40, 100.0 + (n - 1) * 100, w: 20),
      // 周四列（锚点 x=480）一格，靠表尺定在带 3 → 5-6 节；
      // pitch 翻倍时表尺列被误排除、退化成组序号兜底 → 错成 1-2 节
      blk('操作系统', 480, 300),
      blk('赵六', 480, 320),
      blk('1-16周', 480, 340),
    ];
    final list = TimetableOcrParser.parse(blocks);
    expect(list, hasLength(1));
    final c = list.single;
    expect(c.weekday, 4, reason: '中间缺列应按天序插值补齐');
    expect(c.name, '操作系统');
    expect(c.startSection, 5, reason: 'pitch 被翻倍时表尺列被误排除、节次错成 1-2');
    expect(c.endSection, 6);
  });

  test('表头退化（无网格）：无周次条目也不丢', () {
    final blocks = [
      blk('高等数学', 100, 100),
      blk('教A-301', 100, 118),
    ];
    final list = TimetableOcrParser.parse(blocks);
    expect(list, hasLength(1), reason: '无周次条目此前被 _parseNoGrid 整条过滤');
    expect(list.single.name, '高等数学');
    expect(list.single.weekday, 0);
    expect(list.single.weeks, isEmpty);
    expect(list.single.room, '教A-301');
  });

  test('识别不到表头：全部落到未定列（weekday 0）', () {
    final blocks = [
      blk('高等数学', 100, 100),
      blk('1-16周', 100, 130),
    ];
    final list = TimetableOcrParser.parse(blocks);
    expect(list, hasLength(1));
    expect(list.first.weekday, 0);
    expect(list.first.name, '高等数学');
  });

  test('垃圾块不产出条目', () {
    expect(TimetableOcrParser.parse(const []), isEmpty);
    final list = TimetableOcrParser.parse([
      for (var d = 0; d < 7; d++) blk('星期${'一二三四五六日'[d]}', 120.0 + d * 120, 40),
      blk('第5周', 200, 300),
    ]);
    expect(list, isEmpty);
  });
}
