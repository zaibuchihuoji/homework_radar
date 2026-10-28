import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homework_radar/main.dart' show buildTheme;
import 'package:homework_radar/pages/study_notes_page.dart';
import 'package:homework_radar/services/study_note_bundle.dart';
import 'package:homework_radar/services/study_note_store.dart';
import 'package:homework_radar/ui/tokens.dart';

void main() {
  late Directory directory;
  setUp(
    () async =>
        directory = await Directory.systemTemp.createTemp('note_mature_'),
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

  testWidgets(
    'format at the cursor applies to newly typed text and can be turned off',
    (tester) async {
      final store = StudyNoteStore(directory);
      final note = <String, dynamic>{
        'id': 'type-style',
        'body': '',
        'blocks': <dynamic>[],
        'cards': <dynamic>[],
      };
      await tester.runAsync(() async {
        await store.saveNotes([note]);
        await tester.pumpWidget(
          MaterialApp(
            theme: buildTheme(Brightness.light, ThemeStyle.clean),
            home: StudyNoteEditor(store: store, note: note),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('note-body')));
        await tester.tap(find.byTooltip('文本格式'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('加粗'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byKey(const ValueKey('note-body')), '重点');
        await tester.pump();
        await tester.tap(find.byTooltip('文本格式'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('加粗'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byKey(const ValueKey('note-body')), '重点正文');
        await tester.tap(find.text('保存').first);
        for (
          var i = 0;
          i < 200 && (await store.readNotes()).single['body'] != '重点正文';
          i++
        ) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          await tester.pump(const Duration(milliseconds: 20));
        }
        final saved = (await store.readNotes()).single;
        final marks =
            (((saved['document'] as Map)['nodes'] as List).first
                    as Map)['marks']
                as List;
        expect(marks, [
          {'type': 'bold', 'start': 0, 'end': 2},
        ]);
        await tester.pumpWidget(const SizedBox());
      });
    },
  );

  testWidgets('Chinese composing keeps the selected input style', (
    tester,
  ) async {
    final store = StudyNoteStore(directory);
    final note = <String, dynamic>{
      'id': 'ime',
      'body': '',
      'blocks': <dynamic>[],
      'cards': <dynamic>[],
    };
    await tester.runAsync(() async {
      await store.saveNotes([note]);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(Brightness.light, ThemeStyle.clean),
          home: StudyNoteEditor(store: store, note: note),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('note-body')));
      await tester.tap(find.byTooltip('文本格式'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('加粗'));
      await tester.pumpAndSettle();
      for (final value in [
        const TextEditingValue(
          text: 'z',
          selection: TextSelection.collapsed(offset: 1),
          composing: TextRange(start: 0, end: 1),
        ),
        const TextEditingValue(
          text: 'zh',
          selection: TextSelection.collapsed(offset: 2),
          composing: TextRange(start: 0, end: 2),
        ),
        const TextEditingValue(
          text: '中',
          selection: TextSelection.collapsed(offset: 1),
        ),
      ]) {
        tester.testTextInput.updateEditingValue(value);
        await tester.pump();
      }
      await tester.tap(find.text('保存').first);
      for (
        var i = 0;
        i < 200 && (await store.readNotes()).single['body'] != '中';
        i++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await tester.pump(const Duration(milliseconds: 20));
      }
      final node =
          (((await store.readNotes()).single['document'] as Map)['nodes']
                      as List)
                  .single
              as Map;
      expect(node['text'], '中');
      expect(node['marks'], [
        {'type': 'bold', 'start': 0, 'end': 1},
      ]);
      await tester.pumpWidget(const SizedBox());
    });
  });

  testWidgets(
    'a checklist can start on a blank line without losing that newline',
    (tester) async {
      final store = StudyNoteStore(directory);
      final note = <String, dynamic>{
        'id': 'blank-list',
        'body': '学习计划\n',
        'blocks': <dynamic>[],
        'cards': <dynamic>[],
      };
      await tester.runAsync(() async {
        await store.saveNotes([note]);
        await tester.pumpWidget(
          MaterialApp(
            theme: buildTheme(Brightness.light, ThemeStyle.clean),
            home: StudyNoteEditor(store: store, note: note),
          ),
        );
        await tester.pumpAndSettle();
        tester
            .widget<TextField>(find.byKey(const ValueKey('note-body')))
            .controller!
            .selection = const TextSelection.collapsed(
          offset: 5,
        );
        await tester.tap(find.byTooltip('文本格式'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('待办事项'));
        await tester.pumpAndSettle();
        expect(find.byType(Checkbox), findsOneWidget);
        await tester.tap(find.text('保存').first);
        for (
          var i = 0;
          i < 200 && (await store.readNotes()).single['document'] == null;
          i++
        ) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          await tester.pump(const Duration(milliseconds: 20));
        }
        final saved = (await store.readNotes()).single;
        expect(saved['body'], '学习计划\n');
        final restored = StudyNoteBundle.decode(
          StudyNoteBundle(
            businessJson: '{}',
            notes: [saved],
            attachments: {},
          ).encode(),
        );
        expect(restored.notes.single['body'], '学习计划\n');
        await tester.tap(find.byTooltip('撤销正文'));
        await tester.pumpAndSettle();
        expect(find.byType(Checkbox), findsNothing);
        await tester.tap(find.byTooltip('重做正文'));
        await tester.pumpAndSettle();
        expect(find.byType(Checkbox), findsOneWidget);
        final next = find.byWidgetPredicate(
          (w) =>
              w is TextField &&
              w.key is ValueKey<String> &&
              (w.key! as ValueKey<String>).value.startsWith('note-text:'),
        );
        await tester.enterText(next, '阅读第一章');
        await tester.tap(find.text('保存').first);
        for (
          var i = 0;
          i < 200 && (await store.readNotes()).single['body'] != '学习计划\n阅读第一章';
          i++
        ) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          await tester.pump(const Duration(milliseconds: 20));
        }
        expect((await store.readNotes()).single['body'], '学习计划\n阅读第一章');
        await tester.pumpWidget(const SizedBox());
      });
    },
  );

  testWidgets(
    'formatting leading, middle and trailing blank lines preserves text',
    (tester) async {
      final store = StudyNoteStore(directory);
      await tester.runAsync(() async {
        for (final (text, offset) in [
          ('\n内容', 0),
          ('甲\n\n乙', 2),
          ('\n', 1),
          ('内容\n', 3),
        ]) {
          final note = <String, dynamic>{
            'id': 'case-$offset-${text.length}',
            'body': text,
            'blocks': <dynamic>[],
            'cards': <dynamic>[],
          };
          await store.saveNotes([note]);
          await tester.pumpWidget(
            MaterialApp(
              theme: buildTheme(Brightness.light, ThemeStyle.clean),
              home: StudyNoteEditor(
                key: ValueKey(text),
                store: store,
                note: note,
              ),
            ),
          );
          await tester.pumpAndSettle();
          tester
              .widget<TextField>(find.byKey(const ValueKey('note-body')))
              .controller!
              .selection = TextSelection.collapsed(
            offset: offset,
          );
          await tester.tap(find.byTooltip('文本格式'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('待办事项'));
          await tester.pumpAndSettle();
          expect(find.byType(Checkbox), findsOneWidget, reason: text);
          await tester.tap(find.text('保存').first);
          for (
            var i = 0;
            i < 200 && (await store.readNotes()).single['document'] == null;
            i++
          ) {
            await Future<void>.delayed(const Duration(milliseconds: 20));
            await tester.pump(const Duration(milliseconds: 20));
          }
          final saved = (await store.readNotes()).single;
          expect(saved['body'], text);
          expect((saved['document'] as Map)['version'], 2);
          await tester.pumpWidget(const SizedBox());
        }
      });
    },
  );

  testWidgets(
    'formatting one line preserves existing marks and handwriting in backup',
    (tester) async {
      final store = StudyNoteStore(directory);
      final doc = <String, dynamic>{
        'version': 1,
        'nodes': [
          {
            'id': 'p',
            'type': 'text',
            'style': 'paragraph',
            'text': 'AAA\nBBB\nCCC',
            'marks': [
              {'type': 'bold', 'start': 1, 'end': 10},
            ],
            'annotations': [
              {
                'color': 1,
                'anchor': 5,
                'points': [
                  [0.1, 0.2],
                  [0.2, 0.3],
                ],
              },
            ],
          },
        ],
      };
      final note = <String, dynamic>{
        'id': 'ink-format',
        'body': 'AAA\nBBB\nCCC',
        'document': doc,
        'blocks': <dynamic>[],
        'cards': <dynamic>[],
      };
      await tester.runAsync(() async {
        await store.saveNotes([note]);
        await tester.pumpWidget(
          MaterialApp(
            theme: buildTheme(Brightness.light, ThemeStyle.clean),
            home: StudyNoteEditor(store: store, note: note),
          ),
        );
        await tester.pumpAndSettle();
        tester
            .widget<TextField>(find.byKey(const ValueKey('note-body')))
            .controller!
            .selection = const TextSelection.collapsed(
          offset: 5,
        );
        await tester.tap(find.byTooltip('文本格式'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('标题').last);
        await tester.pumpAndSettle();
        await tester.tap(find.text('保存').first);
        for (var i = 0; i < 200; i++) {
          final saved = (await store.readNotes()).single;
          if (((saved['document'] as Map)['nodes'] as List).length == 3) break;
          await Future<void>.delayed(const Duration(milliseconds: 20));
          await tester.pump(const Duration(milliseconds: 20));
        }
        final saved = (await store.readNotes()).single;
        final nodes = (saved['document'] as Map)['nodes'] as List;
        expect(saved['body'], 'AAA\nBBB\nCCC');
        expect(nodes.map((n) => (n['marks'] as List).length), [1, 1, 1]);
        expect((nodes[1]['annotations'] as List).single['anchor'], 1);
        final restored = StudyNoteBundle.decode(
          StudyNoteBundle(
            businessJson: '{}',
            notes: [saved],
            attachments: {},
          ).encode(),
        );
        expect(restored.notes.single['document'], saved['document']);
        await tester.pumpWidget(const SizedBox());
      });
    },
  );

  testWidgets('formatting a line keeps surrounding paragraphs and text', (
    tester,
  ) async {
    final store = StudyNoteStore(directory);
    final note = <String, dynamic>{
      'id': 'n',
      'body': '第一行\n第二行\n第三行',
      'blocks': <dynamic>[],
      'cards': <dynamic>[],
    };
    await tester.runAsync(() async {
      await store.saveNotes([note]);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(Brightness.light, ThemeStyle.clean),
          home: StudyNoteEditor(store: store, note: note),
        ),
      );
      await tester.pumpAndSettle();
      final field = tester.widget<TextField>(
        find.byKey(const ValueKey('note-body')),
      );
      field.controller!.selection = const TextSelection.collapsed(offset: 5);
      await tester.tap(find.byTooltip('文本格式'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('标题').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('保存').first);
      for (
        var i = 0;
        i < 200 && (await store.readNotes()).single['document'] == null;
        i++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await tester.pump(const Duration(milliseconds: 20));
      }
      final saved = (await store.readNotes()).single;
      expect(saved['body'], '第一行\n第二行\n第三行');
      final nodes = (saved['document'] as Map)['nodes'] as List;
      expect(nodes.map((n) => n['text']), ['第一行', '第二行', '第三行']);
      expect(nodes.map((n) => n['style']), [
        'paragraph',
        'heading',
        'paragraph',
      ]);
      await tester.pumpWidget(const SizedBox());
    });
  });

  testWidgets('checklist enter creates the next checkable item', (
    tester,
  ) async {
    final store = StudyNoteStore(directory);
    final note = <String, dynamic>{
      'id': 'n',
      'body': '',
      'blocks': <dynamic>[],
      'cards': <dynamic>[],
    };
    await tester.runAsync(() async {
      await store.saveNotes([note]);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(Brightness.light, ThemeStyle.clean),
          home: StudyNoteEditor(store: store, note: note),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('文本格式'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('待办事项'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('note-body')), '第一项');
      await tester.enterText(find.byKey(const ValueKey('note-body')), '第一项\n');
      await tester.pumpAndSettle();
      expect(find.byType(Checkbox), findsNWidgets(2));
      final next = find.byWidgetPredicate(
        (w) =>
            w is TextField &&
            w.key is ValueKey<String> &&
            (w.key! as ValueKey<String>).value.startsWith('note-text:'),
      );
      await tester.enterText(next, '第二项');
      await tester.tap(find.byType(Checkbox).last);
      await tester.tap(find.text('保存').first);
      for (var i = 0; i < 200; i++) {
        final saved = (await store.readNotes()).single;
        if (saved['body'] == '第一项\n第二项' &&
            (saved['document'] as Map?)?['nodes'] is List &&
            (((saved['document'] as Map)['nodes'] as List).last
                    as Map)['checked'] ==
                true) {
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await tester.pump(const Duration(milliseconds: 20));
      }
      final saved = (await store.readNotes()).single;
      expect(saved['body'], '第一项\n第二项');
      final nodes = (saved['document'] as Map)['nodes'] as List;
      expect(nodes.map((n) => n['style']), ['check', 'check']);
      expect(nodes.last['checked'], true);
      await tester.pumpWidget(const SizedBox());
    });
  });

  testWidgets(
    'list enter inside a surrogate pair leaves original text intact',
    (tester) async {
      final store = StudyNoteStore(directory);
      final note = <String, dynamic>{
        'id': 'unicode',
        'body': 'A😀B',
        'blocks': <dynamic>[],
        'cards': <dynamic>[],
      };
      await tester.runAsync(() async {
        await store.saveNotes([note]);
        await tester.pumpWidget(
          MaterialApp(
            theme: buildTheme(Brightness.light, ThemeStyle.clean),
            home: StudyNoteEditor(store: store, note: note),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('note-body')));
        await tester.tap(find.byTooltip('文本格式'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('待办事项'));
        await tester.pumpAndSettle();
        final field = tester.widget<TextField>(
          find.byKey(const ValueKey('note-body')),
        );
        field.controller!.selection = const TextSelection.collapsed(offset: 2);
        final old = field.controller!.text;
        tester.testTextInput.updateEditingValue(
          TextEditingValue(
            text: '${old.substring(0, 2)}\n${old.substring(2)}',
            selection: const TextSelection.collapsed(offset: 3),
          ),
        );
        await tester.pump();
        expect(field.controller!.text, 'A😀B');
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      });
    },
  );

  testWidgets('selected lines become separate checklist items', (tester) async {
    final store = StudyNoteStore(directory);
    final note = <String, dynamic>{
      'id': 'multi-list',
      'body': '前言\n买菜\n复习\n结尾',
      'blocks': <dynamic>[],
      'cards': <dynamic>[],
    };
    await tester.runAsync(() async {
      await store.saveNotes([note]);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(Brightness.light, ThemeStyle.clean),
          home: StudyNoteEditor(store: store, note: note),
        ),
      );
      await tester.pumpAndSettle();
      tester
          .widget<TextField>(find.byKey(const ValueKey('note-body')))
          .controller!
          .selection = const TextSelection(
        baseOffset: 3,
        extentOffset: 8,
      );
      await tester.tap(find.byTooltip('文本格式'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('待办事项'));
      await tester.pumpAndSettle();
      expect(find.byType(Checkbox), findsNWidgets(2));
      await tester.tap(find.text('保存').first);
      for (
        var i = 0;
        i < 200 && (await store.readNotes()).single['document'] == null;
        i++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await tester.pump(const Duration(milliseconds: 20));
      }
      final saved = (await store.readNotes()).single;
      final nodes = (saved['document'] as Map)['nodes'] as List;
      expect(saved['body'], '前言\n买菜\n复习\n结尾');
      expect(nodes.map((n) => n['text']), ['前言', '买菜', '复习', '结尾']);
      expect(nodes.map((n) => n['style']), [
        'paragraph',
        'check',
        'check',
        'paragraph',
      ]);
      await tester.pumpWidget(const SizedBox());
    });
  });

  testWidgets('undo and redo preserve saved text and formatting', (
    tester,
  ) async {
    final store = StudyNoteStore(directory);
    final note = <String, dynamic>{
      'id': 'n',
      'body': '原文',
      'blocks': <dynamic>[],
      'cards': <dynamic>[],
    };
    await tester.runAsync(() async {
      await store.saveNotes([note]);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(Brightness.light, ThemeStyle.clean),
          home: StudyNoteEditor(store: store, note: note),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('note-body')), '改过的正文');
      await tester.pump();
      await tester.tap(find.byTooltip('撤销正文'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('note-body')))
            .controller!
            .text,
        '原文',
      );
      await tester.tap(find.byTooltip('重做正文'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('note-body')))
            .controller!
            .text,
        '改过的正文',
      );
      await tester.tap(find.text('保存').first);
      for (
        var i = 0;
        i < 200 && (await store.readNotes()).single['body'] != '改过的正文';
        i++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect((await store.readNotes()).single['body'], '改过的正文');
      await tester.pumpWidget(const SizedBox());
    });
  });
}
