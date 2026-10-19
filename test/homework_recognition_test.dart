import 'package:flutter_test/flutter_test.dart';
import 'package:homework_radar/models/homework.dart';
import 'package:homework_radar/services/homework_recognition.dart';
import 'package:homework_radar/services/homework_duplicates.dart';

void main() {
  final notice = DateTime(2026, 10, 19);
  test('numbered tasks extract only explicit fields and retain source', () {
    final rows = HomeworkRecognition.parse(
      '1. 【高等数学】完成第三章第1—8题，截止2026年10月23日20:00\n'
      '2. 【大学英语】阅读第四单元，截止2026年10月24日18:30',
    );
    expect(rows, hasLength(2));
    expect(rows.first.course, '高等数学');
    expect(rows.first.title, '完成第三章第1—8题');
    expect(rows.first.dueAt, DateTime(2026, 10, 23, 20));
    expect(rows.last.dueAt, DateTime(2026, 10, 24, 18, 30));
    expect(rows.first.sourceText, contains('截止2026年10月23日20:00'));
  });
  test('course heading and continuation deadline belong to their task', () {
    final rows = HomeworkRecognition.parse(
      '课程：高等数学\n1. 完成第三章习题\n截止：2026-10-23 20:00\n'
      '2. 整理实验报告\n截止：2026-10-24 18:00',
    );
    expect(rows, hasLength(2));
    expect(rows.every((r) => r.course == '高等数学'), isTrue);
    expect(rows.first.dueAt, DateTime(2026, 10, 23, 20));
    expect(rows.last.sourceText, contains('整理实验报告'));
  });
  test('known course is matched literally, aliases are not invented', () {
    final known = HomeworkRecognition.parse(
      '大学英语 阅读第四单元',
      knownCourses: ['大学英语', '高等数学'],
    );
    expect(known.single.course, '大学英语');
    final unknown = HomeworkRecognition.parse(
      '高数第三章练习',
      knownCourses: ['高等数学'],
    );
    expect(unknown.single.course, isEmpty);
    expect(unknown.single.title, contains('高数'));
  });
  test('relative date requires an explicit notice date', () {
    final text = '【英语】完成作文，明天晚上八点前提交';
    expect(HomeworkRecognition.parse(text).single.dueAt, isNull);
    expect(
      HomeworkRecognition.parse(text, referenceDate: notice).single.dueAt,
      DateTime(2026, 10, 20, 20),
    );
  });
  test('explicit this/next week dates use notice date', () {
    expect(
      HomeworkRecognition.parse(
        '【英语】完成作文，本周五下午三点半前交',
        referenceDate: notice,
      ).single.dueAt,
      DateTime(2026, 10, 23, 15, 30),
    );
    expect(
      HomeworkRecognition.parse(
        '【英语】完成作文，下周一20:00前交',
        referenceDate: notice,
      ).single.dueAt,
      DateTime(2026, 10, 26, 20),
    );
  });
  test('bare weekday, missing time, and ambiguous am/pm stay unresolved', () {
    for (final date in ['周五晚上八点前交', '2026年10月23日前交', '2026年10月23日八点前交']) {
      final row = HomeworkRecognition.parse(
        '【数学】完成练习，$date',
        referenceDate: notice,
      ).single;
      expect(row.dueAt, isNull, reason: date);
      expect(row.warnings, isNotEmpty);
    }
  });
  test('missing year is not rolled forward or guessed', () {
    const text = '【数学】完成练习，截止10月23日20:00';
    expect(HomeworkRecognition.parse(text).single.dueAt, isNull);
    expect(
      HomeworkRecognition.parse(text, referenceDate: notice).single.dueAt,
      DateTime(2026, 10, 23, 20),
    );
    expect(
      HomeworkRecognition.parse(
        '【数学】完成练习，截止1月2日20:00',
        referenceDate: DateTime(2026, 12, 31),
      ).single.dueAt,
      isNull,
    );
  });
  test(
    'invalid dates, clocks and conflicting deadlines never normalize silently',
    () {
      for (final text in [
        '截止2026年2月30日20:00',
        '截止2026年10月23日25:00',
        '截止2026年10月23日20:75',
        '截止2026年10月23日20:00，改到2026年10月24日21:00',
        '截止2026年10月23日（周四）20:00',
        '暂定截止2026年10月23日20:00',
        '截止2026年10月23日08:00 PM',
        '截止2026年10月23日20:00:30',
        '截止下下周一20:00',
      ]) {
        expect(
          HomeworkRecognition.parse('【数学】完成练习，$text').single.dueAt,
          isNull,
          reason: text,
        );
      }
    },
  );
  test('exercise numbers and chat timestamps are not deadlines', () {
    final row = HomeworkRecognition.parse('【数学】完成第1-8题，阅读1.1到1.6节');
    expect(row.single.dueAt, isNull);
    expect(row.single.title, contains('1.1'));
    expect(HomeworkRecognition.parse('1.1至1.6节练习').single.title, '1.1至1.6节练习');
  });
  test(
    'oversized batches fail explicitly instead of silently dropping tasks',
    () {
      expect(
        () => HomeworkRecognition.parse(
          List.generate(51, (i) => '${i + 1}. 【数学】完成练习${i + 1}').join('\n'),
        ),
        throwsFormatException,
      );
    },
  );
  test('explicit past deadline is preserved, not changed to next year', () {
    expect(
      HomeworkRecognition.parse('【数学】补交练习，截止2020-01-01 08:00').single.dueAt,
      DateTime(2020, 1, 1, 8),
    );
  });
  test(
    'unrecognized text remains reviewable and is not selected by default',
    () {
      final rows = HomeworkRecognition.parse('请大家留意群消息');
      expect(rows.single.title, '请大家留意群消息');
      expect(rows.single.likelyHomework, isFalse);
      expect(rows.single.sourceText, '请大家留意群消息');
      final screenshot = HomeworkRecognition.parse('作业通知\n1. 【英语】阅读第四单元');
      expect(screenshot.first.likelyHomework, isFalse);
      expect(screenshot.last.likelyHomework, isTrue);
    },
  );
  test(
    'duplicate matching is conservative and keeps different numbered tasks',
    () {
      final old = HomeworkItem(
        id: 'old',
        platform: PlatformKind.manual,
        course: '高等数学',
        title: '第三章 · 练习',
      );
      expect(HomeworkDuplicates.matches('高等数学', '第三章练习', old), isTrue);
      expect(HomeworkDuplicates.matches('', '第三章练习', old), isTrue);
      expect(HomeworkDuplicates.matches('大学英语', '第三章练习', old), isFalse);
      expect(HomeworkDuplicates.matches('高等数学', '第三章练习1', old), isFalse);
    },
  );
}
