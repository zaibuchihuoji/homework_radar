import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homework_radar/main.dart' show buildTheme;
import 'package:homework_radar/pages/study_note_canvas.dart';
import 'package:homework_radar/ui/tokens.dart';

void main() {
  testWidgets(
    'selected canvas objects can be deleted without losing other ink',
    (tester) async {
      const ink = [
        {
          'color': 0xffcc4b44,
          'width': 3,
          'points': [
            [0.1, 0.2],
            [0.4, 0.5],
          ],
        },
      ];
      const items = [
        {
          'id': 'photo',
          'type': 'image',
          'attachmentId': 'sample',
          'x': 0.1,
          'y': 0.1,
          'width': 0.35,
          'height': 0.25,
        },
        {
          'id': 'text',
          'type': 'text',
          'text': '保留文字',
          'x': 0.55,
          'y': 0.55,
          'width': 0.35,
          'height': 0.2,
        },
      ];
      var savedStrokes = <dynamic>[];
      var savedItems = <dynamic>[];
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(Brightness.dark, ThemeStyle.clay),
          home: StudyNoteCanvas(
            strokes: ink,
            items: items,
            onChanged: (_) async => true,
            onCanvasChanged: (strokes, entries) async {
              savedStrokes = jsonDecode(jsonEncode(strokes)) as List;
              savedItems = jsonDecode(jsonEncode(entries)) as List;
              return true;
            },
          ),
        ),
      );
      await tester.tap(find.byTooltip('移动画布内容'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('canvas-item:photo')));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('删除画布内容'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('移除').last);
      await tester.pumpAndSettle();
      expect(savedItems, [items[1]]);
      expect(savedStrokes, ink);
      await tester.tap(find.byTooltip('撤销'));
      await tester.pumpAndSettle();
      expect(savedItems, items);
      expect(savedStrokes, ink);
      await tester.tap(find.byKey(const ValueKey('canvas-item:text')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('canvas-text-input')), findsNothing);
      await tester.tap(find.byTooltip('删除画布内容'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('移除').last);
      await tester.pumpAndSettle();
      expect(savedItems, [items[0]]);
      expect(savedStrokes, ink);
    await tester.tap(find.byTooltip('撤销'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('canvas-item:text')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('canvas-item:text')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('canvas-text-input')),
      '修改后的文字',
    );
    await tester.tap(find.widgetWithText(TextButton, '保存').last);
    await tester.pumpAndSettle();
    expect((savedItems[1] as Map)['text'], '修改后的文字');
    expect(savedStrokes, ink);
      expect(tester.takeException(), isNull);
    },
  );

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
