import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homework_radar/app_state.dart';
import 'package:homework_radar/main.dart' show buildTheme;
import 'package:homework_radar/pages/home_page.dart';
import 'package:homework_radar/services/storage.dart';
import 'package:homework_radar/services/widget_theme.dart';
import 'package:homework_radar/ui/capture_parts.dart';
import 'package:homework_radar/ui/themed_masthead.dart';
import 'package:homework_radar/ui/theme_forms.dart';
import 'package:homework_radar/ui/tokens.dart';
import 'package:shared_preferences/shared_preferences.dart';

double contrast(Color a, Color b) {
  final x = a.computeLuminance(), y = b.computeLuminance();
  return (x > y ? x + .05 : y + .05) / (x > y ? y + .05 : x + .05);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final style in ThemeStyle.values) {
    for (final brightness in [
      Brightness.light,
      if (style == ThemeStyle.clean || style == ThemeStyle.green)
        Brightness.dark,
    ]) {
      testWidgets(
        '${style.name}/${brightness.name}: home header faces align and retain search and add actions',
        (t) async {
          SharedPreferences.setMockInitialValues({});
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(
                const MethodChannel('homework_radar/platform'),
                (_) async => null,
              );
          await t.runAsync(Storage.init);
          final state = AppState();
          addTearDown(state.dispose);
          t.view.physicalSize = const Size(320, 800);
          t.view.devicePixelRatio = 1;
          addTearDown(t.view.reset);
          await t.pumpWidget(
            MaterialApp(
              theme: buildTheme(brightness, style),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: const TextScaler.linear(1.3)),
                child: child!,
              ),
              home: HomePage(state: state, onGoAccounts: () {}),
            ),
          );
          await t.pumpAndSettle();
          final faces = <Rect>[];
          for (final label in ['搜索作业', '同步作业', '添加作业']) {
            final button = find
                .ancestor(
                  of: find.byTooltip(label),
                  matching: find.byType(IconButton),
                )
                .first;
            final decoration = find.ancestor(
              of: button,
              matching: find.byType(DecoratedBox),
            );
            final face = decoration.evaluate().isEmpty
                ? find
                      .descendant(of: button, matching: find.byType(Material))
                      .first
                : decoration.first;
            faces.add(t.getRect(face));
            expect(t.getSize(button).shortestSide, greaterThanOrEqualTo(48));
          }
          expect(faces.map((r) => r.size).toSet(), hasLength(1));
          expect(faces.map((r) => r.center.dy).toSet(), hasLength(1));
          expect(
            faces[1].left - faces[0].right,
            faces[2].left - faces[1].right,
          );
          await t.tap(find.byTooltip('搜索作业'));
          await t.pumpAndSettle();
          expect(find.byType(TextField), findsOneWidget);
          await t.tap(find.byTooltip('关闭搜索'));
          await t.pumpAndSettle();
          await t.tap(find.byTooltip('添加作业'));
          await t.pumpAndSettle();
          expect(find.text('手动添加'), findsOneWidget);
          expect(find.text('识别添加'), findsOneWidget);
          expect(t.takeException(), isNull);
          await t.pumpWidget(const SizedBox());
        },
      );
    }
  }

  test('clay is an independent optional theme with readable action colors', () {
    final style = themeStyleFromName('clay');
    expect(style.name, 'clay');
    expect(style.label, '陶白');
    expect(themeStyleFromName(null), ThemeStyle.clean);
    expect(themeStyleFromName('paper'), ThemeStyle.paper);
    final theme = buildTheme(Brightness.light, style);
    final p = theme.extension<StylePalette>()!;
    expect(p.bg, isNot(stylePalette(ThemeStyle.paper, Brightness.light).bg));
    expect(contrast(p.ink, p.bg), greaterThanOrEqualTo(7));
    expect(contrast(p.ink2, p.card), greaterThanOrEqualTo(4.5));
    expect(contrast(p.onAccent, p.accentFill), greaterThanOrEqualTo(4.5));
    final picker = theme.datePickerTheme;
    final todaySelected = <WidgetState>{WidgetState.selected};
    expect(
      contrast(
        picker.todayForegroundColor!.resolve(todaySelected)!,
        picker.todayBackgroundColor!.resolve(todaySelected)!,
      ),
      greaterThanOrEqualTo(4.5),
    );
    final button = theme.filledButtonTheme.style!;
    expect(
      contrast(
        button.foregroundColor!.resolve({})!,
        button.backgroundColor!.resolve({})!,
      ),
      greaterThanOrEqualTo(4.5),
    );
    expect(theme.textTheme.bodyLarge!.fontFamily, isNot('StudySerif'));
    expect(theme.textTheme.titleLarge!.fontFamily, 'StudySerif');
    expect(theme.textTheme.bodyMedium!.fontFamily, isNot('StudySerif'));
  });

  testWidgets(
    'clay headings use the bundled serif while body copy stays sans',
    (t) async {
      await t.pumpWidget(
        MaterialApp(
          theme: buildTheme(Brightness.light, themeStyleFromName('clay')),
          home: const Scaffold(
            body: Column(
              children: [
                ThemedMasthead(dateLine: '10 月 27 日'),
                CaptureHeading(
                  step: '01',
                  title: '识别作业',
                  description: '粘贴原文后核对',
                ),
                ThemeEditorHeading(title: '编辑作业', kicker: 'EDIT'),
              ],
            ),
          ),
        ),
      );
      for (final label in ['作业通', '识别作业', '编辑作业']) {
        final element = t.element(find.text(label));
        final text = t.widget<Text>(find.text(label));
        expect(
          DefaultTextStyle.of(element).style.merge(text.style).fontFamily,
          'StudySerif',
          reason: label,
        );
      }
      final text = t.widget<Text>(find.text('粘贴原文后核对'));
      expect(text.style?.fontFamily, isNot('StudySerif'));
      expect(t.takeException(), isNull);
    },
  );

  test(
    'selecting clay changes only appearance; widgets receive the same palette',
    () async {
      SharedPreferences.setMockInitialValues({
        'homework_json': '[{"id":"old","future":{"keep":true}}]',
        'courses_json': '[{"id":"old-course","unknown":42}]',
        'hidden_items': '["old"]',
        'widget_transparent': true,
        'ui_style': 'paper',
      });
      final saved = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel('home_widget'), (
            call,
          ) async {
            if (call.method == 'saveWidgetData') {
              saved.add((call.arguments as Map)['data'] as String);
            }
            return true;
          });
      await Storage.init();
      final prefs = await SharedPreferences.getInstance();
      final original = {for (final k in prefs.getKeys()) k: prefs.get(k)};
      final state = AppState();
      addTearDown(state.dispose);
      await state.setStyle(themeStyleFromName('clay'));
      await WidgetTheme.push(state.style, ThemeMode.system);
      expect(Storage.uiStyle(), 'clay');
      for (final key in original.keys.where((k) => k != 'ui_style')) {
        expect(prefs.get(key), original[key], reason: key);
      }
      expect(jsonDecode(saved.last)['style'], 'clay');
      final snapshot = widgetThemeSnapshot(state.style, ThemeMode.system);
      expect(snapshot['light'], snapshot['dark']);
      final actual = buildTheme(
        Brightness.dark,
        state.style,
      ).extension<StylePalette>()!;
      expect((snapshot['dark'] as Map)['ink'], actual.ink.toARGB32());
    },
  );
}
