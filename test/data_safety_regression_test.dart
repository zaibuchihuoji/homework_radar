import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:homework_radar/app_state.dart';
import 'package:homework_radar/models/homework.dart';
import 'package:homework_radar/models/course.dart';
import 'package:homework_radar/services/storage.dart';
import 'package:homework_radar/services/sync_service.dart';
import 'package:homework_radar/services/backup_service.dart';
import 'package:homework_radar/services/secure_store.dart';
import 'package:homework_radar/services/safe_http.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  AndroidFlutterLocalNotificationsPlugin.registerWith();
  final secrets = <String, String>{};
  bool failWrite = false, failDelete = false;
  setUp(() async {
    failWrite = false;
    failDelete = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('homework_radar/platform'),
          (call) async {
            final a = call.arguments as Map?;
            if (call.method == 'secureRead') return secrets[a?['key']];
            if (call.method == 'secureWrite') {
              if (failWrite) throw PlatformException(code: 'disk');
              secrets[a?['key']] = a?['value'];
            }
            if (call.method == 'secureDelete') {
              if (failDelete) throw PlatformException(code: 'disk');
              secrets.remove(a?['key']);
            }
            return true;
          },
        );
    for (final key in [
      'cx_cookie',
      'cx_uid',
      'mooc_cookie',
      'mooc_csrf',
      'zhs_cookie',
      'xtx_cookie',
      'ykt_cookie',
      'zf_cookie',
    ]) {
      await SecureStore.delete(key);
    }
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('dexterous.com/flutter/local_notifications'),
          (call) async => true,
        );
    SharedPreferences.setMockInitialValues({});
    await Storage.init();
  });
  HomeworkItem hw(String id) => HomeworkItem(
    id: id,
    platform: PlatformKind.chaoxing,
    course: 'course',
    title: id,
    note: 'user note',
  );
  test('D01 logout while sync reintroduces deleted platform items', () async {
    await Storage.saveHomework([hw('cx_old')]);
    final state = AppState();
    await state.loadLocal();
    final pending = SyncService.run();
    await state.logoutChaoxing();
    await pending;
    expect(Storage.homework().map((h) => h.id), isNot(contains('cx_old')));
  });
  test('D02 restore while sync loses restored platform body', () async {
    await Storage.dismiss('cx_hidden', jsonEncode(hw('cx_hidden').toJson()));
    final state = AppState();
    await state.loadLocal();
    final pending = SyncService.run();
    await state.restoreHomework('cx_hidden');
    await pending;
    expect(Storage.hiddenItems(), isEmpty);
    expect(Storage.homework().map((h) => h.id), contains('cx_hidden'));
  });
  test('D03 import during sync rolls backup platform data back', () async {
    await Storage.saveHomework([hw('cx_before')]);
    final pending = SyncService.run();
    await BackupService.importJson(
      jsonEncode({
        'app': 'homework_radar',
        'version': 1,
        'homework': [hw('cx_backup').toJson()],
      }),
    );
    await pending;
    expect(Storage.homework().map((h) => h.id).toList(), ['cx_backup']);
  });
  test(
    'D04 corrupt hidden restore deletes its only stored copy before throwing',
    () async {
      await Storage.dismiss('cx_hidden', 'broken json');
      final state = AppState();
      await state.loadLocal();
      await expectLater(
        state.restoreHomework('cx_hidden'),
        throwsFormatException,
      );
      expect(Storage.hiddenItems().keys, contains('cx_hidden'));
      expect(Storage.dismissedIds(), contains('cx_hidden'));
    },
  );
  test('D05 malformed times in backup shift later section indexes', () async {
    final times = <dynamic>[
      for (var i = 0; i < 12; i++) [480 + 60 * i, 525 + 60 * i],
    ];
    times[2] = 'broken';
    await BackupService.importJson(
      jsonEncode({
        'app': 'homework_radar',
        'version': 1,
        'sectionTimes': times,
      }),
    );
    final restored = Storage.sectionTimes()!;
    expect(restored.length, 12);
    expect(restored[3].$1, 660);
  });
  test('D06 true adjacent semesters are treated as identical', () {
    expect(
      AppState.sameSemesterText('2025-2026学年第一学期', '2025-2026学年第二学期'),
      isFalse,
    );
    expect(
      AppState.sameSemesterText('2025-2026学年第一学期', '2026-2027学年第一学期'),
      isFalse,
    );
  });
  test(
    'D07 secure write failure reports success but restart loads old credential',
    () async {
      await SecureStore.write('cx_cookie', 'old-fake');
      failWrite = true;
      await expectLater(
        SecureStore.write('cx_cookie', 'new-fake'),
        throwsStateError,
      );
      expect(SecureStore.get('cx_cookie'), 'old-fake');
      await SecureStore.preloadAndMigrate({'cx_cookie': ''});
      expect(SecureStore.get('cx_cookie'), 'old-fake');
      failWrite = false;
      await SecureStore.delete('cx_cookie');
    },
  );
  test('D08 secure deletion failure resurrects credential', () async {
    await SecureStore.write('cx_cookie', 'fake');
    // 删除现在提交加密凭据集合的缺失键，写入失败必须保留旧集合。
    failWrite = true;
    await expectLater(SecureStore.delete('cx_cookie'), throwsStateError);
    expect(SecureStore.get('cx_cookie'), 'fake');
    await SecureStore.preloadAndMigrate({'cx_cookie': ''});
    expect(SecureStore.get('cx_cookie'), 'fake');
    failWrite = false;
    await SecureStore.delete('cx_cookie');
  });
  test(
    'D09 log JSON secrets and short URL session values escape redaction',
    () {
      final e = Storage.redactLogEntry(
        SafeHttpLogEntry(
          DateTime(2026),
          'GET',
          'https://x.chaoxing.com/?enc=fakeSecret&sessionid=shortSecret',
          200,
          '{"token":"shortSecret","password":"secret123"}',
        ),
      );
      expect(e.url, isNot(contains('shortSecret')));
      expect(e.bodySnippet, isNot(contains('secret123')));
    },
  );
  test('redaction protects a secret even when the HTTP snippet ends inside its JSON string', () {
    final raw = '{"password":"${'privateplaintext' * 120}';
    final entry = Storage.redactLogEntry(
      SafeHttpLogEntry(
        DateTime(2026),
        'POST',
        'https://x.chaoxing.com/',
        200,
        raw,
      ),
    );
    expect(entry.bodySnippet, isNot(contains('privateplaintext')));
  });
  test(
    'D10 edited odd and even week twins collapse into duplicated even weeks',
    () {
      Course c(List<int> w, {bool edited = false, String teacher = ''}) =>
          Course(
            id: 'same',
            name: 'Math',
            weekday: 1,
            startSection: 1,
            endSection: 2,
            weeks: w,
            edited: edited,
            teacher: teacher,
          );
      final out = AppState.mergeEdited(
        [
          c([1]),
          c([2]),
        ],
        [
          c([1], edited: true, teacher: 'A'),
          c([2], edited: true, teacher: 'B'),
        ],
      );
      expect(out.map((c) => c.weeks).toList(), [
        [1],
        [2],
      ]);
    },
  );
  test('D11 backup default times do not replace target custom times', () async {
    await Storage.saveSectionTimes([
      for (var i = 0; i < 12; i++) (420 + 60 * i, 465 + 60 * i),
    ]);
    await BackupService.importJson(
      jsonEncode({'app': 'homework_radar', 'version': 1, 'sectionTimes': []}),
    );
    expect(Storage.sectionTimes(), isNull);
  });
  test('D14 current preview edits are overridden by older imported edits', () {
    Course c(String room) => Course(
      id: 'same',
      name: 'Math',
      weekday: 1,
      startSection: 1,
      endSection: 2,
      weeks: [1],
      edited: true,
      room: room,
    );
    final out = AppState.mergeEdited([c('new room')], [c('old room')]);
    expect(out.single.room, 'new room');
  });
  test('D25 edits during sync notification tail are overwritten in UI by old result', () async {
    final arrived = Completer<void>();
    final release = Completer<void>();
    var first = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('dexterous.com/flutter/local_notifications'),
          (call) async {
            if (call.method == 'cancelAllPendingNotifications' && first) {
              first = false;
              arrived.complete();
              await release.future;
            }
            return true;
          },
        );
    await Storage.saveHomework([
      HomeworkItem(
        id: 'manual_tail',
        platform: PlatformKind.manual,
        course: 'x',
        title: 'x',
        status: HwStatus.todo,
      ),
    ]);
    final state = AppState();
    await state.loadLocal();
    final pending = state.syncAll();
    await arrived.future;
    final deleting = state.deleteManualHomework('manual_tail');
    await Future<void>.delayed(Duration.zero);
    expect(Storage.homework(), isEmpty);
    release.complete();
    await pending;
    await deleting;
    expect(Storage.homework(), isEmpty);
    expect(state.homework.map((h) => h.id), isNot(contains('manual_tail')));
  });
}
