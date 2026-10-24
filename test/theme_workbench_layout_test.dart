import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homework_radar/app_state.dart';
import 'package:homework_radar/main.dart' show buildTheme;
import 'package:homework_radar/models/course.dart';
import 'package:homework_radar/models/homework.dart';
import 'package:homework_radar/pages/accounts_page.dart';
import 'package:homework_radar/pages/calendar_page.dart';
import 'package:homework_radar/pages/detail_page.dart';
import 'package:homework_radar/pages/home_page.dart';
import 'package:homework_radar/pages/settings_page.dart';
import 'package:homework_radar/pages/timetable_page.dart';
import 'package:homework_radar/services/storage.dart';
import 'package:homework_radar/ui/focus_account_row.dart';
import 'package:homework_radar/ui/focus_parts.dart';
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
    final n = DateTime.now();
    await Storage.saveHomework([
      HomeworkItem(
        id: 'today',
        platform: PlatformKind.manual,
        course: '数学',
        title: '今天的练习',
        note: '旧备注',
        dueAt: DateTime(n.year, n.month, n.day, 23, 59),
      ),
      HomeworkItem(
        id: 'undated',
        platform: PlatformKind.manual,
        course: '英语',
        title: '未定时间的作业',
      ),
    ]);
    await Storage.saveCourses([
      Course(
        id: 'course',
        name: '测试课程',
        weekday: n.weekday,
        startSection: 1,
        endSection: 2,
        weeks: [1],
        room: '教室402',
      ),
    ]);
    await Storage.saveSemesterStart(
      DateUtils.dateOnly(n).subtract(Duration(days: n.weekday - 1)),
    );
    state = AppState();
    await state.loadLocal();
  });
  tearDown(() => state.dispose());

  for (final style in ThemeStyle.values) {
    testWidgets(
      '${style.name}: shared workbench hierarchy retains theme and data',
      (t) async {
        t.view.physicalSize = const Size(360, 920);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.reset);
        final before = jsonEncode([
          Storage.homework().map((h) => h.toJson()).toList(),
          Storage.courses().map((c) => c.toJson()).toList(),
          Storage.hiddenItems(),
        ]);
        Future<void> show(Widget page) async {
          await t.pumpWidget(const SizedBox());
          await t.pumpWidget(
            MaterialApp(
              theme: buildTheme(Brightness.light, style),
              builder: (c, child) => MediaQuery(
                data: MediaQuery.of(c)
                    .copyWith(textScaler: const TextScaler.linear(1.3)),
                child: child!,
              ),
              home: page,
            ),
          );
          await t.pumpAndSettle();
          final actual = paletteOf(t.element(find.byType(Scaffold).first));
          expect(
            actual.accentFill,
            stylePalette(style, Brightness.light).accentFill,
          );
          expect(t.takeException(), isNull);
        }

        await show(HomePage(state: state, onGoAccounts: () {}));
        expect(find.byType(FloatingActionButton), findsNothing);
        expect(find.byTooltip('添加作业'), findsOneWidget);
        expect(find.byKey(const ValueKey('focus_today')), findsOneWidget);
        final sort = t.getCenter(find.byTooltip('排序方式'));
        expect(
          (sort.dy - t.getCenter(find.text('未完成').first).dy).abs(),
          lessThan(25),
        );
        await show(HomeworkDetailPage(homeworkId: 'today', state: state));
        expect(find.byTooltip('更多作业操作'), findsOneWidget);
        expect(
          t.widget<Scaffold>(find.byType(Scaffold).first).bottomNavigationBar,
          isNotNull,
        );
        final action = find.widgetWithText(FilledButton, '标记完成');
        final buttonContext = t.element(action);
        final background = FilledButtonTheme.of(buttonContext)
            .style!
            .backgroundColor!
            .resolve({})!;
        final icon = t.widget<Icon>(
          find.descendant(
            of: action,
            matching: find.byIcon(Icons.check_circle_outline_rounded),
          ),
        );
        final a = background.computeLuminance(),
            b = icon.color!.computeLuminance();
        expect(
          ((a > b ? a : b) + .05) / ((a < b ? a : b) + .05),
          greaterThanOrEqualTo(3),
          reason: 'completion icon remains visible on the theme button fill',
        );
        await show(TimetablePage(state: state));
        expect(find.byType(FocusViewSwitch), findsOneWidget);
        await t.tap(find.text('当日清单'));
        await t.pumpAndSettle();
        expect(find.text('测试课程'), findsOneWidget);
        await t.tap(find.text('测试课程'));
        await t.pumpAndSettle();
        expect(find.byTooltip('关闭课程详情'), findsOneWidget);
        expect(find.text('编辑课程'), findsOneWidget);
        await t.tap(find.byTooltip('关闭课程详情'));
        await t.pumpAndSettle();
        await show(CalendarPage(state: state));
        expect(find.byTooltip('返回今天'), findsOneWidget);
        expect(find.byType(FocusSummary), findsOneWidget);
        await show(AccountsPage(state: state));
        expect(find.byType(FocusAccountRow), findsNWidgets(6));
        await t.tap(find.byTooltip('学习通账号详情'));
        await t.pumpAndSettle();
        expect(find.text('登录学习通'), findsOneWidget);
        await t.tap(find.byTooltip('关闭账号详情'));
        await t.pumpAndSettle();
        await show(SettingsPage(state: state));
        expect(find.byType(FocusSummary), findsOneWidget);
        expect(find.text('学习偏好'), findsOneWidget);
        await t.tap(find.text('同步与后台'));
        await t.pumpAndSettle();
        expect(find.byType(FocusSummary), findsOneWidget);
        expect(t.takeException(), isNull);
        expect(
          jsonEncode([
            Storage.homework().map((h) => h.toJson()).toList(),
            Storage.courses().map((c) => c.toJson()).toList(),
            Storage.hiddenItems(),
          ]),
          before,
        );
        await t.pumpWidget(const SizedBox());
      },
    );
  }
}
