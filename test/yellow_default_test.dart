import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homework_radar/main.dart' show buildTheme;
import 'package:homework_radar/services/storage.dart';
import 'package:homework_radar/services/backup_service.dart';
import 'package:homework_radar/ui/themed_navigation.dart';
import 'package:homework_radar/ui/tokens.dart';
import 'package:shared_preferences/shared_preferences.dart';

double contrast(Color a, Color b) {
  final x = a.computeLuminance(), y = b.computeLuminance();
  return ((x > y ? x : y) + .05) / ((x > y ? y : x) + .05);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'default keeps persisted key with dark commands and yellow accents',
    () async {
      SharedPreferences.setMockInitialValues({});
      await Storage.init();
      final style = themeStyleFromName(Storage.uiStyle());
      expect(style, ThemeStyle.clean);
      final t = buildTheme(Brightness.light, style);
      expect(
        t.filledButtonTheme.style!.backgroundColor!.resolve({}),
        const Color(0xFF202423),
      );
      expect(
        t.floatingActionButtonTheme.backgroundColor,
        const Color(0xFFFFE044),
      );
      expect(t.scaffoldBackgroundColor, const Color(0xFFFFFFFF));
    },
  );
  test('green is independently selectable and retains the original light and dark palette', () {
    final green = ThemeStyle.values.where((s) => s.name == 'green').firstOrNull;
    expect(green, isNotNull);
    if (green == null) return;
    expect(
      stylePalette(green, Brightness.light).accent,
      const Color(0xFF087F6D),
    );
    expect(buildTheme(Brightness.dark, green).brightness, Brightness.dark);
    expect(
      stylePalette(green, Brightness.dark).accent,
      const Color(0xFF34D399),
    );
  });
  test('theme changes preserve unrelated persisted data', () async {
    SharedPreferences.setMockInitialValues({
      'ui_style': 'clean',
      'homework': 'old homework bytes',
      'courses': 'old course bytes',
      'hidden_items': 'old hidden bytes',
      'theme_mode': 'dark',
    });
    await Storage.init();
    final p = await SharedPreferences.getInstance();
    final before = {for (final k in p.getKeys()) k: p.get(k)};
    await Storage.saveUiStyle('green');
    await Storage.saveUiStyle('clean');
    expect({for (final k in p.getKeys()) k: p.get(k)}, before);
  });
  test(
    'green preference survives backup and restore using its own key',
    () async {
      SharedPreferences.setMockInitialValues({});
      await Storage.init();
      await Storage.saveUiStyle('green');
      final backup = BackupService.encode();
      SharedPreferences.setMockInitialValues({});
      await Storage.init();
      await BackupService.importJson(backup);
      expect(Storage.uiStyle(), 'green');
      expect(themeStyleFromName(Storage.uiStyle()).label, '清夏');
    },
  );
  for (final b in Brightness.values) {
    testWidgets(
      'yellow navigation and action use the actual production palette in ${b.name}',
      (tester) async {
        var selected = -1;
        await tester.pumpWidget(
          MaterialApp(
            theme: buildTheme(b, ThemeStyle.clean),
            home: Scaffold(
              bottomNavigationBar: ThemedNavigationBar(
                selectedIndex: 0,
                onSelected: (i) => selected = i,
              ),
            ),
          ),
        );
        final icon = tester.widget<Icon>(find.byIcon(Icons.assignment_rounded));
        expect(
          contrast(icon.color!, const Color(0xFFFFE044)),
          greaterThanOrEqualTo(4.5),
        );
        final indicator = find
            .ancestor(
              of: find.byIcon(Icons.assignment_rounded),
              matching: find.byType(AnimatedContainer),
            )
            .first;
        final indicatorSize = tester.getSize(indicator);
        expect(
          indicatorSize.width / indicatorSize.height,
          closeTo(1, .05),
          reason:
              'selected icon sits in a compact square, not a flat rectangle',
        );
        final target = find
            .ancestor(
              of: find.byIcon(Icons.assignment_rounded),
              matching: find.byType(InkWell),
            )
            .first;
        expect(tester.getSize(target).height, greaterThanOrEqualTo(48));
        for (var i = 0; i < ThemedNavigationBar.labels.length; i++) {
          await tester.tap(find.text(ThemedNavigationBar.labels[i]));
          expect(selected, i);
        }
        expect(tester.takeException(), isNull);
      },
    );
    test(
      'yellow controls, foregrounds and pickers stay readable in ${b.name}',
      () {
        final t = buildTheme(b, ThemeStyle.clean),
            p = t.extension<StylePalette>()!;
        final s = t.filledButtonTheme.style!;
        expect(
          contrast(
            s.foregroundColor!.resolve({})!,
            s.backgroundColor!.resolve({})!,
          ),
          greaterThanOrEqualTo(4.5),
        );
        expect(
          contrast(t.colorScheme.primary, p.card),
          greaterThanOrEqualTo(4.5),
        );
        expect(
          t.datePickerTheme.dayBackgroundColor!.resolve({WidgetState.selected}),
          const Color(0xFFFFE044),
        );
        expect(
          contrast(
            t.datePickerTheme.dayForegroundColor!.resolve({
              WidgetState.selected,
            })!,
            const Color(0xFFFFE044),
          ),
          greaterThanOrEqualTo(4.5),
        );
        expect(
          t.datePickerTheme.todayBackgroundColor?.resolve({
            WidgetState.selected,
          }),
          const Color(0xFFFFE044),
        );
        expect(
          t.datePickerTheme.yearBackgroundColor?.resolve({
            WidgetState.selected,
          }),
          const Color(0xFFFFE044),
        );
        expect(
          t.datePickerTheme.yearForegroundColor?.resolve({
            WidgetState.selected,
          }),
          p.onAccent,
        );
        expect(t.timePickerTheme.dialHandColor, const Color(0xFFFFE044));
        expect(t.inputDecorationTheme.fillColor, p.card);
        expect(t.dialogTheme.backgroundColor, p.modal);
      },
    );
  }
}
