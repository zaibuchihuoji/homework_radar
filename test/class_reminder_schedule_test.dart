import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:homework_radar/models/course.dart';
import 'package:homework_radar/models/homework.dart';
import 'package:homework_radar/services/class_reminder_plan.dart';
import 'package:homework_radar/services/notification_service.dart';
import 'package:homework_radar/services/storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final calls = <MethodCall>[];
  var pending = <Map<String, Object?>>[];
  var exact = true;
  var readFails = false;
  var exactRace = false;
  final today = DateTime.now();
  final monday = DateTime(
    today.year,
    today.month,
    today.day + 8 - today.weekday,
  );
  final course = Course(
    id: 'c',
    name: '数学',
    room: 'A302',
    weekday: 1,
    startSection: 1,
    endSection: 2,
    weeks: [1],
  );
  setUp(() async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    FlutterLocalNotificationsPlatform.instance =
        AndroidFlutterLocalNotificationsPlugin();
    SharedPreferences.setMockInitialValues({});
    await Storage.init();
    await Storage.saveSemesterStart(monday);
    NotificationService.clock = () => monday;
    pending = [];
    calls.clear();
    exact = true;
    readFails = false;
    exactRace = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('dexterous.com/flutter/local_notifications'),
          (c) async {
            calls.add(c);
            if (c.method == 'pendingNotificationRequests') {
              if (readFails) throw PlatformException(code: 'read');
              return pending;
            }
            if (c.method == 'canScheduleExactNotifications') return exact;
            if (c.method == 'zonedSchedule' &&
                exactRace &&
                (c.arguments as Map)['platformSpecifics']['scheduleMode'] ==
                    'exactAllowWhileIdle') {
              throw PlatformException(code: 'exact_alarms_not_permitted');
            }
            return true;
          },
        );
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    NotificationService.clock = DateTime.now;
  });
  List<Map> scheduled() => calls
      .where((c) => c.method == 'zonedSchedule')
      .map((c) => c.arguments as Map)
      .toList();

  test(
    'iOS reserves an open-app reminder before notification slots run out',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      FlutterLocalNotificationsPlatform.instance =
          IOSFlutterLocalNotificationsPlugin();
      await Storage.saveClassReminder(false);
      await Storage.saveReminders(
        ReminderSettings(before24h: false, before6h: false),
      );
      final items = [
        for (var i = 1; i <= 65; i++)
          HomeworkItem(
            id: 'manual_$i',
            platform: PlatformKind.manual,
            course: '数学',
            title: '作业$i',
            status: HwStatus.todo,
            dueAt: monday.add(Duration(hours: i + 1)),
          ),
      ];
      await NotificationService.reschedule(items);
      expect(scheduled(), hasLength(64));
      expect(
        scheduled().where(
          (item) => (item['payload'] as String).startsWith('reminder-refresh:'),
        ),
        hasLength(1),
      );
    },
  );

  test(
    'iOS uses every slot for actual reminders when all of them fit',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      FlutterLocalNotificationsPlatform.instance =
          IOSFlutterLocalNotificationsPlugin();
      await Storage.saveClassReminder(false);
      await Storage.saveReminders(
        ReminderSettings(before24h: false, before6h: false),
      );
      final items = [
        for (var i = 1; i <= 64; i++)
          HomeworkItem(
            id: 'manual_fit_$i',
            platform: PlatformKind.manual,
            course: '数学',
            title: '作业$i',
            status: HwStatus.todo,
            dueAt: monday.add(Duration(hours: i + 1)),
          ),
      ];
      await NotificationService.reschedule(items);
      expect(scheduled(), hasLength(64));
      expect(
        scheduled().where(
          (item) => (item['payload'] as String).startsWith('reminder-refresh:'),
        ),
        isEmpty,
      );
    },
  );

  test('iOS warns before a class beyond the 56-day planning window', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    FlutterLocalNotificationsPlatform.instance =
        IOSFlutterLocalNotificationsPlugin();
    await Storage.saveClassReminder(true);
    final later = Course(
      id: 'future_class',
      name: '后续课程',
      weekday: 1,
      startSection: 1,
      endSection: 2,
      weeks: [20],
    );
    await NotificationService.reschedule([], courses: [later]);
    expect(scheduled(), hasLength(1));
    final payload = scheduled().single['payload'] as String;
    expect(payload, startsWith('reminder-refresh:'));
    expect(NotificationService.navigationPayload(payload), isEmpty);
  });

  test(
    'a delayed legacy reminder is migrated to the current deadline',
    () async {
      await Storage.saveReminders(
        ReminderSettings(before24h: false, before6h: false),
      );
      final hw = HomeworkItem(
        id: 'manual_legacy',
        platform: PlatformKind.manual,
        course: '数学',
        title: '作业',
        status: HwStatus.todo,
        dueAt: monday.add(const Duration(hours: 2)),
      );
      await NotificationService.reschedule([hw]);
      final alarm = scheduled().single;
      pending = [
        {
          'id': alarm['id'],
          'title': alarm['title'],
          'body': alarm['body'],
          'payload': hw.id,
        },
      ];
      calls.clear();
      NotificationService.clock = () =>
          monday.add(const Duration(hours: 1, minutes: 5));
      await NotificationService.reschedule([hw]);
      expect(scheduled(), hasLength(1));
      expect(
        NotificationService.navigationPayload(scheduled().single['payload']),
        hw.id,
      );
      expect(scheduled().single['body'], contains('临近截止'));
      final migrated = scheduled().single;
      pending = [
        {
          'id': migrated['id'],
          'title': migrated['title'],
          'body': migrated['body'],
          'payload': migrated['payload'],
        },
      ];
      calls.clear();
      NotificationService.clock = () =>
          monday.add(const Duration(hours: 1, minutes: 5, seconds: 10));
      await NotificationService.reschedule([hw]);
      expect(
        calls.where(
          (c) =>
              c.method == 'cancel' ||
              c.method == 'cancelAllPendingNotifications',
        ),
        isEmpty,
      );
      expect(scheduled(), isEmpty);
    },
  );

  test(
    'a delayed homework reminder survives rescheduling until its deadline',
    () async {
      await Storage.saveReminders(
        ReminderSettings(before24h: false, before6h: false),
      );
      final hw = HomeworkItem(
        id: 'manual_delayed',
        platform: PlatformKind.manual,
        course: '数学',
        title: '作业',
        status: HwStatus.todo,
        dueAt: monday.add(const Duration(hours: 2)),
      );
      await NotificationService.reschedule([hw]);
      final alarm = scheduled().single;
      pending = [
        {
          'id': alarm['id'],
          'title': alarm['title'],
          'body': alarm['body'],
          'payload': alarm['payload'],
        },
      ];
      calls.clear();
      NotificationService.clock = () =>
          monday.add(const Duration(hours: 1, minutes: 5));
      await NotificationService.reschedule([hw]);
      expect(
        calls.where(
          (c) =>
              c.method == 'cancel' ||
              c.method == 'cancelAllPendingNotifications',
        ),
        isEmpty,
      );
      expect(scheduled(), isEmpty);
      NotificationService.clock = () =>
          monday.add(const Duration(hours: 2, minutes: 1));
      calls.clear();
      await NotificationService.reschedule([hw]);
      expect(
        calls.any(
          (c) =>
              c.method == 'cancel' ||
              c.method == 'cancelAllPendingNotifications',
        ),
        isTrue,
      );
    },
  );

  test('changing the deadline cancels an obsolete delayed alarm and preserves navigation', () async {
    await Storage.saveReminders(
      ReminderSettings(before24h: false, before6h: false),
    );
    HomeworkItem task(DateTime due) => HomeworkItem(
      id: 'manual_edit',
      platform: PlatformKind.manual,
      course: '数学',
      title: '作业',
      status: HwStatus.todo,
      dueAt: due,
    );
    await NotificationService.reschedule([
      task(monday.add(const Duration(hours: 2))),
    ]);
    final old = scheduled().single;
    expect(
      NotificationService.navigationPayload(old['payload']),
      'manual_edit',
    );
    expect(NotificationService.navigationPayload('legacy-id'), 'legacy-id');
    pending = [
      {
        'id': old['id'],
        'title': old['title'],
        'body': old['body'],
        'payload': old['payload'],
      },
    ];
    calls.clear();
    NotificationService.clock = () =>
        monday.add(const Duration(hours: 1, minutes: 5));
    await NotificationService.reschedule([
      task(monday.add(const Duration(hours: 3))),
    ]);
    expect(
      calls.any(
        (c) =>
            c.method == 'cancel' || c.method == 'cancelAllPendingNotifications',
      ),
      isTrue,
    );
    expect(scheduled(), hasLength(1));
    expect(scheduled().single['payload'], isNot(old['payload']));
  });

  test(
    'classes use precise alarms when allowed, real payload and countdown',
    () async {
      await NotificationService.reschedule([], courses: [course]);
      final alarm = scheduled().single;
      expect(
        alarm['platformSpecifics']['scheduleMode'],
        AndroidScheduleMode.exactAllowWhileIdle.name,
      );
      expect(alarm['title'], '30分钟后上课：数学');
      expect(alarm['body'], contains('08:00'));
      expect(alarm['body'], contains('A302'));
      expect(ClassReminderTarget.parse(alarm['payload'])?.courseId, 'c');
      expect(alarm['platformSpecifics']['usesChronometer'], true);
      expect(alarm['platformSpecifics']['chronometerCountDown'], true);
      expect(NotificationService.classSchedule.value.next?.course.id, 'c');
      expect(NotificationService.classSchedule.value.scheduledCount, 1);
    },
  );
  test(
    'denied exact permission degrades honestly without dropping reminder',
    () async {
      exact = false;
      await NotificationService.reschedule([], courses: [course]);
      expect(
        scheduled().single['platformSpecifics']['scheduleMode'],
        AndroidScheduleMode.inexactAllowWhileIdle.name,
      );
      expect(NotificationService.classSchedule.value.exact, false);
      expect(
        calls.any((c) => c.method == 'requestExactAlarmsPermission'),
        false,
      );
    },
  );
  test(
    'exact permission revocation race still schedules ordinary reminder',
    () async {
      exactRace = true;
      await NotificationService.reschedule([], courses: [course]);
      expect(scheduled().map((n) => n['platformSpecifics']['scheduleMode']), [
        'exactAllowWhileIdle',
        'inexactAllowWhileIdle',
      ]);
      expect(NotificationService.classSchedule.value.exact, false);
      expect(NotificationService.classSchedule.value.scheduledCount, 1);
    },
  );

  test(
    'changing lead inside its new window still preserves an undelivered class',
    () async {
      final old = ClassReminderPlan.build(
        courses: [course],
        semesterStart: monday,
        now: monday,
        enabled: true,
        minutes: 15,
        slots: Course.sectionTimes,
      ).entries.single;
      pending = [
        {
          'id': old.id,
          'title': old.title,
          'body': old.body,
          'payload': old.payload,
        },
      ];
      NotificationService.clock = () =>
          DateTime(monday.year, monday.month, monday.day, 7, 40);
      await NotificationService.reschedule([], courses: [course]);
      expect(scheduled(), hasLength(1));
      expect(
        ClassReminderTarget.parse(scheduled().single['payload'])?.courseId,
        'c',
      );
      expect(NotificationService.classSchedule.value.scheduledCount, 1);
    },
  );
  test('pending class inside late trigger window survives sync, no duplicate alert', () async {
    final entry = ClassReminderPlan.build(
      courses: [course],
      semesterStart: monday,
      now: monday,
      enabled: true,
      minutes: 30,
      slots: Course.sectionTimes,
    ).entries.single;
    pending = [
      {
        'id': entry.id,
        'title': entry.title,
        'body': entry.body,
        'payload': entry.payload,
      },
    ];
    NotificationService.clock = () =>
        DateTime(monday.year, monday.month, monday.day, 7, 40);
    await NotificationService.reschedule([], courses: [course]);
    expect(
      calls.where((c) => c.method == 'cancelAllPendingNotifications'),
      isEmpty,
    );
    expect(calls.where((c) => c.method == 'cancel'), isEmpty);
    expect(scheduled(), isEmpty);
    expect(NotificationService.classSchedule.value.scheduledCount, 1);
    pending = []; // delivered by OS: never re-alert during later sync
    calls.clear();
    await NotificationService.reschedule([], courses: [course]);
    expect(scheduled(), isEmpty);
    expect(NotificationService.classSchedule.value.next, isNull);
  });
  test('changed or deleted class cancels stale pending reminder', () async {
    final entry = ClassReminderPlan.build(
      courses: [course],
      semesterStart: monday,
      now: monday,
      enabled: true,
      minutes: 30,
      slots: Course.sectionTimes,
    ).entries.single;
    pending = [
      {
        'id': entry.id,
        'title': entry.title,
        'body': entry.body,
        'payload': entry.payload,
      },
    ];
    await NotificationService.reschedule([]);
    expect(
      calls.any(
        (c) =>
            c.method == 'cancelAllPendingNotifications' || c.method == 'cancel',
      ),
      true,
    );
  });
  test(
    'one minute scheduled test survives data sync and uses class channel',
    () async {
      final fire = await NotificationService.scheduleClassTest();
      expect(fire, monday.add(const Duration(minutes: 1)));
      final alarm = scheduled().single;
      expect(alarm['platformSpecifics']['channelId'], 'class_reminder');
      pending = [
        {
          'id': alarm['id'],
          'title': alarm['title'],
          'body': alarm['body'],
          'payload': alarm['payload'],
        },
      ];
      calls.clear();
      await NotificationService.reschedule([]);
      expect(
        calls.where(
          (c) =>
              c.method == 'cancelAllPendingNotifications' ||
              c.method == 'cancel',
        ),
        isEmpty,
      );
    },
  );
  test('cannot read pending queue leaves existing reminders intact', () async {
    readFails = true;
    await expectLater(
      NotificationService.reschedule([], courses: [course]),
      throwsA(isA<PlatformException>()),
    );
    expect(calls.where((c) => c.method.startsWith('cancel')), isEmpty);
    expect(NotificationService.scheduleError.value, isNotNull);
  });
}
