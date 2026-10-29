import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homework_radar/main.dart' show buildTheme;
import 'package:homework_radar/pages/study_note_canvas.dart';
import 'package:homework_radar/pages/study_notes_page.dart';
import 'package:homework_radar/services/study_note_store.dart';
import 'package:homework_radar/ui/tokens.dart';

void main() {
  testWidgets('image editor and annotation toolbar fit every theme', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final directory = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('note_all_themes_'),
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
      final store = StudyNoteStore(directory);
      final bytes = await File('assets/splash/splash_slogan.png').readAsBytes();
      final attachment = await store.putAttachment(bytes);
      final note = <String, dynamic>{
        'id': 'themes',
        'title': '图文笔记',
        'body': '文字内容',
        'blocks': <dynamic>[],
        'cards': <dynamic>[],
        'document': {
          'version': 1,
          'nodes': [
            {
              'id': 'photo',
              'type': 'image',
              'attachmentId': attachment,
              'strokes': <dynamic>[],
            },
            {
              'id': 'text',
              'type': 'text',
              'text': '文字内容',
              'style': 'paragraph',
              'marks': <dynamic>[],
              'annotations': <dynamic>[],
            },
          ],
        },
      };
      await store.saveNotes([note]);
      for (final style in ThemeStyle.values) {
        for (final brightness in Brightness.values) {
          final theme = buildTheme(brightness, style);
          Widget scaled(Widget child) => MaterialApp(
            theme: theme,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(1.6)),
              child: child!,
            ),
            home: child,
          );
          tester.view.viewInsets = const FakeViewPadding(bottom: 260);
          await tester.pumpWidget(
            scaled(
              StudyNoteEditor(
                key: ValueKey('${style.name}-${brightness.name}'),
                store: store,
                note: note,
              ),
            ),
          );
          await tester.pumpAndSettle();
          final imageViewport = find.byKey(
            const ValueKey('note-image-viewport:photo'),
          );
          for (var i = 0; i < 100 && imageViewport.evaluate().isEmpty; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 20));
            await tester.pump(const Duration(milliseconds: 20));
          }
          expect(
            imageViewport,
            findsOneWidget,
            reason: '${style.name} ${brightness.name}',
          );
          expect(
            find.widgetWithText(TextButton, '删除图片'),
            findsOneWidget,
            reason: '${style.name} ${brightness.name}',
          );
          await tester.tap(find.byTooltip('批注正文'));
          await tester.pumpAndSettle();
          expect(
            find.text('撤销'),
            findsOneWidget,
            reason: '${style.name} ${brightness.name}',
          );
          expect(
            find.text('重做'),
            findsOneWidget,
            reason: '${style.name} ${brightness.name}',
          );
          expect(
            find.text('橡皮'),
            findsOneWidget,
            reason: '${style.name} ${brightness.name}',
          );
          expect(
            find.text('设置'),
            findsOneWidget,
            reason: '${style.name} ${brightness.name}',
          );
          expect(
            tester.takeException(),
            isNull,
            reason: '${style.name} ${brightness.name} editor',
          );
          await tester.pumpWidget(const SizedBox());
          tester.view.viewInsets = const FakeViewPadding();
          await tester.pumpWidget(
            scaled(
              StudyNoteCanvas(
                image: bytes,
                strokes: const [],
                onChanged: (_) async => true,
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(
            find.text('画笔'),
            findsOneWidget,
            reason: '${style.name} ${brightness.name}',
          );
          expect(
            find.text('橡皮'),
            findsOneWidget,
            reason: '${style.name} ${brightness.name}',
          );
          expect(
            find.text('缩放'),
            findsOneWidget,
            reason: '${style.name} ${brightness.name}',
          );
          expect(
            find.byTooltip('画笔设置'),
            findsOneWidget,
            reason: '${style.name} ${brightness.name}',
          );
          expect(
            tester.takeException(),
            isNull,
            reason: '${style.name} ${brightness.name} canvas',
          );
          await tester.pumpWidget(const SizedBox());
          await tester.pumpWidget(
            scaled(
              StudyNoteCanvas(
                strokes: const [],
                items: const [
                  {
                    'id': 'photo',
                    'type': 'image',
                    'attachmentId': 'example',
                    'x': 0.1,
                    'y': 0.1,
                    'width': 0.4,
                    'height': 0.3,
                  },
                ],
                readAttachment: (_) async => bytes,
                saveAttachment: (_) async => 'example',
                onChanged: (_) async => true,
                onCanvasChanged: (_, _) async => true,
              ),
            ),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.byTooltip('移动画布内容'));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const ValueKey('canvas-item:photo')));
          await tester.pumpAndSettle();
          expect(
            find.byTooltip('删除画布内容'),
            findsOneWidget,
            reason: '${style.name} ${brightness.name}',
          );
          expect(
            tester.takeException(),
            isNull,
            reason: '${style.name} ${brightness.name} object actions',
          );
          await tester.pumpWidget(const SizedBox());
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
  });
}
