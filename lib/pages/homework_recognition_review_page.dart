import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models/homework.dart';
import '../models/homework_draft.dart';
import '../services/homework_duplicates.dart';
import '../services/storage.dart';
import '../services/recognition_draft_store.dart';
import '../ui/adaptive.dart';
import '../ui/settings_parts.dart';
import '../ui/capture_parts.dart';
import '../ui/theme_forms.dart';

class HomeworkRecognitionReviewPage extends StatefulWidget {
  const HomeworkRecognitionReviewPage({
    super.key,
    required this.state,
    required this.drafts,
    required this.knownCourses,
    this.session,
    this.onDraftChanged,
  });
  final AppState state;
  final List<HomeworkDraft> drafts;
  final List<String> knownCourses;
  final RecognitionSession? session;
  final VoidCallback? onDraftChanged;
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
    for (var i = 0; i < _rows.length; i++) {
      final row = _rows[i];
      final saved = widget.session?.rows;
      if (saved != null && i < saved.length) {
        row.course.text = saved[i].course;
        row.title.text = saved[i].title;
        row.due = saved[i].dueAt;
        row.selected = saved[i].selected;
      } else {
        row.selected = row.draft.likelyHomework && !_duplicate(row);
      }
      row.course.addListener(_remember);
      row.title.addListener(_remember);
    }
    _remember();
    widget.state.addListener(_refresh);
  }

  void _remember() {
    widget.session?.rows = [
      for (final row in _rows)
        RecognitionReviewRow(
          source: row.draft,
          course: row.course.text,
          title: row.title.text,
          dueAt: row.due,
          selected: row.selected,
        ),
    ];
    widget.onDraftChanged?.call();
  }

  void _refresh() {
    if (mounted) {
      setState(() => _existing = Storage.homeworkForDuplicateCheck());
    }
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
    _remember();
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
        builder: (context) => SettingsAlertDialog(
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
    child: SettingsScaffold(
      title: '核对识别结果',
      bottomNavigationBar: CaptureBottomBar(
        label:
            '已选 ${_rows.where((r) => r.selected).length} / ${_rows.length} 项 · 最终确认后保存',
        child: FilledButton(
          key: const ValueKey('review_save'),
          onPressed: _saving || !_rows.any((r) => r.selected) ? null : _save,
          child: Text(
            _saving
                ? '请稍候…'
                : '检查并添加（${_rows.where((r) => r.selected).length}）',
          ),
        ),
      ),
      body: AbsorbPointer(
        absorbing: _saving,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              CaptureHeading(
                step: '02 / 核对内容',
                title: '只添加你选中的',
                description:
                    '识别到 ${_rows.length} 项。课程、标题和截止时间均可修改；不明确的内容请补充确认。',
              ),
              for (var i = 0; i < _rows.length; i++) _card(_rows[i], i),
            ],
          ),
        ),
      ),
    ),
  );
  Widget _card(_Row row, int index) => SettingsSection(
    children: [
      Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Checkbox(
                  key: ValueKey('select_$index'),
                  value: row.selected,
                  onChanged: (v) {
                    setState(() => row.selected = v ?? false);
                    _remember();
                  },
                ),
                Expanded(
                  child: Text(
                    '作业 ${index + 1}',
                    style: serifTitle(
                      context,
                      monoText(
                        context,
                        TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                          color: textPrimary(context),
                        ),
                      ),
                    ),
                  ),
                ),
                Text(
                  row.selected ? '已选' : '未选',
                  style: TextStyle(fontSize: 12, color: textSecondary(context)),
                ),
              ],
            ),
            if (_duplicate(row))
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  '疑似重复：已有同名作业或与本次勾选项相同，请核对',
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.6,
                    color: Theme.of(context).colorScheme.error,
                  ),
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
                    onPressed: () {
                      setState(() => row.due = null);
                      _remember();
                    },
                    child: const Text('清除时间'),
                  ),
              ],
            ),
            if (row.course.text.trim().isEmpty) const SettingsNote('所属课程待确认'),
            if (row.due == null)
              ...row.draft.warnings
                  .where((w) => !w.contains('所属课程') && !w.contains('未检测到'))
                  .map((w) => SettingsNote(w)),
            if (!row.draft.likelyHomework)
              const SettingsNote('未检测到明确作业描述，请核对后再勾选'),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('查看原文'),
              children: [SelectableText(row.draft.sourceText)],
            ),
          ],
        ),
      ),
    ],
  );
  String _format(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}
