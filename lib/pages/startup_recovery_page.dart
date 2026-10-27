import 'dart:convert';
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
      final bytes = Uint8List.fromList(utf8.encode(BackupService.encode()));
      final path = await FilePicker.saveFile(
        fileName: 'homework_radar_recovery.json',
        bytes: bytes,
        mimeType: 'application/json',
      );
      if (mounted) {
        setState(() => _message = path == null ? '已取消导出' : '本地备份已导出');
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
