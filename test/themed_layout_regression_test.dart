import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homework_radar/app_state.dart';
import 'package:homework_radar/main.dart';
import 'package:homework_radar/models/homework.dart';
import 'package:homework_radar/pages/home_page.dart';
import 'package:homework_radar/pages/detail_page.dart';
import 'package:homework_radar/services/storage.dart';
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

  test('secondary text remains legible on every theme card', () {
    for (final style in ThemeStyle.values) {
      final p = stylePalette(style, Brightness.light);
      final a = p.ink2.computeLuminance();
      final b = p.card.computeLuminance();
      final contrast = ((a > b ? a : b) + 0.05) / ((a < b ? a : b) + 0.05);
      expect(contrast, greaterThanOrEqualTo(4.5), reason: style.name);
    }
  });

  for (final style in ThemeStyle.values.where((s) => s != ThemeStyle.clean)) {
    testWidgets('${style.name}: detail metadata wraps at enlarged text sizes', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(640, 1480);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await Storage.saveHomework([
        HomeworkItem(
          id: 'detail',
          platform: PlatformKind.mooc,
          course: '一门课程名称特别长的课程',
          title: '完整的作业标题和说明',
          dueAt: DateTime(2026, 12, 25, 23, 59),
          status: HwStatus.submitted,
          score: 98.5,
        ),
      ]);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(Brightness.light, style),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.6)),
            child: child!,
          ),
          home: const HomeworkDetailPage(homeworkId: 'detail'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('98.5 分'), findsOneWidget);
      expect(find.text('中国大学MOOC'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
    testWidgets(
      '${style.name}: overview and filters keep the same task semantics',
      (tester) async {
        tester.view.physicalSize = const Size(640, 1480);
        tester.view.devicePixelRatio = 2;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final now = DateTime.now();
        final state = AppState()
          ..homework = [
            HomeworkItem(
              id: 'todo',
              platform: PlatformKind.mooc,
              course: '一门名称特别长的测试课程',
              title: '需要完整说明要求的阅读与写作练习',
              note: '请在作业中保留计算过程和引用出处',
              dueAt: DateTime(now.year, now.month, now.day, 23, 59, 59),
              status: HwStatus.todo,
            ),
            HomeworkItem(
              id: 'submitted',
              platform: PlatformKind.mooc,
              course: '测试',
              title: '已经提交的练习',
              status: HwStatus.submitted,
              score: 95,
            ),
            HomeworkItem(
              id: 'done',
              platform: PlatformKind.manual,
              course: '测试',
              title: '已完成的练习',
              status: HwStatus.done,
            ),
          ];
        final semantics = tester.ensureSemantics();
        await tester.pumpWidget(
          MaterialApp(
            theme: buildTheme(Brightness.light, style),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(1.6)),
              child: child!,
            ),
            home: HomePage(
              key: ValueKey(style),
              state: state,
              onGoAccounts: () {},
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.bySemanticsLabel('待完成 1 项，今天截止 1 项'), findsOneWidget);
        expect(find.text('需要完整说明要求的阅读与写作练习'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('已提交'));
        await tester.pumpAndSettle();
        expect(find.text('已经提交的练习'), findsOneWidget);
        expect(find.textContaining('95'), findsOneWidget);
        expect(find.text('已完成的练习'), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        semantics.dispose();
        state.dispose();
      },
    );

    testWidgets(
      '${style.name}: navigation reserves its own space above the system gesture area',
      (tester) async {
        tester.view.physicalSize = const Size(720, 1280);
        tester.view.devicePixelRatio = 2;
        tester.view.padding = const FakeViewPadding(top: 24, bottom: 24);
        tester.view.viewPadding = const FakeViewPadding(top: 24, bottom: 24);
        addTearDown(tester.view.reset);
        final state = AppState();
        await tester.pumpWidget(
          MaterialApp(
            theme: buildTheme(Brightness.light, style),
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
        final settings = find.byWidgetPredicate(
          (w) => w is Semantics && w.properties.label == '设置标签页',
        );
        await tester.tap(settings);
        await tester.pumpAndSettle();
        expect(tester.widget<Semantics>(settings).properties.selected, isTrue);
        expect(find.text('界面风格'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        state.dispose();
      },
    );
  }
}
