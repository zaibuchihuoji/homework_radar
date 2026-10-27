import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homework_radar/app_state.dart';
import 'package:homework_radar/models/course.dart';
import 'package:homework_radar/models/homework.dart';
import 'package:homework_radar/services/backup_service.dart';
import 'package:homework_radar/services/storage.dart';
import 'package:homework_radar/services/sync_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

class _Store extends InMemorySharedPreferencesStore {
  _Store() : super.empty();
  String? failKey;
  @override
  Future<bool> setValue(String type, String key, Object value) async {
    if (key == failKey) {
      failKey = null;
      return false;
    }
    return super.setValue(type, key, value);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  AndroidFlutterLocalNotificationsPlugin.registerWith();
  late AppState state;
  late SharedPreferences prefs;
  late _Store store;
  final item = HomeworkItem(
    id: 'manual_keep',
    platform: PlatformKind.manual,
    course: '数学',
    title: '原作业',
    note: '原备注',
  );
  final course = Course(
    id: 'manual_course',
    name: '数学',
    weekday: 1,
    startSection: 1,
    endSection: 2,
    weeks: [1, 2],
  );
  final opaque = {
    'id': 'unreadable',
    'title': 123,
    'name': 123,
    'opaque': [7, 8],
  };
  setUp(() async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('homework_radar/platform'),
      (_) async => null,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('home_widget'),
      (_) async => true,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('dexterous.com/flutter/local_notifications'),
      (call) async => call.method == 'pendingNotificationRequests'
          ? <Map<String, Object?>>[]
          : true,
    );
    SharedPreferences.setMockInitialValues({});
    store = _Store();
    SharedPreferencesStorePlatform.instance = store;
    await Storage.init();
    prefs = await SharedPreferences.getInstance();
    await Storage.saveClassReminder(false);
    await Storage.saveHomework([item]);
    state = AppState();
    await state.loadLocal();
  });
  tearDown(() => state.dispose());

  for (final action in ['add', 'edit', 'note', 'status', 'unhide']) {
    test(
      '$action homework preserves unreadable neighbors and unknown fields',
      () async {
        final body = {
          ...item.toJson(),
          'future': {'keep': true},
        };
        await prefs.setString('homework_json', jsonEncode([body, opaque]));
        switch (action) {
          case 'add':
            await state.addManualHomework(course: '英语', title: '新增');
          case 'edit':
            await state.updateManualHomework(item.copyWith(note: '修改备注'));
          case 'note':
            await state.updateNote(item.id, '修改备注');
          case 'status':
            await state.setHomeworkStatus(item.id, HwStatus.done);
          case 'unhide':
            final hidden = HomeworkItem(
              id: 'manual_hidden',
              platform: PlatformKind.manual,
              course: '英语',
              title: '隐藏',
            );
            await Storage.dismiss(hidden.id, jsonEncode(hidden.toJson()));
            await state.restoreHomework(hidden.id);
        }
        final rows = jsonDecode(prefs.getString('homework_json')!) as List;
        expect(rows, contains(equals(opaque)));
        expect(rows.first['future'], {'keep': true});
      },
    );
  }
  for (final action in ['add', 'edit', 'delete']) {
    test('$action course preserves unrelated raw records', () async {
      final other = Course(
        id: 'other',
        name: '英语',
        weekday: 3,
        startSection: 3,
        endSection: 4,
        weeks: [1],
      );
      final otherBody = {...other.toJson(), 'future': 'keep'};
      await prefs.setString(
        'courses_json',
        jsonEncode([course.toJson(), otherBody, opaque]),
      );
      switch (action) {
        case 'add':
          await state.addManualCourse(
            Course(
              id: 'new',
              name: '体育',
              weekday: 5,
              startSection: 1,
              endSection: 2,
              weeks: [1],
            ),
          );
        case 'edit':
          await state.updateCourse(
            course,
            Course(
              id: course.id,
              name: '新数学',
              weekday: 1,
              startSection: 1,
              endSection: 2,
              weeks: [1, 2],
            ),
          );
        case 'delete':
          await state.deleteCourse(course);
      }
      final rows = jsonDecode(prefs.getString('courses_json')!) as List;
      expect(rows, contains(equals(opaque)));
      expect(rows, contains(equals(otherBody)));
    });
  }
  test('concurrent note and status edits retain both changes', () async {
    await Future.wait([
      state.updateNote(item.id, '并发备注'),
      state.setHomeworkStatus(item.id, HwStatus.done),
    ]);
    expect(Storage.homework().single.note, '并发备注');
    expect(Storage.homework().single.status, HwStatus.done);
  });
  test('failed hide rolls back disk and restores the visible record', () async {
    store.failKey = 'flutter.dismissed_ids';
    await expectLater(state.dismissHomework(item), throwsStateError);
    await prefs.reload();
    expect(state.homework.map((h) => h.id), contains(item.id));
    expect(Storage.hiddenItems(), isEmpty);
    expect(Storage.dismissedIds(), isEmpty);
  });
  test(
    'hidden-body identity mismatch is refused without restoring another record',
    () async {
      await Storage.dismiss('manual_expected', jsonEncode(item.toJson()));
      await expectLater(
        state.restoreHomework('manual_expected'),
        throwsFormatException,
      );
      expect(Storage.hiddenItems(), contains('manual_expected'));
      expect(Storage.dismissedIds(), contains('manual_expected'));
    },
  );
  test('sync preserves unreadable local records and unknown fields', () async {
    final body = {...item.toJson(), 'future': 'keep'};
    await prefs.setString('homework_json', jsonEncode([body, opaque]));
    await SyncService.run();
    final rows = jsonDecode(prefs.getString('homework_json')!) as List;
    expect(rows, contains(equals(opaque)));
    expect(rows, contains(equals(body)));
  });
  test('backup includes raw homework and courses without silently dropping records', () async {
    final body = {...item.toJson(), 'future': 'keep'};
    await prefs.setString('homework_json', jsonEncode([body, opaque]));
    await prefs.setString(
      'courses_json',
      jsonEncode([course.toJson(), opaque]),
    );
    final exported = jsonDecode(BackupService.encode()) as Map;
    expect(exported['homework'], [body, opaque]);
    expect(exported['courses'], [course.toJson(), opaque]);
  });
  test(
    'account archiving retains every original platform body and unrelated row',
    () async {
      final platformBody = {
        ...item.toJson(),
        'id': 'cx_old',
        'platform': 'chaoxing',
        'future': 'platform keep',
      };
      final malformedPlatform = {
        ...opaque,
        'id': 'cx_bad',
        'platform': 'chaoxing',
      };
      final manualBody = {...item.toJson(), 'future': 'manual keep'};
      await prefs.setString(
        'homework_json',
        jsonEncode([platformBody, malformedPlatform, manualBody, opaque]),
      );
      await Storage.businessTransaction(
        () => Storage.archivePlatform(PlatformKind.chaoxing),
      );
      expect(jsonDecode(prefs.getString('homework_json')!), [
        manualBody,
        opaque,
      ]);
      expect(Storage.accountArchives().single['homework'], [
        platformBody,
        malformedPlatform,
      ]);
    },
  );
  test(
    'partial timetable import retains unreadable rows and existing extensions',
    () async {
      final body = {...course.toJson(), 'future': 'keep'};
      await prefs.setString('courses_json', jsonEncode([body, opaque]));
      await state.onTimetableCaptured(
        courses: [
          Course(
            id: 'new_course',
            name: '英语',
            weekday: 2,
            startSection: 3,
            endSection: 4,
            weeks: [1],
          ),
        ],
        rawPage: '',
      );
      final rows = jsonDecode(prefs.getString('courses_json')!) as List;
      expect(rows, contains(equals(body)));
      expect(rows, contains(equals(opaque)));
    },
  );
  test(
    'archiving a timetable includes unreadable rows and extensions',
    () async {
      final body = {...course.toJson(), 'future': 'keep'};
      await prefs.setString('courses_json', jsonEncode([body, opaque]));
      await Storage.businessTransaction(Storage.archiveCourses);
      expect(Storage.accountArchives().single['courses'], [body, opaque]);
    },
  );
  test(
    'backup round trip retains unknown fields in readable records',
    () async {
      final body = {...item.toJson(), 'future': 'keep'};
      final courseBody = {...course.toJson(), 'future': 'course keep'};
      await prefs.setString('homework_json', jsonEncode([body]));
      await prefs.setString('courses_json', jsonEncode([courseBody]));
      final backup = BackupService.encode();
      await BackupService.importJson(backup);
      expect(jsonDecode(prefs.getString('homework_json')!), [body]);
      expect(jsonDecode(prefs.getString('courses_json')!), [courseBody]);
    },
  );
}
