import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homework_radar/main.dart' show buildTheme;
import 'package:homework_radar/pages/study_notes_page.dart';
import 'package:homework_radar/services/study_note_bundle.dart';
import 'package:homework_radar/services/study_note_store.dart';
import 'package:homework_radar/ui/study_note_ink.dart';
import 'package:homework_radar/ui/tokens.dart';

class DelayedAttachmentStore extends StudyNoteStore {
  DelayedAttachmentStore(super.directory, this.ready);
  final Future<void> ready;

  @override
  Future<Uint8List> readAttachment(String id) async {
    await ready;
    return super.readAttachment(id);
  }
}

class FailingPreviewStore extends StudyNoteStore {
  FailingPreviewStore(super.directory);
  bool failPreview = true;

  @override
  Future<Uint8List> readAttachment(String id) async {
    if (failPreview) throw const FileSystemException('preview unavailable');
    return super.readAttachment(id);
  }
}

class FailingWriteStore extends StudyNoteStore {
  FailingWriteStore(super.directory);
  bool failWrites = false;

  @override
  Future<void> updateNotes(
    List<Map<String, dynamic>> Function(List<Map<String, dynamic>>) update,
  ) async {
    if (failWrites) throw const FileSystemException('write unavailable');
    await super.updateNotes(update);
  }
}

Future<void> waitFor(WidgetTester tester, Future<bool> Function() ready) async {
  final deadline = DateTime.now().add(const Duration(seconds: 12));
  while (DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await tester.pump(const Duration(milliseconds: 20));
    if (await ready()) return;
  }
  fail('等待图片或笔记保存超时');
}

Map<String, dynamic> imageNote(String attachment) => {
  'id': 'image-note',
  'title': '示例笔记',
  'body': '图片前\n图片后',
  'blocks': <dynamic>[],
  'cards': <dynamic>[],
  'document': {
    'version': 1,
    'nodes': [
      {
        'id': 'before',
        'type': 'text',
        'text': '图片前',
        'style': 'paragraph',
        'marks': <dynamic>[],
        'annotations': <dynamic>[],
      },
      {
        'id': 'photo',
        'type': 'image',
        'attachmentId': attachment,
        'strokes': [
          {
            'color': 0xffcc4b44,
            'width': 3,
            'points': [
              [0.1, 0.5],
              [0.9, 0.5],
            ],
          },
        ],
      },
      {
        'id': 'after',
        'type': 'text',
        'text': '图片后',
        'style': 'paragraph',
        'marks': <dynamic>[],
        'annotations': <dynamic>[],
      },
    ],
  },
};

