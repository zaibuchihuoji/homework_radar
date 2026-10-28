import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../models/course.dart';
import '../models/homework.dart';
import '../services/backup_service.dart';
import '../services/storage.dart';

/// A read-only, credential-free escape hatch when normal startup is unsafe.
class StartupRecoveryApp extends StatefulWidget {
  const StartupRecoveryApp({
    super.key,
    required this.retry,
    required this.canReadLocalData,
    required this.secureFailure,
  });

  final Future<void> Function() retry;
  final bool canReadLocalData;
  final bool secureFailure;

  @override
  State<StartupRecoveryApp> createState() => _StartupRecoveryAppState();
}

class _StartupRecoveryAppState extends State<StartupRecoveryApp> {
  final _navigatorKey = GlobalKey<NavigatorState>();
  bool _busy = false;
  String? _message;

  Future<void> _retry() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await widget.retry();
    } catch (_) {
      if (mounted) setState(() => _message = '暂时无法恢复访问，请稍后重试。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _export() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      if (!Storage.localDataReadyForRecovery) {
        throw StateError('本地事务尚未恢复');
      }
      await Storage.waitForBusinessTransaction();
      Uint8List bytes;
      var currentOnly = false;
      try {
        bytes = await BackupService.exportBundle();
      } catch (_) {
        final dialogContext = _navigatorKey.currentContext;
        if (!mounted || dialogContext == null || !dialogContext.mounted) return;
        final proceed = await showDialog<bool>(
          context: dialogContext,
          builder: (dc) => AlertDialog(
            title: const Text('完整备份未能完成'),
            content: const Text(
              '部分历史版本或附件可能无法读取，也可能超过备份大小限制。可尝试仅导出当前数据，该文件不包含笔记历史版本。请保留设备中的旧数据。',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dc, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dc, true),
                child: const Text('仅导出当前数据'),
              ),
            ],
          ),
        );
        if (proceed != true) return;
        bytes = await BackupService.exportBundle(includeHistory: false);
        currentOnly = true;
      }
      final path = await FilePicker.saveFile(
        fileName: currentOnly
            ? 'homework_radar_recovery_current_only.hwbackup'
            : 'homework_radar_recovery.hwbackup',
        bytes: bytes,
        mimeType: 'application/octet-stream',
      );
      if (mounted) {
        setState(
          () => _message = path == null
              ? '已取消导出'
              : currentOnly
              ? '当前数据已导出，文件不含笔记历史版本'
              : '本地完整备份已导出',
        );
      }
    } catch (_) {
      if (mounted) setState(() => _message = '导出未完成，请稍后重试；本地数据未被修改。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    List<HomeworkItem> homework = const [];
    List<Course> courses = const [];
    final canReadLocalData =
        widget.canReadLocalData && Storage.localDataReadyForRecovery;
    var canShow = canReadLocalData;
    if (canShow) {
      try {
        homework = Storage.homework();
        courses = Storage.courses();
      } catch (_) {
        canShow = false;
      }
    }
    return MaterialApp(
      navigatorKey: _navigatorKey,
      home: Scaffold(
        appBar: AppBar(title: const Text('恢复访问')),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                widget.secureFailure ? '安全存储暂不可用' : '本地数据暂不可用',
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                canReadLocalData
                    ? widget.secureFailure
                          ? '登录状态暂时无法读取。本地数据可只读查看和导出，重试不会清除数据。'
                          : '启动暂未完成。本地数据可只读查看和导出，重试不会清除数据。'
                    : '本地数据尚未完成恢复，请重试。为保护数据，暂不进行修改或导出。',
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  FilledButton(
                    onPressed: _busy ? null : _retry,
                    child: const Text('重试'),
                  ),
                  if (canReadLocalData)
                    OutlinedButton(
                      onPressed: _busy ? null : _export,
                      child: const Text('导出本地备份'),
                    ),
                ],
              ),
              if (_message != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(_message!),
                ),
              if (canShow) ...[
                const SizedBox(height: 24),
                Text(
                  '本地作业 ${homework.length} 项 · 课程 ${courses.length} 门',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                for (final item in homework)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(item.title),
                    subtitle: Text(item.course),
                  ),
                for (final course in courses)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(course.name),
                    subtitle: Text(course.room),
                  ),
              ] else if (canReadLocalData) ...[
                const SizedBox(height: 16),
                const Text('部分本地记录暂时无法预览；可以尝试导出或重试。'),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
