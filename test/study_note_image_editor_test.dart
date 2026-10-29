import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homework_radar/main.dart' show buildTheme;
import 'package:homework_radar/pages/study_note_canvas.dart';
import 'package:homework_radar/pages/study_notes_page.dart';
import 'package:homework_radar/services/study_note_store.dart';
import 'package:homework_radar/ui/tokens.dart';

final _imageBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/aXcAAAAASUVORK5CYII=',
);

Future<void> _waitFor(
  WidgetTester tester,
  Future<bool> Function() predicate,
) async {
  final deadline = DateTime.now().add(const Duration(seconds: 12));
  while (DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await tester.pump(const Duration(milliseconds: 20));
    if (await predicate()) return;
  }
  fail('等待笔记保存超时');
}

void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('note_image_editor_');
  });
  tearDown(() async {
    final root = (await Directory.systemTemp.resolveSymbolicLinks())
        .toLowerCase();
    final target = (await directory.resolveSymbolicLinks()).toLowerCase();
    if (!target.startsWith('$root${Platform.pathSeparator}')) {
      throw StateError('Test directory is outside the temp root');
    }
    await directory.delete(recursive: true);
  });

  testWidgets('inserting an image into an empty note leaves no line above it', (
    tester,
  ) async {
    final store = StudyNoteStore(directory);
    final note = <String, dynamic>{
      'id': 'insert-image',
      'body': '',
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
      final image = File('${directory.path}${Platform.pathSeparator}test.png');
      await image.writeAsBytes(_imageBytes);
      messenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/image_picker'),
        (call) async => call.method == 'pickMultiImage' ? [image.path] : null,
      );
      await store.saveNotes([note]);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(Brightness.light, ThemeStyle.clay),
          home: StudyNoteEditor(store: store, note: note),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('添加图片'));
      await _waitFor(tester, () async {
        final doc = (await store.readNotes()).single['document'] as Map?;
        final text = tester.widget<TextField>(
          find.byKey(const ValueKey('note-body')),
        );
        final button = tester.widget<TextButton>(
          find.widgetWithText(TextButton, '保存'),
        );
        return doc != null &&
            (doc['nodes'] as List).any((node) => node['type'] == 'image') &&
            text.focusNode!.hasFocus &&
            button.onPressed != null;
      });
      final saved = (await store.readNotes()).single;
      final nodes = (saved['document'] as Map)['nodes'] as List;
      expect(nodes.first['type'], 'image');
      expect(nodes.last['type'], 'text');
      expect(
        await store.readAttachment(nodes.first['attachmentId']),
        _imageBytes,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  });

  testWidgets(
    'an existing empty line above an image can be removed and undone',
    (tester) async {
      final store = StudyNoteStore(directory);
      await tester.runAsync(() async {
        final attachment = await store.putAttachment(_imageBytes);
        final strokes = [
          {
            'color': 0xff244d7a,
            'width': 3,
            'points': [
              [0.1, 0.2],
              [0.4, 0.5],
            ],
          },
        ];
        final note = <String, dynamic>{
          'id': 'old-image',
          'body': '图片后的文字',
          'blocks': <dynamic>[],
          'cards': <dynamic>[],
          'document': {
            'version': 1,
            'nodes': [
              {
                'id': 'blank',
                'type': 'text',
                'text': '',
                'style': 'paragraph',
                'marks': <dynamic>[],
                'annotations': <dynamic>[],
              },
              {
                'id': 'image',
                'type': 'image',
                'attachmentId': attachment,
                'strokes': strokes,
              },
              {
                'id': 'after',
                'type': 'text',
                'text': '图片后的文字',
                'style': 'paragraph',
                'marks': <dynamic>[],
                'annotations': <dynamic>[],
              },
            ],
          },
        };
        await store.saveNotes([note]);
        await tester.pumpWidget(
          MaterialApp(
            theme: buildTheme(Brightness.dark, ThemeStyle.green),
            home: StudyNoteEditor(store: store, note: note),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('删除空行'));
        await tester.pumpAndSettle();
        await _waitFor(tester, () async {
          final doc = (await store.readNotes()).single['document'] as Map;
          return (doc['nodes'] as List).first['id'] == 'image';
        });
        final removed = (await store.readNotes()).single;
        final nodes = (removed['document'] as Map)['nodes'] as List;
        expect(nodes.map((node) => node['id']), ['image', 'after']);
        expect(nodes.first['strokes'], strokes);
        expect(removed['body'], '图片后的文字');
        expect(await store.readAttachment(attachment), _imageBytes);
        await tester.tap(find.byTooltip('撤销正文'));
        await tester.pumpAndSettle();
        await _waitFor(tester, () async {
          final doc = (await store.readNotes()).single['document'] as Map;
          return (doc['nodes'] as List).first['id'] == 'blank';
        });
        await tester.tap(find.byKey(const ValueKey('note-body')));
        await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
        await tester.pumpAndSettle();
        await _waitFor(tester, () async {
          final doc = (await store.readNotes()).single['document'] as Map;
          return (doc['nodes'] as List).first['id'] == 'image';
        });
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      });
    },
  );

  testWidgets(
    'a line with handwriting above an image is never removed as blank',
    (tester) async {
      final store = StudyNoteStore(directory);
      await tester.runAsync(() async {
        final attachment = await store.putAttachment(_imageBytes);
        final ink = [
          {
            'color': 0xff244d7a,
            'anchor': 0,
            'points': [
              [0.1, 0.2],
              [0.4, 0.5],
            ],
          },
        ];
        final note = <String, dynamic>{
          'id': 'annotated-line',
          'body': '',
          'blocks': <dynamic>[],
          'cards': <dynamic>[],
          'document': {
            'version': 1,
            'nodes': [
              {
                'id': 'ink',
                'type': 'text',
                'text': '',
                'style': 'paragraph',
                'marks': <dynamic>[],
                'annotations': ink,
              },
              {
                'id': 'image',
                'type': 'image',
                'attachmentId': attachment,
                'strokes': <dynamic>[],
              },
            ],
          },
        };
        await store.saveNotes([note]);
        await tester.pumpWidget(
          MaterialApp(
            theme: buildTheme(Brightness.dark, ThemeStyle.green),
            home: StudyNoteEditor(store: store, note: note),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byTooltip('删除空行'), findsNothing);
        await tester.tap(find.byKey(const ValueKey('note-body')));
        await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(TextButton, '保存'));
        await _waitFor(tester, () async {
          final button = tester.widget<TextButton>(
            find.widgetWithText(TextButton, '保存'),
          );
          return button.onPressed != null;
        });
        final nodes =
            (((await store.readNotes()).single['document'] as Map)['nodes']
                as List);
        expect(nodes.map((node) => node['id']), ['ink', 'image']);
        expect(nodes.first['annotations'], ink);
        expect(await store.readAttachment(attachment), _imageBytes);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      });
    },
  );

  testWidgets('inserting an image at the start keeps formatted text and ink', (
    tester,
  ) async {
    final store = StudyNoteStore(directory);
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    addTearDown(
      () => messenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/image_picker'),
        null,
      ),
    );
    await tester.runAsync(() async {
      final image = File('${directory.path}${Platform.pathSeparator}test.png');
      await image.writeAsBytes(_imageBytes);
      messenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/image_picker'),
        (call) async => call.method == 'pickMultiImage' ? [image.path] : null,
      );
      final text = <String, dynamic>{
        'id': 'text',
        'type': 'text',
        'text': '原来的文字',
        'style': 'paragraph',
        'marks': [
          {'type': 'bold', 'start': 0, 'end': 2},
        ],
        'annotations': [
          {
            'color': 1,
            'anchor': 1,
            'points': [
              [0.1, 0.2],
              [0.2, 0.3],
            ],
          },
        ],
      };
      final note = <String, dynamic>{
        'id': 'insert-at-start',
        'body': '原来的文字',
        'blocks': <dynamic>[],
        'cards': <dynamic>[],
        'document': {
          'version': 1,
          'nodes': [text],
        },
      };
      await store.saveNotes([note]);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(Brightness.light, ThemeStyle.clay),
          home: StudyNoteEditor(store: store, note: note),
        ),
      );
      await tester.pumpAndSettle();
      tester
          .widget<TextField>(find.byKey(const ValueKey('note-body')))
          .controller!
          .selection = const TextSelection.collapsed(
        offset: 0,
      );
      await tester.tap(find.byTooltip('添加图片'));
      await _waitFor(tester, () async {
        final doc = (await store.readNotes()).single['document'] as Map;
        final button = tester.widget<TextButton>(
          find.widgetWithText(TextButton, '保存'),
        );
        return (doc['nodes'] as List).length == 2 &&
            tester
                .widget<TextField>(find.byKey(const ValueKey('note-body')))
                .focusNode!
                .hasFocus &&
            button.onPressed != null;
      });
      final saved = (await store.readNotes()).single;
      final nodes = (saved['document'] as Map)['nodes'] as List;
      expect(nodes.first['type'], 'image');
      expect(nodes.last, text);
      expect(saved['body'], '原来的文字');
      expect(
        await store.readAttachment(nodes.first['attachmentId']),
        _imageBytes,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  });

  testWidgets('image annotation stays in place while a stroke is saved', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final save = Completer<bool>();
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.light, ThemeStyle.clay),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(1.3)),
          child: child!,
        ),
        home: StudyNoteCanvas(
          image: _imageBytes,
          strokes: const [],
          onChanged: (_) => save.future,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final canvas = find.byKey(const ValueKey('note-canvas'));
    final before = tester.getRect(canvas);
    final gesture = await tester.startGesture(tester.getCenter(canvas));
    await gesture.moveBy(const Offset(40, 30));
    await tester.pump();
    await gesture.up();
    await tester.pump();
    expect(find.text('正在保存…'), findsOneWidget);
    expect(tester.getRect(canvas), before);
    save.complete(true);
    await tester.pumpAndSettle();
    expect(tester.getRect(canvas), before);
    expect(tester.takeException(), isNull);
  });
}
