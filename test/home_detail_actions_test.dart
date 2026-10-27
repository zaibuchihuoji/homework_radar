import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:homework_radar/app_state.dart';
import 'package:homework_radar/main.dart';
import 'package:homework_radar/models/homework.dart';
import 'package:homework_radar/pages/detail_page.dart';
import 'package:homework_radar/pages/home_page.dart';
import 'package:homework_radar/services/storage.dart';
import 'package:homework_radar/services/notification_service.dart';
import 'package:homework_radar/ui/tokens.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  AndroidFlutterLocalNotificationsPlugin.registerWith();
  late AppState state;
  final today = DateTime.now();
  final items = [
    HomeworkItem(
      id: 'manual_keep',
      platform: PlatformKind.manual,
      course: '原课程',
      title: '今天的作业',
      note: '旧备注',
      dueAt: DateTime(today.year, today.month, today.day, 23, 59),
      status: HwStatus.todo,
      sourceKey: 'keep-source',
      score: 87,
    ),
    HomeworkItem(
      id: 'cx_keep',
      platform: PlatformKind.chaoxing,
      course: '平台课程',
      title: '平台作业',
      note: '平台备注',
      status: HwStatus.submitted,
      sourceKey: 'keep-platform-source',
    ),
    HomeworkItem(
      id: 'undated_keep',
      platform: PlatformKind.manual,
      course: '其他课程',
      title: '尚未定截止时间的作业',
      status: HwStatus.todo,
    ),
  ];

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final channel in [
      'homework_radar/platform',
      'home_widget',
      'dexterous.com/flutter/local_notifications',
    ]) {
      messenger.setMockMethodCallHandler(
        MethodChannel(channel),
        (_) async => null,
      );
    }
    messenger.setMockMethodCallHandler(
      const MethodChannel('dexterous.com/flutter/local_notifications'),
      (call) async => call.method == 'pendingNotificationRequests'
          ? <Map<String, Object?>>[]
          : true,
    );
    await Storage.init();
    await NotificationService.init();
    await Storage.saveClassReminder(false);
    await Storage.saveHomework(items);
    state = AppState();
    await state.loadLocal();
    appStateForHome = state;
  });
  tearDown(() {
    appStateForHome = null;
    state.dispose();
  });

  Future<void> mount(WidgetTester tester, Widget home) => tester.pumpWidget(
    MaterialApp(
      theme: buildTheme(Brightness.light, ThemeStyle.clean),
      home: ListenableBuilder(
        listenable: state,
        builder: (_, _) => home is HomePage
            ? HomePage(state: state, onGoAccounts: home.onGoAccounts)
            : home,
      ),
    ),
  );

  testWidgets(
    'today shortcut filters presentation and all restores untouched records',
    (tester) async {
      final before = jsonEncode(
        Storage.homework().map((h) => h.toJson()).toList(),
      );
      await mount(tester, HomePage(state: state, onGoAccounts: () {}));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('今天截止 1 项'));
      await tester.pumpAndSettle();
      expect(find.text('今天的作业'), findsOneWidget);
      expect(find.text('尚未定截止时间的作业'), findsNothing);
      await tester.tap(find.text('全部'));
      await tester.pumpAndSettle();
      expect(find.text('尚未定截止时间的作业'), findsOneWidget);
      expect(
        jsonEncode(Storage.homework().map((h) => h.toJson()).toList()),
        before,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'empty today filter has a visible exit and preserves undated work',
    (tester) async {
      await Storage.saveHomework([items.last]);
      await state.loadLocal();
      final before = jsonEncode(
        Storage.homework().map((h) => h.toJson()).toList(),
      );
      await mount(tester, HomePage(state: state, onGoAccounts: () {}));
      await tester.pumpAndSettle();
      await tester.tap(find.text('今天截止 0 项'));
      await tester.pumpAndSettle();
      expect(find.text('今天没有待完成的截止作业'), findsOneWidget);
      await tester.tap(find.text('待完成 1 项'));
      await tester.pumpAndSettle();
      expect(find.text('尚未定截止时间的作业'), findsOneWidget);
      expect(
        jsonEncode(Storage.homework().map((h) => h.toJson()).toList()),
        before,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'detail semantics retains course and deadline alongside its title',
    (tester) async {
      final semantics = tester.ensureSemantics();
      await mount(tester, const HomeworkDetailPage(homeworkId: 'manual_keep'));
      await tester.pumpAndSettle();
      expect(
        tester.getSemantics(find.text('原课程')).getSemanticsData().label,
        contains('原课程'),
      );
      expect(
        tester.getSemantics(find.text('截止时间')).getSemanticsData().label,
        contains('截止时间'),
      );
      await tester.pumpWidget(const SizedBox());
      semantics.dispose();
    },
  );

  testWidgets(
    'manual detail editing hiding and undo preserve identity and old data',
    (tester) async {
      await mount(tester, HomePage(state: state, onGoAccounts: () {}));
      await tester.tap(find.text('今天的作业'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('编辑作业'),
        220,
        scrollable: find
            .descendant(
              of: find.byType(HomeworkDetailPage),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(find.text('编辑作业'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).at(1), '修改后的作业');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      final saved = Storage.homework().firstWhere((h) => h.id == 'manual_keep');
      expect(saved.title, '修改后的作业');
      expect(saved.sourceKey, 'keep-source');
      expect(saved.score, 87);
      expect(saved.note, '旧备注');
      expect(saved.status, HwStatus.todo);
      expect(saved.dueAt, items.first.dueAt);
      expect(Storage.homework().length, 3);
      expect(find.text('修改后的作业'), findsOneWidget);
      await tester.tap(find.byTooltip('更多作业操作'));
      await tester.pumpAndSettle();
      expect(tester.getCenter(find.text('隐藏这条作业')).dy, lessThan(600));
      await tester.tap(find.text('隐藏这条作业'));
      for (
        var i = 0;
        i < 10 && find.byType(HomeworkDetailPage).evaluate().isNotEmpty;
        i++
      ) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.pumpAndSettle();
      expect(find.byType(HomeworkDetailPage), findsNothing);
      expect(Storage.dismissedIds(), contains('manual_keep'));
      expect(Storage.homework().length, 3);
      await tester.tap(find.text('撤销'));
      await tester.pumpAndSettle();
      expect(Storage.dismissedIds(), isNot(contains('manual_keep')));
      expect(find.text('修改后的作业'), findsOneWidget);
      expect(Storage.homework().first.note, '旧备注');
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 600));
    },
  );

  testWidgets(
    'editing an old deadline can open the date picker without losing its date',
    (tester) async {
      final old = HomeworkItem(
        id: 'manual_old',
        platform: PlatformKind.manual,
        course: '旧课程',
        title: '去年的作业',
        dueAt: DateTime(2020, 5, 17, 22, 30),
      );
      await Storage.saveHomework([old]);
      await state.loadLocal();
      await mount(tester, const HomeworkDetailPage(homeworkId: 'manual_old'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('编辑作业'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('选择时间'));
      await tester.tap(find.text('选择时间'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(DatePickerDialog), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(Storage.homework().single.dueAt, DateTime(2020, 5, 17, 22, 30));
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    },
  );

  testWidgets(
    'platform detail can change a note but never exposes local submission edits',
    (tester) async {
      await mount(tester, const HomeworkDetailPage(homeworkId: 'cx_keep'));
      await tester.pumpAndSettle();
      expect(find.text('编辑作业'), findsNothing);
      expect(find.text('标记完成'), findsNothing);
      await tester.ensureVisible(find.text('编辑备注'));
      await tester.tap(find.text('编辑备注'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '修改后的平台备注');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      final saved = Storage.homework().firstWhere((h) => h.id == 'cx_keep');
      expect(saved.note, '修改后的平台备注');
      expect(saved.status, HwStatus.submitted);
      expect(saved.sourceKey, 'keep-platform-source');
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 600));
    },
  );
}
