import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:homework_radar/app_state.dart';
import 'package:homework_radar/main.dart';
import 'package:homework_radar/models/homework.dart';
import 'package:homework_radar/pages/detail_page.dart';
import 'package:homework_radar/services/storage.dart';
import 'package:homework_radar/ui/themed_navigation.dart';
import 'package:homework_radar/ui/tokens.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  String? initial;
  setUp(() async {
    initial = null;
    SharedPreferences.setMockInitialValues({});
    await Storage.init();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('homework_radar/platform'),
      (_) async => null,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('home_widget'),
      (call) async =>
          call.method == 'initiallyLaunchedFromHomeWidget' ? initial : null,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('home_widget/updates'),
      (_) async => null,
    );
  });
  Future<void> send(WidgetTester tester, String value) async {
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          'home_widget/updates',
          const StandardMethodCodec().encodeSuccessEnvelope(value),
          (_) {},
        );
    await tester.pumpAndSettle();
  }

  Future<AppState> start(WidgetTester tester, {bool ready = true}) async {
    tester.view.physicalSize = const Size(420, 920);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await Storage.saveHomework([
      HomeworkItem(
        id: 'safe / 📚',
        platform: PlatformKind.manual,
        course: '网络',
        title: '保留的旧作业',
        note: '旧备注',
      ),
    ]);
    final state = AppState();
    await state.loadLocal();
    appStateForHome = state;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.light, ThemeStyle.clean),
        home: MainShell(state: state, widgetLaunchReady: ready),
      ),
    );
    await tester.pumpAndSettle();
    return state;
  }

  tearDown(() => appStateForHome = null);

  testWidgets(
    'real shell opens the exact detail on cold and warm widget clicks',
    (tester) async {
      initial = Uri(
        scheme: 'homework-radar',
        host: 'widget',
        path: '/homework',
        queryParameters: {'id': 'safe / 📚'},
      ).toString();
      await start(tester);
      expect(
        tester
            .widget<HomeworkDetailPage>(find.byType(HomeworkDetailPage))
            .homeworkId,
        'safe / 📚',
      );
      await send(tester, 'homework-radar://widget/timetable');
      expect(find.byType(HomeworkDetailPage), findsNothing);
      expect(
        tester
            .widget<ThemedNavigationBar>(find.byType(ThemedNavigationBar))
            .selectedIndex,
        1,
      );
      await send(tester, initial!);
      expect(find.byType(HomeworkDetailPage), findsOneWidget);
      expect(Storage.homework().single.note, '旧备注');
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'hidden or account-switched IDs fall back without opening old details',
    (tester) async {
      await start(tester);
      await send(
        tester,
        'homework-radar://widget/homework?id=old-account-task',
      );
      expect(find.byType(HomeworkDetailPage), findsNothing);
      expect(
        tester
            .widget<ThemedNavigationBar>(find.byType(ThemedNavigationBar))
            .selectedIndex,
        0,
      );
      expect(find.textContaining('已移除或隐藏'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'shell queues initial destination until splash readiness changes',
    (tester) async {
      initial = 'homework-radar://widget/timetable';
      final state = await start(tester, ready: false);
      expect(
        tester
            .widget<ThemedNavigationBar>(find.byType(ThemedNavigationBar))
            .selectedIndex,
        0,
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(Brightness.light, ThemeStyle.clean),
          home: MainShell(state: state),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<ThemedNavigationBar>(find.byType(ThemedNavigationBar))
            .selectedIndex,
        1,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
}
