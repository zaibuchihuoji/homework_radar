import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:homework_radar/app_state.dart';
import 'package:homework_radar/main.dart' show buildTheme;
import 'package:homework_radar/models/homework.dart';
import 'package:homework_radar/pages/home_page.dart';
import 'package:homework_radar/pages/homework_recognition_page.dart';
import 'package:homework_radar/services/storage.dart';
import 'package:homework_radar/services/notification_service.dart';
import 'package:homework_radar/ui/tokens.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppState state;
  setUp(() async {
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('homework_radar/platform'),
      (_) async => null,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('home_widget'),
      (_) async => true,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('dexterous.com/flutter/local_notifications'),
      (_) async => true,
    );
    SharedPreferences.setMockInitialValues({});
    await Storage.init();
    await NotificationService.init();
    await Storage.saveClassReminder(false);
    await Storage.saveHomework([
      HomeworkItem(
        id: 'old',
        platform: PlatformKind.manual,
        course: '数学',
        title: '原有练习',
        note: '保留旧备注',
      ),
    ]);
    state = AppState();
    await state.loadLocal();
  });
  tearDown(() => state.dispose());
  Widget harness(Widget child, {bool large = false}) => MaterialApp(
    theme: buildTheme(
      Brightness.light,
      large ? ThemeStyle.terminal : ThemeStyle.clean,
    ),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(large ? 1.4 : 1)),
      child: child!,
    ),
    home: child,
  );

  testWidgets('+ offers manual and recognition without changing old data', (
    tester,
  ) async {
    await tester.pumpWidget(
      harness(HomePage(state: state, onGoAccounts: () {})),
    );
    await tester.tap(find.byTooltip('添加作业'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);
    expect(
      tester.getCenter(find.byType(Dialog)).dy,
      closeTo(
        tester.view.physicalSize.height / tester.view.devicePixelRatio / 2,
        1,
      ),
    );
    expect(find.text('手动添加'), findsOneWidget);
    await tester.tap(find.text('识别添加'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('recognition_input')), findsOneWidget);
    expect(Storage.homework(), hasLength(1));
  });
  testWidgets(
    'review is editable, duplicate defaults unchecked, cancel does not save',
    (tester) async {
      await tester.pumpWidget(harness(HomeworkRecognitionPage(state: state)));
      await tester.enterText(
        find.byKey(const ValueKey('recognition_input')),
        '1. 【数学】原有练习\n2. 【英语】阅读第四单元，截止2026-10-23 20:00',
      );
      await tester.tap(find.text('识别作业'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<Checkbox>(find.byKey(const ValueKey('select_0'))).value,
        isFalse,
      );
      expect(
        tester.widget<Checkbox>(find.byKey(const ValueKey('select_1'))).value,
        isTrue,
      );
      await tester.enterText(find.byKey(const ValueKey('course_1')), '大学英语');
      await tester.enterText(find.byKey(const ValueKey('title_1')), '修改后的阅读练习');
      expect(Storage.homework(), hasLength(1));
      tester.state<NavigatorState>(find.byType(Navigator).first).pop();
      await tester.pumpAndSettle();
      expect(Storage.homework().single.note, '保留旧备注');
    },
  );
  testWidgets('only selected edited work is saved after final confirmation', (
    tester,
  ) async {
    await tester.pumpWidget(harness(HomeworkRecognitionPage(state: state)));
    await tester.enterText(
      find.byKey(const ValueKey('recognition_input')),
      '1. 【数学】原有练习\n2. 【英语】阅读第四单元，截止2026-10-23 20:00',
    );
    await tester.tap(find.text('识别作业'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('course_1')), '大学英语');
    await tester.enterText(find.byKey(const ValueKey('title_1')), '修改后的阅读练习');
    await tester.tap(find.byKey(const ValueKey('review_save')));
    await tester.pumpAndSettle();
    expect(Storage.homework(), hasLength(1));
    await tester.tap(find.text('确认添加 1 项'));
    await tester.pumpAndSettle();
    expect(Storage.homework(), hasLength(2));
    expect(Storage.homework().last.course, '大学英语');
    expect(Storage.homework().last.title, '修改后的阅读练习');
    expect(Storage.homework().last.dueAt, DateTime(2026, 10, 23, 20));
  });
  testWidgets(
    'screenshot path uses the same review and large text fits a small screen',
    (tester) async {
      tester.view.physicalSize = const Size(320, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        harness(
          HomeworkRecognitionPage(
            state: state,
            chooseImageText: () async => '【英语】阅读第四单元，明天交',
          ),
          large: true,
        ),
      );
      await tester.tap(find.text('选择截图'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('select_0')), findsOneWidget);
      expect(find.textContaining('截止时间待确认'), findsOneWidget);
      expect(Storage.homework(), hasLength(1));
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('date picker cancellation and clear never fabricate a deadline', (
    tester,
  ) async {
    await tester.pumpWidget(harness(HomeworkRecognitionPage(state: state)));
    await tester.enterText(
      find.byKey(const ValueKey('recognition_input')),
      '【英语】阅读第四单元',
    );
    await tester.tap(find.text('识别作业'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('设置截止时间'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('截止时间待确认'), findsOneWidget);
    await tester.tap(find.text('设置截止时间'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('截止时间待确认'), findsOneWidget);
    await tester.tap(find.text('设置截止时间'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.text('截止时间待确认'), findsNothing);
    await tester.tap(find.text('清除时间'));
    await tester.pumpAndSettle();
    expect(find.text('截止时间待确认'), findsOneWidget);
    expect(Storage.homework(), hasLength(1));
  });
  testWidgets(
    'paste uses clipboard and duplicate warning requires final confirmation',
    (tester) async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'Clipboard.getData') return {'text': '【数学】原有练习'};
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null),
      );
      await tester.pumpWidget(harness(HomeworkRecognitionPage(state: state)));
      await tester.tap(find.text('粘贴文字'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('识别作业'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<Checkbox>(find.byKey(const ValueKey('select_0'))).value,
        isFalse,
      );
      await tester.tap(find.byKey(const ValueKey('select_0')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('review_save')));
      await tester.pumpAndSettle();
      expect(find.textContaining('其中 1 项疑似重复'), findsOneWidget);
      await tester.tap(find.text('返回核对'));
      await tester.pumpAndSettle();
      expect(Storage.homework(), hasLength(1));
      await tester.tap(find.byKey(const ValueKey('review_save')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('确认添加 1 项'));
      await tester.pumpAndSettle();
      expect(Storage.homework(), hasLength(2));
    },
  );
}
