import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homework_radar/main.dart' show buildTheme;
import 'package:homework_radar/pages/study_note_canvas.dart';
import 'package:homework_radar/pages/study_notes_page.dart';
import 'package:homework_radar/services/study_note_bundle.dart';
import 'package:homework_radar/services/study_note_store.dart';
import 'package:homework_radar/ui/tokens.dart';

Future<void> waitForSave(
  WidgetTester tester,
  Future<bool> Function() ready,
) async {
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
        directory = await Directory.systemTemp.createTemp('note_document_'),
  );
  tearDown(() async {
    final root = await Directory.systemTemp.resolveSymbolicLinks();
    final target = await directory.resolveSymbolicLinks();
    if (!target.toLowerCase().startsWith(
      '${root.toLowerCase()}${Platform.pathSeparator}',
    )) {
      throw StateError(
        'Refusing to remove a test directory outside the temp root',
      );
    }
    await directory.delete(recursive: true);
  });

  testWidgets(
    'legacy text can be extended with a second editable section and reopened',
    (tester) async {
      final store = StudyNoteStore(directory);
      final note = <String, dynamic>{
        'id': 'n',
        'title': '旧笔记',
        'body': '原来的内容',
        'blocks': <dynamic>[],
        'cards': [
          {'question': '问题', 'answer': '答案'},
        ],
      };
      await tester.runAsync(() async {
        await store.saveNotes([note]);
        final revision = await store.revision();
        await tester.pumpWidget(
          MaterialApp(
            theme: buildTheme(Brightness.light, ThemeStyle.clean),
            home: StudyNoteEditor(store: store, note: note),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('note-body')), findsOneWidget);
        expect(await store.revision(), revision);
        await tester.tap(find.byTooltip('插入文字'));
        await tester.pumpAndSettle();
        final second = find.byWidgetPredicate(
          (widget) =>
              widget is TextField &&
              widget.key is ValueKey<String> &&
              (widget.key! as ValueKey<String>).value.startsWith('note-text:'),
        );
        expect(second, findsOneWidget);
        await tester.enterText(second, '新增内容');
        await tester.tap(find.text('保存').first);
        await waitForSave(tester, () async {
          final saved = (await store.readNotes()).single;
          return saved['body'] == '原来的内容\n新增内容';
        });
        final saved = (await store.readNotes()).single;
        expect((saved['cards'] as List).single['answer'], '答案');
        expect((saved['document'] as Map)['version'], 1);
        await tester.pumpWidget(
          MaterialApp(
            theme: buildTheme(Brightness.light, ThemeStyle.clean),
            home: StudyNoteEditor(store: store, note: saved),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('原来的内容'), findsOneWidget);
        expect(find.text('新增内容'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      });
    },
  );

  testWidgets('handwriting over text survives editing and reopening', (
    tester,
  ) async {
    final store = StudyNoteStore(directory);
    final note = <String, dynamic>{
      'id': 'ink',
      'body': '极限的定义',
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
      await tester.tap(find.byTooltip('批注正文'));
      await tester.pumpAndSettle();
      final gesture = await tester.startGesture(
        tester.getCenter(
          find.byKey(const ValueKey('note-body')),
          warnIfMissed: false,
        ),
      );
      await gesture.moveBy(const Offset(45, 12));
      await gesture.up();
      await tester.pumpAndSettle();
      await waitForSave(tester, () async {
        final doc = (await store.readNotes()).single['document'] as Map?;
        return doc != null &&
            ((doc['nodes'] as List).first['annotations'] as List).isNotEmpty;
      });
      await tester.tap(find.byTooltip('完成批注'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('note-body')),
        '复习：极限的定义',
      );
      await tester.tap(find.text('保存').first);
      await waitForSave(
        tester,
        () async => (await store.readNotes()).single['body'] == '复习：极限的定义',
      );
      final saved = (await store.readNotes()).single;
      final annotation =
          ((saved['document'] as Map)['nodes'] as List).first['annotations']
              as List;
      expect(annotation, hasLength(1));
      expect((annotation.first as Map)['points'], isNotEmpty);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(Brightness.light, ThemeStyle.clean),
          home: StudyNoteEditor(store: store, note: saved),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('复习：极限的定义'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  });

  testWidgets(
    'content can be inserted at the cursor without losing surrounding text',
    (tester) async {
      final store = StudyNoteStore(directory);
      final note = <String, dynamic>{
        'id': 'insert',
        'body': 'abcdef',
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
        field.controller!.selection = const TextSelection.collapsed(offset: 3);
        await tester.tap(find.byTooltip('插入文字'));
        await tester.pumpAndSettle();
        final added = find.byWidgetPredicate(
          (widget) =>
              widget is TextField &&
              widget.key is ValueKey<String> &&
              (widget.key! as ValueKey<String>).value.startsWith('note-text:'),
        );
        expect(added, findsNWidgets(2));
        await tester.enterText(added.first, '新增');
        await tester.tap(find.text('保存').first);
        await waitForSave(
          tester,
          () async =>
              (await store.readNotes()).single['body'] == 'abc\n新增\ndef',
        );
        final nodes =
            (((await store.readNotes()).single['document'] as Map)['nodes']
                as List);
        expect(nodes.map((node) => node['text']), ['abc', '新增', 'def']);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      });
    },
  );

  testWidgets('selected text formatting is saved without changing its text', (
    tester,
  ) async {
    final store = StudyNoteStore(directory);
    final note = <String, dynamic>{
      'id': 'format',
      'body': '知识重点',
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
      field.controller!.selection = const TextSelection(
        baseOffset: 0,
        extentOffset: 2,
      );
      await tester.tap(find.byTooltip('文本格式'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('加粗').last);
      await tester.pumpAndSettle();
      await waitForSave(tester, () async {
        final doc = (await store.readNotes()).single['document'] as Map?;
        return doc != null &&
            ((doc['nodes'] as List).first['marks'] as List).isNotEmpty;
      });
      final saved = (await store.readNotes()).single;
      expect(saved['body'], '知识重点');
      expect(((saved['document'] as Map)['nodes'] as List).first['marks'], [
        {'type': 'bold', 'start': 0, 'end': 2},
      ]);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  });

  testWidgets('selected text can be used to create a manual review card', (
    tester,
  ) async {
    final store = StudyNoteStore(directory);
    final note = <String, dynamic>{
      'id': 'card',
      'body': '什么是极限',
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
      field.controller!.selection = const TextSelection(
        baseOffset: 0,
        extentOffset: 5,
      );
      await tester.tap(find.byTooltip('文本格式'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('选中文字制卡').last);
      await tester.pumpAndSettle();
      final question = tester.widget<TextField>(
        find.widgetWithText(TextField, '问题'),
      );
      expect(question.controller!.text, '什么是极限');
      await tester.enterText(find.widgetWithText(TextField, '答案'), '趋近的值');
      await tester.tap(find.text('保存').last);
      await waitForSave(
        tester,
        () async =>
            ((await store.readNotes()).single['cards'] as List).isNotEmpty,
      );
      final card =
          ((await store.readNotes()).single['cards'] as List).single as Map;
      expect(card['question'], '什么是极限');
      expect(card['answer'], '趋近的值');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  });

  testWidgets('content can be reordered and keeps the new order after saving', (
    tester,
  ) async {
    final store = StudyNoteStore(directory);
    final document = <String, dynamic>{
      'version': 1,
      'nodes': [
        for (final entry in [('a', '第一段'), ('b', '第二段'), ('c', '第三段')])
          {
            'id': entry.$1,
            'type': 'text',
            'text': entry.$2,
            'style': 'paragraph',
            'marks': <dynamic>[],
            'annotations': <dynamic>[],
          },
      ],
    };
    final note = <String, dynamic>{
      'id': 'order',
      'body': '第一段\n第二段\n第三段',
      'blocks': <dynamic>[],
      'cards': <dynamic>[],
      'document': document,
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
      await tester.tap(find.byTooltip('整理内容'));
      await tester.pumpAndSettle();
      final first = find.byKey(const ValueKey('document-node:a'));
      final last = find.byKey(const ValueKey('document-node:c'));
      final handle = find.descendant(
        of: first,
        matching: find.byType(ReorderableDragStartListener),
      );
      final start = tester.getCenter(handle);
      final gesture = await tester.startGesture(start);
      await tester.pump(const Duration(milliseconds: 50));
      await gesture.moveBy(const Offset(0, 70));
      await tester.pump(const Duration(milliseconds: 300));
      final end = tester.getBottomLeft(last) + const Offset(15, 40);
      await gesture.moveTo(end);
      await tester.pump(const Duration(milliseconds: 300));
      await gesture.up();
      await tester.pumpAndSettle();
      await waitForSave(tester, () async {
        final doc = (await store.readNotes()).single['document'] as Map;
        return (doc['nodes'] as List).first['id'] != 'a';
      });
      final doc = (await store.readNotes()).single['document'] as Map;
      expect((doc['nodes'] as List).map((node) => node['id']), ['b', 'c', 'a']);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  });

  testWidgets('an image placed on a canvas remains in the note and backup', (
    tester,
  ) async {
    final store = StudyNoteStore(directory);
    final note = <String, dynamic>{
      'id': 'canvas',
      'body': '正文',
      'blocks': <dynamic>[],
      'cards': <dynamic>[],
    };
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    addTearDown(
      () => messenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/image_picker'),
        null,
      ),
    );
    await tester.runAsync(() async {
      final bytes = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/aXcAAAAASUVORK5CYII=',
      );
      final image = File(
        '${directory.path}${Platform.pathSeparator}canvas.png',
      );
      await image.writeAsBytes(bytes);
      messenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/image_picker'),
        (call) async => call.method == 'pickMultiImage' ? [image.path] : null,
      );
      await store.saveNotes([note]);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(Brightness.light, ThemeStyle.clean),
          home: StudyNoteEditor(store: store, note: note),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('添加画布'));
      await waitForSave(
        tester,
        () async => find.byType(StudyNoteCanvas).evaluate().isNotEmpty,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('添加画布图片'));
      await waitForSave(tester, () async {
        final doc = (await store.readNotes()).single['document'] as Map?;
        if (doc == null) return false;
        final canvases = (doc['nodes'] as List).where(
          (node) => node['type'] == 'canvas',
        );
        return canvases.isNotEmpty &&
            (canvases.single['items'] as List).isNotEmpty;
      });
      final saved = (await store.readNotes()).single;
      final canvas = ((saved['document'] as Map)['nodes'] as List).firstWhere(
        (node) => node['type'] == 'canvas',
      ) as Map;
      final id = (canvas['items'] as List).single['attachmentId'] as String;
      expect(await store.readAttachment(id), bytes);
      final backup = StudyNoteBundle(
        businessJson: '{}',
        notes: [saved],
        attachments: {id: bytes},
      ).encode();
      expect(StudyNoteBundle.decode(backup).attachments[id], bytes);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  });

  for (final (style, brightness) in [
    (ThemeStyle.clay, Brightness.light),
    (ThemeStyle.green, Brightness.dark),
  ]) {
    testWidgets(
      '${style.name} editor and canvas fit large text on a narrow screen',
      (tester) async {
        tester.view.physicalSize = const Size(320, 740);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final store = StudyNoteStore(directory);
        final note = <String, dynamic>{
          'id': 'layout',
          'body': '复习内容',
          'blocks': <dynamic>[],
          'cards': <dynamic>[],
        };
        await tester.runAsync(() async {
          await store.saveNotes([note]);
          await tester.pumpWidget(
            MaterialApp(
              theme: buildTheme(brightness, style),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: const TextScaler.linear(1.6)),
                child: child!,
              ),
              home: StudyNoteEditor(store: store, note: note),
            ),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.byTooltip('批注正文'));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await tester.tap(find.byTooltip('完成批注'));
          await tester.pumpAndSettle();
          await tester.tap(find.byTooltip('添加画布'));
          await waitForSave(
            tester,
            () async => find.byType(StudyNoteCanvas).evaluate().isNotEmpty,
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        });
      },
    );
  }
}
