import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:homework_radar/models/course.dart';
import 'package:homework_radar/services/class_reminder_plan.dart';
import 'package:homework_radar/services/storage.dart';
import 'package:homework_radar/services/backup_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Course course({int section = 1, List<int> weeks = const [1]}) => Course(
    id: 'c1',
    name: '数学',
    room: 'A302',
    weekday: 1,
    startSection: section,
    endSection: section,
    weeks: weeks,
  );
  final monday = DateTime(2026, 10, 26);
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Storage.init();
  });

  test(
    'legacy switch retained and new lead defaults to 30 without rewriting data',
    () async {
      await Storage.saveClassReminder(false);
      await Storage.saveCourses([course()]);
      final before = jsonEncode(
        Storage.courses().map((c) => c.toJson()).toList(),
      );
      expect(Storage.classReminderMinutes(), 30);
      await Storage.saveClassReminderMinutes(45);
      expect(Storage.classReminder(), false);
      expect(Storage.classReminderMinutes(), 45);
      expect(
        jsonEncode(Storage.courses().map((c) => c.toJson()).toList()),
        before,
      );
      await expectLater(
        Storage.saveClassReminderMinutes(0),
        throwsArgumentError,
      );
      await expectLater(
        Storage.saveClassReminderMinutes(181),
        throwsArgumentError,
      );
    },
  );

  test(
    'real weekdays weeks custom slots and configurable lead determine alarms',
    () {
      final plan = ClassReminderPlan.build(
        courses: [course()],
        semesterStart: monday,
        now: monday,
        enabled: true,
        minutes: 30,
        slots: [(480, 525)],
      );
      expect(plan.entries, hasLength(1));
      expect(plan.entries.single.fire, DateTime(2026, 10, 26, 7, 30));
      expect(plan.entries.single.lesson, DateTime(2026, 10, 26, 8));
      expect(
        ClassReminderTarget.parse(plan.entries.single.payload)?.courseId,
        'c1',
      );
      final moved = ClassReminderPlan.build(
        courses: [
          course(weeks: [2]),
        ],
        semesterStart: monday,
        now: monday,
        enabled: true,
        minutes: 45,
        slots: [(540, 585)],
      );
      expect(moved.entries.single.fire, DateTime(2026, 11, 2, 8, 15));
    },
  );

  test(
    'missing semester or unknown slots are reported instead of invented',
    () {
      final noSemester = ClassReminderPlan.build(
        courses: [course()],
        semesterStart: null,
        now: monday,
        enabled: true,
        minutes: 30,
        slots: [(480, 525)],
      );
      expect(noSemester.entries, isEmpty);
      expect(noSemester.issue, contains('开学日期'));
      final unknown = ClassReminderPlan.build(
        courses: [course(section: 13)],
        semesterStart: monday,
        now: monday,
        enabled: true,
        minutes: 30,
        slots: Course.sectionTimes,
      );
      expect(unknown.entries, isEmpty);
      expect(unknown.issue, contains('作息'));
    },
  );

  test('passed trigger remains identifiable until class starts for pending preservation', () {
    final plan = ClassReminderPlan.build(
      courses: [course()],
      semesterStart: monday,
      now: DateTime(2026, 10, 26, 7, 40),
      enabled: true,
      minutes: 30,
      slots: [(480, 525)],
    );
    expect(
      plan.entries.single.fire.isBefore(DateTime(2026, 10, 26, 7, 40)),
      true,
    );
    final ended = ClassReminderPlan.build(
      courses: [course()],
      semesterStart: monday,
      now: DateTime(2026, 10, 26, 8),
      enabled: true,
      minutes: 30,
      slots: [(480, 525)],
    );
    expect(ended.entries, isEmpty);
  });

  test('backup lead is optional and malformed lead cannot partially overwrite data', () async {
    await Storage.saveClassReminderMinutes(45);
    final backup = BackupService.exportMap();
    expect(backup['settings']['classReminderMinutes'], 45);
    await Storage.saveClassReminderMinutes(10);
    await BackupService.importJson(jsonEncode(backup));
    expect(Storage.classReminderMinutes(), 45);
    (backup['settings'] as Map).remove('classReminderMinutes');
    await BackupService.importJson(jsonEncode(backup));
    expect(Storage.classReminderMinutes(), 45);
    await Storage.saveCourses([course()]);
    backup['settings']['classReminderMinutes'] = 1.5;
    await expectLater(
      BackupService.importJson(jsonEncode(backup)),
      throwsFormatException,
    );
    expect(Storage.courses().single.id, 'c1');
  });
}
