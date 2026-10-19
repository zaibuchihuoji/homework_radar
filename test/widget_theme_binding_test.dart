import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:homework_radar/services/storage.dart';
import 'package:homework_radar/app_state.dart';
import 'package:homework_radar/main.dart';
import 'package:homework_radar/ui/tokens.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'app startup and every theme or mode change refresh the desktop',
    (tester) async {
      await tester.runAsync(() async {
        SharedPreferences.setMockInitialValues({});
        await Storage.init();
      });
      final written = <Map<String, dynamic>>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(const MethodChannel('home_widget'), (
        call,
      ) async {
        if (call.method == 'saveWidgetData') {
          final args = call.arguments as Map;
          if (args['id'] == 'widget_theme') {
            written.add(jsonDecode(args['data'] as String));
          }
        }
        return call.method == 'initiallyLaunchedFromHomeWidget' ? null : true;
      });
      messenger.setMockMethodCallHandler(
        const MethodChannel('home_widget/updates'),
        (_) async => null,
      );
      messenger.setMockMethodCallHandler(
        const MethodChannel('homework_radar/platform'),
        (_) async => null,
      );
      final state = AppState();
      await state.loadLocal();
      final oldSplash = showSplashOnStart;
      showSplashOnStart = false;
      appStateForHome = state;
      addTearDown(() {
        showSplashOnStart = oldSplash;
        appStateForHome = null;
      });
      tester.view.physicalSize = const Size(420, 920);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(HomeworkRadarApp(state: state));
      await tester.pumpAndSettle();
      expect(written.last['style'], 'clean');
      for (final style in ThemeStyle.values) {
        await state.setStyle(style);
        await tester.pumpAndSettle();
        expect(written.last['style'], style.name);
      }
      await state.setThemeMode(ThemeMode.dark);
      await tester.pumpAndSettle();
      expect(written.last['mode'], 'dark');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      state.dispose();
    },
  );
}
