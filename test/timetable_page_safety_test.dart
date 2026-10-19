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
  testWidgets(
    'collapsed overlap covers all occupied sections, not only representative',
    (tester) async {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('homework_radar/platform'),
        (_) async => null,
      );
      tester.view.physicalSize = const Size(390, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
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
      final state = AppState()
        ..courses = [
          Course(
            id: 'A',
            name: 'overlap A',
            weekday: 1,
            startSection: 1,
            endSection: 2,
            weeks: [1],
          ),
          Course(
            id: 'B',
            name: 'overlap B',
            weekday: 1,
            startSection: 2,
            endSection: 3,
            weeks: [1],
          ),
        ];
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(Brightness.light, ThemeStyle.clean),
          home: TimetablePage(state: state),
        ),
      );
      final block = find
          .ancestor(
            of: find.text('overlap A').first,
            matching: find.byType(Positioned),
          )
          .first;
      expect(tester.widget<Positioned>(block).height, 153);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'following current week updates the visible page after calibration or week rollover',
    (tester) async {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('homework_radar/platform'),
        (_) async => null,
      );
      SharedPreferences.setMockInitialValues({});
      await Storage.init();
      final now = DateTime.now();
      final monday = DateTime(
        now.year,
        now.month,
        now.day,
      ).subtract(Duration(days: now.weekday - 1));
      await Storage.saveSemesterStart(monday);
      final state = AppState()
        ..courses = [
          Course(
            id: 'follow',
            name: 'follow',
            weekday: 1,
            startSection: 1,
            endSection: 2,
            weeks: [1, 2],
          ),
        ];
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(Brightness.light, ThemeStyle.clean),
          home: TimetablePage(state: state),
        ),
      );
      expect(
        tester.widget<PageView>(find.byType(PageView)).controller!.page,
        0,
      );
      await Storage.saveSemesterStart(monday.subtract(const Duration(days: 7)));
      await tester.pump(const Duration(minutes: 1));
      await tester.pump();
      expect(
        tester.widget<PageView>(find.byType(PageView)).controller!.page,
        1,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
