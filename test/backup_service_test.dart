// 备份导出/导入往返。
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:homework_radar/models/course.dart';
import 'package:homework_radar/services/backup_service.dart';
import 'package:homework_radar/services/storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('导出 → 清空 → 导入，数据完整恢复', () async {
    SharedPreferences.setMockInitialValues({});
    await Storage.init();
    final courses = [
      Course(
        id: '数学#1#1#1,2',
        name: '数学',
        teacher: '王',
        room: '教A',
        weekday: 1,
        startSection: 1,
        endSection: 2,
        weeks: const [1, 2],
      ),
    ];
    await Storage.saveCourses(courses);
    await Storage.saveSemesterStart(DateTime(2026, 8, 31));
    await Storage.saveSectionTimes([
      for (var i = 0; i < 12; i++) (8 * 60 + i * 60, 8 * 60 + i * 60 + 45),
    ]);
    await Storage.dismiss('hw1', '{"id":"hw1"}');
    final exported = BackupService.encode();

    // 模拟新环境
    SharedPreferences.setMockInitialValues({});
    await Storage.init();
    expect(BackupService.exportMap()['courses'], isEmpty);

    final msg = await BackupService.importJson(exported);
    expect(msg, contains('课表 1 节'));
    expect(Storage.courses().single.name, '数学');
    expect(Storage.courses().single.edited, isFalse);
    expect(Storage.semesterStart(), DateTime(2026, 8, 31));
    expect(Storage.sectionTimes(), hasLength(12));
    expect(Storage.hiddenItems().keys, contains('hw1'));
  });

  test('格式不对抛 FormatException', () async {
    SharedPreferences.setMockInitialValues({});
    await Storage.init();
    expect(
      () => BackupService.importJson(jsonEncode({'app': 'other'})),
      throwsA(isA<FormatException>()),
    );
  });
}
