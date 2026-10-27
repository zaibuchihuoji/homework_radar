import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homework_radar/app_state.dart';
import 'package:homework_radar/main.dart' show buildTheme;
import 'package:homework_radar/models/homework.dart';
import 'package:homework_radar/pages/homework_edit_dialogs.dart';
import 'package:homework_radar/pages/home_page.dart';
import 'package:homework_radar/services/storage.dart';
import 'package:homework_radar/ui/tokens.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

class _Store extends InMemorySharedPreferencesStore {
  _Store() : super.empty();
  bool failOnce = false;
  String failKey = 'flutter.homework_json';
  @override
  Future<bool> setValue(String type, String key, Object value) async {
    if (failOnce && key == failKey) {
      failOnce = false;
      return false;
    }
    return super.setValue(type, key, value);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  AndroidFlutterLocalNotificationsPlugin.registerWith();
  late AppState state;
  late _Store store;
  bool failOutputs = false;
  setUp(() async {
    failOutputs = false;
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
      (call) async {
        if (failOutputs) throw PlatformException(code: 'test-io');
        return call.method == 'pendingNotificationRequests'
            ? <Map<String, Object?>>[]
            : true;
      },
    );
    SharedPreferences.setMockInitialValues({});
    store = _Store();
    SharedPreferencesStorePlatform.instance = store;
    await Storage.init();
    await Storage.saveClassReminder(false);
    state = AppState();
  });
  tearDown(() => state.dispose());

  Future<void> mount(WidgetTester tester, {HomeworkItem? note}) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.light, ThemeStyle.clean),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => note == null
                  ? showManualHomeworkEditor(context, state)
                  : showHomeworkNoteEditor(context, state, note),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Future<void> save(WidgetTester tester, String label) async {
    // Keep native output queues out of an earlier test's fake async zone.
    await tester.runAsync(() async {
      final dynamic action = tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, label))
          .onPressed!;
      await action();
    });
    await tester.pumpAndSettle();
  }

  testWidgets(
    'a failed swipe restores its card without a dismissed-widget exception',
    (tester) async {
      await tester.runAsync(() async {
        await Storage.saveHomework([
          HomeworkItem(
            id: 'manual_swipe',
            platform: PlatformKind.manual,
            course: '数学',
            title: '隐藏失败还要看得见',
            status: HwStatus.todo,
          ),
        ]);
        await state.loadLocal();
      });
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(Brightness.light, ThemeStyle.clean),
          home: HomePage(state: state, onGoAccounts: () {}),
        ),
      );
      await tester.pumpAndSettle();
      store.failKey = 'flutter.dismissed_ids';
      store.failOnce = true;
      await tester.drag(find.byType(Dismissible), const Offset(-700, 0));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('隐藏失败还要看得见'), findsOneWidget);
      expect(Storage.dismissedIds(), isEmpty);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('failed add retains the form and supports one successful retry', (
    tester,
  ) async {
    await mount(tester);
    await tester.enterText(find.byType(TextField).at(1), '不能丢失的输入');
    store.failOnce = true;
    await save(tester, '添加');
    expect(tester.takeException(), isNull);
    expect(find.byType(Dialog), findsOneWidget);
    expect(find.text('不能丢失的输入'), findsOneWidget);
    expect(Storage.homework(), isEmpty);
    await save(tester, '添加');
    expect(Storage.homework().single.title, '不能丢失的输入');
    expect(find.byType(Dialog), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });
  testWidgets('failed note save keeps input and reports failure', (
    tester,
  ) async {
    final item = HomeworkItem(
      id: 'manual_note',
      platform: PlatformKind.manual,
      course: '数学',
      title: '报告',
      note: '旧备注',
    );
    await Storage.saveHomework([item]);
    await mount(tester, note: item);
    await tester.enterText(find.byType(TextField), '新的重要备注');
    store.failOnce = true;
    await save(tester, '保存');
    expect(tester.takeException(), isNull);
    expect(find.text('新的重要备注'), findsOneWidget);
    expect(Storage.homework().single.note, '旧备注');
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });
  testWidgets(
    'reminder failure after commit closes form and does not invite a duplicate add',
    (tester) async {
      await mount(tester);
      await tester.enterText(find.byType(TextField).at(1), '已经保存的作业');
      failOutputs = true;
      await save(tester, '添加');
      expect(tester.takeException(), isNull);
      expect(Storage.homework(), hasLength(1));
      expect(find.byType(Dialog), findsNothing);
      expect(find.textContaining('已保存'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    },
  );
}
