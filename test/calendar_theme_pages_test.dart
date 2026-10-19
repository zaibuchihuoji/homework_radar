import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homework_radar/app_state.dart';
import 'package:homework_radar/main.dart' show buildTheme;
import 'package:homework_radar/models/homework.dart';
import 'package:homework_radar/pages/calendar_page.dart';
import 'package:homework_radar/pages/detail_page.dart';
import 'package:homework_radar/services/storage.dart';
import 'package:homework_radar/ui/tokens.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:table_calendar/table_calendar.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Storage.init();
  });

  HomeworkItem task(String id, DateTime? due) => HomeworkItem(
    id: id,
    platform: PlatformKind.manual,
    course: '数学',
    title: id,
    dueAt: due,
    status: HwStatus.todo,
  );

  Future<void> show(
    WidgetTester tester,
    AppState state,
    ThemeStyle style, {
    bool narrow = false,
  }) async {
    if (narrow) {
      tester.view.physicalSize = const Size(640, 1600);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
    }
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.light, style),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(narrow ? 1.4 : 1)),
          child: child!,
        ),
        home: CalendarPage(state: state),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('month summary counts real dated work only', (tester) async {
    final now = DateTime.now();
    final state = AppState()
      ..homework = [
        task('today one', DateTime(now.year, now.month, now.day, 10)),
        task('today two', DateTime(now.year, now.month, now.day, 20)),
        task(
          'another day',
          DateTime(now.year, now.month, now.day == 1 ? 2 : 1),
        ),
        task('next month', DateTime(now.year, now.month + 1, 2)),
        task('undated', null),
      ];
    await show(tester, state, ThemeStyle.pixel);
    expect(find.text('本月 3 项截止 · 2 天有安排'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    state.dispose();
  });

  for (final style in ThemeStyle.values) {
    testWidgets(
      '${style.name}: date agenda stays ordered and opens its detail',
      (tester) async {
        final now = DateTime.now();
        final chosen = DateTime(now.year, now.month, now.day == 22 ? 23 : 22);
        final state = AppState()
          ..homework = [
            task('晚间练习', chosen.add(const Duration(hours: 20))),
            task('上午练习', chosen.add(const Duration(hours: 9))),
          ];
        await Storage.saveHomework(state.homework);
        await show(tester, state, style, narrow: true);
        await tester.tap(
          find.descendant(
            of: find.byType(TableCalendar<HomeworkItem>),
            matching: find.text('${chosen.day}'),
          ),
        );
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text('上午练习'),
          160,
          scrollable: find
              .descendant(
                of: find.byType(ListView).first,
                matching: find.byType(Scrollable),
              )
              .first,
        );
        await tester.pumpAndSettle();
        expect(
          tester.getTopLeft(find.text('上午练习')).dy,
          lessThan(tester.getTopLeft(find.text('晚间练习')).dy),
        );
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('上午练习'));
        await tester.pumpAndSettle();
        expect(find.byType(HomeworkDetailPage), findsOneWidget);
        expect(find.text('上午练习'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        state.dispose();
      },
    );

    testWidgets(
      '${style.name}: month navigation survives periodic rebuilding',
      (tester) async {
        final state = AppState();
        await show(tester, state, style, narrow: true);
        await tester.tap(
          find.descendant(
            of: find.byType(TableCalendar<HomeworkItem>),
            matching: find.byIcon(Icons.chevron_right),
          ),
        );
        await tester.pumpAndSettle();
        final next = tester
            .widget<TableCalendar<HomeworkItem>>(
              find.byType(TableCalendar<HomeworkItem>),
            )
            .focusedDay;
        await tester.pump(const Duration(minutes: 1));
        await tester.pumpAndSettle();
        final calendar = tester.widget<TableCalendar<HomeworkItem>>(
          find.byType(TableCalendar<HomeworkItem>),
        );
        expect(calendar.focusedDay.month, next.month);
        expect(calendar.focusedDay.year, next.year);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        state.dispose();
      },
    );
  }
}
