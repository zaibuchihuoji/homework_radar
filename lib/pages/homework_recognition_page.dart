import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import '../models/homework_draft.dart';
import '../services/homework_recognition.dart';
import '../services/image_text_reader.dart';
import '../ui/adaptive.dart';
import '../ui/style_background.dart';
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
    try {
      final text =
          await (widget.chooseImageText ?? ImageTextReader.chooseAndRead)();
      if (!mounted || text == null) return;
      if (text.isEmpty) {
        _message('没有识别到文字，请换一张清晰截图，或粘贴文字');
        return;
      }
      _text.text = text;
      await _recognize();
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

  @override
  Widget build(BuildContext context) => StyleBackground(
    child: Scaffold(
      backgroundColor: scaffoldBgOf(context),
      appBar: AppBar(title: const Text('识别添加')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const ThemeEditorHeading(
                title: '把通知变成作业',
                kicker: 'CAPTURE / REVIEW',
                icon: Icons.document_scanner_outlined,
                summary: '截图在本机识别。逐条核对、勾选，确认后才保存。',
              ),
              const SizedBox(height: 20),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _image,
                    icon: const Icon(Icons.image_outlined),
                    label: const Text('选择截图'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _busy
                        ? null
                        : () async {
                            final data = await Clipboard.getData(
                              Clipboard.kTextPlain,
                            );
                            if (!mounted) return;
                            if (data?.text?.trim().isNotEmpty ?? false) {
                              _text.text = data!.text!;
                            } else {
                              _message('剪贴板没有文字');
                            }
                          },
                    icon: const Icon(Icons.content_paste),
                    label: const Text('粘贴文字'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('recognition_input'),
                controller: _text,
                enabled: !_busy,
                minLines: 5,
                maxLines: 12,
                maxLength: 20000,
                decoration: themedInputDecoration(
                  context,
                  labelText: '作业通知',
                  hintText:
                      '例如：\n1. 【大学英语】阅读第四单元，截止2026-10-23 20:00\n2. 【数学】完成第三章练习',
                ),
              ),
              ThemeFieldGroup(
                title: '通知日期（可选）',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _noticeDate == null
                          ? '未设置'
                          : '${_noticeDate!.year}年${_noticeDate!.month}月${_noticeDate!.day}日',
                    ),
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
                    const Text('用于理解“明天”“本周五”和缺少年份的日期。未设置时不推测；缺少具体时间也会留待确认。'),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              if (_busy) const LinearProgressIndicator(),
              FilledButton.icon(
                onPressed: _busy || _reviewing ? null : _recognize,
                icon: const Icon(Icons.auto_awesome_outlined),
                label: const Text('识别作业'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
