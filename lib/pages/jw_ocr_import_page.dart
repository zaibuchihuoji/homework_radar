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
import '../ui/tokens.dart';
import '../ui/adaptive.dart';
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
        if (s <= 1.05) return path; // 差一点点到 2000，不值得重编一次码
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
    final courses = TimetableOcrParser.parse(blocks);
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
    final selected = await Navigator.of(context).push<List<Course>>(
      MaterialPageRoute(
        builder: (_) => JwPreviewPage(courses: courses, sourceLabel: '截图导入'),
      ),
    );
    if (!mounted) return;
    if (selected == null || selected.isEmpty) {
      // 用户在预览页取消：只重置 _busy 的话状态行永远停在「正在按表格重建课表…」
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
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _status = '保存失败：$e（解析结果没丢，可重试保存）';
      });
      return;
    }
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final guide = Text(
      '教务网页无法读取时，可以使用清晰课表截图导入：\n\n'
      '① 在教务里打开课表页面，整屏截图；\n'
      '② 回到这里选截图，离线识别后确认导入。\n\n'
      '要求：截图里有完整的「星期一 ~ 星期日」表头，文字清晰不缩放。',
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
          if (paletteOf(context).sunny) ...[
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
          ] else
            guide,
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _busy ? null : _pickAndRun,
            icon: _busy
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.photo_outlined),
            label: Text(_busy ? '处理中…' : '选择课表截图'),
          ),
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
