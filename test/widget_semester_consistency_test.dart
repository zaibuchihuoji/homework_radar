import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:homework_radar/models/homework.dart';
import 'package:homework_radar/services/homework_widget_snapshot.dart';
import 'package:homework_radar/services/storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HomeworkItem task(
    String id,
    DateTime? due, [
    HwStatus status = HwStatus.todo,
  ]) => HomeworkItem(
    id: id,
    platform: PlatformKind.manual,
    course: '原课程',
    title: id,
    dueAt: due,
    status: status,
    note: '原备注',
  );
  List<String> ids(Map<String, Object> snapshot) => (snapshot['items'] as List)
      .map((row) => (row as Map)['id'] as String)
      .toList();

  test(
    'screenshot regression: May 2025 cannot appear in October 2026 widget',
    () {
      final tasks = [
        task('练习5实验报告', DateTime(2025, 5, 17, 22, 30)),
        task('第五章', DateTime(2026, 10, 21, 20, 56)),
        task('本学期逾期', DateTime(2026, 10, 19, 12)),
        task('未设截止', null),
        task('下一学期', DateTime(2027, 2, 2)),
        task('已完成', DateTime(2026, 10, 18), HwStatus.done),
      ];
      final data = homeworkWidgetSnapshot(
        tasks,
        now: DateTime(2026, 10, 20, 9, 3),
      );
      expect(ids(data).toSet(), {'第五章', '本学期逾期', '未设截止'});
      expect(data['stats'], {'todo': 3, 'overdue': 1, 'done': 1, 'total': 4});
      expect(tasks.first.dueAt, DateTime(2025, 5, 17, 22, 30));
    },
  );

  test('January belongs to previous autumn; semester rolls over in February and August', () {
    final tasks = [
      task('autumn-start', DateTime(2026, 8, 1)),
      task('january', DateTime(2027, 1, 31, 23, 59)),
      task('spring-start', DateTime(2027, 2, 1)),
      task('july', DateTime(2027, 7, 31, 23, 59)),
      task('next-autumn', DateTime(2027, 8, 1)),
      task('undated', null),
    ];
    expect(
      ids(homeworkWidgetSnapshot(tasks, now: DateTime(2027, 1, 20))).toSet(),
      {'autumn-start', 'january', 'undated'},
    );
    expect(
      ids(homeworkWidgetSnapshot(tasks, now: DateTime(2027, 2, 1))).toSet(),
      {'spring-start', 'july', 'undated'},
    );
    expect(
      ids(homeworkWidgetSnapshot(tasks, now: DateTime(2027, 8, 1))).toSet(),
      {'next-autumn', 'undated'},
    );
  });

  test(
    'widget filtering preserves every original stored row and hidden body',
    () async {
      SharedPreferences.setMockInitialValues({});
      await Storage.init();
      final tasks = [
        task('old', DateTime(2025, 5, 17)),
        task('current', DateTime(2026, 10, 21)),
        task('undated', null),
      ];
      await Storage.saveHomework(tasks);
      await Storage.dismiss('old', jsonEncode(tasks.first.toJson()));
      final prefs = await SharedPreferences.getInstance();
      final before = {for (final key in prefs.getKeys()) key: prefs.get(key)};
      final rowsBefore = tasks.map((h) => h.toJson()).toList();
      expect(
        ids(homeworkWidgetSnapshot(tasks, now: DateTime(2026, 10, 20))).toSet(),
        {'current', 'undated'},
      );
      expect({for (final key in prefs.getKeys()) key: prefs.get(key)}, before);
      expect(tasks.map((h) => h.toJson()).toList(), rowsBefore);
      expect(Storage.homework(), hasLength(3));
    },
  );
}
