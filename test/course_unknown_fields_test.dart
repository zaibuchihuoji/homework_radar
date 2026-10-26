import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homework_radar/models/course.dart';
import 'package:homework_radar/pages/course_edit_sheet.dart';
import 'package:homework_radar/main.dart' show buildTheme;
import 'package:homework_radar/ui/tokens.dart';

Course uncertain({
  int day = 1,
  bool sections = false,
  List<int> weeks = const [1, 2],
}) => Course(
  id: 'candidate',
  name: '高等数学',
  weekday: day,
  startSection: 1,
  endSection: 2,
  weeks: weeks,
  sectionsProvisional: sections,
);

Future<void> open(WidgetTester t, Course course) async {
  await t.pumpWidget(
    MaterialApp(
      theme: buildTheme(Brightness.light, ThemeStyle.clean),
      home: Scaffold(body: CourseEditSheet(course: course)),
    ),
  );
  await t.pumpAndSettle();
}

void main() {
  testWidgets('unknown weekday is not silently changed to Monday', (t) async {
    await open(t, uncertain(day: 0));
    expect(
      t.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '周一')).selected,
      isFalse,
    );
    expect(
      t
          .widget<FilledButton>(find.widgetWithText(FilledButton, '保存修改'))
          .onPressed,
      isNull,
    );
  });
  testWidgets('provisional sections require an explicit selection', (t) async {
    await open(t, uncertain(sections: true));
    expect(
      t
          .widget<FilledButton>(find.widgetWithText(FilledButton, '保存修改'))
          .onPressed,
      isNull,
    );
    expect(find.text('请选择'), findsNWidgets(2));
  });
  testWidgets('unknown weeks remain empty rather than filling weeks 1-20', (
    t,
  ) async {
    await open(t, uncertain(weeks: []));
    final fields = t.widgetList<TextField>(find.byType(TextField)).toList();
    expect(fields.last.controller!.text, isEmpty);
    expect(
      t
          .widget<FilledButton>(find.widgetWithText(FilledButton, '保存修改'))
          .onPressed,
      isNull,
    );
  });
}
