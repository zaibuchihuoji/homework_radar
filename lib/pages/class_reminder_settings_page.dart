import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import '../services/notification_service.dart';
import '../services/storage.dart';
import '../ui/focus_parts.dart';
import '../ui/settings_parts.dart';
import 'notification_settings_page.dart';

class ClassReminderSettingsPage extends StatefulWidget {
  const ClassReminderSettingsPage({super.key, required this.state});
  final AppState state;
  @override
  State<ClassReminderSettingsPage> createState() =>
      _ClassReminderSettingsPageState();
}

class _ClassReminderSettingsPageState extends State<ClassReminderSettingsPage>
    with WidgetsBindingObserver {
  bool _busy = false;
  bool? _exact;
  String? _error;
  DateTime? _testAt;
  Map<String, dynamic>? _island;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    try {
      await NotificationService.refreshPermission();
      final exact = await NotificationService.exactAlarmPermission();
      final island = await NotificationService.islandCapability();
      await NotificationService.reschedule(
        widget.state.homework,
        courses: widget.state.courses,
      );
      if (mounted) {
        setState(() {
          _exact = exact;
          _island = island;
          _error = null;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _error = '暂时无法读取排期，请稍后重试');
    }
  }

  Future<void> _change(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      if (mounted) setState(() => _error = null);
    } catch (_) {
      if (mounted) setState(() => _error = '设置或排期未完成，请稍后重试');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _time(DateTime t) =>
      '${t.month}月${t.day}日 ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  Future<void> _custom() async {
    final controller = TextEditingController(
      text: Storage.classReminderMinutes().toString(),
    );
    final value = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('提前多少分钟'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(3),
          ],
          decoration: const InputDecoration(
            labelText: '1–180 分钟',
            suffixText: '分钟',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              final n = int.tryParse(controller.text);
              if (n != null && n >= 1 && n <= 180) Navigator.pop(context, n);
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
    // Dispose after the closing route has released its TextField.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    controller.dispose();
    if (value != null && mounted) {
      await _change(() => widget.state.updateClassReminderMinutes(value));
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.state,
    builder: (context, _) => SettingsScaffold(
      title: '课前提醒',
      body: SettingsList(
        children: [
          const FocusSummary(
            eyebrow: '课程日程',
            title: '提前一点，从容上课',
            detail: '按开学日期、上课周次和学校作息安排提醒。',
          ),
          SettingsSection(
            children: [
              SettingsSwitchRow(
                icon: Icons.school_outlined,
                title: '上课提醒',
                value: Storage.classReminder(),
                onChanged: _busy
                    ? null
                    : (v) => _change(() => widget.state.updateClassReminder(v)),
              ),
              const SettingsDivider(),
              SettingsRow(
                icon: Icons.schedule_rounded,
                title: '提前时间',
                value: '${Storage.classReminderMinutes()} 分钟',
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final n in [5, 10, 15, 30, 60])
                      ChoiceChip(
                        label: Text('$n 分钟'),
                        selected: Storage.classReminderMinutes() == n,
                        onSelected: _busy
                            ? null
                            : (_) => _change(
                                () =>
                                    widget.state.updateClassReminderMinutes(n),
                              ),
                      ),
                    ActionChip(
                      label: const Text('自定义'),
                      onPressed: _busy ? null : _custom,
                    ),
                  ],
                ),
              ),
            ],
          ),
          ValueListenableBuilder<ClassScheduleStatus>(
            valueListenable: NotificationService.classSchedule,
            builder: (context, status, _) {
              final next = status.next;
              final allowed = NotificationService.notificationsEnabled;
              return SettingsSection(
                title: '提醒状态',
                children: [
                  SettingsRow(
                    icon: Icons.event_available_outlined,
                    title: !Storage.classReminder()
                        ? '上课提醒已关闭'
                        : allowed == false
                        ? '通知权限已关闭'
                        : next == null
                        ? '暂无待触发的课前提醒'
                        : '下一条 · ${next.course.name}',
                    subtitle: !Storage.classReminder()
                        ? null
                        : allowed == false
                        ? '请在系统设置中允许作业通发送通知'
                        : next == null
                        ? (status.issue ?? '未来八周没有可排期的课程；请核对开学日期和上课周次')
                        : '${_time(next.fire)} 提醒\n${_time(next.lesson)} 开始${next.course.room.isEmpty ? '' : ' · ${next.course.room}'}',
                  ),
                  if (next != null && status.issue != null)
                    SettingsNote(status.issue!, warning: true),
                  if (_error != null) SettingsNote(_error!, warning: true),
                ],
              );
            },
          ),
          if (defaultTargetPlatform == TargetPlatform.android) ...[
            SettingsSection(
              title: '准时送达',
              children: [
                SettingsRow(
                  icon: Icons.alarm_on_outlined,
                  title: _exact == true ? '精确定时已允许' : '允许精确定时',
                  subtitle: _exact == true
                      ? '课前提醒按设定时刻唤醒；仍受系统勿扰与通知设置影响'
                      : '未允许时使用系统普通定时，锁屏省电时可能延后。',
                  navigation: _exact != true,
                  onTap: _busy
                      ? null
                      : () => _change(() async {
                          await NotificationService.requestExactAlarmPermission();
                          await _refresh();
                        }),
                ),
                const SettingsDivider(),
                SettingsRow(
                  title: '通知横幅与声音',
                  subtitle: '分别检查上课提醒的横幅和声音',
                  navigation: true,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => const NotificationSettingsPage(),
                    ),
                  ),
                ),
              ],
            ),
            SettingsSection(
              title: '厂商提醒卡片',
              children: [
                SettingsRow(
                  icon: Icons.dynamic_feed_outlined,
                  title: _island?['name'] as String? ?? '系统提醒卡片',
                  subtitle: '厂商场景接入尚未开通，目前使用普通课前通知。原子岛、流体云与超级岛需要分别获得厂商准入。',
                ),
              ],
            ),
          ],
          SettingsSection(
            title: '锁屏定时检查',
            children: [
              SettingsRow(
                icon: Icons.timer_outlined,
                title: '一分钟后提醒',
                subtitle: _testAt == null
                    ? '安排后可退到桌面并锁屏，检查后台定时是否送达。'
                    : '已安排在 ${_time(_testAt!)}；请退到桌面或锁屏等待。',
                onTap: _busy
                    ? null
                    : () => _change(() async {
                        final at =
                            await NotificationService.scheduleClassTest();
                        if (mounted) setState(() => _testAt = at);
                      }),
                navigation: true,
              ),
            ],
          ),
          const SettingsNote('课程、周次或作息不完整时不会猜测上课时间。修改课表后会重新安排；请勿在系统中强行停止 App。'),
        ],
      ),
    ),
  );
}
