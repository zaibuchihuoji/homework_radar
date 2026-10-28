import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homework_radar/main.dart' show buildTheme;
import 'package:homework_radar/pages/study_notes_page.dart';
import 'package:homework_radar/services/study_note_store.dart';
import 'package:homework_radar/ui/tokens.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> waitFor(WidgetTester tester, Finder finder) async {
  final deadline = DateTime.now().add(const Duration(seconds: 12));
  while (DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await tester.pump(const Duration(milliseconds: 20));
    if (finder.evaluate().isNotEmpty) return;
  }
  fail('等待笔记界面超时: $finder');
}

Finder option(String prefix, String value) =>
    find.byKey(ValueKey('$prefix:$value'));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    directory = await Directory.systemTemp.createTemp('note_filter_ui_');
  });
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
    'empty filters open anchored menus without the default grey selection',
    (tester) async {
      final store = StudyNoteStore(directory);
      await tester.runAsync(() async {
        await store.saveNotes([]);
        final revision = await store.revision();
        await tester.pumpWidget(
          MaterialApp(
            theme: buildTheme(Brightness.light, ThemeStyle.clean),
            home: StudyNotesPage(store: store),
          ),
        );
        await waitFor(tester, find.text('还没有笔记，点击右上角开始记录'));
        for (final (tooltip, prefix) in [
          ('按课程筛选', 'note-course-option'),
          ('按章节筛选', 'note-chapter-option'),
        ]) {
          final trigger = find.byTooltip(tooltip);
          final button = tester.widget<PopupMenuButton<String>>(
            find
                .ancestor(
                  of: trigger,
                  matching: find.byType(PopupMenuButton<String>),
                )
                .first,
          );
          expect(button.initialValue, '');
          expect(button.position, PopupMenuPosition.under);
          expect(
            button.popUpAnimationStyle?.duration,
            const Duration(milliseconds: 160),
          );
          final triggerRect = tester.getRect(trigger);
          await tester.tap(trigger);
          await tester.pumpAndSettle();
          final all = option(prefix, '');
          expect(all, findsOneWidget);
          expect(
            Theme.of(tester.element(all)).highlightColor,
            Colors.transparent,
          );
          expect(
            tester.getRect(all).top,
            greaterThanOrEqualTo(triggerRect.bottom),
          );
          expect(find.byType(BottomSheet), findsNothing);
          expect(
            find.descendant(
              of: all,
              matching: find.byIcon(Icons.check_rounded),
            ),
            findsOneWidget,
          );
          expect(
            find.descendant(
              of: all,
              matching: find.byWidgetPredicate(
                (w) => w is Semantics && w.properties.selected == true,
              ),
            ),
            findsOneWidget,
          );
          await tester.tapAt(const Offset(10, 10));
          await tester.pumpAndSettle();
          expect(all, findsNothing);
        }
        expect(await store.revision(), revision);
        expect(await store.readNotes(), isEmpty);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      });
    },
  );

  testWidgets(
    'course and chapter menus preserve filtering and do not write notes',
    (tester) async {
      final store = StudyNoteStore(directory);
      final notes = [
        {
          'id': 'math1',
          'title': '数学第一章笔记',
          'body': '正文一',
          'course': '数学',
          'chapter': '第一章',
        },
        {
          'id': 'math2',
          'title': '数学第二章笔记',
          'body': '正文二',
          'course': '数学',
          'chapter': '第二章',
        },
        {
          'id': 'physics',
          'title': '物理笔记',
          'body': '正文三',
          'course': '物理',
          'chapter': '力学',
        },
      ];
      await tester.runAsync(() async {
        await store.saveNotes(notes);
        final before = jsonEncode(await store.readNotes());
        final revision = await store.revision();
        await tester.pumpWidget(
          MaterialApp(
            theme: buildTheme(Brightness.light, ThemeStyle.clean),
            home: StudyNotesPage(store: store),
          ),
        );
        await waitFor(tester, find.text('数学第一章笔记'));
        await tester.tap(find.byTooltip('按课程筛选'));
        await tester.pumpAndSettle();
        await tester.tap(option('note-course-option', '数学'));
        await tester.pumpAndSettle();
        expect(find.text('数学第一章笔记'), findsOneWidget);
        expect(find.text('物理笔记'), findsNothing);
        await tester.tap(find.byTooltip('按课程筛选'));
        await tester.pumpAndSettle();
        expect(
          find.descendant(
            of: option('note-course-option', '数学'),
            matching: find.byIcon(Icons.check_rounded),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: option('note-course-option', ''),
            matching: find.byIcon(Icons.check_rounded),
          ),
          findsNothing,
        );
        await tester.tapAt(const Offset(10, 10));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('按章节筛选'));
        await tester.pumpAndSettle();
        await tester.tap(option('note-chapter-option', '第一章'));
        await tester.pumpAndSettle();
        expect(find.text('数学第一章笔记'), findsOneWidget);
        expect(find.text('数学第二章笔记'), findsNothing);
        await tester.tap(find.byTooltip('按课程筛选'));
        await tester.pumpAndSettle();
        await tester.tap(option('note-course-option', '物理'));
        await tester.pumpAndSettle();
        expect(find.text('物理笔记'), findsOneWidget);
        expect(find.text('全部章节'), findsOneWidget);
        await tester.tap(find.byTooltip('按课程筛选'));
        await tester.pumpAndSettle();
        await tester.tap(option('note-course-option', ''));
        await tester.pumpAndSettle();
        expect(find.text('数学第一章笔记'), findsOneWidget);
        expect(find.text('物理笔记'), findsOneWidget);
        expect(jsonEncode(await store.readNotes()), before);
        expect(await store.revision(), revision);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      });
    },
  );

  testWidgets('long course menus can scroll to every option', (tester) async {
    final store = StudyNoteStore(directory);
    tester.view.physicalSize = const Size(320, 680);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final notes = [
      for (var i = 0; i < 26; i++)
        {
          'id': 'n$i',
          'title': '笔记 $i',
          'body': '原始正文 $i',
          'course': '课程 ${i.toString().padLeft(2, '0')} 专业方向及章节说明',
          'chapter': '第一章',
        },
    ];
    await tester.runAsync(() async {
      await store.saveNotes(notes);
      final before = jsonEncode(await store.readNotes());
      final revision = await store.revision();
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(Brightness.light, ThemeStyle.clean),
          home: StudyNotesPage(store: store),
        ),
      );
      await waitFor(tester, find.text('笔记 0'));
      await tester.tap(find.byTooltip('按课程筛选'));
      await tester.pumpAndSettle();
      final target = option('note-course-option', '课程 25 专业方向及章节说明');
      await tester.ensureVisible(target);
      await tester.pumpAndSettle();
      await tester.tap(target);
      await tester.pumpAndSettle();
      expect(find.text('笔记 25'), findsOneWidget);
      await tester.tap(find.byTooltip('按课程筛选'));
      await tester.pumpAndSettle();
      expect(target.hitTestable(), findsOneWidget);
      expect(
        find.descendant(of: target, matching: find.byIcon(Icons.check_rounded)),
        findsOneWidget,
      );
      expect(jsonEncode(await store.readNotes()), before);
      expect(await store.revision(), revision);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  });

  for (final style in ThemeStyle.values) {
    for (final brightness in [
      Brightness.light,
      if (style == ThemeStyle.clean || style == ThemeStyle.green)
        Brightness.dark,
    ]) {
      testWidgets(
        '${style.name} ${brightness.name}: both popups fit narrow screens and large text',
        (tester) async {
          final store = StudyNoteStore(directory);
          tester.view.physicalSize = const Size(320, 740);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          await tester.runAsync(() async {
            await store.saveNotes([
              {'id': 'n', 'title': '示例笔记', 'course': '数学', 'chapter': '第一章'},
            ]);
            final revision = await store.revision();
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
            await waitFor(tester, find.text('示例笔记'));
            for (final (tooltip, prefix) in [
              ('按课程筛选', 'note-course-option'),
              ('按章节筛选', 'note-chapter-option'),
            ]) {
              await tester.tap(find.byTooltip(tooltip));
              await tester.pumpAndSettle();
              expect(option(prefix, ''), findsOneWidget);
              expect(
                find.descendant(
                  of: option(prefix, ''),
                  matching: find.byIcon(Icons.check_rounded),
                ),
                findsOneWidget,
              );
              expect(tester.takeException(), isNull);
              await tester.tapAt(const Offset(10, 10));
              await tester.pumpAndSettle();
            }
            expect(await store.revision(), revision);
            await tester.pumpWidget(const SizedBox());
          });
        },
      );
    }
  }

  testWidgets('popup honors reduced motion', (tester) async {
    final store = StudyNoteStore(directory);
    await tester.runAsync(() async {
      await store.saveNotes([]);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(Brightness.light, ThemeStyle.clean),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: child!,
          ),
          home: StudyNotesPage(store: store),
        ),
      );
      await waitFor(tester, find.text('还没有笔记，点击右上角开始记录'));
      final trigger = find.byTooltip('按课程筛选');
      final button = tester.widget<PopupMenuButton<String>>(
        find
            .ancestor(
              of: trigger,
              matching: find.byType(PopupMenuButton<String>),
            )
            .first,
      );
      expect(button.popUpAnimationStyle, AnimationStyle.noAnimation);
      await tester.tap(trigger);
      await tester.pumpAndSettle();
      expect(option('note-course-option', ''), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  });
}
