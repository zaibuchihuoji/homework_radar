/// 本地通知：截止前 24h/6h/1h 提醒（可在设置里开关）。
/// 点击通知可携带 payload（作业 id）跳转到详情页。
library;

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../models/course.dart';
import '../models/homework.dart';
import 'section_times.dart';
import 'stable_hash.dart';
import 'storage.dart';

class NotificationService {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;

  /// 通知权限是否被授予（init 时采样；null = 还没查过/平台不支持）。
  /// 此前请求结果直接丢弃、从不检查，Android 13+ 拒绝后全部提醒静默失效。
  static bool? notificationsEnabled;

  /// 点击通知的回调（payload 为作业 id）
  static void Function(String payload)? onSelect;

  /// reschedule 串行队列：冷启动本地重排与同步后重排可能并发交错，
  /// 各自的「清待排 → 重排」两步会互相交错清场，留下过期/已删作业的提醒。
  static Future<void> _rescheduleQueue = Future.value();

  static Future<void> init() async {
    if (_ready) return;
    tzdata.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Shanghai'));
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
    );
    await _plugin.initialize(
      settings,
      onDidReceiveNotificationResponse: (resp) {
        final p = resp.payload;
        if (p != null && p.isNotEmpty) onSelect?.call(p);
      },
    );
    final impl = _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    await impl?.requestNotificationsPermission();
    notificationsEnabled = await impl?.areNotificationsEnabled();
    _ready = true;
  }

  /// 通知权限被拒后引导重开：再次拉起系统授权弹窗并刷新状态。
  /// 永久拒绝时系统不再弹窗，用户需去系统设置——此时提醒静默失效的
  /// 状态至少在设置页可见（notificationsEnabled == false）。
  static Future<void> rerequestPermission() async {
    final impl = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await impl?.requestNotificationsPermission();
    notificationsEnabled = await impl?.areNotificationsEnabled();
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
    final task = _rescheduleQueue.then((_) => _rescheduleNow(items, courses: courses));
    // 队列吞掉单次失败，别让一次排期异常卡死后续所有重排
    _rescheduleQueue = task.catchError((_) {});
    return task;
  }

  static Future<void> _rescheduleNow(
    List<HomeworkItem> items, {
    List<Course> courses = const [],
  }) async {
    await init();
    // 只清「待排」、不清已弹出：cancelAll 会把刚弹出的测试通知/课前提醒
    // 一并灭掉（用户正看着通知它就消失了）；flutter_local_notifications
    // 19.x 起提供 cancelAllPendingNotifications，精确只重置待排队列。
    await _plugin.cancelAllPendingNotifications();
    final r = Storage.reminders();
    final now = DateTime.now();
    // 排近截止的优先：总量封顶时牺牲的是更远的提醒
    final sorted = [...items]
      ..sort((a, b) {
        final ad = a.dueAt, bd = b.dueAt;
        if (ad == null && bd == null) return 0;
        if (ad == null) return 1;
        if (bd == null) return -1;
        return ad.compareTo(bd);
      });
    int id = 1;
    // 上课提醒另占至多 400 个 id；作业提醒封顶 100，总量留在系统
    // 单应用 500 闹钟上限之内，触顶静默丢失的只会是最远的作业提醒。
    const maxHomeworkScheduled = 100;
    var scheduled = 0;
    for (final hw in sorted) {
      if (scheduled >= maxHomeworkScheduled) break;
      // 已提交 = 已交，与卡片/小组件的完结口径一致，不再提醒
      if (hw.status == HwStatus.done || hw.status == HwStatus.submitted) {
        continue;
      }
      final due = hw.dueAt;
      if (due == null || due.isBefore(now)) continue;
      for (final h in r.enabledHours) {
        final fire = due.subtract(Duration(hours: h));
        if (!fire.isAfter(now)) continue;
        final details = NotificationDetails(
          android: const AndroidNotificationDetails(
            'homework_due',
            '作业截止提醒',
            channelDescription: '作业截止前的倒计时提醒（作业通）',
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: const DarwinNotificationDetails(),
        );
        try {
          await _plugin.zonedSchedule(
            id++,
            '作业即将截止：${hw.course}',
            '「${hw.title}」$h小时后截止',
            tz.TZDateTime.from(fire, tz.local),
            details,
            payload: hw.id,
            androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          );
          scheduled++;
        } catch (_) {
          // 单条排期失败不阻塞其余提醒
        }
      }
    }
    await _scheduleClassReminders(courses, now);
  }

  /// 未来 8 周有课的，提前 15 分钟提醒（可在设置里关）。
  static Future<void> _scheduleClassReminders(
      List<Course> courses, DateTime now) async {
    if (courses.isEmpty || !Storage.classReminder()) return;
    final start = Storage.semesterStart();
    // 无后台同步，提醒只能趁打开 App 时排远：一次排 8 周（约大半个学期），
    // 总量封顶，防止极端课表把系统通知排爆。
    const horizonDays = 56;
    const maxScheduled = 400;
    final channel = NotificationDetails(
      android: const AndroidNotificationDetails(
        'class_reminder',
        '上课提醒',
        channelDescription: '课前 15 分钟的上课提醒（作业通）',
        importance: Importance.high,
        priority: Priority.high,
      ),
      iOS: const DarwinNotificationDetails(),
    );
    var scheduled = 0;
    for (var d = 0; d < horizonDays && scheduled < maxScheduled; d++) {
      final day = DateTime(now.year, now.month, now.day + d);
      final week = start == null
          ? null
          : Course.weekNumberOf(start, day);
      if (week == null) continue;
      for (final c in courses) {
        if (c.weekday != day.weekday || !c.inWeek(week)) continue;
        // 作息表没配到该节次时取时刻函数返回 null：此刻不存在真实上课
        // 时间，跳过这节课的提醒排期——绝不能钳到末节（21:45）后
        // 按错误时刻每晚误报
        final lessonStart = SectionTimes.startOfDay(day, c.startSection);
        if (lessonStart == null) continue;
        final fire = lessonStart.subtract(const Duration(minutes: 15));
        if (!fire.isAfter(now)) continue;
        final place = c.room.isEmpty ? '' : ' @${c.room}';
        try {
          await _plugin.zonedSchedule(
            // 同日同起始节次的两门课也要不同 ID，否则后者覆盖前者；
            // 用稳定哈希而非 String.hashCode（跨执行无契约保证）
            0x40000000 |
                (stableHash(
                        '${c.id}#${day.year * 10000 + day.month * 100 + day.day}') &
                    0x3FFFFFFF),
            '15分钟后上课：${c.name}',
            '第${c.startSection}节$place',
            tz.TZDateTime.from(fire, tz.local),
            channel,
            androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          );
          scheduled++;
        } catch (_) {
          // 单条失败不阻塞
        }
      }
    }
  }

  static Future<void> showSimple(String title, String body,
      {String? payload}) async {
    await init();
    await _plugin.show(
      DateTime.now().millisecondsSinceEpoch & 0x7fffffff,
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'homework_due',
          '作业截止提醒',
          channelDescription: '作业截止前的倒计时提醒（作业通）',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),
      payload: payload,
    );
  }
}
