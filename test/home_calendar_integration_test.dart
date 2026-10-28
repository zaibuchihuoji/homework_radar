import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homework_radar/app_state.dart';
import 'package:homework_radar/main.dart' show buildTheme;
import 'package:homework_radar/models/homework.dart';
import 'package:homework_radar/pages/home_page.dart';
import 'package:homework_radar/pages/calendar_page.dart';
import 'package:homework_radar/services/storage.dart';
import 'package:homework_radar/ui/homework_date_bar.dart';
import 'package:homework_radar/ui/themed_navigation.dart';
import 'package:homework_radar/ui/tokens.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:table_calendar/table_calendar.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppState state;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Storage.init();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
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
    'date strip filters the list, expands, and restores undated homework',
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
      expect(find.text('今天的作业'), findsOneWidget);
      expect(find.text('无日期作业'), findsOneWidget);
      await tester.tap(find.byTooltip('展开月历'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('收起月历'), findsOneWidget);
      await tester.tap(find.byTooltip('选择今天'));
      await tester.pumpAndSettle();
      expect(find.text('今天的作业'), findsOneWidget);
      expect(find.text('其他日期作业'), findsNothing);
      expect(find.text('无日期作业'), findsNothing);
      await tester.tap(find.byTooltip('下个月'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('选择今天'));
      await tester.pumpAndSettle();
      expect(
        DateUtils.isSameDay(
          tester
              .widget<TableCalendar<HomeworkItem>>(
                find.byType(TableCalendar<HomeworkItem>),
              )
              .focusedDay,
          DateTime.now(),
        ),
        isTrue,
      );
      await tester.tap(find.text('全部作业'));
      await tester.pumpAndSettle();
      expect(find.text('无日期作业'), findsOneWidget);
      expect(jsonEncode(Storage.homeworkRowsForEdit()), before);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  test('bottom navigation keeps five independent destinations', () {
    expect(ThemedNavigationBar.labels, ['作业', '课表', '账号', '设置', '笔记']);
  });

  testWidgets(
    'date view includes another semester and keeps the status filter',
    (tester) async {
      tester.view.physicalSize = const Size(420, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final now = DateTime.now();
      final nextSemester = now.month >= 8
          ? DateTime(now.year + 1, 2, 4)
          : now.month == 1
          ? DateTime(now.year, 2, 4)
          : DateTime(now.year, 8, 4);
      state.homework = [
        ...state.homework,
        HomeworkItem(
          id: 'next',
          platform: PlatformKind.manual,
          course: '测试',
          title: '下学期待完成',
          status: HwStatus.todo,
          dueAt: nextSemester,
        ),
        HomeworkItem(
          id: 'next-done',
          platform: PlatformKind.manual,
          course: '测试',
          title: '下学期已完成',
          status: HwStatus.done,
          dueAt: nextSemester,
        ),
      ];
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(Brightness.light, ThemeStyle.clean),
          home: HomePage(state: state, onGoAccounts: () {}),
        ),
      );
      await tester.pumpAndSettle();
      tester
          .widget<HomeworkDateBar>(find.byType(HomeworkDateBar))
          .onDateSelected(nextSemester);
      await tester.pumpAndSettle();
      expect(find.text('下学期待完成'), findsOneWidget);
      expect(find.text('下学期已完成'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, '未完成'));
      await tester.pumpAndSettle();
      expect(find.text('下学期已完成'), findsNothing);
      tester
          .widget<HomeworkDateBar>(find.byType(HomeworkDateBar))
          .onDateSelected(nextSemester.add(const Duration(days: 1)));
      await tester.pumpAndSettle();
      tester
          .widget<HomeworkDateBar>(find.byType(HomeworkDateBar))
          .onDateSelected(nextSemester);
      await tester.pumpAndSettle();
      expect(find.text('下学期待完成'), findsOneWidget);
      expect(find.text('下学期已完成'), findsNothing);
      await tester.tap(find.text('完整日历'));
      await tester.pumpAndSettle();
      expect(find.byType(CalendarPage), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('下学期待完成'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final style in ThemeStyle.values) {
    testWidgets('${style.name}: date bar fits a narrow screen when expanded', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(Brightness.light, style),
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(320, 900),
              textScaler: TextScaler.linear(1.3),
            ),
            child: Scaffold(
              body: SingleChildScrollView(
                child: HomeworkDateBar(
                  homework: state.homework,
                  selectedDate: null,
                  onDateSelected: (_) {},
                  onOpenCalendar: () {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('展开月历'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('收起月历'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
