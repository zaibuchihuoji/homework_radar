import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homework_radar/main.dart' show buildTheme;
import 'package:homework_radar/pages/study_notes_page.dart';
import 'package:homework_radar/services/study_note_store.dart';
import 'package:homework_radar/ui/tokens.dart';

Map<String, dynamic> paragraph(
  String id,
  String text, {
  String style = 'paragraph',
}) => {
  'id': id,
  'type': 'text',
  'text': text,
  'style': style,
  'marks': <dynamic>[],
  'annotations': <dynamic>[],
  if (style == 'check') 'checked': false,
};

Map<String, dynamic> noteWith(List<Map<String, dynamic>> nodes) => {
  'id': 'boundary-note',
  'title': '文本示例',
  'body': nodes.map((n) => n['text']).join('\n'),
  'blocks': <dynamic>[],
  'cards': <dynamic>[],
  'document': {'version': 1, 'nodes': nodes},
};

Future<void> waitFor(WidgetTester tester, Future<bool> Function() ready) async {
  final deadline = DateTime.now().add(const Duration(seconds: 12));
  while (DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await tester.pump(const Duration(milliseconds: 20));
    if (await ready()) return;
  }
  fail('等待笔记保存超时');
}

void main() {
  late Directory directory;
  setUp(
    () async =>
        directory = await Directory.systemTemp.createTemp('note_boundaries_'),
  );
  tearDown(() async {
    final root = (await Directory.systemTemp.resolveSymbolicLinks())
        .toLowerCase();
    final target = (await directory.resolveSymbolicLinks()).toLowerCase();
    if (!target.startsWith('$root${Platform.pathSeparator}')) {
      throw StateError('Test directory is outside the temp root');
    }
    await directory.delete(recursive: true);
  });

  testWidgets('an empty checklist item can be deleted and undone', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final store = StudyNoteStore(directory);
      final note = noteWith([
        paragraph('first', '复习', style: 'check'),
        paragraph('empty', '', style: 'check'),
      ]);
      await store.saveNotes([note]);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(Brightness.light, ThemeStyle.clay),
          home: StudyNoteEditor(store: store, note: note),
        ),
      );
      await tester.pumpAndSettle();
      final item = find.byKey(const ValueKey('note-text:empty'));
      await tester.tap(item);
      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      await tester.pumpAndSettle();
      expect(item, findsNothing);
      await waitFor(tester, () async {
        final nodes =
            ((await store.readNotes()).single['document'] as Map)['nodes']
                as List;
        return nodes.length == 1;
      });
      expect((await store.readNotes()).single['body'], '复习');
      await tester.tap(find.byTooltip('撤销正文'));
      await waitFor(tester, () async {
        final nodes =
            ((await store.readNotes()).single['document'] as Map)['nodes']
                as List;
        return nodes.length == 2;
      });
      await tester.tap(find.text('删除空项'));
      await waitFor(tester, () async {
        final nodes =
            ((await store.readNotes()).single['document'] as Map)['nodes']
                as List;
        return nodes.length == 1;
      });
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  });

  testWidgets('joining adjacent paragraphs keeps formatting and handwriting', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final store = StudyNoteStore(directory);
      final first = paragraph('first', '上段')
        ..['marks'] = [
          {'type': 'bold', 'start': 0, 'end': 2},
        ];
      final second = paragraph('second', '下段')
        ..['marks'] = [
          {'type': 'italic', 'start': 0, 'end': 2},
        ]
        ..['annotations'] = [
          {
            'color': 0xff244d7a,
            'anchor': 1,
            'points': [
              [0.2, 0.3],
              [0.3, 0.4],
            ],
          },
        ];
      final note = noteWith([first, second]);
      await store.saveNotes([note]);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(Brightness.dark, ThemeStyle.green),
          home: StudyNoteEditor(store: store, note: note),
        ),
      );
      await tester.pumpAndSettle();
      final field = find.byKey(const ValueKey('note-text:second'));
      await tester.tap(field);
      tester.widget<TextField>(field).controller!.selection =
          const TextSelection.collapsed(offset: 0);
      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      await tester.pumpAndSettle();
      expect(field, findsNothing);
      await waitFor(tester, () async {
        final nodes =
            ((await store.readNotes()).single['document'] as Map)['nodes']
                as List;
        return nodes.length == 1;
      });
      final saved = (await store.readNotes()).single;
      final merged =
          (((saved['document'] as Map)['nodes'] as List).single as Map);
      expect(saved['body'], '上段下段');
      expect(merged['marks'], [
        {'type': 'bold', 'start': 0, 'end': 2},
        {'type': 'italic', 'start': 2, 'end': 4},
      ]);
      expect((merged['annotations'] as List).single['anchor'], 3);
      expect((merged['annotations'] as List).single['points'], [
        [0.2, 0.3],
        [0.3, 0.4],
      ]);
      await tester.tap(find.byTooltip('撤销正文'));
      await waitFor(tester, () async {
        final nodes =
            ((await store.readNotes()).single['document'] as Map)['nodes']
                as List;
        return nodes.length == 2;
      });
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  });

  testWidgets('backspace never removes an empty paragraph with handwriting', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final store = StudyNoteStore(directory);
      final annotated = paragraph('ink', '')
        ..['annotations'] = [
          {
            'color': 1,
            'anchor': 0,
            'points': [
              [0.2, 0.3],
              [0.3, 0.4],
            ],
          },
        ];
      final note = noteWith([paragraph('first', '上一段'), annotated]);
      await store.saveNotes([note]);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(Brightness.light, ThemeStyle.clay),
          home: StudyNoteEditor(store: store, note: note),
        ),
      );
      await tester.pumpAndSettle();
      final field = find.byKey(const ValueKey('note-text:ink'));
      await tester.tap(field);
      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      await tester.pumpAndSettle();
      expect(field, findsOneWidget);
      expect(find.text('删除空行'), findsNothing);
      expect((await store.readNotes()).single['document'], note['document']);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  });

  testWidgets(
    'different paragraph styles require confirmation and can be undone',
    (tester) async {
      await tester.runAsync(() async {
        final store = StudyNoteStore(directory);
        final first = paragraph('first', '正文');
        final second = paragraph('second', '标题', style: 'heading')
          ..['annotations'] = [
            {
              'color': 1,
              'anchor': 1,
              'points': [
                [0.2, 0.3],
                [0.3, 0.4],
              ],
            },
          ];
        final note = noteWith([first, second]);
        await store.saveNotes([note]);
        await tester.pumpWidget(
          MaterialApp(
            theme: buildTheme(Brightness.light, ThemeStyle.clay),
            home: StudyNoteEditor(store: store, note: note),
          ),
        );
        await tester.pumpAndSettle();
        final field = find.byKey(const ValueKey('note-text:second'));
        await tester.tap(field);
        tester.widget<TextField>(field).controller!.selection =
            const TextSelection.collapsed(offset: 0);
        await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
        await tester.pumpAndSettle();
        expect(find.text('合并不同格式的段落？'), findsOneWidget);
        await tester.tap(find.text('合并段落'));
        await waitFor(tester, () async {
          final nodes =
              ((await store.readNotes()).single['document'] as Map)['nodes']
                  as List;
          return nodes.length == 1;
        });
        final saved = (await store.readNotes()).single;
        final merged =
            (((saved['document'] as Map)['nodes'] as List).single as Map);
        expect(saved['body'], '正文标题');
        expect(merged['style'], 'paragraph');
        expect((merged['annotations'] as List).single['anchor'], 3);
        await tester.tap(find.byTooltip('撤销正文'));
        await waitFor(tester, () async {
          final nodes =
              ((await store.readNotes()).single['document'] as Map)['nodes']
                  as List;
          return nodes.length == 2;
        });
        expect(((await store.readNotes()).single['document'] as Map)['nodes'], [
          first,
          second,
        ]);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      });
    },
  );

  testWidgets('an active composing region is not merged across paragraphs', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final store = StudyNoteStore(directory);
      final note = noteWith([
        paragraph('first', '前一段'),
        paragraph('second', 'z'),
      ]);
      await store.saveNotes([note]);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(Brightness.light, ThemeStyle.clay),
          home: StudyNoteEditor(store: store, note: note),
        ),
      );
      await tester.pumpAndSettle();
      final field = find.byKey(const ValueKey('note-text:second'));
      await tester.tap(field);
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'z',
          selection: TextSelection.collapsed(offset: 0),
          composing: TextRange(start: 0, end: 1),
        ),
      );
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      await tester.pumpAndSettle();
      expect(field, findsOneWidget);
      expect((await store.readNotes()).single['document'], note['document']);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  });

  testWidgets(
    'text from separate paragraphs can be selected and copied together',
    (tester) async {
      String? copied;
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String?;
        }
        if (call.method == 'Clipboard.getData') return {'text': copied};
        return null;
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
      );
      await tester.runAsync(() async {
        final store = StudyNoteStore(directory);
        final note = noteWith([
          paragraph('first', '第一段'),
          paragraph('second', '第二段'),
        ]);
        await store.saveNotes([note]);
        await tester.pumpWidget(
          MaterialApp(
            theme: buildTheme(Brightness.light, ThemeStyle.clay),
            home: StudyNoteEditor(store: store, note: note),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('更多工具'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('选择与复制文字'));
        await tester.pumpAndSettle();
        expect(
          find.byWidgetPredicate(
            (widget) => widget is SelectableText && widget.data == '第一段\n第二段',
          ),
          findsOneWidget,
        );
        expect(find.text('复制全文'), findsOneWidget);
        await tester.tap(find.text('复制全文'));
        await tester.pumpAndSettle();
        expect(
          (await Clipboard.getData(Clipboard.kTextPlain))?.text,
          '第一段\n第二段',
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      });
    },
  );
}
