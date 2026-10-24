import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homework_radar/app_state.dart';
import 'package:homework_radar/main.dart' show buildTheme;
import 'package:homework_radar/models/course.dart';
import 'package:homework_radar/pages/timetable_page.dart';
import 'package:homework_radar/services/storage.dart';
import 'package:homework_radar/ui/tokens.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('homework_radar/platform'),
          (_) async => null,
        );
    await Storage.init();
    final now = DateTime.now();
    await Storage.saveSemesterStart(
      DateTime(
        now.year,
        now.month,
        now.day,
      ).subtract(Duration(days: now.weekday - 1)),
    );
  });

  for (final style in ThemeStyle.values.where(
    (s) => !stylePalette(s, Brightness.light).clean,
  )) {
    testWidgets('${style.name}: empty timetable keeps its entry actions', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final state = AppState();
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(Brightness.light, style),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.4)),
            child: child!,
          ),
          home: TimetablePage(state: state),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.widgetWithText(FilledButton, '导入教务课表'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, '手动添加课程'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      state.dispose();
    });

    testWidgets('${style.name}: narrow timetable preserves weekly actions', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final state = AppState()
        ..courses = [
          Course(
            id: 'manual_one',
            name: '主题课程',
            room: '教学楼301',
            weekday: 1,
            startSection: 1,
            endSection: 2,
            weeks: [1, 2],
          ),
          Course(
            id: 'manual_two',
            name: '隔周课程',
            weekday: 2,
            startSection: 3,
            endSection: 4,
            weeks: [2],
          ),
          // Multiple meetings of one subject are still one course in the
          // selected-week summary, and a non-week course is not counted.
          Course(
            id: 'manual_repeat',
            name: '主题课程',
            weekday: 3,
            startSection: 5,
            endSection: 6,
            weeks: [1, 2],
          ),
        ];
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(Brightness.light, style),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.4)),
            child: child!,
          ),
          home: TimetablePage(state: state),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('1 门课程'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('主题课程').first);
      await tester.pumpAndSettle();
      expect(find.text('教学楼301'), findsWidgets);
      expect(find.text('编辑课程'), findsOneWidget);
      await tester.tapAt(const Offset(8, 100));
      await tester.pumpAndSettle();
      await tester.longPress(find.text('主题课程').first);
      await tester.pumpAndSettle();
      expect(find.text('课程颜色 · 主题课程'), findsOneWidget);
      await tester.tapAt(const Offset(8, 100));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('下一周'));
      await tester.pumpAndSettle();
      expect(find.text('第 2 周'), findsOneWidget);
      expect(find.text('2 门课程'), findsOneWidget);
      expect(find.text('回到本周'), findsOneWidget);
      await tester.tap(find.text('回到本周'));
      await tester.pumpAndSettle();
      expect(find.text('第 1 周'), findsOneWidget);
      await tester.drag(find.byType(PageView), const Offset(-270, 0));
      await tester.pumpAndSettle();
      expect(find.text('第 2 周'), findsOneWidget);
      await tester.tap(find.byTooltip('上一周'));
      await tester.pumpAndSettle();
      expect(find.text('第 1 周'), findsOneWidget);

      await tester.tap(find.byTooltip('更多'));
      await tester.pumpAndSettle();
      expect(find.text('粘贴文本导入'), findsOneWidget);
      expect(find.text('设置开学日期（周次）'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      state.dispose();
    });
  }
}
