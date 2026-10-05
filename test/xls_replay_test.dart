import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:homework_radar/services/timetable_xls_parser.dart';

void main() {
  test('openpyxl 生成的 xlsx 回放', () {
    final bytes =
        File('test/fixture_openpyxl.xlsx').readAsBytesSync();
    final courses = TimetableXlsParser.parse(bytes);
    expect(courses, isNotEmpty, reason: 'openpyxl 兼容性回放应至少解析出课程');
    for (final c in courses) {
      expect(c.name, isNotEmpty);
      expect(c.weekday, inInclusiveRange(1, 7));
      expect(c.startSection, inInclusiveRange(1, 12));
      expect(c.endSection, inInclusiveRange(c.startSection, 12));
      expect(c.weeks, isNotEmpty);
    }
  });
}
