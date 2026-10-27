import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:homework_radar/app_state.dart';
import 'package:homework_radar/main.dart' show buildTheme;
import 'package:homework_radar/models/homework.dart';
import 'package:homework_radar/pages/backup_restore_page.dart';
import 'package:homework_radar/pages/data_recovery_page.dart';
import 'package:homework_radar/services/backup_service.dart';
import 'package:homework_radar/services/storage.dart';
import 'package:homework_radar/services/notification_service.dart';
import 'package:homework_radar/services/local_recovery_store.dart';
import 'package:homework_radar/ui/tokens.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  AndroidFlutterLocalNotificationsPlugin.registerWith();
  late AppState state;
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
    await Storage.init();
    await NotificationService.init();
    await Storage.saveClassReminder(false);
    await Storage.saveHomework([
      HomeworkItem(
        id: 'manual_keep',
        platform: PlatformKind.manual,
        course: '高等数学',
        title: '需要保留的原有作业',
        note: '旧备注',
      ),
    ]);
    state = AppState();
    await state.loadLocal();
  });
  tearDown(() => state.dispose());

  final raw = jsonEncode({
    'app': 'homework_radar',
    'version': 2,
    'homework': [
      HomeworkItem(
        id: 'manual_backup',
        platform: PlatformKind.manual,
        course: '英语',
        title: '备份中的阅读作业',
      ).toJson(),
    ],
  });

  Widget harness(Widget child, {ThemeStyle style = ThemeStyle.clean}) =>
      MaterialApp(
        theme: buildTheme(Brightness.light, style),
        home: child,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(1.3)),
          child: child!,
        ),
      );

  testWidgets(
    'empty backup explains the data it will clear before confirmation',
    (tester) async {
      final empty = jsonEncode({
        'app': 'homework_radar',
        'version': 3,
        'homework': [],
        'courses': [],
        'hiddenItems': <String, String>{},
        'manualTrash': <String, Object>{},
        'sectionTimes': [],
        'courseColors': <String, int>{},
        'semesterStart': null,
      });
      final preview = await BackupService.previewJson(empty);
      await tester.pumpWidget(
        harness(BackupRestorePage(state: state, raw: empty, preview: preview)),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('课表将恢复为空'), findsOneWidget);
      expect(find.textContaining('作业列表将恢复为空'), findsOneWidget);
      expect(find.textContaining('隐藏记录将按空备份恢复'), findsOneWidget);
      expect(find.textContaining('回收站将恢复为空'), findsOneWidget);
      expect(find.textContaining('开学日期将清除'), findsOneWidget);
      await tester.tap(find.text('恢复这份备份'));
      await tester.pumpAndSettle();
      expect(find.textContaining('课表将恢复为空'), findsWidgets);
      expect(find.textContaining('作业列表将恢复为空'), findsWidgets);
      expect(Storage.homework().single.id, 'manual_keep');
    },
  );

  testWidgets('a stale restore preview cannot overwrite newer local changes', (
    tester,
  ) async {
    final preview = await BackupService.previewJson(raw);
    await tester.pumpWidget(
      harness(BackupRestorePage(state: state, raw: raw, preview: preview)),
    );
    await Storage.saveHomework([
      HomeworkItem(
        id: 'manual_new',
        platform: PlatformKind.manual,
        course: '新课程',
        title: '预览后新添加的作业',
      ),
    ]);
    await tester.tap(find.text('恢复这份备份'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认恢复'));
    await tester.pumpAndSettle();
    expect(Storage.homework().single.id, 'manual_new');
    expect(find.textContaining('当前数据已变化'), findsOneWidget);
  });

  for (final style in [
    ThemeStyle.clean,
    ThemeStyle.terminal,
    ThemeStyle.comic,
  ]) {
    testWidgets(
      '${style.name}: recovery and preview fit enlarged text and cancel is read only',
      (tester) async {
        tester.view.physicalSize = const Size(360, 820);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await LocalRecoveryStore.saveDeleted([
          DeletedHomework(Storage.homework().single, DateTime(2026, 10, 26)),
        ]);
        await Storage.saveHomework([]);
        await tester.pumpWidget(
          harness(DataRecoveryPage(state: state), style: style),
        );
        await tester.pumpAndSettle();
        expect(find.text('需要保留的原有作业'), findsOneWidget);
        expect(find.text('恢复'), findsOneWidget);
        final preview = await BackupService.previewJson(raw);
        await tester.pumpWidget(
          harness(
            BackupRestorePage(state: state, raw: raw, preview: preview),
            style: style,
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('备份中的阅读作业'), findsOneWidget);
        await tester.tap(find.text('恢复这份备份'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('返回预览'));
        await tester.pumpAndSettle();
        expect(Storage.homework(), isEmpty);
        expect(LocalRecoveryStore.deleted().single.item.note, '旧备注');
        expect(tester.takeException(), isNull);
      },
    );
  }
}
