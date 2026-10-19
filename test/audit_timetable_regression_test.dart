import 'dart:convert';
import 'dart:io';

import 'package:excel/excel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homework_radar/models/course.dart';
import 'package:homework_radar/app_state.dart';
import 'package:homework_radar/pages/course_edit_sheet.dart';
import 'package:homework_radar/pages/jw_preview_page.dart';
import 'package:homework_radar/pages/section_times_page.dart';
import 'package:homework_radar/services/storage.dart';
import 'package:homework_radar/services/timetable_ocr.dart';
import 'package:homework_radar/services/timetable_parser.dart';
import 'package:homework_radar/services/timetable_text_parser.dart';
import 'package:homework_radar/services/timetable_xls_parser.dart';
import 'package:homework_radar/ui/tokens.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _days = ['星期一', '星期二', '星期三', '星期四', '星期五'];
String _grid(String head, {List<String> days = _days}) =>
    '<table><tr>'
    '<th>节次</th>${days.map((d) => '<th>$d</th>').join()}'
    '</tr><tr><td>$head</td><td>高等数学<br>王一<br>1-16周<br>教A301</td>'
    '${List.filled(days.length - 1, '<td></td>').join()}</tr></table>';
OcrBlock _block(String text, double x, double y, {double width = 60}) =>
    OcrBlock(
      text: text,
      left: x - width / 2,
      top: y - 9,
      width: width,
      height: 18,
    );
List<OcrBlock> _headers({int count = 7}) => [
  for (var d = 0; d < count; d++)
    _block('星期${'一二三四五六日'[d]}', 120.0 + d * 120, 40),
];
List<OcrBlock> _ruler() => [
  for (var n = 1; n <= 4; n++)
    _block('$n', 40, 100.0 + (n - 1) * 100, width: 20),
];

