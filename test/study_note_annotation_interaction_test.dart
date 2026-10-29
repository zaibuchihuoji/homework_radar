import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homework_radar/main.dart' show buildTheme;
import 'package:homework_radar/pages/study_note_canvas.dart';
import 'package:homework_radar/ui/tokens.dart';

final imageBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/aXcAAAAASUVORK5CYII=',
);

void main() {
  testWidgets('a tap with the image pen saves a dot and can be undone', (
    tester,
  ) async {
    List<dynamic> saved = [];
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.light, ThemeStyle.clay),
        home: StudyNoteCanvas(
          image: imageBytes,
          strokes: const [],
          onChanged: (strokes) async {
            saved = strokes;
            return true;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('note-canvas')));
    await tester.pumpAndSettle();
    expect(saved, hasLength(1));
    expect((saved.single as Map)['points'], hasLength(1));
    await tester.tap(find.byTooltip('撤销'));
    await tester.pumpAndSettle();
    expect(saved, isEmpty);
  });

  testWidgets('eraser removes a line when touching its middle and can undo', (
    tester,
  ) async {
    final original = [
      {
        'color': 0xffcc4b44,
        'width': 3,
        'points': [
          [0.1, 0.5],
          [0.9, 0.5],
        ],
      },
    ];
    List<dynamic> saved = original;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.dark, ThemeStyle.green),
        home: StudyNoteCanvas(
          image: imageBytes,
          strokes: original,
          onChanged: (strokes) async {
            saved = strokes;
            return true;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('橡皮'));
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('note-canvas'))),
    );
    await gesture.moveBy(const Offset(20, 0));
    await gesture.moveBy(const Offset(30, 0));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(saved, isEmpty);
    await tester.tap(find.byTooltip('撤销'));
    await tester.pumpAndSettle();
    expect(saved, original);
  });

  testWidgets(
    'annotation modes and pen settings are visible on a narrow screen',
    (tester) async {
      tester.view.physicalSize = const Size(320, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(Brightness.light, ThemeStyle.clay),
          home: StudyNoteCanvas(
            image: imageBytes,
            strokes: const [],
            onChanged: (_) async => true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('画笔'), findsOneWidget);
      expect(find.text('橡皮'), findsOneWidget);
      expect(find.text('缩放'), findsOneWidget);
      expect(find.byTooltip('画笔设置'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('image canvas stays in place while the keyboard closes', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1;
    tester.view.viewInsets = const FakeViewPadding(bottom: 260);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.light, ThemeStyle.clay),
        home: StudyNoteCanvas(
          image: imageBytes,
          strokes: const [],
          onChanged: (_) async => true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final canvas = find.byKey(const ValueKey('note-canvas'));
    final before = tester.getRect(canvas);
    tester.view.viewInsets = const FakeViewPadding();
    await tester.pumpAndSettle();
    expect(tester.getRect(canvas), before);
    expect(tester.takeException(), isNull);
  });

  testWidgets('free canvas text dialog stays above the keyboard', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    List<dynamic> items = [];
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.light, ThemeStyle.clay),
        home: StudyNoteCanvas(
          strokes: const [],
          onChanged: (_) async => true,
          onCanvasChanged: (_, value) async {
            items = value;
            return true;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('添加画布文字'));
    await tester.pumpAndSettle();
    tester.view.viewInsets = const FakeViewPadding(bottom: 260);
    await tester.pumpAndSettle();
    final addButton = find.widgetWithText(TextButton, '添加');
    expect(tester.getRect(addButton).bottom, lessThanOrEqualTo(480));
    await tester.enterText(
      find.byKey(const ValueKey('canvas-text-input')),
      '画布文字',
    );
    await tester.tap(find.text('添加'));
    await tester.pumpAndSettle();
    expect(items.single['text'], '画布文字');
    expect(tester.takeException(), isNull);
  });
}
