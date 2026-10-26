import 'package:flutter_test/flutter_test.dart';
import 'package:homework_radar/services/timetable_ocr.dart';

OcrBlock atom(String text, double x, double y, {double width = 60}) => OcrBlock(
  text: text,
  left: x - width / 2,
  top: y - 9,
  width: width,
  height: 18,
);

List<OcrBlock> axis({int rows = 12, bool shortDays = false}) => [
  for (var day = 0; day < 7; day++)
    atom('${shortDays ? '周' : '星期'}${'一二三四五六日'[day]}', 120.0 + day * 120, 40),
  for (var n = 1; n <= rows; n++) atom('$n', 40, n * 100.0, width: 20),
];

List<OcrBlock> course(String name, double y) => [
  atom(name, 120, y),
  atom('王一', 120, y + 20),
  atom('1-16周', 120, y + 40),
];

void main() {
  test('a single-section 1-12 axis preserves the third and tenth periods', () {
    final result = TimetableOcrParser.parse([
      ...axis(),
      ...course('高等数学', 300),
      ...course('晚间课程', 1000),
    ]);
    expect(result.map((c) => c.name), containsAll(['高等数学', '晚间课程']));
    final third = result.firstWhere((c) => c.name == '高等数学');
    final tenth = result.firstWhere((c) => c.name == '晚间课程');
    expect((third.startSection, third.endSection), (3, 3));
    expect((tenth.startSection, tenth.endSection), (10, 10));
    expect(third.sectionsProvisional, isFalse);
  });

  test(
    'bare short axes stay uncertain instead of silently doubling periods',
    () {
      final result = TimetableOcrParser.parse([
        ...axis(rows: 4),
        ...course('高等数学', 300),
      ]);
      expect(result.single.sectionsProvisional, isTrue);
    },
  );

  test('explicit interpretation resolves short axes without another OCR', () {
    final blocks = [...axis(rows: 4), ...course('高等数学', 300)];
    final single = TimetableOcrParser.parse(
      blocks,
      sectionMode: OcrSectionMode.single,
    ).single;
    final paired = TimetableOcrParser.parse(
      blocks,
      sectionMode: OcrSectionMode.paired,
    ).single;
    expect((single.startSection, single.endSection), (3, 3));
    expect((paired.startSection, paired.endSection), (5, 6));
    expect(single.sectionsProvisional, isFalse);
    expect(paired.sectionsProvisional, isFalse);
  });

  test('explicit ranges retain contiguous course spans', () {
    final blocks = [
      for (var d = 0; d < 7; d++) atom('周${'一二三四五六日'[d]}', 120.0 + d * 120, 40),
      atom('1-2节', 40, 100, width: 20),
      atom('3-4节', 40, 200, width: 20),
      atom('连堂课程', 120, 100),
      atom('王一', 120, 130),
      atom('1-16周', 120, 160),
      atom('A301', 120, 190),
    ];
    final result = TimetableOcrParser.parse(blocks).single;
    expect((result.startSection, result.endSection), (1, 4));
    expect(result.sectionsProvisional, isFalse);
  });

  test('short weekday headers preserve the course column', () {
    final result = TimetableOcrParser.parse([
      ...axis(shortDays: true),
      ...course('高等数学', 300),
    ]);
    expect(result.single.weekday, 1);
  });

  test('courses below an incomplete axis remain reviewable', () {
    final result = TimetableOcrParser.parse([
      ...axis(rows: 2),
      ...course('未定位课程', 1000),
    ]);
    expect(result.map((c) => c.name), contains('未定位课程'));
    expect(
      result.firstWhere((c) => c.name == '未定位课程').sectionsProvisional,
      isTrue,
    );
  });
}
