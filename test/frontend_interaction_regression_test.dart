import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:homework_radar/pages/section_times_page.dart';
import 'package:homework_radar/app_state.dart';
import 'package:homework_radar/main.dart';
import 'package:homework_radar/pages/jw_preview_page.dart';
import 'package:homework_radar/pages/jw_text_import_page.dart';
import 'package:homework_radar/services/storage.dart';
import 'package:homework_radar/ui/themed_navigation.dart';
import 'package:homework_radar/ui/tokens.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppState state;
  setUp(() async {
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    SharedPreferences.setMockInitialValues({});
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final name in [
      'homework_radar/platform',
      'home_widget',
      'home_widget/updates',
    ]) {
      messenger.setMockMethodCallHandler(
        MethodChannel(name),
        (_) async => null,
      );
    }
    messenger.setMockMethodCallHandler(
      const MethodChannel('dexterous.com/flutter/local_notifications'),
      (call) async => call.method == 'pendingNotificationRequests'
          ? <Map<String, Object?>>[]
          : true,
    );
    await Storage.init();
    state = AppState();
  });
  tearDown(() => state.dispose());
  Future<void> mount(WidgetTester tester, Widget home) async {
    tester.view.physicalSize = const Size(420, 920);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.light, ThemeStyle.clean),
        home: home,
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder tab(String text) => find.descendant(
    of: find.byType(ThemedNavigationBar),
    matching: find.text(text),
  );

  testWidgets(
    'tapping the original tab during a transition honors the last tap',
    (tester) async {
      await mount(tester, MainShell(state: state));
      await tester.tap(tab('课表'));
      await tester.pump(const Duration(milliseconds: 30));
      await tester.tap(tab('作业'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<ThemedNavigationBar>(find.byType(ThemedNavigationBar))
            .selectedIndex,
        0,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'changing tabs dismisses the keyboard and preserves the search query',
    (tester) async {
      await mount(tester, MainShell(state: state));
      await tester.tap(find.byTooltip('搜索作业'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '查找报告');
      expect(tester.testTextInput.isVisible, isTrue);
      await tester.tap(tab('课表'));
      await tester.pumpAndSettle();
      expect(tester.testTextInput.isVisible, isFalse);
      await tester.tap(tab('作业'));
      await tester.pumpAndSettle();
      expect(find.text('查找报告'), findsOneWidget);
      await tester.showKeyboard(find.byType(TextField));
      await tester.pumpAndSettle();
      expect(tester.testTextInput.isVisible, isTrue);
      await tester.drag(find.byType(PageView).first, const Offset(-400, 0));
      await tester.pumpAndSettle();
      expect(tester.testTextInput.isVisible, isFalse);
      expect(
        tester
            .widget<ThemedNavigationBar>(find.byType(ThemedNavigationBar))
            .selectedIndex,
        1,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('rapid parse taps open only one timetable preview', (
    tester,
  ) async {
    await mount(tester, JwTextImportPage(state: state));
    await tester.enterText(
      find.byType(TextField),
      '周一 1-2节 高等数学 王一 1-16周 3-301',
    );
    final button = find.widgetWithText(FilledButton, '解析并预览');
    await tester.tap(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.byType(JwPreviewPage, skipOffstage: false), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(JwTextImportPage), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isTrue);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.byType(JwPreviewPage, skipOffstage: false), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(Storage.courses(), isEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'back-to-back class times can be saved while a zero-length slot is rejected',
    (tester) async {
      await mount(tester, SectionTimesPage(state: state));
      Future<void> choose(String current, String minute) async {
        await tester.tap(find.text(current).first);
        await tester.pumpAndSettle();
        await tester.tap(find.byIcon(Icons.keyboard_outlined));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField).at(0), '08');
        await tester.enterText(find.byType(TextField).at(1), minute);
        await tester.tap(find.text('OK'));
        await tester.pumpAndSettle();
      }

      await choose('08:45', '55');
      expect(tester.takeException(), isNull);
      expect(Storage.sectionTimes()?.first, (480, 535));
      await choose('08:00', '55');
      expect(Storage.sectionTimes()?.first, (480, 535));
      await tester.pumpWidget(const SizedBox());
    },
  );
}
