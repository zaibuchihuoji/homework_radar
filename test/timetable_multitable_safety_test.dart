import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:homework_radar/services/timetable_parser.dart';

String _table(String course, {String section = '1,2', String caption = ''}) =>
    '<table><caption>$caption</caption><tr><th>节次</th>'
    '<th>星期一</th><th>星期二</th><th>星期三</th>'
    '<th>星期四</th><th>星期五</th></tr><tr><td>$section</td>'
    '<td>$course<br>王一<br>1-16周<br>教A301</td>'
    '<td></td><td></td><td></td><td></td></tr></table>';

Matcher get _ambiguous => throwsA(
  isA<FormatException>().having(
    (e) => e.message,
    'ambiguity explanation',
    contains('多张'),
  ),
);

void main() {
  test('independent valid timetable tables require an explicit choice', () {
    final html = '${_table('上午课程')}${_table('下午课程', section: '5,6')}';
    expect(() => TimetableParser.parseTimetableGrid(html), _ambiguous);
  });

  test(
    'layout wrapper does not hide ambiguity between its child timetables',
    () {
      final html =
          '<table><tr><td>${_table('上午课程')}</td></tr>'
          '<tr><td>${_table('下午课程', section: '5,6')}</td></tr></table>';
      expect(() => TimetableParser.parseTimetableGrid(html), _ambiguous);
    },
  );

  test(
    'matching courses in different semesters are not assumed to be duplicates',
    () {
      final html =
          _table('同名课程', caption: '2026-2027学年第一学期') +
          _table('同名课程', caption: '2026-2027学年第二学期');
      expect(() => TimetableParser.parseTimetableGrid(html), _ambiguous);
    },
  );

  test('one actual grid inside a layout wrapper still parses normally', () {
    final html =
        '<table><tr><td>个人课表</td></tr><tr><td>'
        '${_table('唯一课程')}</td></tr></table>';
    final course = TimetableParser.parseTimetableGrid(html).single;
    expect(course.name, '唯一课程');
    expect((course.weekday, course.startSection, course.endSection), (1, 1, 2));
  });

  test(
    'extraction preserves independent candidates for ambiguity detection',
    () async {
      final first = _table('上午课程');
      final second = _table('下午课程名称更长', section: '5,6');
      final script =
          '''
const tables = [{outerHTML:${jsonEncode(first)},parentElement:null},
                {outerHTML:${jsonEncode(second)},parentElement:null}];
const document = {body:{innerText:''},querySelectorAll:s=>s==='table'?tables:[]};
console.log(${TimetableParser.extractJs});
''';
      final result = await Process.run(
        'node',
        ['-e', script],
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      );
      expect(result.exitCode, 0, reason: result.stderr.toString());
      final html =
          (jsonDecode(result.stdout.toString()) as Map)['table'] as String;
      expect(html, contains('上午课程'));
      expect(html, contains('下午课程名称更长'));
      expect(() => TimetableParser.parseTimetableGrid(html), _ambiguous);
    },
  );
}
