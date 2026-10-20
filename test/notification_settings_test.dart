import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:homework_radar/app_state.dart';
import 'package:homework_radar/main.dart';
import 'package:homework_radar/pages/settings_page.dart';
import 'package:homework_radar/pages/notification_settings_page.dart';
import 'package:homework_radar/services/notification_service.dart';
import 'package:homework_radar/services/storage.dart';
import 'package:homework_radar/ui/tokens.dart';
import 'package:homework_radar/ui/theme_page_parts.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final calls = <MethodCall>[];
  var systemChannels = <Map<String, Object?>>[];
  var readFails = false;
  Map<String, Object?> channel(String id, int importance) => {
    'id': id,
    'name': id,
    'description': '',
    'groupId': null,
    'showBadge': true,
    'importance': importance,
    'bypassDnd': false,
    'playSound': true,
    'soundSource': null,
    'enableLights': false,
    'enableVibration': true,
    'vibrationPattern': null,
    'ledColor': 0,
    'audioAttributesUsage': 5,
  };
  setUp(() async {
    FlutterLocalNotificationsPlatform.instance =
        AndroidFlutterLocalNotificationsPlugin();
    calls.clear();
    systemChannels = [channel('homework_due', 3), channel('class_reminder', 0)];
    readFails = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('dexterous.com/flutter/local_notifications'),
          (call) async {
            calls.add(call);
            if (call.method == 'getNotificationChannels') {
              if (readFails) throw PlatformException(code: 'unavailable');
              return systemChannels;
            }
            return true;
          },
        );
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('homework_radar/platform'),
          (call) async {
            calls.add(call);
            return call.method == 'openNotificationSettings' ? true : null;
          },
        );
    await Storage.init();
  });

  testWidgets('settings exposes banner settings independently of permission', (
    tester,
  ) async {
    final state = AppState();
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.light, ThemeStyle.clean),
        home: SettingsPage(state: state),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('通知横幅与声音'), 180);
    await tester.pumpAndSettle();
    expect(find.text('通知横幅与声音'), findsOneWidget);
    await tester.tap(find.text('通知横幅与声音'));
    await tester.pumpAndSettle();
    expect(find.byType(NotificationSettingsPage), findsOneWidget);
    expect(
      calls.where((c) => c.method == 'getNotificationChannels'),
      isNotEmpty,
    );
    await tester.pumpWidget(const SizedBox());
    state.dispose();
  });

  testWidgets(
    'channel inspection is read-only and never equates app grant with banners',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(Brightness.light, ThemeStyle.clean),
          home: const NotificationSettingsPage(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('App 通知权限已允许'), findsOneWidget);
      expect(find.textContaining('当前优先级不足'), findsOneWidget);
      expect(
        calls.where(
          (c) => [
            'cancelAll',
            'zonedSchedule',
            'createNotificationChannel',
            'requestNotificationsPermission',
          ].contains(c.method),
        ),
        isEmpty,
      );
      await tester.scrollUntilVisible(find.text('此类通知已关闭'), 200);
      await tester.pumpAndSettle();
      expect(find.text('此类通知已关闭'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('设置上课提醒'), 160);
      await tester.pumpAndSettle();
      await tester.tap(find.text('设置上课提醒'));
      await tester.pumpAndSettle();
      expect(
        calls
            .lastWhere((c) => c.method == 'openNotificationSettings')
            .arguments,
        {'channelId': 'class_reminder'},
      );
      expect(
        calls.where((c) => c.method == 'deleteNotificationChannel'),
        isEmpty,
      );
      // Android can retain a sound URI after the user selects Silent. LOW
      // importance still prevents sound, irrespective of that saved URI.
      systemChannels = [
        channel('homework_due', 2),
        channel('class_reminder', 0),
      ];
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text('当前优先级不足以显示顶部横幅 · 声音关闭'), findsOneWidget);
      // Returning from the system page must show its new saved status.
      systemChannels = [
        channel('homework_due', 4),
        channel('class_reminder', 4),
      ];
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text('此类通知已关闭'), findsNothing);
      expect(find.textContaining('系统高优先级'), findsAtLeastNWidgets(1));
    },
  );

  testWidgets('failed status query still allows opening system settings', (
    tester,
  ) async {
    readFails = true;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.light, ThemeStyle.clean),
        home: const NotificationSettingsPage(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('暂时无法读取'), findsAtLeastNWidgets(1));
    await tester.tap(find.text('打开 App 通知设置'));
    await tester.pumpAndSettle();
    expect(
      calls.lastWhere((c) => c.method == 'openNotificationSettings').arguments,
      {'channelId': null},
    );
    expect(tester.takeException(), isNull);
  });

  test(
    'test notifications retain real channels, priority and homework payload',
    () async {
      await NotificationService.showSimple(
        'task',
        'body',
        payload: 'original-hw',
      );
      await NotificationService.showSimple(
        'course',
        'body',
        channelId: 'class_reminder',
      );
      final notices = calls
          .where((c) => c.method == 'show')
          .map((c) => c.arguments as Map)
          .toList();
      expect(notices, hasLength(2));
      expect(notices.first['payload'], 'original-hw');
      expect(notices.last['payload'], isEmpty);
      expect(notices.first['platformSpecifics']['channelId'], 'homework_due');
      expect(notices.last['platformSpecifics']['channelId'], 'class_reminder');
      for (final notice in notices) {
        expect(
          notice['platformSpecifics']['importance'],
          Importance.high.value,
        );
        expect(notice['platformSpecifics']['priority'], Priority.high.value);
        expect(notice['platformSpecifics']['silent'], false);
      }
      await expectLater(
        NotificationService.openAndroidNotificationSettings(channelId: 'other'),
        throwsArgumentError,
      );
      expect(
        calls.where((c) => c.method == 'openNotificationSettings'),
        isEmpty,
      );
    },
  );

  for (final style in ThemeStyle.values) {
    testWidgets(
      '${style.name}: notification settings fit narrow enlarged text',
      (tester) async {
        tester.view.physicalSize = const Size(640, 1480);
        tester.view.devicePixelRatio = 2;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          MaterialApp(
            theme: buildTheme(Brightness.light, style),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(1.4)),
              child: child!,
            ),
            home: const NotificationSettingsPage(),
          ),
        );
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(find.text('设置上课提醒'), 300);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final send = find.descendant(
          of: find.widgetWithText(ThemePanel, '上课提醒'),
          matching: find.text('发送一条提醒'),
        );
        await tester.scrollUntilVisible(send, 160);
        await tester.pumpAndSettle();
        await tester.tap(send);
        await tester.pumpAndSettle();
        expect(calls.where((c) => c.method == 'show'), hasLength(1));
        expect(tester.takeException(), isNull);
      },
    );
  }
}
