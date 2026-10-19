import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homework_radar/app_state.dart';
import 'package:homework_radar/main.dart';
import 'package:homework_radar/pages/settings_page.dart';
import 'package:homework_radar/services/storage.dart';
import 'package:homework_radar/ui/tokens.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _SettingsState extends AppState {
  @override
  Future<void> updateReminders(ReminderSettings value) async {
    await Storage.saveReminders(value);
    notifyListeners();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('homework_radar/platform'),
          (_) async => null,
        );
    await Storage.init();
    await Storage.saveReminders(
      ReminderSettings(before24h: false, before6h: false, before1h: false),
    );
    await Storage.saveClassReminder(false);
  });
  for (final style in ThemeStyle.values.where(
    (s) => !stylePalette(s, Brightness.light).clean,
  )) {
    testWidgets(
      '${style.name}: reminder summary follows its control at narrow enlarged layout',
      (tester) async {
        tester.view.physicalSize = const Size(640, 1480);
        tester.view.devicePixelRatio = 2;
        addTearDown(tester.view.reset);
        final state = _SettingsState();
        await state.setStyle(style);
        await tester.pumpWidget(
          MaterialApp(
            theme: buildTheme(Brightness.light, style),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(1.4)),
              child: child!,
            ),
            home: SettingsPage(state: state),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.textContaining('提醒 0/3 已开启'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.scrollUntilVisible(find.text('截止前 24 小时'), 180);
        await tester.tap(find.text('截止前 24 小时'));
        await tester.pumpAndSettle();
        expect(Storage.reminders().before24h, isTrue);
        expect(Storage.reminders().before6h, isFalse);
        expect(Storage.reminders().before1h, isFalse);
        expect(tester.takeException(), isNull);
        await tester.fling(
          find.byType(ListView).first,
          const Offset(0, 1800),
          2000,
        );
        await tester.pumpAndSettle();
        expect(find.textContaining('提醒 1/3 已开启'), findsOneWidget);
        await tester.tap(find.text('界面风格'));
        await tester.pumpAndSettle();
        expect(find.text('选择适合你的学习氛围'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        state.dispose();
      },
    );
  }
}
