import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homework_radar/app_state.dart';
import 'package:homework_radar/main.dart' show buildTheme, MainShell;
import 'package:homework_radar/models/homework.dart';
import 'package:homework_radar/pages/home_page.dart';
import 'package:homework_radar/services/storage.dart';
import 'package:homework_radar/services/local_recovery_store.dart';
import 'package:homework_radar/ui/themed_navigation.dart';
import 'package:homework_radar/ui/tokens.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppState state;

  setUp(() async {
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    SharedPreferences.setMockInitialValues({});
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final name in [
      'homework_radar/platform',
      'home_widget',
      'home_widget/updates',
    ]) {
      messenger.setMockMethodCallHandler(
        MethodChannel(name),
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
    final items = [
      for (final (id, title, status) in [
        ('todo', '待办样本', HwStatus.todo),
        ('submitted', '提交样本', HwStatus.submitted),
        ('done', '完成样本', HwStatus.done),
      ])
        HomeworkItem(
          id: id,
          platform: PlatformKind.manual,
          course: '测试课程',
          title: title,
          status: status,
          note: '保留备注',
        ),
    ];
    await Storage.saveHomework(items);
    state = AppState()..homework = items;
  });
  tearDown(() => state.dispose());

  for (final style in ThemeStyle.values) {
    testWidgets(
      '${style.name}: left advances and right returns without changing homework',
      (tester) async {
        tester.view.physicalSize = const Size(400, 850);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final before = jsonEncode(Storage.homeworkRowsForEdit());
        await tester.pumpWidget(
          MaterialApp(
            theme: buildTheme(Brightness.light, style),
            home: HomePage(state: state, onGoAccounts: () {}),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('待办样本'), findsOneWidget);

        // At the leftmost filter, a right swipe has nowhere to go.
        await tester.drag(find.text('待办样本'), const Offset(260, 0));
        await tester.pumpAndSettle();
        expect(find.text('待办样本'), findsOneWidget);

        await tester.drag(find.text('待办样本'), const Offset(-260, 0));
        await tester.pumpAndSettle();
        expect(find.text('提交样本'), findsOneWidget);
        expect(find.text('待办样本'), findsNothing);

        await tester.drag(find.text('提交样本'), const Offset(-260, 0));
        await tester.pumpAndSettle();
        expect(find.text('完成样本'), findsOneWidget);
        await tester.drag(find.text('完成样本'), const Offset(260, 0));
        await tester.pumpAndSettle();
        expect(find.text('提交样本'), findsOneWidget);
        expect(jsonEncode(Storage.homeworkRowsForEdit()), before);
        expect(Storage.dismissedIds(), isEmpty);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets('empty filter can be swiped and the end filters do not wrap', (
    tester,
  ) async {
    state.homework = state.homework
        .where((h) => h.status == HwStatus.todo)
        .toList();
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.light, ThemeStyle.clean),
        home: HomePage(state: state, onGoAccounts: () {}),
      ),
    );
    await tester.pumpAndSettle();
    await tester.drag(find.text('待办样本'), const Offset(-260, 0));
    await tester.pumpAndSettle();
    expect(find.text('这里空空的'), findsOneWidget);
    await tester.drag(find.text('这里空空的'), const Offset(-260, 0));
    await tester.pumpAndSettle();
    expect(find.text('这里空空的'), findsOneWidget);
    await tester.drag(find.text('这里空空的'), const Offset(-260, 0));
    await tester.pumpAndSettle();
    expect(find.text('待办样本'), findsOneWidget);
    await tester.drag(find.text('待办样本'), const Offset(-260, 0));
    await tester.pumpAndSettle();
    expect(find.text('待办样本'), findsOneWidget);
    await tester.drag(find.text('待办样本'), const Offset(260, 0));
    await tester.pumpAndSettle();
    expect(find.text('这里空空的'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'incoming content follows the swipe direction in both directions',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(Brightness.light, ThemeStyle.clean),
          home: HomePage(state: state, onGoAccounts: () {}),
        ),
      );
      await tester.pumpAndSettle();
      await tester.drag(find.text('待办样本'), const Offset(-260, 0));
      await tester.pump();
      final start = tester.getTopLeft(find.text('提交样本')).dx;
      await tester.pump(const Duration(milliseconds: 130));
      final middle = tester.getTopLeft(find.text('提交样本')).dx;
      await tester.pumpAndSettle();
      final end = tester.getTopLeft(find.text('提交样本')).dx;
      expect(start, greaterThan(middle));
      expect(middle, greaterThan(end));

      await tester.drag(find.text('提交样本'), const Offset(260, 0));
      await tester.pump();
      final backStart = tester.getTopLeft(find.text('待办样本')).dx;
      await tester.pump(const Duration(milliseconds: 130));
      final backMiddle = tester.getTopLeft(find.text('待办样本')).dx;
      await tester.pumpAndSettle();
      final backEnd = tester.getTopLeft(find.text('待办样本')).dx;
      expect(backStart, lessThan(backMiddle));
      expect(backMiddle, lessThan(backEnd));
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('swiping reveals the selected filter on a narrow screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.light, ThemeStyle.clean),
        home: HomePage(state: state, onGoAccounts: () {}),
      ),
    );
    await tester.pumpAndSettle();
    for (final title in ['待办样本', '提交样本', '完成样本']) {
      await tester.drag(find.text(title), const Offset(-220, 0));
      await tester.pumpAndSettle();
    }
    final all = find.widgetWithText(TextButton, '全部');
    final sort = find.byTooltip('排序方式');
    expect(
      tester.getTopRight(all).dx,
      lessThanOrEqualTo(tester.getTopLeft(sort).dx),
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'list swipes keep the main page while header swipes change page',
    (tester) async {
      tester.view.physicalSize = const Size(420, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(Brightness.light, ThemeStyle.clean),
          home: MainShell(state: state),
        ),
      );
      await tester.pumpAndSettle();
      await tester.drag(find.text('待办样本'), const Offset(-260, 0));
      await tester.pumpAndSettle();
      expect(find.text('提交样本'), findsOneWidget);
      expect(
        tester
            .widget<ThemedNavigationBar>(find.byType(ThemedNavigationBar))
            .selectedIndex,
        0,
      );
      await tester.drag(find.byTooltip('同步作业'), const Offset(-320, 0));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<ThemedNavigationBar>(find.byType(ThemedNavigationBar))
            .selectedIndex,
        1,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'long press still offers a confirmed, recoverable manual delete',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(Brightness.light, ThemeStyle.clean),
          home: HomePage(state: state, onGoAccounts: () {}),
        ),
      );
      await tester.pumpAndSettle();
      await tester.longPress(find.text('待办样本'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();
      expect(find.text('删除这条作业？'), findsOneWidget);
      expect(Storage.homework().any((h) => h.id == 'todo'), isTrue);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(find.text('待办样本'), findsOneWidget);
      await tester.longPress(find.text('待办样本'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '删除'));
      await tester.pumpAndSettle();
      expect(Storage.homework().any((h) => h.id == 'todo'), isFalse);
      expect(LocalRecoveryStore.deleted().single.item.note, '保留备注');
      await tester.pumpWidget(const SizedBox());
    },
  );
}
