import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homework_radar/main.dart' show buildTheme;
import 'package:homework_radar/pages/study_notes_page.dart';
import 'package:homework_radar/pages/study_note_canvas.dart';
import 'package:homework_radar/pages/study_note_review.dart';
import 'package:homework_radar/services/study_note_store.dart';
import 'package:homework_radar/ui/tokens.dart';

Future<void> waitUntil(
  WidgetTester tester,
  Future<bool> Function() ready,
) async {
  final deadline = DateTime.now().add(const Duration(seconds: 15));
  while (DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await tester.pump(const Duration(milliseconds: 20));
    if (await ready()) return;
  }
  fail('等待界面或笔记保存超时');
}

void main() {
  late Directory directory;
  setUp(
    () async => directory = await Directory.systemTemp.createTemp('notes_ui_'),
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
  testWidgets('create and save a note', (tester) async {
    final store = StudyNoteStore(directory);
    await tester.runAsync(() async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(Brightness.light, ThemeStyle.clean),
          home: StudyNotesPage(store: store),
        ),
      );
      await waitUntil(
        tester,
        () async =>
            tester
                .widget<IconButton>(
                  find.byWidgetPredicate(
                    (widget) =>
                        widget is IconButton && widget.tooltip == '新建笔记',
                  ),
                )
                .onPressed !=
            null,
      );
      await tester.tap(find.byTooltip('新建笔记'));
      await waitUntil(
        tester,
        () async =>
            find.byKey(const ValueKey('note-title')).evaluate().isNotEmpty,
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('note-title')), '复习微积分');
      await tester.enterText(find.byKey(const ValueKey('note-body')), '极限的定义');
      await tester.tap(find.text('保存'));
      await waitUntil(
        tester,
        () async => (await store.readNotes()).single['body'] == '极限的定义',
      );
      final notes = await store.readNotes();
      expect(notes.single['title'], '复习微积分');
      expect(notes.single['body'], '极限的定义');
    });
  });

  testWidgets('strokes are saved and undo restores the previous version', (
    tester,
  ) async {
    var saved = <dynamic>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.light, ThemeStyle.clean),
        home: StudyNoteCanvas(
          strokes: const [],
          onChanged: (value) async {
            saved = value;
            return true;
          },
        ),
      ),
    );
    final canvas = find.byKey(const ValueKey('note-canvas'));
    await tester.drag(canvas, const Offset(80, 50));
    await tester.pump();
    expect(saved, hasLength(1));
    expect((saved.single as Map)['points'], isNotEmpty);
    await tester.tap(find.byTooltip('撤销'));
    await tester.pump();
    expect(saved, isEmpty);
  });

  testWidgets('manual flashcard flips and marks hard', (tester) async {
    var saved = <dynamic>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.light, ThemeStyle.clean),
        home: StudyNoteReview(
          cards: const [
            {'question': '什么是极限', 'answer': '变量趋近时的值', 'hard': false},
          ],
          onChanged: (value) async {
            saved = value;
            return true;
          },
        ),
      ),
    );
    expect(find.text('什么是极限'), findsOneWidget);
    await tester.tap(find.text('什么是极限'));
    await tester.pumpAndSettle();
    expect(find.text('变量趋近时的值'), findsOneWidget);
    await tester.tap(find.text('需要再看'));
    await tester.pump();
    expect((saved.single as Map)['hard'], isTrue);
  });

  testWidgets('manual flashcard can be created and persisted', (tester) async {
    final store = StudyNoteStore(directory);
    final note = <String, dynamic>{
      'id': 'n',
      'title': '知识',
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
      await tester.ensureVisible(find.text('新建自测卡片'));
      await tester.tap(find.text('新建自测卡片'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, '问题'), '什么是导数');
      await tester.enterText(find.widgetWithText(TextField, '答案'), '瞬时变化率');
      await tester.tap(find.text('保存').last);
      await tester.pumpAndSettle();
      await waitUntil(
        tester,
        () async =>
            ((await store.readNotes()).single['cards'] as List).isNotEmpty,
      );
      final saved = (await store.readNotes()).single;
      expect((saved['cards'] as List).single['question'], '什么是导数');
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('multiple selected images are saved as original attachments', (
    tester,
  ) async {
    final store = StudyNoteStore(directory);
    final note = <String, dynamic>{
      'id': 'n',
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
      final bytes = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/aXcAAAAASUVORK5CYII=',
      );
      final first = File('${directory.path}${Platform.pathSeparator}one.png');
      final second = File('${directory.path}${Platform.pathSeparator}two.png');
      await first.writeAsBytes(bytes);
      await second.writeAsBytes(bytes);
      messenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/image_picker'),
        (call) async =>
            call.method == 'pickMultiImage' ? [first.path, second.path] : null,
      );
      await store.saveNotes([note]);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(Brightness.light, ThemeStyle.clean),
          home: StudyNoteEditor(store: store, note: note),
        ),
      );
      await tester.ensureVisible(find.text('添加图片'));
      await tester.tap(find.text('添加图片'));
      await waitUntil(
        tester,
        () async =>
            ((await store.readNotes()).single['blocks'] as List).length == 2,
      );
      final blocks = (await store.readNotes()).single['blocks'] as List;
      expect(
        await store.readAttachment(
          (blocks.first as Map)['attachmentId'] as String,
        ),
        bytes,
      );
      expect(
        await store.readAttachment(
          (blocks.last as Map)['attachmentId'] as String,
        ),
        bytes,
      );
    });
  });

  testWidgets('leaving the editor saves unsaved text', (tester) async {
    final store = StudyNoteStore(directory);
    await tester.runAsync(() async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(Brightness.light, ThemeStyle.clean),
          home: StudyNotesPage(store: store),
        ),
      );
      await waitUntil(
        tester,
        () async =>
            tester
                .widget<IconButton>(
                  find.byWidgetPredicate(
                    (widget) =>
                        widget is IconButton && widget.tooltip == '新建笔记',
                  ),
                )
                .onPressed !=
            null,
      );
      await tester.tap(find.byTooltip('新建笔记'));
      await waitUntil(
        tester,
        () async =>
            find.byKey(const ValueKey('note-body')).evaluate().isNotEmpty,
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('note-body')), '退出前的内容');
      await tester.pageBack();
      await waitUntil(
        tester,
        () async => find.byType(StudyNoteEditor).evaluate().isEmpty,
      );
      await tester.pumpAndSettle();
      expect((await store.readNotes()).single['body'], '退出前的内容');
      expect(find.byType(StudyNoteEditor), findsNothing);
    });
  });

  for (final style in ThemeStyle.values) {
    for (final brightness in Brightness.values) {
      testWidgets(
        '${style.name} ${brightness.name} notes fit on narrow screen',
        (tester) async {
          final store = StudyNoteStore(directory);
          tester.view.physicalSize = const Size(320, 740);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          await tester.runAsync(() async {
            await store.saveNotes([
              {
                'id': 'n',
                'title': '复习笔记',
                'body': '记录内容',
                'course': '数学',
                'chapter': '第一章',
              },
            ]);
            await tester.pumpWidget(
              MaterialApp(
                theme: buildTheme(brightness, style),
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: const TextScaler.linear(1.6)),
                  child: child!,
                ),
                home: StudyNotesPage(store: store),
              ),
            );
            await waitUntil(
              tester,
              () async => find.text('复习笔记').evaluate().isNotEmpty,
            );
            expect(find.text('复习笔记'), findsOneWidget);
            expect(tester.takeException(), isNull);
            await tester.tap(find.text('复习笔记'));
            await tester.pumpAndSettle();
            expect(find.byKey(const ValueKey('note-title')), findsOneWidget);
            expect(tester.takeException(), isNull);
          });
        },
      );
    }
  }
}
