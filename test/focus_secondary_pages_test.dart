import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:homework_radar/app_state.dart';
import 'package:homework_radar/main.dart' show buildTheme;
import 'package:homework_radar/models/course.dart';
import 'package:homework_radar/models/homework.dart';
import 'package:homework_radar/pages/accounts_page.dart';
import 'package:homework_radar/pages/calendar_page.dart';
import 'package:homework_radar/pages/timetable_page.dart';
import 'package:homework_radar/pages/jw_text_import_page.dart';
import 'package:homework_radar/pages/jw_ocr_import_page.dart';
import 'package:homework_radar/pages/jw_xls_import_page.dart';
import 'package:homework_radar/pages/jw_preview_page.dart';
import 'package:homework_radar/services/storage.dart';
import 'package:homework_radar/ui/tokens.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('homework_radar/platform'),
          (_) async => null,
        );
    await Storage.init();
  });
  Widget app(Widget home, {double scale = 1}) => MaterialApp(
    theme: buildTheme(Brightness.light, ThemeStyle.clean),
    builder: (c, child) => MediaQuery(
      data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)),
      child: child!,
    ),
    home: home,
  );

  testWidgets('day agenda retains overlapping and section sixteen courses', (
    t,
  ) async {
    t.view.physicalSize = const Size(390, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final n = DateTime.now();
    await Storage.saveSemesterStart(
      DateUtils.dateOnly(n).subtract(Duration(days: n.weekday - 1)),
    );
    final courses = [
      for (final (id, start, end) in [
        ('重叠A', 1, 3),
        ('重叠B', 2, 4),
        ('晚课', 15, 16),
      ])
        Course(
          id: id,
          name: id,
          weekday: n.weekday,
          startSection: start,
          endSection: end,
          weeks: [1],
          room: '教室402',
        ),
    ];
    await Storage.saveCourses(courses);
    final state = AppState()..courses = courses;
    final before = jsonEncode(
      Storage.courses().map((c) => c.toJson()).toList(),
    );
    await t.pumpWidget(app(TimetablePage(state: state)));
    await t.tap(find.text('当日清单'));
    await t.pumpAndSettle();
    for (final title in ['重叠A', '重叠B', '晚课']) {
      await t.scrollUntilVisible(
        find.text(title),
        150,
        scrollable: find.byType(Scrollable).last,
      );
      expect(find.text(title), findsOneWidget);
    }
    await t.tap(find.text('晚课'));
    await t.pumpAndSettle();
    expect(find.textContaining('第15–16节'), findsWidgets);
    expect(find.textContaining('时刻待配置'), findsWidgets);
    expect(find.text('编辑课程'), findsOneWidget);
    await t.tap(find.byTooltip('关闭课程详情'));
    await t.pumpAndSettle();
    expect(
      jsonEncode(Storage.courses().map((c) => c.toJson()).toList()),
      before,
    );
    await t.pumpWidget(const SizedBox());
    state.dispose();
  });

  testWidgets(
    'account details expose connection actions without changing records',
    (t) async {
      t.view.physicalSize = const Size(320, 780);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final state = AppState();
      await Storage.saveHomework([
        HomeworkItem(
          id: 'keep',
          platform: PlatformKind.manual,
          course: '课程',
          title: '旧作业',
          note: '原备注',
        ),
      ]);
      await t.pumpWidget(app(AccountsPage(state: state), scale: 1.4));
      await t.tap(find.byTooltip('学习通账号详情'));
      await t.pumpAndSettle();
      expect(find.text('登录学习通'), findsOneWidget);
      await t.tap(find.byTooltip('关闭账号详情'));
      await t.pumpAndSettle();
      expect(Storage.homework().single.note, '原备注');
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      state.dispose();
    },
  );

  testWidgets('calendar today action preserves all selected-date statuses', (
    t,
  ) async {
    final n = DateTime.now();
    final state = AppState()
      ..homework = [
        for (final status in HwStatus.values)
          HomeworkItem(
            id: status.name,
            platform: PlatformKind.manual,
            course: '数学',
            title: '作业${status.name}',
            status: status,
            dueAt: DateTime(n.year, n.month, n.day, 22),
          ),
      ];
    await t.pumpWidget(app(CalendarPage(state: state)));
    await t.pumpAndSettle();
    await t.tap(find.byTooltip('返回今天'));
    await t.pumpAndSettle();
    for (final h in state.homework) {
      await t.scrollUntilVisible(
        find.text(h.title),
        150,
        scrollable: find
            .descendant(
              of: find.byType(ListView).first,
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(find.text(h.title), findsOneWidget);
    }
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
    state.dispose();
  });

  testWidgets(
    'course import screens fit large text and preview cancellation keeps courses',
    (t) async {
      t.view.physicalSize = const Size(320, 780);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final old = Course(
        id: 'old',
        name: '原课程',
        weekday: 1,
        startSection: 1,
        endSection: 2,
        weeks: [1],
      );
      await Storage.saveCourses([old]);
      final state = AppState()..courses = [old];
      for (final screen in [
        JwOcrImportPage(state: state),
        JwXlsImportPage(state: state),
      ]) {
        await t.pumpWidget(app(screen, scale: 1.4));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
      }
      await t.pumpWidget(app(JwTextImportPage(state: state), scale: 1.4));
      await t.enterText(find.byType(TextField), '周一 1-2节 高等数学 张老师 1-16周 A101');
      t.view.viewInsets = const FakeViewPadding(bottom: 260);
      await t.pumpAndSettle();
      await t.scrollUntilVisible(
        find.text('解析并预览'),
        180,
        scrollable: find
            .descendant(
              of: find.byType(ListView).first,
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await t.pumpAndSettle();
      await t.tap(find.text('解析并预览'));
      await t.pumpAndSettle();
      expect(find.byType(JwPreviewPage), findsOneWidget);
      Navigator.of(t.element(find.byType(JwPreviewPage))).pop();
      await t.pumpAndSettle();
      expect(Storage.courses().single.id, 'old');
      expect(state.courses.single.name, '原课程');
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      state.dispose();
    },
  );
}
