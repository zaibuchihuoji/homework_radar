import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:homework_radar/app_state.dart';
import 'package:homework_radar/models/course.dart';
import 'package:homework_radar/models/homework.dart';
import 'package:homework_radar/pages/home_page.dart';
import 'package:homework_radar/main.dart';
import 'package:homework_radar/ui/tokens.dart';
import 'package:homework_radar/services/notification_service.dart';
import 'package:homework_radar/services/storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final calls = <MethodCall>[];
  const channel = MethodChannel('dexterous.com/flutter/local_notifications');
  setUp(() async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    FlutterLocalNotificationsPlatform.instance =
        AndroidFlutterLocalNotificationsPlugin();
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (call.method == 'areNotificationsEnabled') return true;
          return true;
        });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('homework_radar/platform'),
          (_) async => null,
        );
    SharedPreferences.setMockInitialValues({});
    await Storage.init();
  });
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test(
    'notification initialization does not block startup on permission',
    () async {
      await NotificationService.init();
      expect(
        calls.where((c) => c.method == 'requestNotificationsPermission'),
        isEmpty,
      );
    },
  );

  test(
    'homework notifications strictly respect their 100 item budget',
    () async {
      await Storage.saveClassReminder(false);
      await NotificationService.reschedule(
        List.generate(
          40,
          (i) => HomeworkItem(
            id: 'h$i',
            platform: PlatformKind.manual,
            course: 'course',
            title: 'task$i',
            dueAt: DateTime.now().add(Duration(days: 3 + i)),
            status: HwStatus.todo,
          ),
        ),
      );
      expect(calls.where((c) => c.method == 'zonedSchedule').length, 100);
    },
  );

  test(
    'iOS keeps the globally earliest 64 class and homework reminders',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      FlutterLocalNotificationsPlatform.instance =
          IOSFlutterLocalNotificationsPlugin();
      final now = DateTime.now();
      await Storage.saveSemesterStart(
        now.subtract(Duration(days: now.weekday - 1)),
      );
      final courses = [
        for (var d = 1; d <= 7; d++)
          for (var s = 1; s <= 3; s++)
            Course(
              id: '$d-$s',
              name: 'class',
              weekday: d,
              startSection: s,
              endSection: s,
              weeks: List.generate(20, (i) => i + 1),
            ),
      ];
      await NotificationService.reschedule([
        HomeworkItem(
          id: 'urgent',
          platform: PlatformKind.manual,
          course: 'c',
          title: 'urgent',
          dueAt: now.add(const Duration(hours: 2)),
          status: HwStatus.todo,
        ),
      ], courses: courses);
      final scheduled = calls
          .where((c) => c.method == 'zonedSchedule')
          .toList();
      expect(scheduled.length, 64);
      expect(
        scheduled.any((c) => (c.arguments as Map)['payload'] == 'urgent'),
        isTrue,
      );
      final fires = scheduled
          .map(
            (c) => DateTime.parse(
              (c.arguments as Map)['scheduledDateTime'] as String,
            ),
          )
          .toList();
      expect(fires, orderedEquals([...fires]..sort()));
    },
  );

  test('Android class and homework budgets jointly never exceed 500', () async {
    final now = DateTime.now();
    await Storage.saveSemesterStart(
      now.subtract(Duration(days: now.weekday - 1)),
    );
    final courses = [
      for (var d = 1; d <= 7; d++)
        for (var s = 1; s <= 8; s++)
          Course(
            id: '$d-$s',
            name: 'class',
            weekday: d,
            startSection: s,
            endSection: s,
            weeks: List.generate(20, (i) => i + 1),
          ),
    ];
    await NotificationService.reschedule(
      List.generate(
        40,
        (i) => HomeworkItem(
          id: 'mixed$i',
          platform: PlatformKind.manual,
          course: 'c',
          title: 'task',
          dueAt: now.add(Duration(days: 3 + i)),
          status: HwStatus.todo,
        ),
      ),
      courses: courses,
    );
    final scheduled = calls.where((c) => c.method == 'zonedSchedule').toList();
    expect(scheduled.length, 500);
    expect(
      scheduled.where((c) => (c.arguments as Map)['payload'] == '').length,
      400,
    );
  });

  test(
    'completed and submitted homework never schedules another reminder',
    () async {
      await Storage.saveClassReminder(false);
      await NotificationService.reschedule([
        for (final status in [HwStatus.done, HwStatus.submitted])
          HomeworkItem(
            id: status.name,
            platform: PlatformKind.manual,
            course: 'c',
            title: 'finished',
            dueAt: DateTime.now().add(const Duration(days: 3)),
            status: status,
          ),
      ]);
      expect(calls.where((c) => c.method == 'zonedSchedule'), isEmpty);
    },
  );

  testWidgets('existing manual homework stays manageable without any account', (
    tester,
  ) async {
    final task = HomeworkItem(
      id: 'manual_saved',
      platform: PlatformKind.manual,
      course: 'math',
      title: 'offline task',
      status: HwStatus.todo,
    );
    await Storage.saveHomework([task]);
    final state = AppState();
    await state.loadLocal();
    expect(state.hasAnyAccount, isFalse);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.light, ThemeStyle.clean),
        home: HomePage(state: state, onGoAccounts: () {}),
      ),
    );
    await tester.pump();
    expect(find.text('offline task'), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsOneWidget);
    await tester.longPress(find.text('offline task'));
    await tester.pumpAndSettle();
    expect(find.text('标记完成'), findsOneWidget);
    await tester.tap(find.text('标记完成'));
    await tester.pumpAndSettle();
    expect(Storage.homework().single.status, HwStatus.done);
    await tester.pumpWidget(const SizedBox());
    debugDefaultTargetPlatformOverride = null;
  });
}
