/// 本地通知：截止前 24h/6h/1h 提醒（可在设置里开关）。
/// 点击通知可携带 payload（作业 id）跳转到详情页。
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../models/course.dart';
import '../models/homework.dart';
import 'section_times.dart';
import 'stable_hash.dart';
import 'storage.dart';

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
    final task = _rescheduleQueue.then(
      (_) => _rescheduleNow(snapshot, courses: courseSnapshot),
    );
    // 队列吞掉单次失败，别让一次排期异常卡死后续所有重排
    _rescheduleQueue = task.catchError((_) {});
    return task;
  }

  static Future<void> _rescheduleNow(
    List<HomeworkItem> items, {
    List<Course> courses = const [],
  }) async {
    await init();
    // 完整候选按真实触发时间共同分配预算，远期课程不能挤掉近期作业。
    final now = DateTime.now();
    final candidates = <_Reminder>[];
    for (final hw in items) {
      if (hw.status == HwStatus.done || hw.status == HwStatus.submitted) {
        continue;
      }
      final due = hw.dueAt;
      if (due == null) continue;
      for (final h in Storage.reminders().enabledHours) {
        final fire = due.subtract(Duration(hours: h));
        if (!fire.isAfter(now)) continue;
        candidates.add(
          _Reminder(
            stableHash('hw#${hw.id}#$h') & 0x3fffffff,
            fire,
            '作业即将截止：${hw.course}',
            '「${hw.title}」$h小时后截止',
            payload: hw.id,
          ),
        );
      }
    }
    final start = Storage.semesterStart();
    if (start != null && Storage.classReminder()) {
      for (var d = 0; d < 56; d++) {
        final day = DateTime(now.year, now.month, now.day + d);
        final week = Course.weekNumberOf(start, day);
        if (week < 1) continue;
        for (final c in courses) {
          if (c.weekday != day.weekday || !c.inWeek(week)) continue;
          final lesson = SectionTimes.startOfDay(day, c.startSection);
          if (lesson == null) continue;
          final fire = lesson.subtract(const Duration(minutes: 15));
          if (!fire.isAfter(now)) continue;
          final place = c.room.isEmpty ? '' : ' @${c.room}';
          candidates.add(
            _Reminder(
              0x40000000 |
                  (stableHash('${c.id}#${day.year}-${day.month}-${day.day}') &
                      0x3fffffff),
              fire,
              '15分钟后上课：${c.name}',
              '第${c.startSection}节$place',
              isClass: true,
            ),
          );
        }
      }
    }
    candidates.sort((a, b) {
      final cmp = a.fire.compareTo(b.fire);
      return cmp != 0 ? cmp : a.id.compareTo(b.id);
    });
    final budget = defaultTargetPlatform == TargetPlatform.iOS ? 64 : 500;
    var homeworkCount = 0, classCount = 0, total = 0, failed = 0;
    await _plugin.cancelAllPendingNotifications();
    final usedIds = <int>{};
    for (final item in candidates) {
      if (total >= budget) break;
      if (item.isClass ? classCount >= 400 : homeworkCount >= 100) continue;
      var id = item.id;
      while (!usedIds.add(id)) {
        id = (id + 1) & 0x7fffffff;
      }
      try {
        await _plugin.zonedSchedule(
          id,
          item.title,
          item.body,
          tz.TZDateTime.from(item.fire, tz.local),
          NotificationDetails(
            android: AndroidNotificationDetails(
              item.isClass ? 'class_reminder' : 'homework_due',
              item.isClass ? '上课提醒' : '作业截止提醒',
              importance: Importance.high,
              priority: Priority.high,
            ),
            iOS: const DarwinNotificationDetails(),
          ),
          payload: item.payload,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        );
        total++;
        if (item.isClass) {
          classCount++;
        } else {
          homeworkCount++;
        }
      } catch (_) {
        failed++;
      }
    }
    scheduleError.value = failed == 0 ? null : '$failed 条提醒排期失败，请检查系统通知设置后重试';
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
  });
  final int id;
  final DateTime fire;
  final String title;
  final String body;
  final String? payload;
  final bool isClass;
}
