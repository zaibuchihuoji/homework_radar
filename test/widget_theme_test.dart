import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:homework_radar/services/storage.dart';
import 'package:homework_radar/services/widget_theme.dart';
import 'package:homework_radar/ui/tokens.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'every theme exports its actual app colors and effective brightness',
    () {
      for (final style in ThemeStyle.values) {
        for (final mode in ThemeMode.values) {
          final config = widgetThemeSnapshot(style, mode);
          expect(config['style'], style.name);
          expect(config['mode'], mode.name);
          for (final name in ['light', 'dark']) {
            final brightness =
                name == 'dark' &&
                    (style == ThemeStyle.clean || style == ThemeStyle.green)
                ? Brightness.dark
                : Brightness.light;
            final palette = stylePalette(style, brightness);
            final colors = config[name] as Map;
            expect(colors['ink'], palette.ink.toARGB32());
            expect(colors['focus'], palette.accentFill.toARGB32());
            expect(colors['onFocus'], palette.onAccent.toARGB32());
          }
        }
      }
    },
  );
  test(
    'serialized appearance refresh updates both widgets without touching data',
    () async {
      SharedPreferences.setMockInitialValues({
        'homework_json': 'retained records',
        'courses_json': 'retained courses',
        'widget_transparent': true,
      });
      await Storage.init();
      final prefs = await SharedPreferences.getInstance();
      final before = prefs.getKeys().map(
        (key) => MapEntry(key, prefs.get(key)),
      );
      final original = Map.fromEntries(before);
      final saved = <String>[];
      final updated = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel('home_widget'), (
            call,
          ) async {
            final args = call.arguments as Map;
            if (call.method == 'saveWidgetData') {
              expect(args['id'], 'widget_theme');
              saved.add(args['data'] as String);
              await Future<void>.delayed(const Duration(milliseconds: 5));
            }
            if (call.method == 'updateWidget') {
              updated.add(args['android'] as String);
            }
            return true;
          });
      await Future.wait([
        WidgetTheme.push(ThemeStyle.paper, ThemeMode.light),
        WidgetTheme.push(ThemeStyle.terminal, ThemeMode.system),
        WidgetTheme.push(ThemeStyle.terminal, ThemeMode.system),
      ]);
      expect(saved.length, 2);
      expect(jsonDecode(saved.last)['style'], 'terminal');
      expect(
        updated.where((s) => s.contains('HomeworkWidgetProvider')).length,
        2,
      );
      expect(
        updated.where((s) => s.contains('TimetableWidgetProvider')).length,
        2,
      );
      for (final entry in original.entries) {
        expect(prefs.get(entry.key), entry.value);
      }
    },
  );
  test(
    'a failed native refresh can be retried with the same appearance',
    () async {
      var attempts = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel('home_widget'), (
            call,
          ) async {
            if (call.method == 'saveWidgetData') {
              attempts++;
              if (attempts == 1) throw PlatformException(code: 'temporary');
            }
            return true;
          });
      await WidgetTheme.push(ThemeStyle.comic, ThemeMode.system);
      await WidgetTheme.push(ThemeStyle.comic, ThemeMode.system);
      expect(attempts, 2);
    },
  );
}
