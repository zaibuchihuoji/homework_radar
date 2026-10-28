import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:crypto/crypto.dart';
import 'package:homework_radar/main.dart' show buildTheme;
import 'package:homework_radar/pages/study_notes_page.dart';
import 'package:homework_radar/ui/tokens.dart';
import 'package:homework_radar/services/study_note_bundle.dart';
import 'package:homework_radar/services/study_note_store.dart';

void main() {
  late Directory directory;
  setUp(
    () async =>
        directory = await Directory.systemTemp.createTemp('note_folders_'),
  );
  tearDown(() async {
    final root = (await Directory.systemTemp.resolveSymbolicLinks())
        .toLowerCase();
    final target = (await directory.resolveSymbolicLinks()).toLowerCase();
    if (!target.startsWith('$root${Platform.pathSeparator}')) {
      throw StateError('Test directory is outside temp');
    }
    await directory.delete(recursive: true);
  });

  test(
    'folder and note move are atomic, with restorable old history',
    () async {
      final store = StudyNoteStore(directory);
      final old = <String, dynamic>{
        'id': 'n',
        'title': '旧笔记',
        'body': '旧正文',
        'extra': '保留',
      };
      await store.saveNotes([old]);
      final oldVersion = await store.revision();
      await store.updateLibrary(
        (library) => StudyNoteLibrary(
          folders: [
            {'id': 'f', 'name': '数学'},
            {'id': 'empty', 'name': '空文件夹'},
          ],
          notes: [
            for (final note in library.notes) {...note, 'notebookId': 'f'},
          ],
        ),
      );
      final library = await store.readLibrary();
      expect(library.folders.map((f) => f['name']), ['数学', '空文件夹']);
      expect(library.notes.single, {...old, 'notebookId': 'f'});
      final current = await store.revision();
      expect((await store.readHistoryLibrary(oldVersion)).folders, isEmpty);
      await expectLater(
        store.updateLibrary(
          (library) => StudyNoteLibrary(notes: library.notes, folders: []),
        ),
        throwsFormatException,
      );
      expect(await store.revision(), current);
      await store.restoreHistory(oldVersion, expectedRevision: current);
      final restored = await store.readLibrary();
      expect(restored.notes.single, old);
      expect(restored.folders, isEmpty);
      expect(
        (await store.readHistoryLibrary(current)).folders,
        library.folders,
      );
    },
  );

  test('backup preserves empty folders, assignments, and folder history', () {
    final folders = <Map<String, dynamic>>[
      {'id': 'f', 'name': '数学'},
      {'id': 'e', 'name': '空文件夹'},
    ];
    final notes = <Map<String, dynamic>>[
      {'id': 'n', 'body': '内容', 'notebookId': 'f'},
    ];
    final bundle = StudyNoteBundle(
      businessJson: '{}',
      notes: notes,
      attachments: {},
      folders: folders,
      history: [
        [
          {'id': 'n', 'body': '旧内容'},
        ],
      ],
      historyFolders: [[]],
    );
    final bytes = bundle.encode();
    final size = ByteData.sublistView(bytes, 8, 12).getUint32(0);
    final header = jsonDecode(utf8.decode(bytes.sublist(44, 44 + size))) as Map;
    expect(header['version'], 4);
    final restored = StudyNoteBundle.decode(bytes);
    expect(restored.folders, folders);
    expect(restored.notes, notes);
    expect(restored.historyFolders, [[]]);
    expect(
      () => StudyNoteBundle(
        businessJson: '{}',
        notes: notes,
        attachments: {},
      ).encode(),
      throwsFormatException,
    );
    header['version'] = 3;
    final changed = utf8.encode(jsonEncode(header));
    final length = ByteData(4)..setUint32(0, changed.length);
    final downgraded = BytesBuilder()
      ..add(bytes.sublist(0, 8))
      ..add(length.buffer.asUint8List())
      ..add(sha256.convert(changed).bytes)
      ..add(changed)
      ..add(bytes.sublist(44 + size));
    expect(
      () => StudyNoteBundle.decode(downgraded.takeBytes()),
      throwsFormatException,
    );
  });

  testWidgets(
    'create, rename, move and delete a folder without deleting notes',
    (tester) async {
      final store = StudyNoteStore(directory);
      await tester.runAsync(() async {
        await store.saveNotes([
          {
            'id': 'n',
            'title': '知识笔记',
            'body': '保留正文',
            'cards': <dynamic>[],
            'blocks': <dynamic>[],
          },
        ]);
        await tester.pumpWidget(
          MaterialApp(
            theme: buildTheme(Brightness.light, ThemeStyle.clay),
            home: StudyNotesPage(store: store),
          ),
        );
        Future<void> wait(Future<bool> Function() predicate) async {
          for (var i = 0; i < 200; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 20));
            await tester.pump(const Duration(milliseconds: 20));
            if (await predicate()) return;
          }
          fail('等待文件夹界面超时');
        }

        await wait(() async => find.text('知识笔记').evaluate().isNotEmpty);
        await tester.tap(find.byTooltip('浏览笔记分类'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('新建文件夹'));
        await tester.pumpAndSettle();
        await tester.enterText(find.widgetWithText(TextField, '文件夹名称'), '数学');
        await tester.tap(find.text('保存').last);
        await wait(() async => (await store.readLibrary()).folders.isNotEmpty);
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('笔记操作'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('移动到文件夹'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('数学').last);
        await wait(
          () async => (await store.readNotes()).single['notebookId'] != null,
        );
        await tester.tap(find.byTooltip('浏览笔记分类'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('文件夹操作'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('重命名'));
        await tester.pumpAndSettle();
        await tester.enterText(find.widgetWithText(TextField, '文件夹名称'), '数学复习');
        await tester.tap(find.text('保存').last);
        await wait(
          () async =>
              (await store.readLibrary()).folders.single['name'] == '数学复习',
        );
        expect((await store.readNotes()).single['body'], '保留正文');
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('浏览笔记分类'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('文件夹操作'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('删除文件夹'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('删除文件夹').last);
        await wait(() async => (await store.readLibrary()).folders.isEmpty);
        final library = await store.readLibrary();
        expect(library.notes.single['body'], '保留正文');
        expect(library.notes.single['notebookId'], isNull);
        await tester.pumpWidget(const SizedBox());
      });
    },
  );

  testWidgets('choose a folder inside the editor and reopen the note', (
    tester,
  ) async {
    final store = StudyNoteStore(directory);
    final note = <String, dynamic>{
      'id': 'edit',
      'title': '复习',
      'body': '重要知识',
      'cards': <dynamic>[],
      'blocks': <dynamic>[],
    };
    final folders = <Map<String, dynamic>>[
      {'id': 'math', 'name': '数学'},
    ];
    await tester.runAsync(() async {
      await store.updateLibrary(
        (_) => StudyNoteLibrary(notes: [note], folders: folders),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(Brightness.light, ThemeStyle.clean),
          home: StudyNoteEditor(store: store, note: note, folders: folders),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('未分类 ·'));
      for (var i = 0; i < 200 && find.text('数学').evaluate().isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await tester.pump(const Duration(milliseconds: 20));
      }
      await tester.tap(find.text('数学').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('保存'));
      for (
        var i = 0;
        i < 200 && (await store.readNotes()).single['notebookId'] != 'math';
        i++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await tester.pump(const Duration(milliseconds: 20));
      }
      final saved = (await store.readNotes()).single;
      expect(saved['notebookId'], 'math');
      expect(saved['body'], '重要知识');
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(Brightness.light, ThemeStyle.clean),
          home: StudyNoteEditor(store: store, note: saved, folders: folders),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('数学 ·'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  });

  testWidgets('folder navigation fits each theme with large text', (
    tester,
  ) async {
    final store = StudyNoteStore(directory);
    await tester.runAsync(() async {
      await store.updateLibrary(
        (_) => StudyNoteLibrary(
          notes: [
            {'id': 'n', 'title': '样例', 'body': '内容'},
          ],
          folders: [
            {'id': 'long', 'name': '一门很长的学习课程与复习资料文件夹'},
          ],
        ),
      );
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      for (final style in ThemeStyle.values) {
        for (final brightness in Brightness.values) {
          await tester.pumpWidget(
            MaterialApp(
              theme: buildTheme(brightness, style),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: const TextScaler.linear(1.3)),
                child: child!,
              ),
              home: StudyNotesPage(store: store),
            ),
          );
          for (var i = 0; i < 100 && find.text('样例').evaluate().isEmpty; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 10));
            await tester.pump(const Duration(milliseconds: 20));
          }
          await tester.tap(find.byTooltip('浏览笔记分类'));
          await tester.pumpAndSettle();
          expect(find.text('我的文件夹'), findsOneWidget);
          expect(
            tester.takeException(),
            isNull,
            reason: '${style.name} ${brightness.name}',
          );
          await tester.pumpWidget(const SizedBox());
        }
      }
    });
  });
}
