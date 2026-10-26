import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:homework_radar/app_state.dart';
import 'package:homework_radar/models/homework.dart';
import 'package:homework_radar/services/notification_service.dart';
import 'package:homework_radar/services/storage.dart';
import 'package:homework_radar/services/sync_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final today = DateTime.now();
  final cache = <String, dynamic>{};
  Completer<void>? entered, release;
  var failNotifications = false;
  late AppState state;
  HomeworkItem task(String id) => HomeworkItem(
    id: id,
    platform: PlatformKind.manual,
    course: '课程',
    title: '作业 $id',
    dueAt: DateTime(today.year, today.month, today.day),
    status: HwStatus.todo,
    note: '保留的旧备注 $id',
  );
  List<String> widgetIds() =>
      (jsonDecode(cache['homework_snapshot'] as String)['items'] as List)
          .map((row) => row['id'] as String)
          .toList();

  setUp(() async {
    cache.clear();
    entered = release = null;
    failNotifications = false;
    FlutterLocalNotificationsPlatform.instance =
        AndroidFlutterLocalNotificationsPlugin();
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
        final args = call.arguments as Map;
        cache[args['id'] as String] = args['data'];
      }
      return true;
    });
    messenger.setMockMethodCallHandler(
      const MethodChannel('dexterous.com/flutter/local_notifications'),
      (call) async {
            if (call.method == 'pendingNotificationRequests') { return <Map<String, Object?>>[]; }
        if (call.method == 'cancelAllPendingNotifications') {
          if (entered != null && !entered!.isCompleted) entered!.complete();
          if (release != null) await release!.future;
          if (failNotifications) {
            throw PlatformException(code: 'notification-failed');
          }
        }
        return true;
      },
    );
    SharedPreferences.setMockInitialValues({});
    await Storage.init();
    await NotificationService.init();
    await Storage.saveClassReminder(false);
    await Storage.saveHomework([task('manual_old'), task('manual_keep')]);
    state = AppState();
    await state.loadLocal();
    await SyncService.updateHomeWidget(state.homework);
  });
  tearDown(() => state.dispose());

  for (final operation in [
    'delete',
    'hide',
    'complete',
    'submit',
    'edit',
    'add',
    'restore',
    'reload',
  ]) {
    test(
      '$operation publishes committed homework before slow notification scheduling',
      () async {
        if (operation == 'restore') {
          await Storage.dismiss(
            'manual_old',
            jsonEncode(task('manual_old').toJson()),
          );
          await state.loadLocal();
          await SyncService.updateHomeWidget(state.homework);
          expect(widgetIds(), isNot(contains('manual_old')));
        }
        if (operation == 'reload') {
          await Storage.saveHomework([task('manual_keep')]);
        }
        entered = Completer<void>();
        release = Completer<void>();
        final action = switch (operation) {
          'delete' => state.deleteManualHomework('manual_old'),
          'hide' => state.dismissHomework(task('manual_old')),
          'complete' => state.setHomeworkStatus('manual_old', HwStatus.done),
          'submit' => state.setHomeworkStatus('manual_old', HwStatus.submitted),
          'edit' => state.updateManualHomework(
            HomeworkItem(
              id: 'manual_old',
              platform: PlatformKind.manual,
              course: '课程',
              title: '修改后的作业',
              dueAt: task('manual_old').dueAt,
              status: HwStatus.todo,
              note: task('manual_old').note,
            ),
          ),
          'add' => state.addManualHomework(course: '课程', title: '新增作业'),
          'reload' => state.reloadLocal(),
          _ => state.restoreHomework('manual_old'),
        };
        try {
          await entered!.future;
          // Drain the finite local cache publication, leaving notifications blocked.
          await Future<void>.delayed(const Duration(milliseconds: 20));
          if ([
            'delete',
            'hide',
            'complete',
            'submit',
            'reload',
          ].contains(operation)) {
            expect(widgetIds(), ['manual_keep']);
          } else if (operation == 'add') {
            expect(widgetIds(), hasLength(3));
          } else if (operation == 'restore') {
            expect(widgetIds(), contains('manual_old'));
          } else {
            final rows =
                jsonDecode(cache['homework_snapshot'] as String)['items']
                    as List;
            expect(
              rows.singleWhere((r) => r['id'] == 'manual_old')['title'],
              '修改后的作业',
            );
          }
        } finally {
          release!.complete();
          await action;
        }
        expect(
          Storage.homework().singleWhere((h) => h.id == 'manual_keep').note,
          '保留的旧备注 manual_keep',
        );
        if (operation == 'hide') {
          expect(Storage.dismissedIds(), contains('manual_old'));
          expect(Storage.hiddenItems()['manual_old'], contains('保留的旧备注'));
        }
      },
    );
  }

  test(
    'notification failure cannot leave a deleted homework in the widget cache',
    () async {
      failNotifications = true;
      await expectLater(
        state.deleteManualHomework('manual_old'),
        throwsA(isA<PlatformException>()),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(widgetIds(), ['manual_keep']);
      expect(Storage.homework().map((h) => h.id), ['manual_keep']);
    },
  );

  test('rapid hides and restores keep all rows and notes consistent with the widget', () async {
    await Future.wait([
      state.dismissHomework(task('manual_old')),
      state.dismissHomework(task('manual_keep')),
    ]);
    expect(widgetIds(), isEmpty);
    expect(Storage.dismissedIds(), {'manual_old', 'manual_keep'});
    expect(Storage.hiddenItems(), hasLength(2));
    expect(Storage.homework(), hasLength(2));
    await Future.wait([
      state.restoreHomework('manual_old'),
      state.restoreHomework('manual_keep'),
    ]);
    expect(widgetIds().toSet(), {'manual_old', 'manual_keep'});
    expect(Storage.hiddenItems(), isEmpty);
    expect(Storage.homework().map((h) => h.note).toSet(), {
      '保留的旧备注 manual_old',
      '保留的旧备注 manual_keep',
    });
  });

  test('deleting the final homework publishes an empty collection', () async {
    await state.deleteManualHomework('manual_old');
    await state.deleteManualHomework('manual_keep');
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(widgetIds(), isEmpty);
    final data = jsonDecode(cache['homework_snapshot'] as String);
    expect(data['stats']['todo'], 0);
  });
}
