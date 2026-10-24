import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homework_radar/app_state.dart';
import 'package:homework_radar/main.dart';
import 'package:homework_radar/models/homework.dart';
import 'package:homework_radar/pages/home_page.dart';
import 'package:homework_radar/services/storage.dart';
import 'package:homework_radar/ui/activity_icon.dart';
import 'package:homework_radar/ui/tokens.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _PaintCounter extends CustomPainter {
  int paints = 0;
  @override
  void paint(Canvas canvas, Size size) {
    paints++;
    canvas.drawColor(Colors.white, BlendMode.src);
  }

  @override
  bool shouldRepaint(covariant _PaintCounter oldDelegate) => false;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
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
    await Storage.init();
  });

  for (final mode in ['upcoming', 'today', 'course']) {
    final today = mode == 'today';
    testWidgets('large $mode group builds only viewport rows', (t) async {
      await Storage.saveSortMode(mode == 'course' ? 'course' : 'time');
      t.view.physicalSize = const Size(390, 844);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final n = DateTime.now();
      final state = AppState()
        ..homework = [
          for (var i = 0; i < 300; i++)
            HomeworkItem(
              id: 'task$i',
              platform: PlatformKind.manual,
              status: HwStatus.todo,
              course: '课程',
              title: '任务 $i',
              dueAt: today ? DateTime(n.year, n.month, n.day, 23, 59) : null,
            ),
        ];
      await t.pumpWidget(
        MaterialApp(
          theme: buildTheme(Brightness.light, ThemeStyle.clean),
          home: HomePage(state: state, onGoAccounts: () {}),
        ),
      );
      await t.pumpAndSettle();
      final built = find.byType(Dismissible).evaluate().length;
      debugPrint('$mode rows built on first screen: $built / 300');
      expect(built, lessThan(25));
      await t.scrollUntilVisible(
        find.text('任务 299'),
        600,
        maxScrolls: 100,
        scrollable: find.byType(Scrollable).first,
      );
      await t.pumpAndSettle();
      expect(find.text('任务 299'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
      state.dispose();
    });
  }

  testWidgets('spinning glyph does not repaint static page artwork', (t) async {
    final painter = _PaintCounter();
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              Positioned.fill(child: CustomPaint(painter: painter)),
              const ActivityIcon(Icons.refresh_rounded, active: true),
            ],
          ),
        ),
      ),
    );
    await t.pump();
    final before = painter.paints;
    for (var i = 0; i < 10; i++) {
      await t.pump(const Duration(milliseconds: 16));
    }
    debugPrint(
      'static artwork repaints over 10 animation frames: ${painter.paints - before}',
    );
    expect(painter.paints, before);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets(
    'sync progress updates home without recreating application themes',
    (t) async {
      final state = AppState();
      final splash = showSplashOnStart;
      showSplashOnStart = false;
      appStateForHome = state;
      addTearDown(() {
        showSplashOnStart = splash;
        appStateForHome = null;
      });
      await t.pumpWidget(HomeworkRadarApp(state: state));
      await t.pumpAndSettle();
      final app = t.widget<MaterialApp>(find.byType(MaterialApp));
      state.syncing = true;
      state.syncProgress = '3/20';
      state.notifyListeners();
      await t.pump();
      expect(find.text('课程进度 3/20'), findsOneWidget);
      expect(
        identical(t.widget<MaterialApp>(find.byType(MaterialApp)), app),
        isTrue,
      );
      state.syncing = false;
      state.notifyListeners();
      await t.pumpAndSettle();
      await t.pumpWidget(const SizedBox());
      state.dispose();
    },
  );
}
