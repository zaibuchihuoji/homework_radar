/// 本地通知：截止前 24h/6h/1h 提醒（可在设置里开关）。
/// 点击通知可携带 payload（作业 id）跳转到详情页。
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../models/course.dart';
import '../models/homework.dart';
import 'class_reminder_plan.dart';
import 'section_times.dart';
import 'stable_hash.dart';
import 'storage.dart';

class ClassScheduleStatus {
  const ClassScheduleStatus({
    this.next,
    this.scheduledCount = 0,
    this.exact,
    this.issue,
  });
  final ClassReminderEntry? next;
  final int scheduledCount;
  final bool? exact;
  final String? issue;
}

class NotificationService {
  static const _platform = MethodChannel('homework_radar/platform');
  // Keep these IDs stable: Android retains the user's channel preferences.
  static const androidReminderChannels = [
    AndroidNotificationChannel(
      'homework_due',
      '作业截止提醒',
      description: '作业截止前的倒计时提醒（作业通）',
      importance: Importance.high,
    ),
    AndroidNotificationChannel(
      'class_reminder',
      '上课提醒',
      importance: Importance.high,
    ),
  ];

  static AndroidNotificationChannel _reminderChannel(String id) =>
      androidReminderChannels.firstWhere(
        (channel) => channel.id == id,
        orElse: () => throw ArgumentError.value(id, 'channelId'),
      );

  /// Inspect saved settings; never infer banner permission from app permission.
  static Future<List<AndroidNotificationChannel>?>
  androidChannelSettings() async {
    await init();
    return _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.getNotificationChannels();
  }

  static Future<bool> openAndroidNotificationSettings({
    String? channelId,
  }) async {
    final channel = channelId == null ? null : _reminderChannel(channelId);
    await init();
    if (channel != null) {
      // Create only if absent so a device with no future reminders can open it.
      // Re-registering never overrides saved importance/sound/user choices.
      await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(channel);
    }
    return await _platform.invokeMethod<bool>('openNotificationSettings', {
          'channelId': channelId,
        }) ??
        false;
  }

  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;
  static Future<void>? _initializing;

  /// 通知权限是否被授予（init 时采样；null = 还没查过/平台不支持）。
  /// 此前请求结果直接丢弃、从不检查，Android 13+ 拒绝后全部提醒静默失效。
  static final permission = ValueNotifier<bool?>(null);
  static bool? get notificationsEnabled => permission.value;
  static final scheduleError = ValueNotifier<String?>(null);
  static final classSchedule = ValueNotifier(const ClassScheduleStatus());
  @visibleForTesting
  static DateTime Function() clock = DateTime.now;
  static const _testId = 0x7fffffff;
  static const _refreshId = 0x7ffffffe;
  static const _testPayload = 'class-reminder-test:';
  static const _homeworkPayload = 'homework-reminder:';
  static const _refreshPayload = 'reminder-refresh:';

  /// New alarms carry their deadline so a delayed, still-pending alarm can be
  /// distinguished from one for an edited deadline. Old plain IDs still work.
  static String navigationPayload(String payload) {
    if (payload.startsWith(_refreshPayload)) return '';
    if (!payload.startsWith(_homeworkPayload)) return payload;
    try {
      final value = jsonDecode(payload.substring(_homeworkPayload.length));
      return value is Map && value['id'] is String ? value['id'] as String : '';
    } catch (_) {
      return '';
    }
  }

  static Future<bool?> exactAlarmPermission() async {
    if (defaultTargetPlatform != TargetPlatform.android) return null;
    await init();
    return _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.canScheduleExactNotifications();
  }

  // Only called from an explicit settings action, never from background sync.
  static Future<void> requestExactAlarmPermission() async {
    await init();
    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestExactAlarmsPermission();
  }

  static bool isClassPayload(String value) =>
      ClassReminderTarget.parse(value) != null ||
      value.startsWith(_testPayload);

  static Future<Map<String, dynamic>?> islandCapability() async {
    if (defaultTargetPlatform != TargetPlatform.android) return null;
    try {
      return await const MethodChannel('homework_radar/class_reminders')
          .invokeMapMethod<String, dynamic>('capability');
    } on MissingPluginException {
      return null;
    }
  }

