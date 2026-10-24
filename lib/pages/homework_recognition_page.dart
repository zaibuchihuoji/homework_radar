import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import '../models/homework_draft.dart';
import '../services/homework_recognition.dart';
import '../services/image_text_reader.dart';
import '../ui/adaptive.dart';
import '../ui/tokens.dart';
import '../ui/settings_parts.dart';
import '../ui/capture_parts.dart';
import '../ui/theme_forms.dart';
import 'homework_recognition_review_page.dart';

class HomeworkRecognitionPage extends StatefulWidget {
  const HomeworkRecognitionPage({
    super.key,
    required this.state,
    this.chooseImageText,
  });
  final AppState state;
  final Future<String?> Function()? chooseImageText;
  @override
  State<HomeworkRecognitionPage> createState() =>
      _HomeworkRecognitionPageState();
}

class _HomeworkRecognitionPageState extends State<HomeworkRecognitionPage> {
  final _text = TextEditingController();
  DateTime? _noticeDate;
  bool _busy = false;
  bool _reviewing = false;
  bool _imageMode = false;
  String? _imagePath;
  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _message(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  Future<void> _image() async {
    if (_busy) return;
    setState(() => _busy = true);
    String? selectedPath;
    try {
      final text = widget.chooseImageText != null
          ? await widget.chooseImageText!()
          : await ImageTextReader.chooseAndRead(
              onImageSelected: (path) {
                selectedPath = path;
              },
            );
      if (!mounted || text == null) return;
      if (text.isEmpty) {
        _message('没有识别到文字，请换一张清晰截图，或粘贴文字');
        return;
      }
      setState(() {
        if (selectedPath != null) _imagePath = selectedPath;
        _text.text = text;
        _imageMode = selectedPath != null;
      });
    } on FormatException catch (e) {
      if (mounted) _message(e.message);
    } catch (_) {
      if (mounted) _message('截图识别失败，请重试或粘贴文字');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _recognize() async {
    if (_reviewing) return;
    final known = {
      ...widget.state.courses.map((c) => c.name),
      ...widget.state.homework.map((h) => h.course),
    }.where((c) => c.trim().isNotEmpty).toList();
    try {
      final drafts = HomeworkRecognition.parse(
        _text.text,
        knownCourses: known,
        referenceDate: _noticeDate,
      );
      if (drafts.isEmpty) {
        _message('请先选择截图或输入作业文字');
        return;
      }
      FocusScope.of(context).unfocus();
      setState(() => _reviewing = true);
      final result = await Navigator.of(context).push<HomeworkImportResult>(
        MaterialPageRoute(
          builder: (_) => HomeworkRecognitionReviewPage(
            state: widget.state,
            drafts: drafts,
            knownCourses: known,
          ),
        ),
      );
      if (!mounted || result == null) return;
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop(result);
      } else {
        _text.clear();
        _message(
          '已添加 ${result.count} 项${result.outputsDelayed ? '，提醒或小组件刷新稍有延迟，请勿重复添加' : ''}',
        );
      }
    } on FormatException catch (e) {
      if (mounted) _message(e.message);
    } finally {
      if (mounted) setState(() => _reviewing = false);
    }
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (!mounted) return;
    if (data?.text?.trim().isNotEmpty ?? false) {
      setState(() {
        _text.text = data!.text!;
        _imageMode = false;
      });
    } else {
      _message('剪贴板没有文字');
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = paletteOf(context);
    return SettingsScaffold(
      title: '识别添加',
      bottomNavigationBar: CaptureBottomBar(
        busy: _busy,
        label: _busy ? '正在本机读取截图…' : '核对后确认添加',
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : _image,
                    icon: const Icon(Icons.image_outlined, size: 20),
                    label: const Text('选择截图'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : _paste,
                    icon: const Icon(Icons.content_paste_outlined, size: 20),
                    label: const Text('粘贴文字'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: _busy || _reviewing ? null : _recognize,
              icon: Icon(
                Icons.arrow_forward_rounded,
                size: 22,
                color: p.sunny && !isDark(context) ? p.accentFill : null,
              ),
              label: const Text('识别并核对'),
            ),
          ],
        ),
      ),
      body: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(22, 8, 22, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  for (final image in [true, false])
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border(
                            bottom: BorderSide(
                              color: _imageMode == image
                                  ? p.accentFill
                                  : p.hairline,
                              width: _imageMode == image ? 3 : .5,
                            ),
                          ),
                        ),
                        child: TextButton(
                          onPressed: _busy
                              ? null
                              : () => setState(() => _imageMode = image),
                          child: Text(
                            image ? '截图' : '文字',
                            style: TextStyle(
                              fontSize: 14,
                              color: _imageMode == image ? p.ink : p.ink2,
                              fontWeight: _imageMode == image
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              if (_imageMode) ...[
                Container(
                  key: const ValueKey('recognition_image_preview'),
                  constraints: const BoxConstraints(
                    minHeight: 220,
                    maxHeight: 340,
                  ),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Color.alphaBlend(
                      p.ink.withValues(alpha: .04),
                      p.card,
                    ),
                    borderRadius: BorderRadius.circular(p.clean ? 12 : 2),
                  ),
                  child: _imagePath == null
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.image_search_outlined,
                                size: 40,
                                color: p.ink2,
                              ),
                              const SizedBox(height: 12),
                              const Text('尚未选择截图'),
                              const SizedBox(height: 6),
                              const SettingsNote('选择一张清晰的作业通知'),
                            ],
                          ),
                        )
                      : Image.file(
                          File(_imagePath!),
                          fit: BoxFit.contain,
                          semanticLabel: '所选作业通知截图',
                          errorBuilder: (_, _, _) =>
                              const Center(child: Text('截图预览不可用，可切换文字查看读取结果')),
                        ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _imagePath == null ? '截图文字在本机识别' : '所选截图 · 本机识别',
                        style: TextStyle(fontSize: 12, color: p.ink2),
                      ),
                    ),
                    if (_imagePath != null)
                      TextButton(
                        onPressed: _busy ? null : _image,
                        child: const Text('更换'),
                      ),
                  ],
                ),
                if (_text.text.isNotEmpty)
                  TextButton.icon(
                    onPressed: _busy
                        ? null
                        : () => setState(() => _imageMode = false),
                    icon: const Icon(Icons.edit_note_outlined, size: 18),
                    label: const Text('查看或修改读取文字'),
                  ),
              ] else
                TextField(
                  key: const ValueKey('recognition_input'),
                  controller: _text,
                  enabled: !_busy,
                  minLines: 7,
                  maxLines: 14,
                  maxLength: 20000,
                  style: TextStyle(fontSize: 14, height: 1.65, color: p.ink),
                  decoration: themedInputDecoration(
                    context,
                    hintText: '粘贴老师通知，或直接输入：\n\n【大学英语】阅读第五单元\n【数学】完成第三章练习',
                  ).copyWith(hintMaxLines: 8),
                ),
              const SizedBox(height: 16),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: const EdgeInsets.only(bottom: 12),
                leading: const Icon(Icons.calendar_today_outlined, size: 21),
                title: const Text('通知日期'),
                subtitle: Text(
                  _noticeDate == null
                      ? '未设置 · 相对日期留待确认'
                      : '${_noticeDate!.year}年${_noticeDate!.month}月${_noticeDate!.day}日',
                ),
                children: [
                  Wrap(
                    spacing: 8,
                    children: [
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () => setState(
                                () => _noticeDate = DateUtils.dateOnly(
                                  DateTime.now(),
                                ),
                              ),
                        child: const Text('使用今天'),
                      ),
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () async {
                                final date = await showDatePicker(
                                  context: context,
                                  initialDate: _noticeDate ?? DateTime.now(),
                                  firstDate: DateTime(2000),
                                  lastDate: DateTime(2100, 12, 31),
                                );
                                if (mounted && date != null) {
                                  setState(() => _noticeDate = date);
                                }
                              },
                        child: const Text('选择日期'),
                      ),
                      if (_noticeDate != null)
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => setState(() => _noticeDate = null),
                          child: const Text('清除'),
                        ),
                    ],
                  ),
                  const SettingsNote(
                    '用于理解“明天”“本周五”和缺少年份的日期。未设置时不推测；缺少具体时间也会留待确认。',
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
