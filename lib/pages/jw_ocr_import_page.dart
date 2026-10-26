/// 截图导入：选一张课表截图 → 小字先放大 → ML Kit 中文 OCR → 按表格布局重建 → 预览入库。
/// 模型随 App 打包（离线识别），不需要外部服务。
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';

import '../app_state.dart';
import '../ui/focus_parts.dart';
import '../ui/adaptive.dart';
import '../ui/theme_forms.dart';
import '../models/course.dart';
import '../services/timetable_ocr.dart';
import 'jw_preview_page.dart';
import 'timetable_import_confirmation.dart';

class JwOcrImportPage extends StatefulWidget {
  const JwOcrImportPage({super.key, required this.state});

  final AppState state;

  @override
  State<JwOcrImportPage> createState() => _JwOcrImportPageState();
}

class _JwOcrImportPageState extends State<JwOcrImportPage> {
  bool _busy = false;
  String _status = '';
  List<OcrBlock>? _blocks;
  List<Course>? _courses;
  Set<int>? _selectedRows;
  List<Course>? _pendingSelection;
  String? _sourceImage;
  bool _saveFailed = false;
  OcrSectionMode _sectionMode = OcrSectionMode.auto;

  /// 课表格里字很小（手机截图 20px 上下），放大后再识别明显更准：
  /// 短边 <2000 的图放大到短边 2000（最长边不超过 4000）。
  /// 长边 >4000 的大图等比缩小到 4000——保证任何输入最长边 ≤4000，
  /// 此前 short≥2000 的相机照片原样直通 ML Kit，识别慢且内存峰值高。
  /// 读宽高走 ImageDescriptor 只解头部元数据：此前 instantiateImageCodec
  /// 无 target 会把首帧全尺寸解码出来（48MP 照片 RGBA 峰值 ~183MB），
  /// 只为拿两个 int。任一步失败退回原图。
  Future<String> _prepareImage(String path) async {
    ui.ImmutableBuffer? buffer;
    ui.ImageDescriptor? descriptor;
    ui.Codec? codec;
    try {
      final bytes = await File(path).readAsBytes();
      buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      final w = descriptor.width;
      final h = descriptor.height;
      final short = w < h ? w : h;
      final long = w < h ? h : w;
      double scale;
      if (short < 2000) {
        var s = 2000 / short;
        if (long * s > 4000) s = 4000 / long;
        if (s <= 1.05 && long <= 4000) return path;
        scale = s;
      } else if (long > 4000) {
        scale = 4000 / long;
      } else {
        return path;
      }
      codec = await descriptor.instantiateCodec(
        targetWidth: (w * scale).round(),
        targetHeight: (h * scale).round(),
      );
      final f = await codec.getNextFrame();
      final data = await f.image.toByteData(format: ui.ImageByteFormat.png);
      f.image.dispose();
      if (data == null) return path;
      final out = File(
        '${Directory.systemTemp.path}/ocr_scale_${DateTime.now().millisecondsSinceEpoch}.png',
      );
      await out.writeAsBytes(data.buffer.asUint8List());
      return out.path;
    } catch (_) {
      return path;
    } finally {
      // 描述器/缓冲/编解码器及时释放，大图反复导入不积内存
      codec?.dispose();
      descriptor?.dispose();
      buffer?.dispose();
    }
  }

