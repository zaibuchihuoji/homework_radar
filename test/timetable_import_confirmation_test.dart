import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homework_radar/models/course.dart';
import 'package:homework_radar/pages/timetable_import_confirmation.dart';

Course c(String name) => Course(
  id: name,
  name: name,
  weekday: 1,
  startSection: 1,
  endSection: 2,
  weeks: [1],
);

void main() {
  testWidgets(
    'import defaults to preserving courses absent from the selection',
    (tester) async {
      bool? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await confirmTimetableImport(
                    context,
                    selected: [c('新课')],
                    existing: [c('原课程')],
                  );
                },
                child: const Text('开始'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('开始'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('确认补充导入'));
      await tester.pumpAndSettle();
      expect(result, isFalse);
    },
  );
  testWidgets(
    'replacement requires selection and shows courses to be removed',
    (tester) async {
      bool? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await confirmTimetableImport(
                    context,
                    selected: [c('保留课')],
                    existing: [c('保留课'), c('将移除课')],
                  );
                },
                child: const Text('开始'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('开始'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('整表替换'));
      await tester.pumpAndSettle();
      expect(find.textContaining('将移除课'), findsOneWidget);
      expect(find.textContaining('将移除 1 条'), findsOneWidget);
      await tester.tap(find.text('确认替换课表'));
      await tester.pumpAndSettle();
      expect(result, isTrue);
    },
  );
}