  static Future<DateTime> scheduleClassTest() async {
    await init();
    final fire = clock().add(const Duration(minutes: 1));
    final exact = await exactAlarmPermission();
    final operation = _rescheduleQueue.then((_) async {
      await _plugin.cancel(_testId);
      await _schedule(
        _Reminder(
          _testId,
          fire,
          '课前定时测试',
          '这是一分钟前安排的提醒；点击查看课表',
          payload: '$_testPayload${fire.millisecondsSinceEpoch}',
          isClass: true,
          lesson: fire.add(const Duration(minutes: 5)),
        ),
        exact == true,
      );
    });
    _rescheduleQueue = operation.catchError((_) {});
    await operation;
    return fire;
  }

  /// 点击通知的回调（payload 为作业 id）
  static void Function(String payload)? onSelect;

  /// reschedule 串行队列：冷启动本地重排与同步后重排可能并发交错，
  /// 各自的「清待排 → 重排」两步会互相交错清场，留下过期/已删作业的提醒。
  static Future<void> _rescheduleQueue = Future.value();

  static Future<void> init() {
    if (_ready) return Future.value();
    return _initializing ??= _initialize().whenComplete(
      () => _initializing = null,
    );
  }

  static Future<void> _initialize() async {
    tzdata.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Shanghai'));
    await _plugin.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
      onDidReceiveNotificationResponse: (resp) {
        final p = resp.payload;
        if (p != null && p.isNotEmpty) onSelect?.call(p);
      },
    );
    _ready = true;
    try {
      await refreshPermission();
    } catch (_) {
      permission.value = null;
    }
  }

  static Future<void> refreshPermission() async {
    if (defaultTargetPlatform == TargetPlatform.android) {
      permission.value = await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.areNotificationsEnabled();
    } else if (defaultTargetPlatform == TargetPlatform.iOS) {
      permission.value =
          (await _plugin
                  .resolvePlatformSpecificImplementation<
                    IOSFlutterLocalNotificationsPlugin
                  >()
                  ?.checkPermissions())
              ?.isEnabled;
    }
  }

  /// 权限请求不进入冷启动深链关键路径。
  static Future<void> rerequestPermission() async {
    await init();
    if (defaultTargetPlatform == TargetPlatform.android) {
      await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestNotificationsPermission();
    } else if (defaultTargetPlatform == TargetPlatform.iOS) {
      await _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >()
          ?.requestPermissions(alert: true, badge: true, sound: true);
    }
    await refreshPermission();
  }

  /// App 冷启动时若由通知拉起，返回其 payload。
  static Future<String?> initialPayload() async {
    final d = await _plugin.getNotificationAppLaunchDetails();
    if (d == null || !d.didNotificationLaunchApp) return null;
    return d.notificationResponse?.payload;
  }

  /// 按最新作业列表与课表重排全部提醒（多次并发调用按序串行执行）。
  static Future<void> reschedule(
    List<HomeworkItem> items, {
    List<Course> courses = const [],
  }) {
    final snapshot = List<HomeworkItem>.of(items);
    final courseSnapshot = List<Course>.of(courses);
    final task = _rescheduleQueue.then((_) async {
      await _rescheduleNow(snapshot, courses: courseSnapshot);
    });
    // 队列吞掉单次失败，别让一次排期异常卡死后续所有重排
    _rescheduleQueue = task.catchError((Object error) {
      scheduleError.value = '提醒排期未完成，原有数据已保留，请稍后重试';
    });
    return task;
  }

  /// A time-limited iOS background refresh must not clear existing alarms:
  /// the system can suspend the process midway through a replan. Refill only
  /// after the pending queue has drained, on the same serial queue as the UI.
  static Future<bool> rescheduleIfNoPending(
    List<HomeworkItem> items, {
    List<Course> courses = const [],
  }) {
    final snapshot = List<HomeworkItem>.of(items);
    final courseSnapshot = List<Course>.of(courses);
    final task = _rescheduleQueue.then(
      (_) => _rescheduleNow(
        snapshot,
        courses: courseSnapshot,
        onlyWhenEmpty: true,
      ),
    );
    _rescheduleQueue = task.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {
        scheduleError.value = '提醒排期未完成，原有数据已保留，请稍后重试';
      },
    );
    return task;
  }

  static Future<bool> _rescheduleNow(
    List<HomeworkItem> items, {
    List<Course> courses = const [],
    bool onlyWhenEmpty = false,
  }) async {
    await init();
    // 完整候选按真实触发时间共同分配预算，远期课程不能挤掉近期作业。
    final now = clock();
    final pending = await _plugin.pendingNotificationRequests();
    if (onlyWhenEmpty && pending.isNotEmpty) return false;
    final exact = await exactAlarmPermission();
    final candidates = <_Reminder>[];
    final keptIds = <int>{};
    var keptHomework = 0;
    for (final hw in items) {
      if (hw.status == HwStatus.done || hw.status == HwStatus.submitted) {
        continue;
      }
      final due = hw.dueAt;
      if (due == null) continue;
      for (final h in Storage.reminders().enabledHours) {
        final fire = due.subtract(Duration(hours: h));
        final reminder = _Reminder(
          stableHash('hw#${hw.id}#$h') & 0x3fffffff,
          fire,
          '作业即将截止：${hw.course}',
          '「${hw.title}」$h小时后截止',
          payload:
              '$_homeworkPayload${jsonEncode({'id': hw.id, 'due': due.millisecondsSinceEpoch, 'hours': h})}',
        );
        if (fire.isAfter(now)) {
          candidates.add(reminder);
        } else if (due.isAfter(now)) {
          final lateBody = '「${hw.title}」临近截止，请查看详情';
          var keptCurrent = false;
          for (final p in pending) {
            if (p.payload == reminder.payload &&
                p.title == reminder.title &&
                (p.body == reminder.body || p.body == lateBody) &&
                keptIds.add(p.id)) {
              keptHomework++;
              keptCurrent = true;
            }
          }
          if (!keptCurrent &&
              pending.any(
                (p) =>
                    p.payload == reminder.payload ||
                    (p.payload == hw.id &&
                        (p.id == reminder.id ||
                            (p.title == reminder.title &&
                                p.body == reminder.body)) &&
                        (p.body?.endsWith('$h小时后截止') ?? false)),
              )) {
            // Older versions only stored the homework ID, so their trigger
            // time cannot be verified. Replace the pending legacy alarm with
            // an immediate reminder for the current, still-active deadline.
            candidates.add(
              _Reminder(
                reminder.id,
                now.add(const Duration(seconds: 2)),
                reminder.title,
                lateBody,
                payload: reminder.payload,
              ),
            );
          }
        }
      }
    }
    final plan = ClassReminderPlan.build(
      courses: courses,
      semesterStart: Storage.semesterStart(),
      now: now,
      enabled: Storage.classReminder(),
      minutes: Storage.classReminderMinutes(),
      slots: SectionTimes.current(),
    );
    final keptClasses = <ClassReminderEntry>[];
    for (final entry in plan.entries) {
      if (entry.fire.isAfter(now)) {
        candidates.add(
          _Reminder(
            entry.id,
            entry.fire,
            entry.title,
            entry.body,
            payload: entry.payload,
            isClass: true,
            lesson: entry.lesson,
            entry: entry,
          ),
        );
      } else if (pending.any(
        (p) => p.id == entry.id && p.payload == entry.payload,
      )) {
        // Android may still be holding an inexact alarm. Sync must not cancel
        // that un-delivered reminder just because its intended time has passed.
        keptIds.add(entry.id);
        keptClasses.add(entry);
      } else if (pending.any((p) {
        final target = ClassReminderTarget.parse(p.payload);
        if (target != null && target.courseId == entry.course.id) {
          final day = DateTime.fromMillisecondsSinceEpoch(target.lessonMs);
          return day.year == entry.lesson.year &&
              day.month == entry.lesson.month &&
              day.day == entry.lesson.day;
        }
        // Upgrade an old 15-minute alarm only with both its class ID and title.
        return p.id == entry.id &&
            (p.payload == null || p.payload!.isEmpty) &&
            p.title == '15分钟后上课：${entry.course.name}';
      })) {
        // A setting/content edit moved the intended trigger into the past.
        // There is positive proof this occurrence has not yet been delivered.
        final replacement = entry.at(now.add(const Duration(seconds: 2)));
        candidates.add(
          _Reminder(
            entry.id,
            replacement.fire,
            '即将上课：${entry.course.name}',
            entry.body,
            payload: entry.payload,
            isClass: true,
            lesson: entry.lesson,
            entry: replacement,
          ),
        );
      }
    }
    for (final p in pending) {
      if (p.id == _testId && p.payload?.startsWith(_testPayload) == true) {
        final stamp = int.tryParse(p.payload!.substring(_testPayload.length));
        // Give an inexact diagnostic up to an hour to arrive; never preserve
        // an unbounded stale test after a device restore.
        if (stamp != null &&
            stamp >
                now.subtract(const Duration(hours: 1)).millisecondsSinceEpoch) {
          keptIds.add(p.id);
        }
      }
    }
    candidates.sort((a, b) {
      final cmp = a.fire.compareTo(b.fire);
      return cmp != 0 ? cmp : a.id.compareTo(b.id);
    });
    final isIos = defaultTargetPlatform == TargetPlatform.iOS;
    DateTime? nextUnscheduled;
    if (isIos && courses.isNotEmpty && Storage.classReminder()) {
      // The normal plan covers 56 days. Find the next occurrence beyond that
      // window so iOS can ask the user to reopen before reminders run out.
      final start = Storage.semesterStart();
      if (start != null) {
        final startDay = DateTime(start.year, start.month, start.day);
        final firstMonday = startDay.subtract(
          Duration(days: startDay.weekday - 1),
        );
        var cursor = DateTime(now.year, now.month, now.day + 56);
        if (cursor.isBefore(firstMonday)) cursor = firstMonday;
        // Course entry supports at most 30 weeks; four 56-day windows cover it.
        for (
          var window = 0;
          window < 4 && Course.weekNumberOf(start, cursor) <= 30;
          window++
        ) {
          final later = ClassReminderPlan.build(
            courses: courses,
            semesterStart: start,
            now: cursor,
            enabled: true,
            minutes: Storage.classReminderMinutes(),
            slots: SectionTimes.current(),
          );
          if (later.entries.isNotEmpty) {
            nextUnscheduled = later.entries.first.fire;
            break;
          }
          cursor = DateTime(cursor.year, cursor.month, cursor.day + 56);
        }
      }
    }
    final needsRefreshSlot =
        isIos &&
        (nextUnscheduled != null || candidates.length + keptIds.length > 64);
    final budget = isIos ? (needsRefreshSlot ? 63 : 64) : 500;
    var homeworkCount = keptHomework,
        classCount = keptClasses.length,
        total = keptIds.length,
        failed = 0;
    if (!onlyWhenEmpty) {
      if (keptIds.isEmpty) {
        await _plugin.cancelAllPendingNotifications();
      } else {
        for (final p in pending) {
          if (!keptIds.contains(p.id)) await _plugin.cancel(p.id);
        }
      }
    }
    final usedIds = <int>{_testId, _refreshId, ...keptIds};
    final scheduledClasses = [...keptClasses];
    var actualExact = exact;
    for (final item in candidates) {
      if (total >= budget ||
          (item.isClass ? classCount >= 400 : homeworkCount >= 100)) {
        if (isIos &&
            (nextUnscheduled == null || item.fire.isBefore(nextUnscheduled))) {
          nextUnscheduled = item.fire;
        }
        continue;
      }
      var id = item.id;
      while (!usedIds.add(id)) {
        id = (id + 1) & 0x7fffffff;
      }
      try {
        final precise = await _schedule(
          item.withId(id),
          item.isClass && actualExact == true,
        );
        if (item.isClass &&
            !precise &&
            defaultTargetPlatform == TargetPlatform.android) {
          actualExact = false;
        }
        total++;
        if (item.isClass) {
          classCount++;
          scheduledClasses.add(item.entry!);
        } else {
          homeworkCount++;
        }
      } catch (_) {
        failed++;
      }
    }
    if (isIos && nextUnscheduled != null && total < 64) {
      final proposed = nextUnscheduled.subtract(const Duration(hours: 6));
      final refreshAt = proposed.isAfter(now.add(const Duration(minutes: 1)))
          ? proposed
          : now.add(const Duration(minutes: 1));
      try {
        await _schedule(
          _Reminder(
            _refreshId,
            refreshAt,
            '打开作业通以更新后续提醒',
            'iOS 的待发送提醒数量有限，打开应用后会继续安排后续提醒。',
            payload: '$_refreshPayload${refreshAt.millisecondsSinceEpoch}',
          ),
          false,
        );
      } catch (_) {
        failed++;
      }
    } else if (isIos && nextUnscheduled != null) {
      failed++;
    }
    scheduledClasses.sort((a, b) => a.fire.compareTo(b.fire));
    scheduleError.value = failed == 0 ? null : '$failed 条提醒排期失败，请检查系统通知设置后重试';
    classSchedule.value = ClassScheduleStatus(
      next: scheduledClasses.firstOrNull,
      scheduledCount: classCount,
      exact: actualExact,
      issue:
          scheduleError.value ??
          plan.issue ??
          (nextUnscheduled == null ? null : 'iOS 需要重新打开应用以安排更远的提醒'),
    );
    return true;
  }

  /// Returns the mode actually accepted; permission can be revoked between the
  /// check and AlarmManager call. A precise failure must not drop the reminder.
  static Future<bool> _schedule(_Reminder item, bool precise) async {
    Future<void> send(bool exact) => _plugin.zonedSchedule(
      item.id,
      item.title,
      item.body,
      tz.TZDateTime.from(item.fire, tz.local),
      NotificationDetails(
        android: AndroidNotificationDetails(
          item.isClass ? 'class_reminder' : 'homework_due',
          item.isClass ? '上课提醒' : '作业截止提醒',
          importance: Importance.high,
          priority: Priority.high,
          styleInformation: BigTextStyleInformation(item.body),
          category: item.isClass ? AndroidNotificationCategory.reminder : null,
          when: item.lesson?.millisecondsSinceEpoch,
          usesChronometer: item.isClass,
          chronometerCountDown: item.isClass,
          // System renders the countdown; no running foreground service/timer.
          timeoutAfter: item.lesson?.difference(item.fire).inMilliseconds,
        ),
        iOS: const DarwinNotificationDetails(),
      ),
      payload: item.payload,
      androidScheduleMode: exact
          ? AndroidScheduleMode.exactAllowWhileIdle
          : AndroidScheduleMode.inexactAllowWhileIdle,
    );
    try {
      await send(precise);
      return precise;
    } on PlatformException catch (e) {
      if (!precise || e.code != 'exact_alarms_not_permitted') rethrow;
      await send(false);
      return false;
    }
  }

  static Future<void> showSimple(
    String title,
    String body, {
    String? payload,
    String channelId = 'homework_due',
  }) async {
    final channel = _reminderChannel(channelId);
    await init();
    await _plugin.show(
      DateTime.now().millisecondsSinceEpoch & 0x7fffffff,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          channel.id,
          channel.name,
          channelDescription: channel.description,
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: const DarwinNotificationDetails(),
      ),
      payload: payload,
    );
  }
}

class _Reminder {
  const _Reminder(
    this.id,
    this.fire,
    this.title,
    this.body, {
    this.payload,
    this.isClass = false,
    this.lesson,
    this.entry,
  });
  final int id;
  final DateTime fire;
  final String title;
  final String body;
  final String? payload;
  final bool isClass;
  final DateTime? lesson;
  final ClassReminderEntry? entry;
  _Reminder withId(int value) => _Reminder(
    value,
    fire,
    title,
    body,
    payload: payload,
    isClass: isClass,
    lesson: lesson,
    entry: entry,
  );
}
