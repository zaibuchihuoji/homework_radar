import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:homework_radar/app_state.dart';
import 'package:homework_radar/main.dart' show buildTheme;
import 'package:homework_radar/models/course.dart';
import 'package:homework_radar/pages/timetable_page.dart';
import 'package:homework_radar/services/storage.dart';
import 'package:homework_radar/ui/tokens.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppState state;
  setUp(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('homework_radar/platform'),
          (_) async => null,
        );
    SharedPreferences.setMockInitialValues({});
    await Storage.init();
    final now = DateTime.now();
    await Storage.saveSemesterStart(
      DateTime(
        now.year,
        now.month,
        now.day,
      ).subtract(Duration(days: now.weekday - 1)),
    );
    await Storage.saveShowNonWeekCourses(false);
    state = AppState()
      ..courses = [
        for (var day = 1; day <= 7; day++)
          Course(
            id: 'day_$day',
            name: 'Day $day course',
            weekday: day,
            startSection: 1,
            endSection: 2,
            weeks: [1, 2, 3],
          ),
      ];
  });
  tearDown(() => state.dispose());
  Widget app({ThemeStyle style = ThemeStyle.clean}) => MaterialApp(
    theme: buildTheme(Brightness.light, style),
    home: TimetablePage(state: state),
  );

  testWidgets(
    'daily swipes change the selected weekday and courses without further taps',
    (tester) async {
      await tester.pumpWidget(app());
      await tester.tap(find.text('当日清单'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('周三'));
      await tester.pumpAndSettle();
      expect(find.text('Day 3 course'), findsOneWidget);
      await tester.drag(find.byType(PageView), const Offset(-600, 0));
      await tester.pumpAndSettle();
      expect(find.text('周四的安排'), findsOneWidget);
      expect(find.text('Day 4 course'), findsOneWidget);
      expect(find.text('第 1 周'), findsOneWidget);
      await tester.drag(find.byType(PageView), const Offset(-600, 0));
      await tester.pumpAndSettle();
      expect(find.text('周五的安排'), findsOneWidget);
      expect(find.text('Day 5 course'), findsOneWidget);
      await tester.drag(find.byType(PageView), const Offset(600, 0));
      await tester.pumpAndSettle();
      expect(find.text('周四的安排'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'daily paging crosses Sunday and view switches keep week and weekday in sync',
    (tester) async {
      await tester.pumpWidget(app(style: ThemeStyle.terminal));
      await tester.tap(find.text('当日清单'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('周日'));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(PageView), const Offset(-600, 0));
      await tester.pumpAndSettle();
      expect(find.text('第 2 周'), findsOneWidget);
      expect(find.text('周一的安排'), findsOneWidget);
      expect(find.text('Day 1 course'), findsOneWidget);
      await tester.tap(find.text('周视图'));
      await tester.pumpAndSettle();
      expect(find.text('第 2 周'), findsOneWidget);
      await tester.tap(find.byTooltip('上一周'));
      await tester.pumpAndSettle();
      expect(find.text('第 1 周'), findsOneWidget);
      await tester.tap(find.text('当日清单'));
      await tester.pumpAndSettle();
      expect(find.text('周一的安排'), findsOneWidget);
      await tester.drag(find.byType(PageView), const Offset(600, 0));
      await tester.pumpAndSettle();
      expect(find.text('第 1 周'), findsOneWidget);
      expect(find.text('周一的安排'), findsOneWidget);
      await tester.tap(find.byTooltip('下一周'));
      await tester.pumpAndSettle();
      expect(find.text('第 2 周'), findsOneWidget);
      expect(find.text('周一的安排'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
