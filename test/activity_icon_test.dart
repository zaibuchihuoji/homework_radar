import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:homework_radar/app_state.dart';
import 'package:homework_radar/main.dart' show buildTheme;
import 'package:homework_radar/ui/tokens.dart';
import 'package:homework_radar/pages/home_page.dart';
import 'package:homework_radar/pages/settings_page.dart';
import 'package:homework_radar/pages/update_dialog.dart';
import 'package:homework_radar/services/app_update_controller.dart';
import 'package:homework_radar/services/storage.dart';
import 'package:homework_radar/ui/activity_icon.dart';
import 'package:homework_radar/ui/settings_parts.dart';
import 'package:homework_radar/ui/sync_status_parts.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> expectTurning(WidgetTester tester, Finder icon) async {
    final rotation = find.ancestor(
      of: icon,
      matching: find.byType(RotationTransition),
    );
    expect(rotation, findsOneWidget);
    final turns = tester.widget<RotationTransition>(rotation).turns;
    await tester.pump(const Duration(milliseconds: 100));
    final before = turns.value;
    await tester.pump(const Duration(milliseconds: 250));
    expect(turns.value, isNot(before));
  }

  testWidgets('home refresh arrow turns throughout sync and stops afterward', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('homework_radar/platform'),
          (_) async => null,
        );
    await Storage.init();
    final state = AppState()..syncing = true;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.light, ThemeStyle.clean),
        home: HomePage(state: state, onGoAccounts: () {}),
      ),
    );
    final icon = find.descendant(
      of: find.byTooltip('同步作业'),
      matching: find.byIcon(Icons.refresh_rounded),
    );
    await expectTurning(tester, icon);
    state.syncing = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.light, ThemeStyle.clean),
        home: HomePage(state: state, onGoAccounts: () {}),
      ),
    );
    await tester.pumpAndSettle();
    final rotation = find.ancestor(
      of: icon,
      matching: find.byType(RotationTransition),
    );
    expect(tester.widget<RotationTransition>(rotation).turns.value, 0);
    await tester.pumpWidget(const SizedBox());
    state.dispose();
  });

  testWidgets('busy sync notice arrow animates', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.light, ThemeStyle.clean),
        home: Scaffold(body: SyncProgressNotice(busy: true, progress: '1/4')),
      ),
    );
    await expectTurning(tester, find.byIcon(Icons.sync_rounded));
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });

  testWidgets('every theme rotates the settings glyph without its frame', (
    tester,
  ) async {
    for (final style in ThemeStyle.values) {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(Brightness.light, style),
          home: const Scaffold(
            body: SettingsRow(
              title: '立即同步',
              icon: Icons.refresh_rounded,
              iconSpinning: true,
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 400));
      await expectTurning(tester, find.byIcon(Icons.refresh_rounded));
      expect(
        tester
            .widget<RotationTransition>(
              find.ancestor(
                of: find.byIcon(Icons.refresh_rounded),
                matching: find.byType(RotationTransition),
              ),
            )
            .child,
        isA<Icon>(),
      );
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('motion preference and inactive routes stop the ticker', (
    tester,
  ) async {
    Widget app({bool reduced = false, bool visible = true}) => MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduced),
        child: TickerMode(
          enabled: visible,
          child: const ActivityIcon(Icons.refresh_rounded, active: true),
        ),
      ),
    );
    await tester.pumpWidget(app());
    await expectTurning(tester, find.byIcon(Icons.refresh_rounded));
    for (final replacement in [app(reduced: true), app(visible: false)]) {
      await tester.pumpWidget(replacement);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<RotationTransition>(find.byType(RotationTransition))
            .turns
            .value,
        0,
      );
    }
    await tester.pumpWidget(app());
    await expectTurning(tester, find.byIcon(Icons.refresh_rounded));
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });

  for (final failed in [false, true]) {
    testWidgets(
      'update check animates, rejects duplicate taps, stops on ${failed ? 'failure' : 'result'}',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        await Storage.init();
        PackageInfo.setMockInitialValues(
          appName: '作业通',
          packageName: 'com.worknote.homework_radar',
          version: '1.3.0',
          buildNumber: '9',
          buildSignature: '',
        );
        final state = AppState();
        final result = Completer<Map<String, dynamic>>();
        var requests = 0;
        const channel = MethodChannel('homework_radar/updater');
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) {
              if (call.method == 'status') {
                requests++;
                return result.future;
              }
              if (call.method == 'device') {
                throw PlatformException(code: 'synthetic unavailable');
              }
              return Future.value({'phase': 'idle'});
            });
        await tester.pumpWidget(
          MaterialApp(
            theme: buildTheme(Brightness.light, ThemeStyle.clean),
            home: SettingsPage(state: state),
          ),
        );
        await tester.tap(find.text('关于与帮助'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('检查更新'));
        await tester.pump();
        expect(appUpdateChecking.value, isTrue);
        await expectTurning(tester, find.byIcon(Icons.update_rounded));
        await tester.tap(find.text('检查更新'));
        await tester.pump();
        expect(requests, 1);
        if (failed) {
          result.complete({'phase': 'idle'});
        } else {
          result.complete({'phase': 'ready', 'version': '1.3.0'});
        }
        await tester.pumpAndSettle();
        expect(appUpdateChecking.value, isFalse);
        final row = tester
            .widgetList<SettingsRow>(
              find.byType(SettingsRow, skipOffstage: false),
            )
            .singleWhere((row) => row.title == '检查更新');
        expect(row.iconSpinning, isFalse);
        if (failed) {
          await tester.pump(const Duration(seconds: 1));
          await tester.pumpAndSettle();
        }
        expect(find.text(failed ? '无法读取更新信息，请稍后再试' : '更新已准备好'), findsOneWidget);
        if (!failed) {
          await tester.tap(find.text('稍后'));
          await tester.pumpAndSettle();
        }
        await tester.pumpWidget(const SizedBox());
        await AppUpdateController.instance.cancel();
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
        state.dispose();
        expect(tester.takeException(), isNull);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.android),
    );
  }
}
