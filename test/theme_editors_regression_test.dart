import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:homework_radar/app_state.dart';
import 'package:homework_radar/main.dart' show buildTheme;
import 'package:homework_radar/models/course.dart';
import 'package:homework_radar/models/homework.dart';
import 'package:homework_radar/pages/course_edit_sheet.dart';
import 'package:homework_radar/pages/home_page.dart';
import 'package:homework_radar/services/storage.dart';
import 'package:homework_radar/ui/tokens.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget harness(Widget child, ThemeStyle style, {double scale = 1}) =>
    MaterialApp(
      theme: buildTheme(Brightness.light, style),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: child,
    );

Future<void> pressSave(WidgetTester tester, String label) async {
  var done = false;
  Object? failure;
  await tester.runAsync(() async {
    final dynamic action = tester
        .widget<FilledButton>(find.widgetWithText(FilledButton, label))
        .onPressed!;
    final dynamic result = action();
    if (result is Future) {
      result.then(
        (_) => done = true,
        onError: (Object error, StackTrace stack) {
          failure = error;
          done = true;
        },
      );
    } else {
      done = true;
    }
  });
  // Native-channel completions and widget microtasks belong to different
  // clocks; drain both before the next route or theme owns the shared queue.
  for (var i = 0; i < 100 && !done; i++) {
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 1)),
    );
  }
  expect(failure, isNull);
  expect(done, isTrue, reason: 'save did not finish');
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  AndroidFlutterLocalNotificationsPlugin.registerWith();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('homework_radar/platform'),
          (_) async => null,
        );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('dexterous.com/flutter/local_notifications'),
          (call) async => call.method == 'pendingNotificationRequests'
              ? <Map<String, Object?>>[]
              : true,
        );
    await Storage.init();
  });

  testWidgets(
    'course editor remains usable at 320dp with large text and keyboard',
    (tester) async {
      tester.view.physicalSize = const Size(320, 740);
      tester.view.devicePixelRatio = 1;
      tester.view.viewInsets = const FakeViewPadding(bottom: 260);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        harness(
          Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => const CourseEditSheet().show(context),
                child: const Text('open'),
              ),
            ),
          ),
          ThemeStyle.clean,
          scale: 1.4,
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.enterText(find.byType(TextField).first, '晚间课程');
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('添加到课表'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('添加到课表'));
      await tester.pumpAndSettle();
      expect(find.text('添加课程'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'homework date and time cancellation preserves the previous deadline',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final state = AppState();
      await tester.pumpWidget(
        harness(
          AnimatedBuilder(
            animation: state,
            builder: (context, _) =>
                HomePage(state: state, onGoAccounts: () {}),
          ),
          ThemeStyle.clean,
        ),
      );
      await tester.tap(find.byTooltip('添加作业'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('手动添加'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).at(1), '时间测试');
      await tester.pumpAndSettle();
      Future<void> chooseDate() async {
        await tester.ensureVisible(find.text('选择时间'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('选择时间'));
        await tester.pumpAndSettle();
      }

      await chooseDate();
      expect(find.byType(DatePickerDialog), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('未设置截止时间'), findsOneWidget);
      await chooseDate();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(find.byType(TimePickerDialog), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('未设置截止时间'), findsOneWidget);
      await chooseDate();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(find.text('未设置截止时间'), findsNothing);
      final beforeCancel = tester
          .widget<Text>(find.textContaining('截止时间：').first)
          .data;
      await chooseDate();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<Text>(find.textContaining('截止时间：').first).data,
        beforeCancel,
      );
      await tester.tap(find.byTooltip('清除截止时间'));
      await tester.pumpAndSettle();
      expect(find.text('未设置截止时间'), findsOneWidget);
      await tester.ensureVisible(find.widgetWithText(FilledButton, '添加'));
      await tester.pumpAndSettle();
      await pressSave(tester, '添加');
      expect(Storage.homework().single.dueAt, isNull);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
      state.dispose();
    },
  );

  for (final style in ThemeStyle.values) {
    testWidgets(
      '${style.name}: course create, validate, edit and cancel preserve identity',
      (tester) async {
        tester.view.physicalSize = const Size(320, 740);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        Course? editing;
        Course? result;
        await tester.pumpWidget(
          harness(
            Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () async {
                    result = await CourseEditSheet(
                      course: editing,
                      initialWeekday: 7,
                    ).show(context);
                  },
                  child: const Text('open'),
                ),
              ),
            ),
            style,
            scale: 1.4,
          ),
        );
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        expect(
          tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
          isNull,
        );
        await tester.enterText(find.byType(TextField).at(0), '新课程');
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField).at(3), '错误周次');
        await tester.pumpAndSettle();
        expect(
          tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
          isNull,
        );
        await tester.enterText(find.byType(TextField).at(3), '1-15(单)');
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('添加到课表'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('添加到课表'));
        await tester.pumpAndSettle();
        expect(result!.name, '新课程');
        expect(result!.weekday, 7);
        expect(result!.weeks, [1, 3, 5, 7, 9, 11, 13, 15]);
        expect(result!.id, startsWith('manual_'));
        expect(result!.edited, isTrue);
        editing = Course(
          id: 'stable-id',
          name: '晚课',
          teacher: '原教师',
          room: 'A101',
          weekday: 5,
          startSection: 13,
          endSection: 16,
          weeks: [2, 4, 6],
          anchorKey: 'original-anchor',
        );
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField).at(0), '修改晚课');
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField).at(3), '');
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('保存修改'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('保存修改'));
        await tester.pumpAndSettle();
        expect(result!.id, 'stable-id');
        expect(result!.anchorKey, 'original-anchor');
        expect(result!.startSection, 13);
        expect(result!.endSection, 16);
        expect(result!.weeks, [2, 4, 6]);
        expect(result!.teacher, '原教师');
        expect(result!.room, 'A101');
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField).first, '不应保存');
        await tester.pumpAndSettle();
        tester.state<NavigatorState>(find.byType(Navigator).first).pop();
        await tester.pumpAndSettle();
        expect(result, isNull);
        expect(editing.name, '晚课');
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
  // The app's serialized output queues live for a process, so exercise every
  // theme in one fake-clock lifetime and await saves before changing routes.
  testWidgets(
    'all themes: homework and note editors preserve save and cancel behavior',
    (tester) async {
      for (final style in ThemeStyle.values) {
        tester.view.physicalSize = const Size(320, 740);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final original = HomeworkItem(
          id: 'manual_test',
          platform: PlatformKind.manual,
          course: '课程',
          title: '原作业',
          note: '原备注',
          status: HwStatus.unknown,
          dueAt: DateTime.now().add(const Duration(days: 2)),
          url: 'https://example.invalid/task',
          score: 91.5,
          sourceKey: 'source-identity',
        );
        await Storage.saveManualHomeworkTrash({});
        await Storage.saveHomework([original]);
        final state = AppState()..homework = [original];
        await tester.pumpWidget(
          harness(
            AnimatedBuilder(
              animation: state,
              builder: (context, _) =>
                  HomePage(state: state, onGoAccounts: () {}),
            ),
            style,
            scale: 1.4,
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('添加作业'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('手动添加'));
        await tester.pumpAndSettle();
        tester.view.viewInsets = const FakeViewPadding(bottom: 240);
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.widgetWithText(FilledButton, '添加'));
        await tester.pumpAndSettle();
        await pressSave(tester, '添加');
        expect(Storage.homework(), hasLength(1));
        expect(find.byType(TextField), findsNWidgets(3));
        await tester.enterText(find.byType(TextField).at(0), '新课程');
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField).at(1), '新作业');
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField).at(2), '新增备注');
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.widgetWithText(FilledButton, '添加'));
        await tester.pumpAndSettle();
        await pressSave(tester, '添加');
        tester.view.resetViewInsets();
        await tester.pumpAndSettle();
        expect(Storage.homework(), hasLength(2));
        final created = Storage.homework().singleWhere((h) => h.title == '新作业');
        expect(created.course, '新课程');
        expect(created.note, '新增备注');
        await tester.tap(find.byTooltip('添加作业'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('手动添加'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField).at(1), '放弃新增');
        await tester.pumpAndSettle();
        tester.state<NavigatorState>(find.byType(Navigator).first).pop();
        await tester.pumpAndSettle();
        expect(Storage.homework(), hasLength(2));

        Future<void> openOption(String option) async {
          await tester.ensureVisible(find.text('原作业').first);
          await tester.pumpAndSettle();
          await tester.longPress(find.text('原作业').first);
          await tester.pumpAndSettle();
          await tester.ensureVisible(find.text(option));
          await tester.pumpAndSettle();
          await tester.tap(find.text(option));
          await tester.pumpAndSettle();
        }

        await openOption('编辑作业');
        await tester.enterText(find.byType(TextField).at(1), '取消的修改');
        await tester.pumpAndSettle();
        tester.state<NavigatorState>(find.byType(Navigator).first).pop();
        await tester.pumpAndSettle();
        expect(Storage.homework().first.title, '原作业');
        await openOption('编辑作业');
        await tester.enterText(find.byType(TextField).at(0), '修订课程');
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField).at(2), '修订备注');
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.widgetWithText(FilledButton, '保存'));
        await tester.pumpAndSettle();
        await pressSave(tester, '保存');
        var saved = Storage.homework().singleWhere((h) => h.id == original.id);
        expect(saved.course, '修订课程');
        expect(saved.note, '修订备注');
        expect(saved.status, original.status);
        expect(
          saved.dueAt!.millisecondsSinceEpoch,
          original.dueAt!.millisecondsSinceEpoch,
        );
        expect(saved.url, original.url);
        expect(saved.score, original.score);
        expect(saved.sourceKey, original.sourceKey);
        await openOption('编辑备注');
        await tester.enterText(find.byType(TextField), '放弃备注');
        await tester.pumpAndSettle();
        await tester.tap(find.text('取消'));
        await tester.pumpAndSettle();
        expect(
          Storage.homework().singleWhere((h) => h.id == original.id).note,
          '修订备注',
        );
        await openOption('编辑备注');
        await tester.enterText(find.byType(TextField), '独立备注');
        await tester.pumpAndSettle();
        await pressSave(tester, '保存');
        saved = Storage.homework().singleWhere((h) => h.id == original.id);
        expect(saved.note, '独立备注');
        expect(saved.sourceKey, original.sourceKey);
        expect(saved.url, original.url);
        await openOption('删除');
        expect(find.text('删除这条作业？'), findsOneWidget);
        await tester.tap(find.text('取消'));
        await tester.pumpAndSettle();
        expect(Storage.homework(), hasLength(2));
        await openOption('删除');
        await tester.tap(find.widgetWithText(FilledButton, '删除'));
        await tester.pumpAndSettle();
        for (
          var i = 0;
          i < 100 && find.textContaining('已移入回收站').evaluate().isEmpty;
          i++
        ) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 1)),
          );
          await tester.pump();
        }
        expect(
          find.textContaining('已移入回收站'),
          findsOneWidget,
          reason: style.name,
        );
        expect(
          Storage.homework().map((h) => h.id),
          isNot(contains(original.id)),
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 1));
        state.dispose();
      }
    },
  );
}
