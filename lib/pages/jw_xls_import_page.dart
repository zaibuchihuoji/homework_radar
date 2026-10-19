/// Excel 文件导入：选 .xlsx/.xls/CSV 课表文件 → 解析 → 预览入库。
/// 适合教务能导出表格文件的情况（老系统常见）。
library;

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models/course.dart';
import '../services/timetable_xls_parser.dart';
import 'jw_preview_page.dart';
import 'timetable_import_confirmation.dart';

class JwXlsImportPage extends StatefulWidget {
  const JwXlsImportPage({super.key, required this.state});

  final AppState state;

  @override
  State<JwXlsImportPage> createState() => _JwXlsImportPageState();
}

class _JwXlsImportPageState extends State<JwXlsImportPage> {
  bool _busy = false;
  String _status = '';

  Future<void> _pickAndRun() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _status = '正在选择文件…';
    });
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls', 'csv'],
      );
      if (!mounted) return;
      final file = files.isEmpty ? null : files.first;
      if (file == null || file.path == null) {
        setState(() {
          _busy = false;
          _status = '';
        });
        return;
      }
      setState(() => _status = '正在解析 ${file.name} …');
      final List<Course> courses;
      try {
        // 读文件与解码都放进后台 isolate，大文件不冻结 UI
        final bytes = await File(file.path!).readAsBytes();
        courses = await compute(TimetableXlsParser.parse, bytes);
      } on FormatException catch (e) {
        if (!mounted) return;
        setState(() {
          _busy = false;
          _status = e.message;
        });
        return;
      }
      if (!mounted) return;
      if (courses.isEmpty) {
        setState(() {
          _busy = false;
          _status = '文件里没认出课程。需要含「星期一~星期日」表头的二维表；'
              '先在教务里切到「二维表」视图再导出。';
        });
        return;
      }
      final selected = await Navigator.of(context).push<List<Course>>(
        MaterialPageRoute(
          builder: (_) =>
              JwPreviewPage(courses: courses, sourceLabel: 'Excel导入'),
        ),
      );
      if (!mounted) return;
      if (selected == null || selected.isEmpty) {
        // 预览页取消：重置状态行，别永远停在「正在解析 …」
        setState(() {
          _busy = false;
          _status = '';
        });
        return;
      }
      final replace = await confirmTimetableImport(
        context,
        selected: selected,
        existing: widget.state.courses,
        requiresReplacement: widget.state.timetableRequiresReplacement(),
        replacementPreview: widget.state.timetableReplacement(selected),
        sourceLabel: 'Excel导入',
      );
      if (!mounted) return;
      if (replace == null) {
        setState(() {
          _busy = false;
          _status = '';
        });
        return;
      }
      try {
        await widget.state.onTimetableCaptured(
          courses: selected,
          rawPage: '',
          // 只有明确选择并确认删除影响，才替换未包含的旧课。
          fullImport: replace,
          source: 'Excel导入',
        );
      } catch (e) {
        // 保存阶段的异常此前被外层 catch 报成「解析失败」误导用户换文件
        if (!mounted) return;
        setState(() {
          _busy = false;
          _status = '保存失败：$e（解析结果没丢，可重试保存）';
        });
        return;
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _status = '解析失败：请确认是 .xlsx / .csv 课表表格'
              '（老版二进制 .xls 请先在 Excel/WPS 里另存为 .xlsx）。';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Excel 导入')),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '适合教务能导出课表文件的情况：\n\n'
              '① 在教务里把课表切到「二维表」，导出/下载表格文件；\n'
              '② 回到这里选文件，解析后确认导入。\n\n'
              '支持 .xlsx / .xls / .csv；要求表格里有'
              '「星期一 ~ 星期日」表头。\n'
              '老版二进制 .xls 请先另存为 .xlsx。',
              style: TextStyle(
                fontSize: 13,
                height: 1.8,
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _busy ? null : _pickAndRun,
              icon: _busy
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.table_view_rounded),
              label: Text(_busy ? '处理中…' : '选择课表文件'),
            ),
            if (_status.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                _status,
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.6,
                  color: Colors.grey.shade700,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
