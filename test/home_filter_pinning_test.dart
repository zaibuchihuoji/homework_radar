import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homework_radar/app_state.dart';
import 'package:homework_radar/main.dart' show buildTheme;
import 'package:homework_radar/models/homework.dart';
import 'package:homework_radar/pages/home_page.dart';
import 'package:homework_radar/services/storage.dart';
import 'package:homework_radar/ui/tokens.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppState state;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('homework_radar/platform'),
          (_) async => null,
        );
    await Storage.init();
    final items = [
      for (final (status, title) in [
        (HwStatus.todo, '待办任务'),
        (HwStatus.submitted, '已交任务'),
        (HwStatus.done, '完成任务'),
      ])
        for (var i = 0; i < 40; i++)
          HomeworkItem(
            id: '${status.name}_$i',
            platform: PlatformKind.manual,
            course: '测试课程',
            title: '$title $i',
            status: status,
          ),
    ];
    await Storage.saveHomework(items);
    state = AppState()..homework = items;
  });
  tearDown(() => state.dispose());

  for (final style in ThemeStyle.values) {
    for (final brightness in [
      Brightness.light,
      if (style == ThemeStyle.clean || style == ThemeStyle.green)
        Brightness.dark,
    ]) {
      testWidgets(
        '${style.name}/${brightness.name}: filters pin below the safe area and remain usable',
        (t) async {
          t.view.physicalSize = const Size(320, 740);
          t.view.devicePixelRatio = 1;
          addTearDown(t.view.reset);
          final original = jsonEncode(Storage.homeworkRowsForEdit());
          await t.pumpWidget(
            MaterialApp(
              theme: buildTheme(brightness, style),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  padding: const EdgeInsets.only(top: 24),
                  textScaler: const TextScaler.linear(1.3),
                ),
                child: child!,
              ),
              home: HomePage(state: state, onGoAccounts: () {}),
            ),
          );
          await t.pumpAndSettle();
          final sort = find.byTooltip('排序方式');
          final initialY = t.getCenter(sort).dy;
          expect(initialY, greaterThan(90));
          await t.drag(find.byType(CustomScrollView), const Offset(0, -450));
          await t.pumpAndSettle();
          final pinnedY = t.getCenter(sort).dy;
          expect(t.getTopLeft(sort).dy, greaterThanOrEqualTo(24));
          expect(pinnedY, lessThan(85));
          await t.drag(find.byType(CustomScrollView), const Offset(0, -500));
          await t.pumpAndSettle();
          expect(t.getCenter(sort).dy, closeTo(pinnedY, .1));
          await t.tap(find.widgetWithText(TextButton, '已提交'));
          await t.pumpAndSettle();
          expect(find.textContaining('待办任务'), findsNothing);
          expect(find.textContaining('已交任务'), findsWidgets);
          await t.tap(sort);
          await t.pumpAndSettle();
          await t.tap(find.text('按课程分组'));
          await t.pumpAndSettle();
          expect(Storage.sortMode(), 'course');
          final tabs = find
              .ancestor(
                of: find.widgetWithText(TextButton, '已完成'),
                matching: find.byType(SingleChildScrollView),
              )
              .first;
          await t.drag(tabs, const Offset(-200, 0));
          await t.pumpAndSettle();
          await t.tap(find.widgetWithText(TextButton, '已完成'));
          await t.pumpAndSettle();
          expect(find.textContaining('已交任务'), findsNothing);
          expect(find.textContaining('完成任务'), findsWidgets);
          final scroll = t.state<ScrollableState>(
            find
                .descendant(
                  of: find.byType(CustomScrollView),
                  matching: find.byType(Scrollable),
                )
                .first,
          );
          scroll.position.jumpTo(0);
          await t.pumpAndSettle();
          expect(t.getCenter(sort).dy, closeTo(initialY, .1));
          expect(jsonEncode(Storage.homeworkRowsForEdit()), original);
          expect(t.takeException(), isNull);
          await t.pumpWidget(const SizedBox());
        },
      );
    }
  }
}
