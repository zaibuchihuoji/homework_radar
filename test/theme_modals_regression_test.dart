import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homework_radar/app_state.dart';
import 'package:homework_radar/main.dart' show buildTheme;
import 'package:homework_radar/models/course.dart';
import 'package:homework_radar/pages/course_edit_sheet.dart';
import 'package:homework_radar/pages/settings_page.dart';
import 'package:homework_radar/ui/settings_parts.dart';
import 'package:homework_radar/pages/timetable_import_confirmation.dart';
import 'package:homework_radar/pages/timetable_page.dart';
import 'package:homework_radar/services/storage.dart';
import 'package:homework_radar/ui/theme_forms.dart';
import 'package:homework_radar/ui/tokens.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Keep popup dispatch tests independent of OS notification queues. Persistence
// and reminder scheduling are covered by the existing data-safety service tests.
class _ModalState extends AppState {
  Course? deletedCourse;

  @override
  Future<void> deleteCourse(Course target) async {
    deletedCourse = target;
  }
}

Course _course(String id, String name) => Course(
  id: id,
  name: name,
  teacher: '任课教师',
  room: '第一教学楼三层301教室',
  weekday: 1,
  startSection: 1,
  endSection: 2,
  weeks: [1, 2],
);

Widget _app(ThemeStyle style, Widget home, {double textScale = 1.4}) =>
    MaterialApp(
      theme: buildTheme(Brightness.light, style),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: home,
    );

void _narrow(WidgetTester tester) {
  tester.view.physicalSize = const Size(320, 740);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    for (final name in ['homework_radar/platform', 'home_widget']) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(MethodChannel(name), (_) async => null);
    }
    await Storage.init();
    final now = DateTime.now();
    await Storage.saveSemesterStart(
      DateTime(
        now.year,
        now.month,
        now.day,
      ).subtract(Duration(days: now.weekday - 1)),
    );
  });

  for (final style in ThemeStyle.values) {
    testWidgets(
      '${style.name}: import keeps cancel, merge default and long replacement preview',
      (tester) async {
        _narrow(tester);
        bool? result;
        var closed = false;
        final selected = [_course('new', '新课程')];
        final existing = [
          for (var i = 0; i < 24; i++)
            _course('old_$i', '原课程第${i + 1}条：需要确认后才会移除'),
        ];
        await tester.pumpWidget(
          _app(
            style,
            Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () async {
                    closed = false;
                    result = await confirmTimetableImport(
                      context,
                      selected: selected,
                      existing: existing,
                      sourceLabel: '学校教务平台的本学期完整课程导入预览',
                    );
                    closed = true;
                  },
                  child: const Text('打开导入'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('打开导入'));
        await tester.pumpAndSettle();
        expect(find.byType(ThemedAlertDialog), findsOneWidget);
        expect(find.text('确认补充导入'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('取消'));
        await tester.pumpAndSettle();
        expect(closed, isTrue);
        expect(result, isNull);
        expect(existing, hasLength(24));

        await tester.tap(find.text('打开导入'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('确认补充导入'));
        await tester.pumpAndSettle();
        expect(result, isFalse);
        expect(existing, hasLength(24));

        await tester.tap(find.text('打开导入'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('整表替换'));
        await tester.pumpAndSettle();
        final removed = find.textContaining('原课程第24条');
        await tester.ensureVisible(removed);
        await tester.pumpAndSettle();
        expect(removed.hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('确认替换课表'));
        await tester.pumpAndSettle();
        expect(result, isTrue);
        expect(existing, hasLength(24));
      },
    );

    testWidgets(
      '${style.name}: theme sheet scrolls and widget guide can close',
      (tester) async {
        _narrow(tester);
        final state = AppState();
        await state.setStyle(style);
        await tester.pumpWidget(_app(style, SettingsPage(state: state)));
        await tester.pumpAndSettle();
        await tester.tap(find.text('外观与小组件'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('界面风格'));
        await tester.pumpAndSettle();
        expect(find.byType(ThemeModalSurface), findsOneWidget);
        expect(find.text('选择后立即生效'), findsOneWidget);
        final lastTheme = find.descendant(
          of: find.byType(ThemeModalSurface),
          matching: find.text(ThemeStyle.values.last.label),
        );
        await tester.ensureVisible(lastTheme);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.tap(lastTheme);
        await tester.pumpAndSettle();
        expect(state.style, ThemeStyle.values.last);
        expect(find.byType(ThemeModalSurface), findsNothing);

        await tester.scrollUntilVisible(
          find.text('桌面小组件').hitTestable(),
          220,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.tap(find.text('桌面小组件'));
        await tester.pumpAndSettle();
        expect(find.text('添加桌面小组件'), findsOneWidget);
        final guide = find
            .descendant(
              of: find.byType(SettingsAlertDialog),
              matching: find.byType(SingleChildScrollView),
            )
            .last;
        await tester.drag(guide, const Offset(0, -650));
        await tester.pumpAndSettle();
        expect(find.byType(SegmentedButton<bool>), findsOneWidget);
        expect(find.text('跟随主题'), findsOneWidget);
        expect(find.text('透明'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('知道了'));
        await tester.pumpAndSettle();
        expect(find.byType(SettingsAlertDialog), findsNothing);
        await tester.pumpWidget(const SizedBox.shrink());
        state.dispose();
      },
    );

    testWidgets(
      '${style.name}: course popup preserves edit, color, menu and delete actions',
      (tester) async {
        _narrow(tester);
        final course = _course('manual_modal', '主题课程');
        await Storage.saveCourses([course]);
        final state = _ModalState()..courses = [course];
        await tester.pumpWidget(_app(style, TimetablePage(state: state)));
        await tester.pumpAndSettle();
        await tester.tap(find.text('主题课程').first);
        await tester.pumpAndSettle();
        expect(find.byType(ThemedDialog), findsOneWidget);
        await tester.ensureVisible(find.text('编辑课程'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('编辑课程'));
        await tester.pumpAndSettle();
        expect(find.byType(CourseEditSheet), findsOneWidget);
        await tester.tapAt(const Offset(4, 100));
        await tester.pumpAndSettle();
        expect(state.courses.single, same(course));

        await tester.longPress(find.text('主题课程').first);
        await tester.pumpAndSettle();
        expect(find.text('课程颜色 · 主题课程'), findsOneWidget);
        await tester.tap(find.bySemanticsLabel('颜色2，当前未选中'));
        await tester.pumpAndSettle();
        expect(Storage.courseColors()['主题课程'], 1);
        expect(state.courses.single, same(course));

        await tester.tap(find.byTooltip('更多'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('显示非本周课程'));
        await tester.pumpAndSettle();
        expect(Storage.showNonWeekCourses(), isFalse);
        await tester.tap(find.text('主题课程').first);
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('删除课程'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('删除课程'));
        await tester.pumpAndSettle();
        expect(state.deletedCourse, same(course));
        expect(find.byType(ThemedDialog), findsNothing);
        expect(find.textContaining('保存失败'), findsNothing);
        expect(find.text('已删除手动添加的课程'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        state.dispose();
      },
    );
  }
}
