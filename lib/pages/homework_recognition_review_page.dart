import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models/homework.dart';
import '../models/homework_draft.dart';
import '../services/homework_duplicates.dart';
import '../services/storage.dart';
import '../ui/adaptive.dart';
import '../ui/style_background.dart';
import '../ui/theme_forms.dart';

class HomeworkRecognitionReviewPage extends StatefulWidget {
  const HomeworkRecognitionReviewPage({
    super.key,
    required this.state,
    required this.drafts,
    required this.knownCourses,
  });
  final AppState state;
  final List<HomeworkDraft> drafts;
  final List<String> knownCourses;
  @override
  State<HomeworkRecognitionReviewPage> createState() =>
      _HomeworkRecognitionReviewPageState();
}

class _Row {
  _Row(this.draft)
    : course = TextEditingController(text: draft.course),
      title = TextEditingController(text: draft.title),
      due = draft.dueAt;
  final HomeworkDraft draft;
  final TextEditingController course, title;
  DateTime? due;
  bool selected = false;
}

class _HomeworkRecognitionReviewPageState
    extends State<HomeworkRecognitionReviewPage> {
  late final List<_Row> _rows;
  List<HomeworkItem> _existing = [];
  bool _saving = false;
  @override
  void initState() {
    super.initState();
    _existing = Storage.homeworkForDuplicateCheck();
    _rows = widget.drafts.map(_Row.new).toList();
    for (final row in _rows) {
      row.selected = row.draft.likelyHomework && !_duplicate(row);
    }
    widget.state.addListener(_refresh);
  }

  void _refresh() {
    if (mounted) setState(() => _existing = Storage.homeworkForDuplicateCheck());
  }

  @override
  void dispose() {
    widget.state.removeListener(_refresh);
    for (final row in _rows) {
      row.course.dispose();
      row.title.dispose();
    }
    super.dispose();
  }

  bool _duplicate(_Row row) =>
      _existing.any(
        (h) => HomeworkDuplicates.matches(row.course.text, row.title.text, h),
      ) ||
      _rows.any(
        (other) =>
            other != row &&
            other.selected &&
            HomeworkDuplicates.same(
              row.course.text,
              row.title.text,
              other.course.text,
              other.title.text,
            ),
      );
  void _message(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  Future<void> _date(_Row row) async {
    final initial = row.due ?? DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(initial.year < 2000 ? initial.year : 2000),
      lastDate: DateTime(initial.year > 2100 ? initial.year : 2100, 12, 31),
    );
    if (!mounted || date == null) return;
    final time = await showTimePicker(
      context: context,
      initialTime: row.due == null
          ? TimeOfDay.now()
          : TimeOfDay.fromDateTime(row.due!),
    );
    if (!mounted || time == null) return;
    setState(
      () => row.due = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      ),
    );
  }

  Future<void> _save() async {
    if (_saving) return;
    final selected = _rows.where((r) => r.selected).toList();
    if (selected.isEmpty) return;
    if (selected.any((r) => r.title.text.trim().isEmpty)) {
      _message('请补全已勾选作业的标题');
      return;
    }
    _existing = Storage.homeworkForDuplicateCheck();
    // Freeze exactly the values and duplicate warnings shown in confirmation.
    final entries = selected
        .map(
          (r) => ManualHomeworkEntry(
            course: r.course.text,
            title: r.title.text,
            dueAt: r.due,
            note: '识别原文：\n${r.draft.sourceText}',
            duplicateApproved: _duplicate(r),
          ),
        )
        .toList();
    final duplicates = entries.where((e) => e.duplicateApproved).length;
    setState(() => _saving = true);
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => ThemedAlertDialog(
          title: const Text('确认添加作业'),
          scrollable: true,
          content: Text(
            '将新增 ${entries.length} 项作业。\n${entries.any((e) => e.course.trim().isEmpty) ? '\n有作业尚未填写课程。\n' : ''}${entries.any((e) => e.dueAt == null) ? '\n有作业未确认截止时间，暂不安排截止提醒。\n' : ''}${duplicates > 0 ? '\n其中 $duplicates 项疑似重复，仍会新增，请确认是否需要。\n' : ''}\n原有作业不会合并或覆盖。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('返回核对'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text('确认添加 ${entries.length} 项'),
            ),
          ],
        ),
      );
      if (!mounted || confirmed != true) return;
      final result = await widget.state.addRecognizedHomework(entries);
      if (mounted) Navigator.pop(context, result);
    } on HomeworkImportDuplicateException {
      if (mounted) {
        _refresh();
        _message('保存前发现新的疑似重复作业，请核对后重新确认');
      }
    } catch (_) {
      if (mounted) _message('添加未完成，原有数据已保留。请核对后重试');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: StyleBackground(
      child: Scaffold(
        backgroundColor: scaffoldBgOf(context),
        appBar: AppBar(title: const Text('核对识别结果')),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: FilledButton(
              key: const ValueKey('review_save'),
              onPressed: _saving || !_rows.any((r) => r.selected)
                  ? null
                  : _save,
              child: Text(
                _saving
                    ? '请稍候…'
                    : '检查并添加（${_rows.where((r) => r.selected).length}）',
              ),
            ),
          ),
        ),
        body: AbsorbPointer(
          absorbing: _saving,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const ThemeEditorHeading(
                  title: '只添加你选中的',
                  kicker: 'REVIEW / SELECT',
                  icon: Icons.checklist,
                  summary: '不明确的内容已留待确认。标题、课程和截止时间均可修改；点最终确认前不会保存。',
                ),
                const SizedBox(height: 12),
                for (var i = 0; i < _rows.length; i++) _card(_rows[i], i),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  Widget _card(_Row row, int index) => Card(
    color: cardColor(context),
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Checkbox(
                key: ValueKey('select_$index'),
                value: row.selected,
                onChanged: (v) => setState(() => row.selected = v ?? false),
              ),
              Expanded(
                child: Text(
                  '第 ${index + 1} 项',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          if (_duplicate(row))
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                '疑似重复：已有同名作业或与本次勾选项相同，请核对',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          TextField(
            key: ValueKey('course_$index'),
            controller: row.course,
            onChanged: (_) => setState(() {}),
            decoration: themedInputDecoration(
              context,
              labelText: '课程（可修改）',
              suffixIcon: widget.knownCourses.isEmpty
                  ? null
                  : PopupMenuButton<String>(
                      tooltip: '选择已有课程',
                      icon: const Icon(Icons.arrow_drop_down),
                      onSelected: (course) =>
                          setState(() => row.course.text = course),
                      itemBuilder: (_) => widget.knownCourses
                          .map((c) => PopupMenuItem(value: c, child: Text(c)))
                          .toList(),
                    ),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            key: ValueKey('title_$index'),
            controller: row.title,
            minLines: 1,
            maxLines: 5,
            onChanged: (_) => setState(() {}),
            decoration: themedInputDecoration(context, labelText: '作业标题'),
          ),
          const SizedBox(height: 14),
          Text(
            row.due == null ? '截止时间待确认' : '截止 ${_format(row.due!)}',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          Wrap(
            spacing: 8,
            children: [
              TextButton.icon(
                onPressed: () => _date(row),
                icon: const Icon(Icons.schedule),
                label: Text(row.due == null ? '设置截止时间' : '修改截止时间'),
              ),
              if (row.due != null)
                TextButton(
                  onPressed: () => setState(() => row.due = null),
                  child: const Text('清除时间'),
                ),
            ],
          ),
          if (row.course.text.trim().isEmpty) const Text('所属课程待确认'),
          if (row.due == null)
            ...row.draft.warnings
                .where((w) => !w.contains('所属课程') && !w.contains('未检测到'))
                .map((w) => Text(w)),
          if (!row.draft.likelyHomework) const Text('未检测到明确作业描述，请核对后再勾选'),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text('查看原文'),
            children: [SelectableText(row.draft.sourceText)],
          ),
        ],
      ),
    ),
  );
  String _format(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}
