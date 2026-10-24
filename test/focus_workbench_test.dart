import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:homework_radar/app_state.dart';
import 'package:homework_radar/main.dart' show buildTheme;
import 'package:homework_radar/models/homework.dart';
import 'package:homework_radar/pages/home_page.dart';
import 'package:homework_radar/pages/homework_edit_dialogs.dart';
import 'package:homework_radar/pages/homework_recognition_page.dart';
import 'package:homework_radar/pages/homework_recognition_review_page.dart';
import 'package:homework_radar/services/storage.dart';
import 'package:homework_radar/ui/tokens.dart';

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
        id: 'today1',
        platform: PlatformKind.manual,
        course: '数学',
        title: '今天的练习',
        dueAt: DateTime(n.year, n.month, n.day, 23, 59),
        note: '原备注',
      ),
      HomeworkItem(
        id: 'today2',
        platform: PlatformKind.mooc,
        course: '英语',
        title: '今天的阅读',
        dueAt: DateTime(n.year, n.month, n.day, 22),
      ),
      HomeworkItem(
        id: 'overdue',
        platform: PlatformKind.mooc,
        course: '数学',
        title: '昨天的练习',
        dueAt: DateTime(
          n.year,
          n.month,
          n.day,
        ).subtract(const Duration(hours: 1)),
      ),
      HomeworkItem(
        id: 'undated',
        platform: PlatformKind.manual,
        course: '英语',
        title: '未定时间的作业',
      ),
      HomeworkItem(
        id: 'submitted',
        platform: PlatformKind.chaoxing,
        course: '英语',
        title: '已提交的作业',
        status: HwStatus.submitted,
      ),
    ]);
    state = AppState();
    await state.loadLocal();
  });
  tearDown(() => state.dispose());
  Widget app(Widget home) => MaterialApp(
    theme: buildTheme(Brightness.light, ThemeStyle.clean),
    home: home,
  );

  testWidgets(
    'priority group retains overdue undated and submitted records without duplication',
    (t) async {
      t.view.physicalSize = const Size(420, 1400);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final before = jsonEncode(
        Storage.homework().map((h) => h.toJson()).toList(),
      );
      await t.pumpWidget(app(HomePage(state: state, onGoAccounts: () {})));
      final group = find.byKey(const ValueKey('focus_today'));
      expect(group, findsOneWidget);
      expect(
        find.descendant(of: group, matching: find.text('今天的练习')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: group, matching: find.text('今天的阅读')),
        findsOneWidget,
      );
      expect(find.text('今天的练习'), findsOneWidget);
      expect(find.text('昨天的练习'), findsOneWidget);
      expect(find.text('未定时间的作业'), findsOneWidget);
      await t.tap(find.text('全部'));
      await t.pumpAndSettle();
      expect(find.text('已提交的作业'), findsOneWidget);
      await t.tap(find.byTooltip('排序方式'));
      await t.pumpAndSettle();
      await t.tap(find.text('按课程分组'));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('focus_today')), findsNothing);
      expect(
        jsonEncode(Storage.homework().map((h) => h.toJson()).toList()),
        before,
      );
      await t.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'reading a screenshot requires review action and cancellation preserves pasted text',
    (t) async {
      await t.pumpWidget(
        app(
          HomeworkRecognitionPage(
            state: state,
            chooseImageText: () async => '【英语】阅读第五单元，明天交',
          ),
        ),
      );
      await t.tap(find.text('选择截图'));
      await t.pumpAndSettle();
      expect(find.byType(HomeworkRecognitionReviewPage), findsNothing);
      expect(find.byKey(const ValueKey('recognition_input')), findsOneWidget);
      expect(Storage.homework(), hasLength(5));
      await t.tap(find.text('识别并核对'));
      await t.pumpAndSettle();
      expect(find.byType(HomeworkRecognitionReviewPage), findsOneWidget);
      expect(find.textContaining('截止时间待确认'), findsOneWidget);
      Navigator.of(t.element(find.byType(HomeworkRecognitionReviewPage))).pop();
      await t.pumpAndSettle();
      expect(
        t
            .widget<TextField>(find.byKey(const ValueKey('recognition_input')))
            .controller!
            .text,
        contains('阅读第五单元'),
      );
      expect(Storage.homework().first.note, '原备注');
    },
  );
  testWidgets(
    'cancelled unreadable and failed images preserve the current draft',
    (t) async {
      var attempt = 0;
      await t.pumpWidget(
        app(
          HomeworkRecognitionPage(
            state: state,
            chooseImageText: () async {
              attempt++;
              if (attempt == 1) return null;
              if (attempt == 2) return '';
              throw const FormatException('Invalid screenshot');
            },
          ),
        ),
      );
      await t.enterText(
        find.byKey(const ValueKey('recognition_input')),
        'Original draft',
      );
      for (var i = 0; i < 3; i++) {
        await t.tap(find.text('选择截图'));
        await t.pumpAndSettle();
        expect(
          t
              .widget<TextField>(
                find.byKey(const ValueKey('recognition_input')),
              )
              .controller!
              .text,
          'Original draft',
        );
        expect(find.byType(HomeworkRecognitionReviewPage), findsNothing);
      }
      expect(Storage.homework(), hasLength(5));
    },
  );
  testWidgets('sunny priority and fixed detail actions fit narrow large text', (
    t,
  ) async {
    t.view.physicalSize = const Size(320, 740);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final title =
        'A long homework title that needs to wrap without hiding its deadline';
    final n = DateTime.now();
    await Storage.saveHomework([
      ...Storage.homework(),
      HomeworkItem(
        id: 'long',
        platform: PlatformKind.manual,
        course: 'A long course name',
        title: title,
        dueAt: DateTime(n.year, n.month, n.day, 23, 58),
      ),
    ]);
    await state.loadLocal();
    await t.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.light, ThemeStyle.clean),
        builder: (c, child) => MediaQuery(
          data: MediaQuery.of(c)
              .copyWith(textScaler: const TextScaler.linear(1.6)),
          child: child!,
        ),
        home: HomePage(state: state, onGoAccounts: () {}),
      ),
    );
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    await t.scrollUntilVisible(
      find.text(title),
      200,
      scrollable: find
          .descendant(
            of: find.byType(CustomScrollView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await t.pumpAndSettle();
    await t.tap(find.text(title));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    expect(t.getCenter(find.text('标记完成')).dy, lessThan(740));
    expect(t.getCenter(find.text('编辑作业')).dy, lessThan(740));
    expect(Storage.homework().first.note, '原备注');
    await t.pumpWidget(const SizedBox());
  });
  testWidgets('manual save stays entirely visible above keyboard', (t) async {
    t.view.physicalSize = const Size(400, 890);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await Storage.saveHomework([
      ...Storage.homework(),
      for (final course in ['计算机网络A', '软件工程', '高等数学', '移动应用程序设计'])
        HomeworkItem(
          id: course,
          platform: PlatformKind.manual,
          course: course,
          title: '保留原课程',
        ),
    ]);
    await state.loadLocal();
    await t.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.light, ThemeStyle.clean),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(1.4)),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showManualHomeworkEditor(
                context,
                state,
                edit: state.homework.first,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    for (final keyboard in [0.0, 280.0]) {
      t.view.viewInsets = FakeViewPadding(bottom: keyboard);
      await t.pumpAndSettle();
      final dialog = t.getRect(find.byType(Dialog));
      final save = t.getRect(find.widgetWithText(FilledButton, '保存'));
      expect(save.bottom, lessThanOrEqualTo(dialog.bottom - 12));
      expect(save.top, greaterThan(dialog.top));
      expect(save.bottom, lessThan(890 - keyboard));
      expect(t.takeException(), isNull);
    }
    await t.tap(find.byTooltip('取消'));
    await t.pumpAndSettle();
    await t.pump(const Duration(milliseconds: 600));
    expect(Storage.homework().first.note, '原备注');
  });
}
