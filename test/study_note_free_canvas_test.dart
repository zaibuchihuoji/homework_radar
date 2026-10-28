import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homework_radar/main.dart' show buildTheme;
import 'package:homework_radar/pages/study_note_canvas.dart';
import 'package:homework_radar/ui/tokens.dart';

void main() {
  testWidgets('canvas text can be placed, moved and saved with handwriting', (
    tester,
  ) async {
    var savedStrokes = <dynamic>[];
    var savedItems = <dynamic>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.light, ThemeStyle.clean),
        home: StudyNoteCanvas(
          strokes: const [],
          items: const [],
          onChanged: (_) async => true,
          onCanvasChanged: (strokes, items) async {
            savedStrokes = jsonDecode(jsonEncode(strokes)) as List;
            savedItems = jsonDecode(jsonEncode(items)) as List;
            return true;
          },
        ),
      ),
    );
    await tester.tap(find.byTooltip('添加画布文字'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('canvas-text-input')),
      '极限公式',
    );
    await tester.tap(find.text('添加').last);
    await tester.pumpAndSettle();
    expect(savedItems, hasLength(1));
    expect((savedItems.single as Map)['text'], '极限公式');
    final id = (savedItems.single as Map)['id'] as String;
    final oldX = (savedItems.single as Map)['x'] as num;
    await tester.drag(
      find.byKey(ValueKey('canvas-item:$id')),
      const Offset(45, 0),
    );
    await tester.pumpAndSettle();
    expect((savedItems.single as Map)['x'] as num, greaterThan(oldX));
    await tester.tap(find.byTooltip('画笔'));
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const ValueKey('note-canvas')),
      const Offset(30, 20),
    );
    await tester.pumpAndSettle();
    expect(savedStrokes, hasLength(1));
    expect(savedItems, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('rapid canvas edits are written in order', (tester) async {
    final gate = Completer<bool>();
    final writes = <List<dynamic>>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.light, ThemeStyle.clean),
        home: StudyNoteCanvas(
          strokes: const [],
          items: const [],
          onChanged: (_) async => true,
          onCanvasChanged: (strokes, items) async {
            writes.add(jsonDecode(jsonEncode(strokes)) as List);
            if (writes.length == 1) return gate.future;
            return true;
          },
        ),
      ),
    );
    final canvas = find.byKey(const ValueKey('note-canvas'));
    await tester.drag(canvas, const Offset(40, 20));
    await tester.pump();
    await tester.drag(canvas, const Offset(35, -15));
    await tester.pump();
    expect(writes, hasLength(1));
    gate.complete(true);
    await tester.pumpAndSettle();
    expect(writes.map((strokes) => strokes.length), [1, 2]);
  });

  testWidgets('a failed canvas save keeps the page open until retry succeeds', (
    tester,
  ) async {
    var fail = true;
    var saved = <dynamic>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.light, ThemeStyle.clean),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => StudyNoteCanvas(
                    strokes: const [],
                    onChanged: (strokes) async {
                      if (fail) return false;
                      saved = strokes;
                      return true;
                    },
                  ),
                ),
              ),
              child: const Text('打开画布'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开画布'));
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const ValueKey('note-canvas')),
      const Offset(40, 20),
    );
    await tester.pumpAndSettle();
    expect(find.text('笔迹保存失败，请检查存储空间并重试。'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(StudyNoteCanvas), findsOneWidget);
    fail = false;
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(find.byType(StudyNoteCanvas), findsNothing);
    expect(saved, hasLength(1));
    expect(tester.takeException(), isNull);
  });
}
