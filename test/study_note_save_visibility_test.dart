import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homework_radar/main.dart' show buildTheme;
import 'package:homework_radar/pages/study_notes_page.dart';
import 'package:homework_radar/services/study_note_store.dart';
import 'package:homework_radar/ui/tokens.dart';

class RetryStore extends StudyNoteStore {
  RetryStore(super.directory);
  bool failWrites = false;

  @override
  Future<void> updateNotes(
    List<Map<String, dynamic>> Function(List<Map<String, dynamic>>) update,
  ) async {
    if (failWrites) throw const FileSystemException('synthetic failure');
    return super.updateNotes(update);
  }
}

void main() {
  testWidgets(
    'save failure remains visible while editing a long note and can retry',
    (tester) async {
      tester.view.physicalSize = const Size(320, 740);
      tester.view.devicePixelRatio = 1;
      tester.view.viewInsets = const FakeViewPadding(bottom: 260);
      addTearDown(tester.view.reset);
      final directory = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('note_save_visible_'),
      ))!;
      addTearDown(() async {
        final root = (await Directory.systemTemp.resolveSymbolicLinks())
            .toLowerCase();
        final target = (await directory.resolveSymbolicLinks()).toLowerCase();
        if (!target.startsWith('$root${Platform.pathSeparator}')) {
          throw StateError('Test directory is outside the temp root');
        }
        await directory.delete(recursive: true);
      });
      await tester.runAsync(() async {
        final store = RetryStore(directory);
        final note = <String, dynamic>{
          'id': 'long-note',
          'title': '长笔记',
          'body': '原内容',
          'blocks': <dynamic>[],
          'cards': <dynamic>[],
          'document': {
            'version': 1,
            'nodes': [
              for (var i = 0; i < 22; i++)
                {
                  'id': 'p$i',
                  'type': 'text',
                  'text': '第 $i 段已有内容',
                  'style': 'paragraph',
                  'marks': <dynamic>[],
                  'annotations': <dynamic>[],
                },
            ],
          },
        };
        await store.saveNotes([note]);
        store.failWrites = true;
        await tester.pumpWidget(
          MaterialApp(
            theme: buildTheme(Brightness.light, ThemeStyle.clay),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(1.6)),
              child: child!,
            ),
            home: StudyNoteEditor(store: store, note: note),
          ),
        );
        await tester.pumpAndSettle();
        final last = find.byKey(const ValueKey('note-text:p21'));
        await tester.ensureVisible(last);
        await tester.pumpAndSettle();
        await tester.enterText(last, '尚未保存的修改');
        await tester.tap(find.widgetWithText(TextButton, '保存'));
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await tester.pumpAndSettle();
        final banner = find.byKey(const ValueKey('note-save-error'));
        expect(banner, findsOneWidget);
        expect(tester.getRect(banner).top, greaterThanOrEqualTo(0));
        expect(tester.getRect(banner).bottom, lessThan(480));
        expect(find.text('重试保存'), findsOneWidget);
        store.failWrites = false;
        await tester.tap(find.text('重试保存'));
        final deadline = DateTime.now().add(const Duration(seconds: 12));
        while (DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          await tester.pump(const Duration(milliseconds: 20));
          if (((await store.readNotes()).single['body'] as String).contains(
                '尚未保存的修改',
              ) &&
              banner.evaluate().isEmpty) {
            break;
          }
        }
        expect(
          ((await store.readNotes()).single['body'] as String),
          contains('尚未保存的修改'),
        );
        expect(find.byKey(const ValueKey('note-save-error')), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      });
    },
  );
}
