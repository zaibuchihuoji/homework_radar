import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homework_radar/app_state.dart';
import 'package:homework_radar/main.dart';
import 'package:homework_radar/models/homework.dart';
import 'package:homework_radar/pages/home_page.dart';
import 'package:homework_radar/pages/settings_page.dart';
import 'package:homework_radar/services/storage.dart';
import 'package:homework_radar/ui/hw_card.dart';
import 'package:homework_radar/ui/tokens.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  testWidgets('overview counts only current semester unfinished work', (
    tester,
  ) async {
    final now = DateTime.now();
    final state = AppState()
      ..homework = [
        for (final status in HwStatus.values)
          HomeworkItem(
            id: status.name,
            platform: PlatformKind.manual,
            course: '高等数学',
            title: '任务 ${status.name}',
            status: status,
            dueAt: DateTime(now.year, now.month, now.day, 23, 59, 59),
          ),
        HomeworkItem(
          id: 'old',
          platform: PlatformKind.manual,
          course: '旧课程',
          title: '旧学期作业',
          status: HwStatus.todo,
          dueAt: DateTime(now.year - 2),
        ),
        HomeworkItem(
          id: 'no-date',
          platform: PlatformKind.manual,
          course: '英语',
          title: '阅读练习',
          status: HwStatus.todo,
        ),
      ];
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.light, ThemeStyle.clean),
        home: HomePage(state: state, onGoAccounts: () {}),
      ),
    );
    expect(find.bySemanticsLabel('待完成 3 项，今天截止 2 项'), findsOneWidget);
    await tester.tap(find.text('已完成'));
    await tester.pumpAndSettle();
    expect(find.text('任务 done'), findsOneWidget);
    expect(find.text('阅读练习'), findsNothing);
    expect(find.bySemanticsLabel('待完成 3 项，今天截止 2 项'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    semantics.dispose();
    state.dispose();
  });

  testWidgets('add action stays separated from navigation on a narrow phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(720, 1280);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final state = AppState();
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.light, ThemeStyle.clean),
        home: MainShell(state: state),
      ),
    );
    await tester.pumpAndSettle();
    final nav = find.byWidgetPredicate(
      (w) => w is Semantics && w.properties.label == '作业标签页',
    );
    expect(
      tester.getRect(find.byType(FloatingActionButton)).bottom,
      lessThanOrEqualTo(tester.getRect(nav).top - 12),
    );
    await tester.tap(find.byTooltip('添加作业'));
    await tester.pumpAndSettle();
    expect(find.text('添加作业'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    state.dispose();
  });

  testWidgets('appearance chooser exposes all themes and persists selection', (
    tester,
  ) async {
    final state = AppState();
    await tester.pumpWidget(
      ListenableBuilder(
        listenable: state,
        builder: (_, _) => MaterialApp(
          theme: buildTheme(Brightness.light, state.style),
          home: SettingsPage(state: state),
        ),
      ),
    );
    await tester.tap(find.text('外观与小组件'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('界面风格'));
    await tester.pumpAndSettle();
    for (final style in ThemeStyle.values) {
      expect(find.text(style.label).last, findsOneWidget);
    }
    await tester.ensureVisible(find.text('手账').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('手账').last);
    await tester.pumpAndSettle();
    expect(Storage.uiStyle(), 'journal');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    state.dispose();
  });

  testWidgets('long task text stays readable without layout overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(640, 1480);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final state = AppState()
      ..homework = [
        HomeworkItem(
          id: 'long',
          platform: PlatformKind.mooc,
          course: '一门课程名称特别长的课程',
          title: '这是一份需要较多文字才能描述清楚的作业标题，点击仍可查看完整内容',
          note: '备注也可能很长，需要交纸质报告和电子版本',
          score: 98.5,
          status: HwStatus.done,
        ),
      ];
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.light, ThemeStyle.clean),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(1.6)),
          child: child!,
        ),
        home: HomePage(state: state, onGoAccounts: () {}),
      ),
    );
    await tester.tap(find.text('已完成'));
    await tester.pumpAndSettle();
    expect(find.textContaining('98.5'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('搜索作业'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '不存在的作业');
    await tester.pumpAndSettle();
    expect(find.textContaining('没有匹配'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    state.dispose();
  });

  testWidgets('all retained styles still display title note status and score', (
    tester,
  ) async {
    final task = HomeworkItem(
      id: 'style',
      platform: PlatformKind.mooc,
      course: '高等数学',
      title: '积分练习',
      note: '带上计算过程',
      score: 95,
      status: HwStatus.submitted,
    );
    for (final style in ThemeStyle.values) {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(Brightness.light, style),
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(20),
              child: Builder(builder: (context) => buildHwCard(context, task)),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('积分练习'), findsOneWidget, reason: style.name);
      expect(find.text('带上计算过程'), findsOneWidget, reason: style.name);
      expect(find.textContaining('95'), findsOneWidget, reason: style.name);
      expect(tester.takeException(), isNull, reason: style.name);
    }
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('theme changes keep the selected page and navigation aligned', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(720, 1280);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final state = AppState();
    await tester.pumpWidget(
      ListenableBuilder(
        listenable: state,
        builder: (_, _) => MaterialApp(
          theme: buildTheme(Brightness.light, state.style),
          home: MainShell(state: state),
        ),
      ),
    );
    Finder tab(String label) => find.byWidgetPredicate(
      (w) => w is Semantics && w.properties.label == label,
    );
    await tester.tap(tab('设置标签页'));
    await tester.pumpAndSettle();
    await state.setStyle(ThemeStyle.morandi);
    await tester.pumpAndSettle();
    expect(tester.widget<Semantics>(tab('设置标签页')).properties.selected, isTrue);
    await tester.tap(tab('账号标签页'));
    await tester.pumpAndSettle();
    expect(tester.widget<Semantics>(tab('账号标签页')).properties.selected, isTrue);
    expect(
      tester.widget<PageView>(find.byType(PageView).first).controller!.page,
      3,
    );
    await tester.pumpWidget(const SizedBox());
    state.dispose();
  });
}
