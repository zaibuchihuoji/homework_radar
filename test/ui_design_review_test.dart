import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homework_radar/app_state.dart';
import 'package:homework_radar/main.dart' show buildTheme;
import 'package:homework_radar/pages/homework_edit_dialogs.dart';
import 'package:homework_radar/services/storage.dart';
import 'package:homework_radar/ui/focus_account_row.dart';
import 'package:homework_radar/ui/tokens.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Storage.init();
  });

  for (final style in ThemeStyle.values) {
    test('${style.name}: emphasis text is readable against its fill', () {
      final palette = stylePalette(style, Brightness.light);
      final a = palette.onAccent.computeLuminance();
      final b = palette.accentFill.computeLuminance();
      final contrast =
          (a > b ? a + .05 : b + .05) / (a > b ? b + .05 : a + .05);
      expect(contrast, greaterThanOrEqualTo(4.5));
    });
    testWidgets('${style.name}: expired account has direct login action', (
      t,
    ) async {
      var called = false;
      t.view.physicalSize = const Size(320, 740);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(
        MaterialApp(
          theme: buildTheme(Brightness.light, style),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.6)),
            child: child!,
          ),
          home: Scaffold(
            body: FocusAccountRow(
              index: 1,
              title: '学习通',
              state: AccountState.needRelogin,
              label: '登录已失效，请重新登录',
              onLogin: () => called = true,
              onLogout: () {},
            ),
          ),
        ),
      );
      await t.tap(find.widgetWithText(TextButton, '重新登录'));
      expect(called, isTrue);
      expect(find.text('退出账号'), findsNothing);
      expect(t.takeException(), isNull);
    });

    testWidgets('${style.name}: blank manual title explains what to fix', (
      t,
    ) async {
      final state = AppState();
      await t.pumpWidget(
        MaterialApp(
          theme: buildTheme(Brightness.light, style),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showManualHomeworkEditor(context, state),
                child: const Text('打开'),
              ),
            ),
          ),
        ),
      );
      await t.tap(find.text('打开'));
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(FilledButton, '添加'));
      await t.pumpAndSettle();
      expect(find.text('请填写作业标题'), findsOneWidget);
      expect(state.homework, isEmpty);
      await t.pumpWidget(const SizedBox());
      state.dispose();
    });

    testWidgets(
      '${style.name}: deadline shortcut reveals the picker at large text',
      (t) async {
        t.view.physicalSize = const Size(320, 640);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.reset);
        final state = AppState();
        await t.pumpWidget(
          MaterialApp(
            theme: buildTheme(Brightness.light, style),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(1.6)),
              child: child!,
            ),
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => showManualHomeworkEditor(context, state),
                  child: const Text('打开'),
                ),
              ),
            ),
          ),
        );
        await t.tap(find.text('打开'));
        await t.pumpAndSettle();
        expect(find.text('截止时间：未设置'), findsOneWidget);
        await t.tap(find.text('设置'));
        await t.pumpAndSettle();
        expect(find.text('选择时间').hitTestable(), findsOneWidget);
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
        state.dispose();
      },
    );
  }
}