  Future<void> _pickAndRun() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _status = '正在选择截图…';
    });
    // 只包「选图 + 识别」这一段：保存入库阶段的异常也报「识别失败请换
    // 截图」会误导用户重拍（数据其实已经入库一半）
    final RecognizedText result;
    final String prepared;
    late final String originalPath;
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 95,
      );
      if (!mounted) return;
      if (picked == null) {
        setState(() {
          _busy = false;
          _status = '';
        });
        return;
      }
      originalPath = picked.path;
      setState(() => _status = '正在识别截图文字…');
      prepared = await _prepareImage(picked.path);
      final input = InputImage.fromFilePath(prepared);
      final recognizer = TextRecognizer(script: TextRecognitionScript.chinese);
      try {
        result = await recognizer.processImage(input);
      } finally {
        // 识别失败也要释放原生检测器、删掉放大的临时 PNG，
        // 避免反复导入累积泄漏 temp 目录
        await recognizer.close();
        if (prepared != picked.path) {
          try {
            File(prepared).deleteSync();
          } catch (_) {}
        }
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _status =
            '识别失败：请换一张文字更清晰的整屏课表截图再试'
            '（含「星期一~星期日」表头），或改用文本导入。';
      });
      return;
    }

    if (!mounted) return;
    setState(() => _status = '正在按表格重建课表…');
    // 元素级：一行可能横跨两列（相邻格子同行文字被 ML Kit 连成一行），
    // 元素框才能按列正确归位；解析器内按列+行带重组。
    // 表格边框竖线是 OCR 常见噪声，会把教师字段顶掉、课名带脏字符
    final blocks = <OcrBlock>[
      for (final b in result.blocks)
        for (final line in b.lines)
          for (final e in line.elements)
            OcrBlock(
              text: e.text.trim().replaceAll('|', ''),
              left: e.boundingBox.left.toDouble(),
              top: e.boundingBox.top.toDouble(),
              width: e.boundingBox.width.toDouble(),
              height: e.boundingBox.height.toDouble(),
            ),
    ];
    final courses = TimetableOcrParser.parse(blocks, sectionMode: _sectionMode);
    if (!mounted) return;
    if (courses.isEmpty) {
      setState(() {
        _busy = false;
        _status =
            '没认出课程。请用整屏课表截图（含「星期一~星期日」表头），'
            '字越大越清晰越好；或改用文本导入。';
      });
      return;
    }
    setState(() {
      _blocks = blocks;
      _courses = courses;
      _sourceImage = originalPath;
      _selectedRows = null;
      _pendingSelection = null;
      _saveFailed = false;
      _busy = false;
      _status = '';
    });
    await _review();
  }

  Future<void> _review() async {
    if (_busy || _courses == null) return;
    setState(() {
      _busy = true;
      _saveFailed = false;
      _pendingSelection = null;
    });
    final selected = await Navigator.of(context).push<List<Course>>(
      MaterialPageRoute(
        builder: (_) => JwPreviewPage(
          courses: _courses!,
          sourceLabel: '截图导入',
          sourceImagePath: _sourceImage,
          selectedRows: _selectedRows,
          onDraftChanged: (courses, rows) {
            _courses = courses;
            _selectedRows = rows;
          },
        ),
      ),
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (selected == null || selected.isEmpty) {
      // 用户在预览页取消：只重置 _busy 的话状态行永远停在「正在按表格重建课表…」
      setState(() {
        _busy = false;
        _status = '';
      });
      return;
    }
    _pendingSelection = selected;
    await _confirmAndSave();
  }

  Future<void> _confirmAndSave() async {
    final selected = _pendingSelection;
    if (_busy || selected == null || selected.isEmpty) return;
    setState(() => _busy = true);
    final replace = await confirmTimetableImport(
      context,
      selected: selected,
      existing: widget.state.courses,
      requiresReplacement: widget.state.timetableRequiresReplacement(),
      replacementPreview: widget.state.timetableReplacement(selected),
      sourceLabel: '截图导入',
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
        source: '截图导入',
        // OCR可能缺列/缺字；默认合并，整表替换必须明确确认。
        fullImport: replace,
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _saveFailed = true;
        _status = '保存未完成，已保留本次核对结果。可重试保存或继续核对，无需重新识别。';
      });
      return;
    }
    if (mounted) Navigator.of(context).pop(true);
  }

  Future<void> _changeSectionMode(OcrSectionMode mode) async {
    if (_busy || mode == _sectionMode) return;
    if (_courses?.any((c) => c.edited) == true) {
      final reset = await showDialog<bool>(
        context: context,
        builder: (context) => ThemedAlertDialog(
          title: const Text('重新整理节次？'),
          content: const Text('这会重置本次识别结果中的人工修改。已保存的旧课表不会改变。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('重新整理'),
            ),
          ],
        ),
      );
      if (!mounted || reset != true) return;
    }
    setState(() {
      _sectionMode = mode;
      if (_blocks != null) {
        _courses = TimetableOcrParser.parse(_blocks!, sectionMode: mode);
      }
      _selectedRows = null;
      _pendingSelection = null;
      _saveFailed = false;
      _status = _blocks == null ? '' : '已重新整理，请核对课程与节次。';
    });
  }

  @override
  Widget build(BuildContext context) {
    final guide = Text(
      '教务网页无法读取时，可以使用清晰课表截图导入：\n\n'
      '① 在教务里打开课表页面，整屏截图；\n'
      '② 回到这里选截图，离线识别后确认导入。\n\n'
      '尽量保留完整的星期表头和左侧节次。支持「星期一」「周一」等表头。\n'
      '标尺不明确时不会自动填写节次，请核对后选择逐节编号或两节一组。',
      style: TextStyle(
        fontSize: 13,
        height: 1.8,
        color: textSecondary(context),
      ),
    );
    return Scaffold(
      backgroundColor: scaffoldBgOf(context),
      appBar: AppBar(title: const Text('截图导入')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        children: [
          ...[
            const FocusSummary(
              eyebrow: '截图导入',
              title: '从截图读取课程',
              detail: '选择清晰课表，离线识别后逐条核对。',
            ),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('使用说明'),
              children: [guide],
            ),
          ],
          const SizedBox(height: 20),
          InputDecorator(
            decoration: const InputDecoration(
              labelText: '节次标尺',
              border: OutlineInputBorder(),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<OcrSectionMode>(
                value: _sectionMode,
                isExpanded: true,
                onChanged: _busy
                    ? null
                    : (value) {
                        if (value != null) _changeSectionMode(value);
                      },
                items: const [
                  DropdownMenuItem(
                    value: OcrSectionMode.auto,
                    child: Text('自动核对'),
                  ),
                  DropdownMenuItem(
                    value: OcrSectionMode.single,
                    child: Text('逐节编号：1、2、3…'),
                  ),
                  DropdownMenuItem(
                    value: OcrSectionMode.paired,
                    child: Text('两节一组：1 代表第 1–2 节'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _busy ? null : () => _pickAndRun(),
            icon: _busy
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.photo_outlined),
            label: Text(_busy ? '处理中…' : '选择课表截图'),
          ),
          if (_courses != null) ...[
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _busy ? null : _review,
              icon: const Icon(Icons.fact_check_outlined),
              label: const Text('继续核对识别结果'),
            ),
          ],
          if (_saveFailed && _pendingSelection != null) ...[
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: _busy ? null : _confirmAndSave,
              icon: const Icon(Icons.save_outlined),
              label: const Text('重试保存'),
            ),
          ],
          if (_status.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              _status,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.6,
                color: textSecondary(context),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
