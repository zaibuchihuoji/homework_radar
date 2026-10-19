import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:homework_radar/app_state.dart';
import 'package:homework_radar/models/homework.dart';
import 'package:homework_radar/models/homework_draft.dart';
import 'package:homework_radar/services/storage.dart';
import 'package:homework_radar/services/notification_service.dart';

class ImportFailingStore extends InMemorySharedPreferencesStore {
  ImportFailingStore() : super.empty();
  bool failOnce = false;
  @override
  Future<bool> setValue(String type, String key, Object value) async {
    if (failOnce && key == 'flutter.homework_json') {
      failOnce = false;
      return false;
    }
    return super.setValue(type, key, value);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppState state;
  bool failOutputs = false;
  final widgetData = <String, dynamic>{};
  final old = HomeworkItem(
    id: 'cx_old',
    platform: PlatformKind.chaoxing,
    course: '旧课程',
    title: '原有作业',
    note: '不能改变的备注',
    dueAt: DateTime(2026),
    status: HwStatus.submitted,
    sourceKey: 'account-scoped',
  );
  setUp(() async {
    failOutputs = false;
    widgetData.clear();
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('homework_radar/platform'),
      (_) async => null,
    );
    messenger.setMockMethodCallHandler(const MethodChannel('home_widget'), (
      call,
    ) async {
      if (call.method == 'saveWidgetData') {
        final a = call.arguments as Map;
        widgetData[a['id'] as String] = a['data'];
      }
      return true;
    });
    messenger.setMockMethodCallHandler(
      const MethodChannel('dexterous.com/flutter/local_notifications'),
      (_) async {
        if (failOutputs) throw PlatformException(code: 'unavailable');
        return true;
      },
    );
    SharedPreferences.setMockInitialValues({});
    await Storage.init();
    await NotificationService.init();
    await Storage.saveClassReminder(false);
    await Storage.saveHomework([old]);
    await Storage.dismiss(old.id, jsonEncode(old.toJson()));
    state = AppState();
    await state.loadLocal();
  });
  tearDown(() => state.dispose());
  ManualHomeworkEntry entry(String title, {bool allow = false}) =>
      ManualHomeworkEntry(
        course: '数学',
        title: title,
        dueAt: DateTime(2026, 10, 23, 20),
        note: '识别原文：$title',
        duplicateApproved: allow,
      );

  test('hidden-only bodies still participate in duplicate checks without being restored', () async {
    await Storage.saveHomework([]);
    expect(Storage.hiddenItems(), contains(old.id));
    await expectLater(
      state.addRecognizedHomework([
        ManualHomeworkEntry(course: old.course, title: old.title),
      ]),
      throwsA(isA<HomeworkImportDuplicateException>()),
    );
    expect(Storage.homework(), isEmpty);
    expect(Storage.hiddenItems()[old.id], jsonEncode(old.toJson()));
  });

  test('one batch appends only submitted selection, preserving hidden old data and unique IDs', () async {
    final result = await state.addRecognizedHomework([
      entry('练习A'),
      entry('练习B'),
    ]);
    expect(result.count, 2);
    final disk = Storage.homework();
    expect(disk.first.toJson(), old.toJson());
    expect(disk.map((h) => h.id).toSet(), hasLength(3));
    expect(
      disk.skip(1).every((h) => h.platform == PlatformKind.manual),
      isTrue,
    );
    expect(Storage.dismissedIds(), {old.id});
    expect(Storage.hiddenItems()[old.id], jsonEncode(old.toJson()));
    expect(state.homework.map((h) => h.title), ['练习A', '练习B']);
    final snapshot = jsonDecode(widgetData['homework_snapshot'] as String);
    expect(snapshot['items'], hasLength(2));
  });
  test(
    'existing and within-batch duplicates require explicit approval',
    () async {
      await state.addRecognizedHomework([entry('练习A')]);
      final before = (await SharedPreferences.getInstance()).getString(
        'homework_json',
      );
      await expectLater(
        state.addRecognizedHomework([entry('练习A')]),
        throwsA(isA<HomeworkImportDuplicateException>()),
      );
      expect(
        (await SharedPreferences.getInstance()).getString('homework_json'),
        before,
      );
      await expectLater(
        state.addRecognizedHomework([entry('练习B'), entry('练习B')]),
        throwsA(isA<HomeworkImportDuplicateException>()),
      );
      expect(Storage.homework(), hasLength(2));
      expect(
        (await state.addRecognizedHomework([entry('练习A', allow: true)])).count,
        1,
      );
    },
  );
  test('unknown old fields and malformed individual rows remain byte-for-value JSON', () async {
    final prefs = await SharedPreferences.getInstance();
    final raw = [
      {
        ...old.toJson(),
        'futureField': {
          'keep': [1, 2],
        },
      },
      'legacy-broken-row',
    ];
    await prefs.setString('homework_json', jsonEncode(raw));
    await state.addRecognizedHomework([entry('练习A')]);
    final after = jsonDecode(prefs.getString('homework_json')!) as List;
    expect(after.take(2).toList(), raw);
  });
  test(
    'corrupt top-level data aborts without replacing the original',
    () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('homework_json', '{broken');
      await expectLater(
        state.addRecognizedHomework([entry('练习A')]),
        throwsStateError,
      );
      expect(prefs.getString('homework_json'), '{broken');
    },
  );
  test(
    'notification failure after commit does not report an unsaved batch',
    () async {
      failOutputs = true;
      final result = await state.addRecognizedHomework([entry('练习A')]);
      expect(result.count, 1);
      expect(result.outputsDelayed, isTrue);
      expect(Storage.homework().last.title, '练习A');
      expect(state.homework.single.title, '练习A');
    },
  );
  test('invalid entries and empty selection do not add any records', () async {
    final prefs = await SharedPreferences.getInstance();
    final before = prefs.getString('homework_json');
    await expectLater(
      state.addRecognizedHomework([
        const ManualHomeworkEntry(course: '', title: ' '),
      ]),
      throwsArgumentError,
    );
    expect((await state.addRecognizedHomework([])).count, 0);
    expect(prefs.getString('homework_json'), before);
  });
  test('failed homework write rolls back the entire batch', () async {
    final store = ImportFailingStore();
    SharedPreferences.setMockInitialValues({});
    SharedPreferencesStorePlatform.instance = store;
    await Storage.init();
    await Storage.saveHomework([old]);
    store.failOnce = true;
    await expectLater(
      state.addRecognizedHomework([entry('练习A'), entry('练习B')]),
      throwsStateError,
    );
    expect(Storage.homework().map((h) => h.toJson()).toList(), [old.toJson()]);
    expect(
      (await SharedPreferences.getInstance()).containsKey(
        'business_transaction',
      ),
      isFalse,
    );
  });
}