void main() {
  late Directory directory;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('note_image_layout_');
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

  testWidgets('landscape image and legacy strokes use the same centre', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.runAsync(() async {
      final store = StudyNoteStore(directory);
      final bytes = await File('assets/splash/splash_slogan.png').readAsBytes();
      final id = await store.putAttachment(bytes);
      final note = imageNote(id);
      await store.saveNotes([note]);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(Brightness.light, ThemeStyle.clay),
          home: StudyNoteEditor(store: store, note: note),
        ),
      );
      final node = find.byKey(const ValueKey('document-node:photo'));
      final image = find.descendant(of: node, matching: find.byType(Image));
      await waitFor(
        tester,
        () async =>
            image.evaluate().isNotEmpty && !tester.getSize(image.first).isEmpty,
      );
      final layer = find.descendant(
        of: node,
        matching: find.byType(StudyNoteInkLayer),
      );
      expect(
        tester.getRect(image.first).center.dy,
        closeTo(tester.getRect(layer).center.dy, 0.5),
      );
      expect(tester.getSize(image.first).width, greaterThanOrEqualTo(260));
      expect((await store.readNotes()).single['document'], note['document']);
      await tester.pumpWidget(const SizedBox());
    });
  });

  testWidgets('tapping whitespace beside a square picture does not open it', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.runAsync(() async {
      final store = StudyNoteStore(directory);
      final bytes = await File('assets/splash/splash_badge.png').readAsBytes();
      final note = imageNote(await store.putAttachment(bytes));
      await store.saveNotes([note]);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(Brightness.dark, ThemeStyle.green),
          home: StudyNoteEditor(store: store, note: note),
        ),
      );
      final node = find.byKey(const ValueKey('document-node:photo'));
      final image = find.descendant(of: node, matching: find.byType(Image));
      await waitFor(
        tester,
        () async =>
            image.evaluate().isNotEmpty && !tester.getSize(image.first).isEmpty,
      );
      final bounds = tester.getRect(node);
      await tester.tapAt(Offset(bounds.left + 6, bounds.center.dy));
      await Future<void>.delayed(const Duration(milliseconds: 150));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('note-canvas')), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  });

  testWidgets('a slow image load does not move the following text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.runAsync(() async {
      final store = StudyNoteStore(directory);
      final bytes = await File('assets/splash/splash_slogan.png').readAsBytes();
      final note = imageNote(await store.putAttachment(bytes));
      await store.saveNotes([note]);
      final delay = Completer<void>();
      final delayedStore = DelayedAttachmentStore(directory, delay.future);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(Brightness.light, ThemeStyle.clay),
          home: StudyNoteEditor(store: delayedStore, note: note),
        ),
      );
      await tester.pumpAndSettle();
      final following = find.byKey(const ValueKey('document-node:after'));
      final before = tester.getTopLeft(following).dy;
      delay.complete();
      final node = find.byKey(const ValueKey('document-node:photo'));
      final image = find.descendant(of: node, matching: find.byType(Image));
      await waitFor(
        tester,
        () async =>
            image.evaluate().isNotEmpty && !tester.getSize(image.first).isEmpty,
      );
      expect(tester.getTopLeft(following).dy, closeTo(before, 0.1));
      await tester.pumpWidget(const SizedBox());
    });
  });

  testWidgets('image actions are accessible and removal is undoable', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final store = StudyNoteStore(directory);
      final bytes = await File('assets/splash/splash_slogan.png').readAsBytes();
      final id = await store.putAttachment(bytes);
      final note = imageNote(id);
      await store.saveNotes([note]);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(Brightness.light, ThemeStyle.clay),
          home: StudyNoteEditor(store: store, note: note),
        ),
      );
      final action = find.byTooltip('图片操作');
      await waitFor(tester, () async => action.evaluate().isNotEmpty);
      await tester.tap(action);
      await tester.pumpAndSettle();
      await tester.tap(find.text('移除图片'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, '删除').last);
      await waitFor(tester, () async {
        final nodes =
            ((await store.readNotes()).single['document'] as Map)['nodes']
                as List;
        return nodes.every((node) => node['id'] != 'photo');
      });
      await tester.tap(find.byTooltip('撤销正文'));
      await waitFor(tester, () async {
        final nodes =
            ((await store.readNotes()).single['document'] as Map)['nodes']
                as List;
        return nodes.any((node) => node['id'] == 'photo');
      });
      final saved = (await store.readNotes()).single;
      final restored = ((saved['document'] as Map)['nodes'] as List).firstWhere(
        (n) => n['id'] == 'photo',
      );
      expect(
        restored['strokes'],
        ((note['document'] as Map)['nodes'] as List)[1]['strokes'],
      );
      expect(await store.readAttachment(id), bytes);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  });

  testWidgets(
    'a visible delete action removes an image and undo restores ink',
    (tester) async {
      await tester.runAsync(() async {
        final store = StudyNoteStore(directory);
        final bytes = await File('assets/splash/splash_slogan.png')
            .readAsBytes();
        final id = await store.putAttachment(bytes);
        final note = imageNote(id);
        await store.saveNotes([note]);
        await tester.pumpWidget(
          MaterialApp(
            theme: buildTheme(Brightness.dark, ThemeStyle.clay),
            home: StudyNoteEditor(store: store, note: note),
          ),
        );
        final remove = find.widgetWithText(TextButton, '删除图片');
        await tester.pump();
        expect(remove, findsOneWidget);
        await tester.tap(remove);
        await tester.pumpAndSettle();
        await tester.tap(find.text('取消').last);
        await tester.pumpAndSettle();
        expect((await store.readNotes()).single['document'], note['document']);
        await tester.tap(remove);
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(TextButton, '删除').last);
        await waitFor(tester, () async {
          final nodes =
              ((await store.readNotes()).single['document'] as Map)['nodes']
                  as List;
          return nodes.every((node) => node['id'] != 'photo');
        });
        await tester.tap(find.byTooltip('撤销正文'));
        await waitFor(tester, () async {
          final nodes =
              ((await store.readNotes()).single['document'] as Map)['nodes']
                  as List;
          return nodes.any((node) => node['id'] == 'photo');
        });
        expect((await store.readNotes()).single['document'], note['document']);
        expect(await store.readAttachment(id), bytes);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      });
    },
  );

  testWidgets('image deletion remains available when preview cannot load', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final store = StudyNoteStore(directory);
      final bytes = await File('assets/splash/splash_slogan.png').readAsBytes();
      final id = await store.putAttachment(bytes);
      final note = imageNote(id);
      await store.saveNotes([note]);
      final previewStore = FailingPreviewStore(directory);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(Brightness.light, ThemeStyle.clean),
          home: StudyNoteEditor(store: previewStore, note: note),
        ),
      );
      await waitFor(
        tester,
        () async => find.text('图片暂时无法读取，请保留原笔记。').evaluate().isNotEmpty,
      );
      expect(find.widgetWithText(TextButton, '删除图片'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, '删除图片'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('取消').last);
      await tester.pumpAndSettle();
      previewStore.failPreview = false;
      expect((await store.readNotes()).single['document'], note['document']);
      expect(await store.readAttachment(id), bytes);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  });

  testWidgets(
    'failed image deletion leaves the saved note and ink recoverable',
    (tester) async {
      await tester.runAsync(() async {
        final store = FailingWriteStore(directory);
        final bytes = await File('assets/splash/splash_slogan.png')
            .readAsBytes();
        final id = await store.putAttachment(bytes);
        final note = imageNote(id);
        await store.saveNotes([note]);
        await tester.pumpWidget(
          MaterialApp(
            theme: buildTheme(Brightness.light, ThemeStyle.clean),
            home: StudyNoteEditor(store: store, note: note),
          ),
        );
        store.failWrites = true;
        await tester.tap(find.widgetWithText(TextButton, '删除图片'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(TextButton, '删除').last);
        final banner = find.byKey(const ValueKey('note-save-error'));
        await waitFor(tester, () async => banner.evaluate().isNotEmpty);
        expect((await store.readNotes()).single['document'], note['document']);
        expect(await store.readAttachment(id), bytes);
        await tester.tap(find.byTooltip('撤销正文'));
        await tester.pumpAndSettle();
        store.failWrites = false;
        await tester.tap(find.text('重试保存'));
        await waitFor(tester, () async => banner.evaluate().isEmpty);
        expect((await store.readNotes()).single['document'], note['document']);
        expect(await store.readAttachment(id), bytes);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      });
    },
  );

  testWidgets('a free canvas can be removed directly and restored', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final store = StudyNoteStore(directory);
      final bytes = await File('assets/splash/splash_slogan.png').readAsBytes();
      final id = await store.putAttachment(bytes);
      final note = imageNote(id);
      final nodes = (note['document'] as Map)['nodes'] as List;
      nodes[1] = {
        'id': 'drawing',
        'type': 'canvas',
        'strokes': [
          {
            'color': 0xffcc4b44,
            'width': 3,
            'points': [
              [0.1, 0.2],
              [0.4, 0.5],
            ],
          },
        ],
        'items': [
          {
            'id': 'image',
            'type': 'image',
            'attachmentId': id,
            'x': 0.1,
            'y': 0.1,
            'width': 0.4,
            'height': 0.3,
          },
        ],
      };
      await store.saveNotes([note]);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(Brightness.light, ThemeStyle.clean),
          home: StudyNoteEditor(store: store, note: note),
        ),
      );
      final remove = find.widgetWithText(TextButton, '删除画布');
      await tester.pump();
      expect(remove, findsOneWidget);
      await tester.tap(remove);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, '删除').last);
      await waitFor(tester, () async {
        final saved =
            ((await store.readNotes()).single['document'] as Map)['nodes']
                as List;
        return saved.every((node) => node['id'] != 'drawing');
      });
      await tester.tap(find.byTooltip('撤销正文'));
      await waitFor(tester, () async {
        final saved =
            ((await store.readNotes()).single['document'] as Map)['nodes']
                as List;
        return saved.any((node) => node['id'] == 'drawing');
      });
      expect((await store.readNotes()).single['document'], note['document']);
      expect(await store.readAttachment(id), bytes);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  });

  testWidgets('legacy ink outside the photo remains inside the preview', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.runAsync(() async {
      final store = StudyNoteStore(directory);
      final bytes = await File('assets/splash/splash_slogan.png').readAsBytes();
      final note = imageNote(await store.putAttachment(bytes));
      final photo = ((note['document'] as Map)['nodes'] as List)[1] as Map;
      photo['strokes'] = [
        {
          'color': 0xffcc4b44,
          'width': 3,
          'points': [
            [0.1, 0.05],
            [0.9, 0.95],
          ],
        },
      ];
      await store.saveNotes([note]);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(Brightness.light, ThemeStyle.clay),
          home: StudyNoteEditor(store: store, note: note),
        ),
      );
      final viewport = find.byKey(const ValueKey('note-image-viewport:photo'));
      await waitFor(tester, () async => viewport.evaluate().isNotEmpty);
      final layer = find.descendant(
        of: find.byKey(const ValueKey('document-node:photo')),
        matching: find.byType(StudyNoteInkLayer),
      );
      final frame = tester.getRect(layer);
      final visible = tester.getRect(viewport);
      expect(
        visible.contains(
          Offset(
            frame.left + frame.width * 0.1,
            frame.top + frame.height * 0.05,
          ),
        ),
        isTrue,
      );
      expect(
        visible.contains(
          Offset(
            frame.left + frame.width * 0.9,
            frame.top + frame.height * 0.95,
          ),
        ),
        isTrue,
      );
      expect((await store.readNotes()).single['document'], note['document']);
      await tester.pumpWidget(const SizedBox());
    });
  });

  testWidgets(
    'zooming an image leaves its original bytes and strokes unchanged',
    (tester) async {
      await tester.runAsync(() async {
        final store = StudyNoteStore(directory);
        final bytes = await File('assets/splash/splash_slogan.png')
            .readAsBytes();
        final id = await store.putAttachment(bytes);
        final note = imageNote(id);
        await store.saveNotes([note]);
        await tester.pumpWidget(
          MaterialApp(
            theme: buildTheme(Brightness.light, ThemeStyle.clay),
            home: StudyNoteEditor(store: store, note: note),
          ),
        );
        final action = find.byTooltip('图片操作');
        await waitFor(tester, () async => action.evaluate().isNotEmpty);
        await tester.tap(action);
        await tester.pumpAndSettle();
        await tester.tap(find.text('放大查看'));
        await waitFor(
          tester,
          () async =>
              find.byKey(const ValueKey('note-canvas')).evaluate().isNotEmpty,
        );
        final viewer = tester.widget<InteractiveViewer>(
          find.byType(InteractiveViewer),
        );
        expect(viewer.scaleEnabled, isTrue);
        expect((await store.readNotes()).single['document'], note['document']);
        expect(await store.readAttachment(id), bytes);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      });
    },
  );

  testWidgets('drawing on the cropped preview retains the canvas coordinates', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.runAsync(() async {
      final store = StudyNoteStore(directory);
      final bytes = await File('assets/splash/splash_slogan.png').readAsBytes();
      final note = imageNote(await store.putAttachment(bytes));
      await store.saveNotes([note]);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(Brightness.light, ThemeStyle.clay),
          home: StudyNoteEditor(store: store, note: note),
        ),
      );
      final viewport = find.byKey(const ValueKey('note-image-viewport:photo'));
      await waitFor(tester, () async => viewport.evaluate().isNotEmpty);
      await tester.tap(find.byTooltip('批注正文'));
      await tester.pumpAndSettle();
      final layer = find.descendant(
        of: find.byKey(const ValueKey('document-node:photo')),
        matching: find.byType(StudyNoteInkLayer),
      );
      final visibleBefore = tester.getRect(viewport);
      final point = Offset(visibleBefore.center.dx, visibleBefore.top + 8);
      final frame = tester.getRect(layer);
      await tester.tapAt(point);
      await waitFor(tester, () async {
        final nodes =
            ((await store.readNotes()).single['document'] as Map)['nodes']
                as List;
        return (nodes[1]['strokes'] as List).length == 2;
      });
      final nodes =
          (((await store.readNotes()).single['document'] as Map)['nodes']
              as List);
      final strokes = nodes[1]['strokes'] as List;
      expect(
        strokes.first,
        ((note['document'] as Map)['nodes'] as List)[1]['strokes'][0],
      );
      final newPoint = (strokes.last['points'] as List).single as List;
      expect(
        newPoint[0],
        closeTo((point.dx - frame.left) / frame.width, 0.001),
      );
      expect(
        newPoint[1],
        closeTo((point.dy - frame.top) / frame.height, 0.001),
      );
      expect(tester.getRect(viewport), visibleBefore);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  });

  testWidgets('legacy image alignment can be chosen without changing strokes', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final store = StudyNoteStore(directory);
      final bytes = await File('assets/splash/splash_slogan.png').readAsBytes();
      final id = await store.putAttachment(bytes);
      final note = imageNote(id);
      await store.saveNotes([note]);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(Brightness.light, ThemeStyle.clay),
          home: StudyNoteEditor(store: store, note: note),
        ),
      );
      final action = find.byTooltip('图片操作');
      await waitFor(tester, () async => action.evaluate().isNotEmpty);
      await tester.tap(action);
      await tester.pumpAndSettle();
      await tester.tap(find.text('调整笔迹对齐'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('按旧正文对齐'));
      await waitFor(tester, () async {
        final nodes =
            ((await store.readNotes()).single['document'] as Map)['nodes']
                as List;
        return nodes[1]['legacyImageAlignment'] == true;
      });
      final saved = (await store.readNotes()).single;
      final nodes = ((saved['document'] as Map)['nodes'] as List);
      expect(
        nodes[1]['strokes'],
        ((note['document'] as Map)['nodes'] as List)[1]['strokes'],
      );
      expect(await store.readAttachment(id), bytes);
      final backup = StudyNoteBundle(
        businessJson: '{}',
        notes: [saved],
        attachments: {id: bytes},
      );
      final restored = StudyNoteBundle.decode(backup.encode());
      expect(restored.notes.single['document'], saved['document']);
      expect(restored.attachments[id], bytes);
      await tester.tap(find.byTooltip('撤销正文'));
      await waitFor(tester, () async {
        final current =
            ((await store.readNotes()).single['document'] as Map)['nodes']
                as List;
        return current[1]['legacyImageAlignment'] == null;
      });
      await tester.tap(find.byTooltip('重做正文'));
      await waitFor(tester, () async {
        final current =
            ((await store.readNotes()).single['document'] as Map)['nodes']
                as List;
        return current[1]['legacyImageAlignment'] == true;
      });
      final viewport = find.byKey(const ValueKey('note-image-viewport:photo'));
      await tester.tapAt(tester.getCenter(viewport));
      await waitFor(
        tester,
        () async =>
            find.byKey(const ValueKey('note-canvas')).evaluate().isNotEmpty,
      );
      final image = find.descendant(
        of: find.byKey(const ValueKey('note-canvas')),
        matching: find.byType(Image),
      );
      expect(tester.widget<Image>(image).alignment, Alignment.topLeft);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  });
}