void main() {
  test('weekday labels determine the day even when Sunday is first', () {
    final c = TimetableParser.parseTimetableGrid(
      _grid('1,2', days: ['星期日', ..._days, '星期六']),
    ).single;
    expect(c.weekday, 7);
  });
  test('range section labels without 第 retain their actual time', () {
    final c = TimetableParser.parseTimetableGrid(_grid('5-6节')).single;
    expect((c.startSection, c.endSection), (5, 6));
  });
  test(
    'ordinary teacher after weeks does not replace the next course name',
    () {
      final cs = TimetableParser.parseCellLines(
        '高等数学\n1-8周\n教A301\n李明\n'
        '大学英语\n9-16周\n教B302\n王五',
      );
      expect(cs.map((c) => c.name), ['高等数学', '大学英语']);
      expect(cs.map((c) => c.teacher), ['李明', '王五']);
    },
  );
  test('block text retains multiword course names', () {
    final c = TimetableTextParser.parse(
      '星期一\nCollege English\n王一\n'
      '1-16周 第1-2节\n教A301',
    ).single;
    expect(c.name, 'College English');
    expect((c.startSection, c.endSection), (1, 2));
  });
  test('inline prefix retains combined week and section fields', () {
    final c = TimetableTextParser.parse('周一 高等数学 王一 1-16周 第3-4节 教A301').single;
    expect((c.startSection, c.endSection), (3, 4));
    expect(c.room, '教A301');
  });
  test('invalid single sections are not trusted for import', () {
    final cs = TimetableTextParser.parse('周一 第99节 高等数学 王一 1-16周 教A301');
    expect(
      cs.every(
        (c) =>
            c.sectionsProvisional ||
            (c.startSection >= 1 && c.endSection <= 16),
      ),
      isTrue,
    );
  });
  test('weeks reject zero and retain common odd-week qualifiers', () {
    expect(Course.parseWeeks('0'), isEmpty);
    expect(Course.parseWeeks('1-16周(单周)'), [1, 3, 5, 7, 9, 11, 13, 15]);
  });
  test('xlsx merged rows retain the whole continuous class', () {
    final x = Excel.createExcel();
    final s = x['课表'];
    for (final row in [
      ['节次', ..._days],
      ['第1节', '连堂课\n王一\n1-16周\n教A301', '', '', '', ''],
      ['第2节', '', '', '', '', ''],
    ]) {
      s.appendRow([for (final v in row) TextCellValue(v)]);
    }
    s.merge(CellIndex.indexByString('B2'), CellIndex.indexByString('B3'));
    final c = TimetableXlsParser.parse(x.encode()!).single;
    expect((c.startSection, c.endSection), (1, 2));
  });
  test('SpreadsheetML merged rows retain the whole continuous class', () {
    final xml =
        '<?xml version="1.0"?><Workbook><Worksheet><Table>'
        '<Row>${['节次', ..._days].map((d) => '<Cell><Data>$d</Data></Cell>').join()}</Row>'
        '<Row><Cell><Data>第1节</Data></Cell><Cell ss:MergeDown="1">'
        '<Data>连堂课&#10;王一&#10;1-16周&#10;教A301</Data></Cell></Row>'
        '<Row><Cell><Data>第2节</Data></Cell></Row></Table></Worksheet></Workbook>';
    final c = TimetableXlsParser.parse(utf8.encode(xml)).single;
    expect((c.startSection, c.endSection), (1, 2));
  });
  test('quoted tabs in CSV fields do not change its delimiter', () {
    final csv = '${_days.join(',')}\n"高等数学\n王一\t李二\n1-16周\n教A301",,,,\n';
    final c = TimetableXlsParser.parse(utf8.encode(csv)).single;
    expect(c.name, '高等数学');
    expect(c.teacher, contains('李二'));
  });
  test('OCR guesses without a ruler require time correction', () {
    final c = TimetableOcrParser.parse([
      ..._headers(),
      _block('下午课程', 120, 300),
      _block('王一', 120, 320),
      _block('1-16周', 120, 340),
    ]).single;
    expect(c.sectionsProvisional, isTrue);
  });
  test('OCR reconstructs a missing trailing weekday anchor', () {
    final cs = TimetableOcrParser.parse([
      ..._headers(count: 6),
      ..._ruler(),
      _block('周一课程', 120, 100),
      _block('1-16周', 120, 120),
      _block('周日课程', 840, 100),
      _block('1-16周', 840, 120),
    ]);
    expect(cs.map((c) => c.weekday), containsAll([1, 7]));
  });
  test('OCR reconstructs multiple missing leading weekday anchors', () {
    final cs = TimetableOcrParser.parse([
      ..._headers().skip(2).take(4),
      ..._ruler(),
      _block('周一课程', 120, 100),
      _block('1-16周', 120, 120),
      _block('周三课程', 360, 100),
      _block('1-16周', 360, 120),
    ]);
    expect(cs.map((c) => c.weekday), containsAll([1, 3]));
  });
  test('extract JS only calibrates an explicitly current week', () async {
    final js = '''const document = {body:{innerText:'公告：第1周教学检查通知\\n当前第7周'},
      querySelectorAll:(s)=>[]}; console.log(${TimetableParser.extractJs});''';
    final p = await Process.run('node', ['-e', js]);
    expect(p.exitCode, 0, reason: p.stderr.toString());
    expect((jsonDecode(p.stdout.toString()) as Map)['week'], '7');
  });
  testWidgets('preview cannot select a course without weeks', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          extensions: [stylePalette(ThemeStyle.clean, Brightness.light)],
        ),
        home: JwPreviewPage(
          courses: [
            Course(
              id: 'x',
              name: '缺周次',
              weekday: 1,
              startSection: 1,
              endSection: 2,
              weeks: [],
            ),
          ],
          sourceLabel: '测试',
        ),
      ),
    );
    expect(
      tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).onChanged,
      isNull,
    );
  });
  testWidgets(
    'out-of-range imported course can be opened for explicit correction',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            extensions: [stylePalette(ThemeStyle.clean, Brightness.light)],
          ),
          home: Scaffold(
            body: CourseEditSheet(
              course: Course(
                id: 'bad',
                name: '坏节次',
                weekday: 1,
                startSection: 99,
                endSection: 99,
                weeks: [1],
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
    },
  );
  testWidgets('preview refuses out-of-range sections before import', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          extensions: [stylePalette(ThemeStyle.clean, Brightness.light)],
        ),
        home: JwPreviewPage(
          courses: [
            Course(
              id: 'bad',
              name: '坏节次',
              weekday: 1,
              startSection: 99,
              endSection: 99,
              weeks: [1],
            ),
          ],
          sourceLabel: '测试',
        ),
      ),
    );
    final tile = tester.widget<CheckboxListTile>(find.byType(CheckboxListTile));
    expect(tile.value, isFalse);
    expect(tile.onChanged, isNull);
  });
  testWidgets(
    'end-of-day section opens a valid time picker instead of hour 24',
    (tester) async {
      await tester.runAsync(() async {
        SharedPreferences.setMockInitialValues({
          'section_times': jsonEncode([
            for (final t in Course.sectionTimes.take(11)) [t.$1, t.$2],
            [1395, 1440],
          ]),
        });
        await Storage.init();
      });
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            extensions: [stylePalette(ThemeStyle.clean, Brightness.light)],
          ),
          home: SectionTimesPage(state: AppState()),
        ),
      );
      await tester.scrollUntilVisible(
        find.text('24:00'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('24:00'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        tester
            .widget<TimePickerDialog>(find.byType(TimePickerDialog))
            .initialTime
            .hour,
        inInclusiveRange(0, 23),
      );
    },
  );
}
