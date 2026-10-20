import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../services/notification_service.dart';
import '../ui/adaptive.dart';
import '../ui/ink_wash.dart';
import '../ui/style_background.dart';
import '../ui/theme_page_parts.dart';

class NotificationSettingsPage extends StatefulWidget {
  const NotificationSettingsPage({super.key, this.homeworkId});
  final String? homeworkId;

  @override
  State<NotificationSettingsPage> createState() =>
      _NotificationSettingsPageState();
}

class _NotificationSettingsPageState extends State<NotificationSettingsPage>
    with WidgetsBindingObserver {
  List<AndroidNotificationChannel>? _channels;
  bool _loading = true;
  bool _failed = false;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      await NotificationService.refreshPermission();
      final channels = await NotificationService.androidChannelSettings();
      if (!mounted) return;
      setState(() {
        _channels = channels;
        _failed = false;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _failed = true;
        _loading = false;
      });
    }
  }

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _open([String? id]) async {
    try {
      if (!await NotificationService.openAndroidNotificationSettings(
        channelId: id,
      )) {
        _message('无法打开，请到手机系统设置 → 应用 → 作业通 → 通知');
      }
    } catch (_) {
      _message('无法打开，请到手机系统设置 → 应用 → 作业通 → 通知');
    }
  }

  String _status(String id) {
    if (_loading) return '正在读取系统设置…';
    if (_failed) return '暂时无法读取；仍可打开系统设置检查';
    final matches = _channels?.where((c) => c.id == id);
    if (matches == null || matches.isEmpty) {
      return '暂未开启，可发送一条提醒或打开系统设置';
    }
    final channel = matches.first;
    if (channel.importance == Importance.none) return '此类通知已关闭';
    final priority = channel.importance.value < Importance.high.value
        ? '当前优先级不足以显示顶部横幅'
        : '系统高优先级';
    final audible =
        channel.playSound &&
        channel.importance.value >= Importance.defaultImportance.value;
    return '$priority · 声音${audible ? '开启' : '关闭'}';
  }

  Future<void> _test(String id) async {
    setState(() => _sending = true);
    try {
      await NotificationService.showSimple(
        id == 'homework_due' ? '作业截止提醒' : '上课提醒',
        '这是一条提醒，点击返回作业通',
        channelId: id,
        payload: id == 'homework_due' ? widget.homeworkId : null,
      );
      _message('提醒已发送');
      await _refresh();
    } catch (_) {
      _message('发送失败，请检查通知权限');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) => StyleBackground(
    child: Scaffold(
      backgroundColor: scaffoldBgOf(context),
      appBar: AppBar(title: appBarTitle(context, '通知横幅与声音')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          ThemePanel(
            label: '顶部横幅',
            icon: Icons.notifications_active_outlined,
            child: const Text('想在屏幕顶部看到提醒，请在系统通知设置中允许横幅或悬浮通知。'),
          ),
          const SizedBox(height: 12),
          ValueListenableBuilder<bool?>(
            valueListenable: NotificationService.permission,
            builder: (context, allowed, _) => ThemePanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    allowed == false
                        ? 'App 通知权限已关闭'
                        : allowed == true
                        ? 'App 通知权限已允许'
                        : 'App 通知权限状态未知',
                  ),
                  const SizedBox(height: 4),
                  const Text('横幅和声音可在系统设置中调整。'),
                  TextButton(
                    onPressed: () => _open(),
                    child: const Text('打开 App 通知设置'),
                  ),
                ],
              ),
            ),
          ),
          for (final channel
              in NotificationService.androidReminderChannels) ...[
            const SizedBox(height: 12),
            ThemePanel(
              label: channel.name,
              icon: channel.id == 'homework_due'
                  ? Icons.assignment_outlined
                  : Icons.school_outlined,
              seed: channel.id,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(_status(channel.id)),
                  const SizedBox(height: 6),
                  const Text('可分别设置横幅、声音和振动。'),
                  TextButton(
                    onPressed: () => _open(channel.id),
                    child: Text('设置${channel.name}'),
                  ),
                  OutlinedButton(
                    onPressed: _sending ? null : () => _test(channel.id),
                    child: const Text('发送一条提醒'),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          const Text('未收到提醒时，请检查系统通知权限和勿扰模式。'),
        ],
      ),
    ),
  );
}
