import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homework_radar/app_state.dart';
import 'package:homework_radar/main.dart' show buildTheme;
import 'package:homework_radar/models/homework.dart';
import 'package:homework_radar/pages/calendar_page.dart';
import 'package:homework_radar/pages/home_page.dart';
import 'package:homework_radar/services/storage.dart';
import 'package:homework_radar/ui/tokens.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:table_calendar/table_calendar.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppState state;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Storage.init();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('homework_radar/platform'),
          (_) async => null,
        );
    final today = DateUtils.dateOnly(DateTime.now());
    final rows = [
      HomeworkItem(
        id: 'today',
        platform: PlatformKind.manual,
        course: '数学',
        title: '今天的作业',
        status: HwStatus.todo,
        dueAt: today.add(const Duration(hours: 12)),
        note: '保留备注',
      ),
      HomeworkItem(
        id: 'today-done',
        platform: PlatformKind.manual,
        course: '英语',
        title: '今天已完成',
        status: HwStatus.done,
        dueAt: today.add(const Duration(hours: 13)),
      ),
      HomeworkItem(
        id: 'other',
        platform: PlatformKind.manual,
        course: '数学',
        title: '其他日期作业',
        status: HwStatus.todo,
        dueAt: today.add(const Duration(days: 2, hours: 12)),
      ),
      HomeworkItem(
        id: 'undated',
        platform: PlatformKind.manual,
        course: '数学',
        title: '无日期作业',
        status: HwStatus.todo,
      ),
    ];
    await Storage.saveHomework(rows);
    state = AppState()..homework = rows;
  });
  tearDown(() => state.dispose());

  testWidgets(
    'calendar entry keeps home clear and transfers an explicit date filter',
    (tester) async {
      tester.view.physicalSize = const Size(420, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final before = jsonEncode(Storage.homeworkRowsForEdit());
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(Brightness.light, ThemeStyle.clean),
          home: HomePage(state: state, onGoAccounts: () {}),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(TableCalendar<HomeworkItem>), findsNothing);
      expect(find.text('今天的作业'), findsOneWidget);
      expect(find.text('无日期作业'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('home-calendar-entry')));
      await tester.pumpAndSettle();
      expect(find.byType(CalendarPage), findsOneWidget);
      expect(
        tester
            .widget<TableCalendar<HomeworkItem>>(
              find.byType(TableCalendar<HomeworkItem>),
            )
            .calendarFormat,
        CalendarFormat.month,
      );
      await tester.tap(find.byTooltip('切换到周视图'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TableCalendar<HomeworkItem>>(
              find.byType(TableCalendar<HomeworkItem>),
            )
            .calendarFormat,
        CalendarFormat.week,
      );
      expect(find.textContaining('本月 '), findsNWidgets(2));
      final beforeWeek = DateUtils.dateOnly(
        tester
            .widget<TableCalendar<HomeworkItem>>(
              find.byType(TableCalendar<HomeworkItem>),
            )
            .focusedDay,
      );
      await tester.tap(find.byTooltip('下一周'));
      await tester.pumpAndSettle();
      final afterWeek = DateUtils.dateOnly(
        tester
            .widget<TableCalendar<HomeworkItem>>(
              find.byType(TableCalendar<HomeworkItem>),
            )
            .focusedDay,
      );
      expect(afterWeek.difference(beforeWeek).inDays, 7);
      await tester.tap(find.byTooltip('返回今天'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('在作业列表中查看'));
      await tester.tap(find.text('在作业列表中查看'));
      await tester.pumpAndSettle();
      expect(find.byType(CalendarPage), findsNothing);
      expect(find.text('清除日期'), findsOneWidget);
      expect(find.text('今天的作业'), findsOneWidget);
      expect(find.text('今天已完成'), findsOneWidget);
      expect(find.text('其他日期作业'), findsNothing);
      expect(find.text('无日期作业'), findsNothing);
      await tester.tap(find.widgetWithText(TextButton, '未完成'));
      await tester.pumpAndSettle();
      expect(find.text('今天已完成'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('home-calendar-entry')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('在作业列表中查看'));
      await tester.tap(find.text('在作业列表中查看'));
      await tester.pumpAndSettle();
      expect(find.text('今天已完成'), findsNothing);
      await tester.tap(find.text('清除日期'));
      await tester.pumpAndSettle();
      expect(find.text('无日期作业'), findsOneWidget);
      expect(jsonEncode(Storage.homeworkRowsForEdit()), before);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'calendar date filtering retains work from a different semester',
    (tester) async {
      tester.view.physicalSize = const Size(420, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final now = DateTime.now();
      final nextSemester = now.month >= 8
          ? DateTime(now.year + 1, 2, 4)
          : now.month == 1
          ? DateTime(now.year, 2, 4)
          : DateTime(now.year, 8, 4);
      final task = HomeworkItem(
        id: 'next',
        platform: PlatformKind.manual,
        course: '测试',
        title: '下学期的作业',
        status: HwStatus.todo,
        dueAt: nextSemester,
      );
      state.homework = [...state.homework, task];
      await Storage.saveHomework(state.homework);
      final before = jsonEncode(Storage.homeworkRowsForEdit());
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(Brightness.light, ThemeStyle.clean),
          home: HomePage(state: state, onGoAccounts: () {}),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('下学期的作业'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('home-calendar-entry')));
      await tester.pumpAndSettle();
      final months =
          (nextSemester.year - now.year) * 12 + nextSemester.month - now.month;
      for (var i = 0; i < months; i++) {
        await tester.tap(find.byTooltip('下个月'));
        await tester.pumpAndSettle();
      }
      final day = find.descendant(
        of: find.byType(TableCalendar<HomeworkItem>),
        matching: find.text('${nextSemester.day}'),
      );
      await tester.ensureVisible(day);
      await tester.tap(day);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('在作业列表中查看'));
      await tester.tap(find.text('在作业列表中查看'));
      await tester.pumpAndSettle();
      expect(find.text('下学期的作业'), findsOneWidget);
      expect(find.text('清除日期'), findsOneWidget);
      expect(jsonEncode(Storage.homeworkRowsForEdit()), before);
      await tester.tap(find.text('清除日期'));
      await tester.pumpAndSettle();
      expect(find.text('下学期的作业'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('active date filter stays visible while scrolling the list', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(420, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final today = DateUtils.dateOnly(DateTime.now())
        .add(const Duration(hours: 20));
    state.homework = [
      for (var i = 0; i < 20; i++)
        HomeworkItem(
          id: 'long-$i',
          platform: PlatformKind.manual,
          course: '测试',
          title: '练习$i',
          status: HwStatus.todo,
          dueAt: today,
        ),
    ];
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.light, ThemeStyle.clean),
        home: HomePage(state: state, onGoAccounts: () {}),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('home-calendar-entry')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('在作业列表中查看'));
    await tester.tap(find.text('在作业列表中查看'));
    await tester.pumpAndSettle();
    await tester.drag(
      find.byType(CustomScrollView).first,
      const Offset(0, -500),
    );
    await tester.pumpAndSettle();
    expect(find.text('清除日期'), findsOneWidget);
    expect(tester.getTopLeft(find.text('清除日期')).dy, lessThan(160));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  for (final style in ThemeStyle.values) {
    testWidgets(
      '${style.name}: compact calendar entry and week view fit narrow screens',
      (tester) async {
        tester.view.physicalSize = const Size(320, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          MaterialApp(
            theme: buildTheme(Brightness.light, style),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(1.3)),
              child: child!,
            ),
            home: HomePage(state: state, onGoAccounts: () {}),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(TableCalendar<HomeworkItem>), findsNothing);
        await tester.tap(find.byKey(const ValueKey('home-calendar-entry')));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('切换到周视图'));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<TableCalendar<HomeworkItem>>(
                find.byType(TableCalendar<HomeworkItem>),
              )
              .calendarFormat,
          CalendarFormat.week,
        );
        await tester.ensureVisible(find.text('在作业列表中查看'));
        await tester.tap(find.text('在作业列表中查看'));
        await tester.pumpAndSettle();
        expect(find.text('清除日期'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
