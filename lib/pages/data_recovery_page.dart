import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models/homework.dart';
import '../services/backup_service.dart';
import '../services/local_recovery_store.dart';
import '../services/storage.dart';
import '../ui/settings_parts.dart';
import 'backup_restore_page.dart';

class DataRecoveryPage extends StatefulWidget {
  const DataRecoveryPage({super.key, required this.state});
  final AppState state;
  @override
  State<DataRecoveryPage> createState() => _DataRecoveryPageState();
}

class _DataRecoveryPageState extends State<DataRecoveryPage> {
  bool _busy = false;
  String? _error;

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (error) {
      if (context.mounted) {
        setState(
          () => _error = error is StateError
              ? error.message.toString()
              : '操作未完成，原记录已保留，请重试。',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _date(DateTime date) =>
      '${date.month}月${date.day}日 ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    List<DeletedHomework> deleted = [];
    List<LocalRecoveryPoint> points = [];
    String? readError;
    try {
      deleted = LocalRecoveryStore.deleted();
      points = LocalRecoveryStore.points();
    } catch (_) {
      readError = '部分本地恢复记录暂时无法读取，原始记录仍保留，请先导出当前数据。';
    }
    return PopScope(
      canPop: !_busy,
      child: SettingsScaffold(
        title: '本地恢复',
        actions: [
          TextButton(
            onPressed: _busy
                ? null
                : () => _run(() async {
                    await Storage.waitForBusinessTransaction();
                    await LocalRecoveryStore.capture(
                      BackupService.encode(),
                      reason: '手动备份',
                    );
                  }),
            child: const Text('立即备份'),
          ),
        ],
        body: SettingsList(
          children: [
            const SettingsSection(
              children: [
                Padding(
                  padding: EdgeInsets.all(16),
                  child: SettingsNote(
                    '本机保留最近 7 份历史备份；每天首次使用及恢复数据前自动保存。卸载应用或设备丢失后可能无法找回，请同时保留外部导出的备份。',
                  ),
                ),
              ],
            ),
            if (_error ?? readError ?? LocalRecoveryStore.error.value
                case final error?)
              SettingsSection(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: SettingsNote(error),
                  ),
                ],
              ),
            SettingsSection(
              title: '已删除的手动作业 · ${deleted.length}',
              footer: '平台作业仍使用“隐藏”，可以在已隐藏的作业中恢复。',
              children: [
                if (deleted.isEmpty)
                  const SettingsRow(
                    icon: Icons.delete_outline,
                    title: '没有已删除的手动作业',
                  ),
                for (final entry in deleted)
                  SettingsRow(
                    icon: Icons.assignment_return_outlined,
                    title: entry.item.title,
                    subtitle:
                        '${entry.item.course} · ${_date(entry.deletedAt)} 删除\n${entry.item.dueAt == null ? '截止时间未设置' : HomeworkItem.formatDueTime(entry.item.dueAt!)}',
                    trailing: TextButton(
                      onPressed: _busy
                          ? null
                          : () => _run(() async {
                              await widget.state.restoreDeletedHomework(
                                entry.item.id,
                              );
                              if (context.mounted) {
                                final messenger = ScaffoldMessenger.of(context)
                                  ..clearSnackBars();
                                messenger.showSnackBar(
                                  SnackBar(
                                    content: Text('已恢复「${entry.item.title}」'),
                                  ),
                                );
                              }
                            }),
                      child: const Text('恢复'),
                    ),
                  ),
              ],
            ),
            SettingsSection(
              title: '历史备份 · ${points.length}',
              children: [
                if (points.isEmpty)
                  const SettingsRow(
                    icon: Icons.history_outlined,
                    title: '暂无历史备份',
                    subtitle: '有作业或课表后自动开始保存',
                  ),
                for (final point in points)
                  SettingsRow(
                    icon: Icons.restore_outlined,
                    title: '${_date(point.createdAt)} · ${point.reason}',
                    subtitle:
                        '作业 ${point.homeworkCount} 项 · 课程 ${point.courseCount} 节',
                    navigation: true,
                    onTap: _busy
                        ? null
                        : () => _run(
                            () => openBackupRestore(
                              context,
                              widget.state,
                              point.readBackup(),
                            ),
                          ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
