import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../app_state.dart';
import '../models/homework.dart';
import '../services/backup_service.dart';
import '../services/storage.dart';
import '../ui/settings_parts.dart';

Future<void> openBackupRestore(
  BuildContext context,
  AppState state,
  String raw,
) async {
  final preview = await BackupService.previewJson(raw);
  if (!context.mounted) return;
  await Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) =>
          BackupRestorePage(state: state, raw: raw, preview: preview),
    ),
  );
}

class BackupRestorePage extends StatefulWidget {
  const BackupRestorePage({
    super.key,
    required this.state,
    required this.raw,
    required this.preview,
  });
  final AppState state;
  final String raw;
  final BackupPreview preview;
  @override
  State<BackupRestorePage> createState() => _BackupRestorePageState();
}

class _BackupRestorePageState extends State<BackupRestorePage> {
  late final int _epoch;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _epoch = Storage.syncEpoch;
  }

  Future<void> _restore() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => SettingsAlertDialog(
        title: const Text('恢复这份备份？'),
        content: const Text('会先保存当前数据的本地备份，再恢复预览中的内容。账号登录不变；已登录平台的备份作业放入只读归档。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('返回预览'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认恢复'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    if (_epoch != Storage.syncEpoch) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('当前数据已变化，请重新打开预览后恢复。')));
      return;
    }
    setState(() => _busy = true);
    var committed = false;
    try {
      var message = await BackupService.importJson(widget.raw);
      committed = true;
      try {
        await widget.state.reloadLocal();
      } catch (_) {
        message = '数据已恢复，提醒或小组件刷新稍有延迟，请勿重复恢复。';
      }
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.pop(context);
      messenger.clearSnackBars();
      messenger.showSnackBar(SnackBar(content: Text(message)));
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              committed
                  ? '数据已恢复，请返回查看，勿重复操作。'
                  : error is FormatException
                  ? error.message
                  : '恢复未完成，当前数据已保留，请重试。',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.preview;
    return PopScope(
      canPop: !_busy,
      child: SettingsScaffold(
        title: '恢复预览',
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
            child: FilledButton(
              onPressed: _busy ? null : _restore,
              child: Text(_busy ? '正在恢复…' : '恢复这份备份'),
            ),
          ),
        ),
        body: ListView.builder(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          itemCount: 1 + p.items.length + p.courses.length,
          itemBuilder: (context, index) {
            if (index == 0) {
              return SettingsSection(
                title: '确认恢复内容',
                children: [
                  SettingsRow(
                    icon: Icons.inventory_2_outlined,
                    title: '作业 ${p.items.length} 项 · 课程 ${p.courses.length} 节',
                    subtitle: '隐藏记录 ${p.hiddenCount} 项 · 回收站 ${p.trashCount} 项',
                  ),
                  if (p.exportedAt != null)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: SettingsNote(
                        '备份时间 ${DateFormat('yyyy/MM/dd HH:mm').format(p.exportedAt!.toLocal())}',
                      ),
                    ),
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: SettingsNote(
                      '备份中包含的手动作业、课表和设置会替换当前内容。已登录平台的当前作业与隐藏记录保留，备份里的对应平台记录放入历史归档。恢复前会自动备份当前数据。',
                    ),
                  ),
                  if (!p.hasCourses)
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: SettingsNote('这份备份未包含课表，当前课表保留。'),
                    ),
                  if (!p.hasHomework)
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: SettingsNote('这份备份未包含作业列表，当前作业保留。'),
                    ),
                ],
              );
            }
            final taskIndex = index - 1;
            if (taskIndex < p.items.length) {
              final item = p.items[taskIndex];
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.assignment_outlined),
                title: Text(item.title),
                subtitle: Text(
                  '${item.course} · ${item.platform.label}\n${item.dueAt == null ? '截止时间未设置' : HomeworkItem.formatDueTime(item.dueAt!)}',
                ),
              );
            }
            final course = p.courses[taskIndex - p.items.length];
            return ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.calendar_today_outlined),
              title: Text(course.name),
              subtitle: Text(
                '周${course.weekday} · ${course.startSection}–${course.endSection} 节 · ${course.room}',
              ),
            );
          },
        ),
      ),
    );
  }
}
