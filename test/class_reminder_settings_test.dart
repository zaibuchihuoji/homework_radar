import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:homework_radar/app_state.dart';
import 'package:homework_radar/main.dart';
import 'package:homework_radar/pages/class_reminder_settings_page.dart';
import 'package:homework_radar/services/storage.dart';
import 'package:homework_radar/ui/tokens.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final calls = <MethodCall>[];
  setUp(() async {
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    SharedPreferences.setMockInitialValues({});
    await Storage.init();
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('dexterous.com/flutter/local_notifications'),
          (c) async {
            calls.add(c);
            if (c.method == 'pendingNotificationRequests') {
              return <Map<String, Object?>>[];
            }
            return c.method == 'canScheduleExactNotifications' ? false : true;
          },
        );
  });
  testWidgets('all themes: controls fit large text and retain selected lead', (
    tester,
  ) async {
    for (final style in ThemeStyle.values) {
      calls.clear();
      tester.view.physicalSize = const Size(640, 1480);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      final state = AppState();
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(Brightness.light, style),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.4)),
            child: child!,
          ),
          home: ClassReminderSettingsPage(state: state),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        calls.where((c) => c.method == 'requestExactAlarmsPermission'),
        isEmpty,
      );
      await tester.scrollUntilVisible(
        find.widgetWithText(ChoiceChip, '60 分钟'),
        140,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, '60 分钟'));
      await tester.pumpAndSettle();
      expect(Storage.classReminderMinutes(), 60);
      await tester.scrollUntilVisible(find.text('一分钟后提醒'), 200);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('一分钟后提醒'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('一分钟后提醒'));
      await tester.pumpAndSettle();
      expect(calls.where((c) => c.method == 'zonedSchedule'), hasLength(1));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      state.dispose();
    }
  });
}
