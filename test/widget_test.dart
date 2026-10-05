import 'package:flutter_test/flutter_test.dart';

import 'package:homework_radar/models/homework.dart';

void main() {
  test('HomeworkItem 序列化/反序列化', () {
    final hw = HomeworkItem(
      id: 'cx_1_2_3',
      platform: PlatformKind.chaoxing,
      course: '高等数学',
      title: '第三章作业',
      dueAt: DateTime(2026, 10, 1, 23, 59),
      status: HwStatus.todo,
    );
    final json = hw.toJson();
    final back = HomeworkItem.fromJson(json);
    expect(back.id, hw.id);
    expect(back.platform, PlatformKind.chaoxing);
    expect(back.course, '高等数学');
    expect(back.title, '第三章作业');
    expect(back.dueAt, DateTime(2026, 10, 1, 23, 59));
    expect(back.status, HwStatus.todo);
  });

  test('urgency 排序权重：越接近截止越紧急', () {
    final soon = HomeworkItem(
      id: 'a',
      platform: PlatformKind.mooc,
      course: 'c',
      title: 't',
      dueAt: DateTime.now().add(const Duration(hours: 2)),
    );
    final later = HomeworkItem(
      id: 'b',
      platform: PlatformKind.mooc,
      course: 'c',
      title: 't',
      dueAt: DateTime.now().add(const Duration(hours: 100)),
    );
    expect(soon.urgency, greaterThan(later.urgency));
  });
}
