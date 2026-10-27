import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:homework_radar/app_state.dart';
import 'package:homework_radar/models/homework.dart';
import 'package:homework_radar/services/backup_service.dart';
import 'package:homework_radar/services/storage.dart';
import 'package:homework_radar/services/local_recovery_store.dart';

class _FailingStore extends InMemorySharedPreferencesStore {
  _FailingStore() : super.empty();
  String? failKey;
  bool persistBeforeFailure = false;
  String? failRemoveKey;
  @override
  Future<bool> setValue(String type, String key, Object value) async {
    if (key == failKey) {
      failKey = null;
      if (persistBeforeFailure) await super.setValue(type, key, value);
      return false;
    }
    return super.setValue(type, key, value);
  }

  @override
  Future<bool> remove(String key) async {
    if (key == failRemoveKey) {
      failRemoveKey = null;
      return false;
    }
    return super.remove(key);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  AndroidFlutterLocalNotificationsPlugin.registerWith();
  late AppState state;
  late _FailingStore store;
  final secrets = <String, String>{};
  final widgetSnapshots = <Map>[];
  setUp(() async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('homework_radar/platform'),
      (call) async {
        final args = call.arguments as Map?;
        if (call.method == 'secureRead') return secrets[args?['key']];
        if (call.method == 'secureWrite') {
          secrets[args?['key']] = args?['value'];
        }
        if (call.method == 'secureDelete') secrets.remove(args?['key']);
        return true;
      },
    );
    messenger.setMockMethodCallHandler(const MethodChannel('home_widget'), (
      call,
    ) async {
      if (call.method == 'saveWidgetData' &&
          call.arguments['id'] == 'homework_snapshot') {
        widgetSnapshots.add(jsonDecode(call.arguments['data']) as Map);
      }
      return true;
    });
    messenger.setMockMethodCallHandler(
      const MethodChannel('dexterous.com/flutter/local_notifications'),
      (call) async => call.method == 'pendingNotificationRequests'
          ? <Map<String, Object?>>[]
          : true,
    );
    SharedPreferences.setMockInitialValues({});
    secrets.clear();
    widgetSnapshots.clear();
    store = _FailingStore();
    SharedPreferencesStorePlatform.instance = store;
    await Storage.init();
    await Storage.saveClassReminder(false);
    await Storage.saveHomework([
      HomeworkItem(
        id: 'manual_original',
        platform: PlatformKind.manual,
        course: '数学',
        title: '需要恢复的作业',
        note: '纸质报告',
        dueAt: DateTime(2027, 1, 10, 18),
      ),
    ]);
    state = AppState();
    await state.loadLocal();
  });
  tearDown(() => state.dispose());

  test(
    'journal creation failure preserves data and permits a later transaction',
    () async {
      store.failKey = 'flutter.business_transaction';
      await expectLater(
        Storage.businessTransaction(() => Storage.saveHomework([])),
        throwsStateError,
      );
      expect(Storage.homework().single.id, 'manual_original');
      await Storage.businessTransaction(() => Storage.saveHomework([]));
      expect(Storage.homework(), isEmpty);
    },
  );

  test(
    'an ambiguously persisted journal is safely removed before retry',
    () async {
      store.persistBeforeFailure = true;
      store.failKey = 'flutter.business_transaction';
      await expectLater(
        Storage.businessTransaction(() => Storage.saveHomework([])),
        throwsStateError,
      );
      expect(Storage.homework().single.id, 'manual_original');
      await Storage.businessTransaction(() => Storage.saveHomework([]));
      await Storage.init();
      expect(Storage.homework(), isEmpty);
    },
  );

  test(
    'uncertain journal cleanup blocks writes until startup recovery',
    () async {
      store.persistBeforeFailure = true;
      store.failKey = 'flutter.business_transaction';
      store.failRemoveKey = 'flutter.business_transaction';
      await expectLater(
        Storage.businessTransaction(() => Storage.saveHomework([])),
        throwsStateError,
      );
      await expectLater(
        Storage.businessTransaction(() => Storage.saveHomework([])),
        throwsStateError,
      );
      await Storage.init();
      expect(Storage.homework().single.id, 'manual_original');
      await Storage.businessTransaction(() => Storage.saveHomework([]));
      expect(Storage.homework(), isEmpty);
    },
  );

  test(
    'deleting manual homework retains its complete body in a recycle bin',
    () async {
      await state.deleteManualHomework('manual_original');
      expect(Storage.homework(), isEmpty);
      final raw = (await SharedPreferences.getInstance()).getString(
        'manual_homework_trash_v1',
      );
      expect(raw, isNotNull);
      final trash = jsonDecode(raw!) as Map;
      expect((trash['manual_original'] as Map)['item']['note'], '纸质报告');
      expect(
        (trash['manual_original'] as Map)['item']['dueAt'],
        DateTime(2027, 1, 10, 18).millisecondsSinceEpoch,
      );
    },
  );

  test('recycle restore survives restart and republishes the same note and deadline', () async {
    final original = Storage.homework().single.toJson();
    await state.deleteManualHomework('manual_original');
    expect((widgetSnapshots.last['items'] as List), isEmpty);
    await Storage.init();
    await state.restoreDeletedHomework('manual_original');
    expect(Storage.homework().single.toJson(), original);
    expect(LocalRecoveryStore.deleted(), isEmpty);
    expect(
      (widgetSnapshots.last['items'] as List).single['id'],
      'manual_original',
    );
  });

  test(
    'failed delete rolls back the recycle bin together with active records',
    () async {
      store.failKey = 'flutter.homework_json';
      await expectLater(
        state.deleteManualHomework('manual_original'),
        throwsStateError,
      );
      await (await SharedPreferences.getInstance()).reload();
      expect(Storage.homework().single.note, '纸质报告');
      expect(LocalRecoveryStore.deleted(), isEmpty);
    },
  );

  test(
    'recycling preserves unknown fields and unreadable neighboring records',
    () async {
      final target = {
        ...Storage.homework().single.toJson(),
        'futureField': 'keep exactly',
      };
      final neighbor = {
        'id': 'future_row',
        'title': 42,
        'opaque': [1, 2],
      };
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('homework_json', jsonEncode([target, neighbor]));
      await state.deleteManualHomework('manual_original');
      expect(jsonDecode(prefs.getString('homework_json')!), [neighbor]);
      await state.restoreDeletedHomework('manual_original');
      final rows = jsonDecode(prefs.getString('homework_json')!) as List;
      expect(rows.first, neighbor);
      expect(rows.last, target);
    },
  );

  test(
    'failed restore rolls back the active copy and retains the deleted record',
    () async {
      await state.deleteManualHomework('manual_original');
      store.failKey = 'flutter.manual_homework_trash_v1';
      await expectLater(
        state.restoreDeletedHomework('manual_original'),
        throwsStateError,
      );
      await (await SharedPreferences.getInstance()).reload();
      expect(Storage.homework(), isEmpty);
      expect(LocalRecoveryStore.deleted().single.item.note, '纸质报告');
    },
  );

  test('recycle ID conflict never overwrites a newer active record', () async {
    await state.deleteManualHomework('manual_original');
    await Storage.saveHomework([
      HomeworkItem(
        id: 'manual_original',
        platform: PlatformKind.manual,
        course: '新课程',
        title: '新作业',
      ),
    ]);
    await expectLater(
      state.restoreDeletedHomework('manual_original'),
      throwsStateError,
    );
    expect(Storage.homework().single.title, '新作业');
    expect(LocalRecoveryStore.deleted().single.item.title, '需要恢复的作业');
  });

  test('daily capture is bounded and backups exclude login secrets and recognition text', () async {
    await Storage.saveChaoxing(
      cookie: 'synthetic-cookie',
      uid: 'synthetic-user',
    );
    await Storage.saveRecognitionDraft('private recognition source');
    for (var day = 1; day <= 10; day++) {
      await LocalRecoveryStore.capture(
        BackupService.encode(),
        reason: 'daily',
        daily: true,
        now: DateTime(2030, 1, day),
      );
      await LocalRecoveryStore.capture(
        BackupService.encode(),
        reason: 'same day',
        daily: true,
        now: DateTime(2030, 1, day, 18),
      );
    }
    final points = LocalRecoveryStore.points();
    expect(points, hasLength(7));
    expect(points.first.createdAt, DateTime(2030, 1, 10));
    expect(points.last.createdAt, DateTime(2030, 1, 4));
    final body = points.first.readBackup();
    expect(body, contains('纸质报告'));
    expect(body, isNot(contains('synthetic-cookie')));
    expect(body, isNot(contains('private recognition source')));
  });

  test(
    'preview validates without writes and old backups preserve the recycle bin',
    () async {
      await state.deleteManualHomework('manual_original');
      final before = LocalRecoveryStore.points().map((p) => p.id).toList();
      final raw = jsonEncode({
        'app': 'homework_radar',
        'version': 2,
        'homework': [],
      });
      final preview = await BackupService.previewJson(raw);
      expect(preview.items, isEmpty);
      expect(LocalRecoveryStore.deleted(), hasLength(1));
      expect(LocalRecoveryStore.points().map((p) => p.id), before);
      await BackupService.importJson(raw);
      expect(LocalRecoveryStore.deleted(), hasLength(1));
      await expectLater(
        BackupService.previewJson('{broken'),
        throwsFormatException,
      );
      expect(LocalRecoveryStore.deleted().single.item.note, '纸质报告');
    },
  );

  test(
    'restoring a local point keeps the current platform account isolated',
    () async {
      final backup = jsonEncode({
        'app': 'homework_radar',
        'version': 2,
        'homework': [
          HomeworkItem(
            id: 'cx_same',
            platform: PlatformKind.chaoxing,
            course: '旧账号',
            title: '旧作业',
            note: '旧账号备注',
          ).toJson(),
        ],
      });
      await Storage.saveChaoxing(
        cookie: 'synthetic-cookie',
        uid: 'new-account',
      );
      await Storage.saveHomework([
        HomeworkItem(
          id: 'cx_same',
          platform: PlatformKind.chaoxing,
          course: '当前账号',
          title: '当前作业',
          note: '当前备注',
        ),
      ]);
      await BackupService.importJson(backup);
      expect(Storage.homework().single.note, '当前备注');
      expect(Storage.chaoxingUid(), 'new-account');
      expect(
        Storage.accountArchives().single['homework'].single['note'],
        '旧账号备注',
      );
    },
  );

  test(
    'backup round trip includes deleted manual work and rejects corrupt trash',
    () async {
      await state.deleteManualHomework('manual_original');
      final exported = BackupService.encode();
      await LocalRecoveryStore.saveDeleted([]);
      await BackupService.importJson(exported);
      expect(LocalRecoveryStore.deleted().single.item.note, '纸质报告');
      final broken = jsonDecode(exported) as Map<String, dynamic>;
      broken['manualTrash']['manual_original']['item']['platform'] = 'chaoxing';
      await expectLater(
        BackupService.importJson(jsonEncode(broken)),
        throwsFormatException,
      );
      expect(
        LocalRecoveryStore.deleted().single.item.platform,
        PlatformKind.manual,
      );
    },
  );

  test(
    'backup restore first retains the data it is about to replace',
    () async {
      await BackupService.importJson(
        jsonEncode({'app': 'homework_radar', 'version': 2, 'homework': []}),
      );
      expect(Storage.homework(), isEmpty);
      final points = (await SharedPreferences.getInstance()).getStringList(
        'local_recovery_points_v1',
      );
      expect(points, isNotEmpty);
    },
  );
}
