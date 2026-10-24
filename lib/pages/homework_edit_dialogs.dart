import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models/homework.dart';
import '../ui/adaptive.dart';
import '../ui/tokens.dart';
import '../ui/theme_forms.dart';

// Shared by list and detail; persistence stays with the existing AppState methods.
void showHomeworkNoteEditor(
  BuildContext context,
  AppState state,
  HomeworkItem hw,
) {
  final ctrl = TextEditingController(text: hw.note ?? '');
  showDialog<void>(
    context: context,
    builder: (dialogContext) => ThemedAlertDialog(
      backgroundColor: cardColor(context),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: const ThemeEditorHeading(
        title: '备注',
        kicker: 'NOTE / 备忘',
        icon: Icons.sticky_note_2_outlined,
      ),
      scrollable: true,
      content: TextField(
        controller: ctrl,
        autofocus: true,
        maxLines: 3,
        style: TextStyle(fontSize: 14, color: textPrimary(context)),
        decoration:
            (!isCleanStyle(dialogContext) || paletteOf(dialogContext).sunny)
            ? themedInputDecoration(dialogContext, hintText: '例如：需要交纸质版 / 小组作业')
            : InputDecoration(
                hintText: '例如：需要交纸质版 / 小组作业',
                hintStyle: TextStyle(fontSize: 13, color: textFaint(context)),
                filled: true,
                fillColor: bgColor(context),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () {
            state.updateNote(hw.id, ctrl.text.trim());
            Navigator.of(dialogContext).pop();
          },
          child: const Text('保存'),
        ),
      ],
    ),
  ).whenComplete(() {
    // 等退场动画走完再释放：立即 dispose 会炸 _dependents 断言
    Future<void>.delayed(const Duration(milliseconds: 500), ctrl.dispose);
  });
}

void showManualHomeworkEditor(
  BuildContext context,
  AppState state, {
  HomeworkItem? edit,
}) {
  final courseCtrl = TextEditingController(text: edit?.course ?? '');
  final titleCtrl = TextEditingController(text: edit?.title ?? '');
  final noteCtrl = TextEditingController(text: edit?.note ?? '');
  DateTime? due = edit?.dueAt;
  final existingCourses = state.homework
      .map((h) => h.course.trim())
      .where((c) => c.isNotEmpty)
      .toSet()
      .toList();

  showDialog<void>(
    context: context,
    builder: (sheetContext) => StatefulBuilder(
      builder: (sheetContext, setSheet) => ThemedDialog(
        backgroundColor: cardColor(sheetContext),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420, maxHeight: 660),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: ThemeEditorHeading(
                              title: edit == null ? '添加作业' : '编辑作业',
                              kicker: 'HOMEWORK / 自定义',
                              icon: Icons.edit_note_rounded,
                            ),
                          ),
                          IconButton(
                            tooltip: '取消',
                            onPressed: () => Navigator.of(sheetContext).pop(),
                            icon: const Icon(Icons.close_rounded, size: 20),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      ThemeFieldGroup(
                        title: '所属课程',
                        index: 1,
                        child: TextField(
                          controller: courseCtrl,
                          style: TextStyle(
                            fontSize: 14.5,
                            color: textPrimary(sheetContext),
                          ),
                          decoration: _homeworkInput(sheetContext, '课程名称'),
                        ),
                      ),
                      if (existingCourses.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: existingCourses
                              .take(6)
                              .map(
                                (c) => GestureDetector(
                                  onTap: () =>
                                      setSheet(() => courseCtrl.text = c),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 5,
                                    ),
                                    decoration: BoxDecoration(
                                      color: accentColor(sheetContext)
                                          .withValues(alpha: 0.08),
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                    child: Text(
                                      c,
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        color: accentColor(sheetContext),
                                      ),
                                    ),
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                      ],
                      const SizedBox(height: 12),
                      ThemeFieldGroup(
                        title: '作业内容',
                        index: 2,
                        child: TextField(
                          controller: titleCtrl,
                          style: TextStyle(
                            fontSize: 14.5,
                            color: textPrimary(sheetContext),
                          ),
                          decoration: _homeworkInput(sheetContext, '作业标题（必填）'),
                        ),
                      ),
                      const SizedBox(height: 12),
                      ThemeFieldGroup(
                        title: '补充备注',
                        index: 3,
                        child: TextField(
                          controller: noteCtrl,
                          style: TextStyle(
                            fontSize: 14.5,
                            color: textPrimary(sheetContext),
                          ),
                          maxLines: 2,
                          decoration: _homeworkInput(
                            sheetContext,
                            '备注（选填）：需要交纸质版等',
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Icon(
                            Icons.schedule_rounded,
                            size: 18,
                            color: textSecondary(sheetContext),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              due == null
                                  ? '未设置截止时间'
                                  : '${due!.year}-${due!.month.toString().padLeft(2, '0')}-${due!.day.toString().padLeft(2, '0')} '
                                        '${due!.hour.toString().padLeft(2, '0')}:${due!.minute.toString().padLeft(2, '0')}',
                              style: TextStyle(
                                fontSize: 13.5,
                                color: due == null
                                    ? textFaint(sheetContext)
                                    : textPrimary(sheetContext),
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: () async {
                              final now = DateTime.now();
                              final d = await showDatePicker(
                                context: sheetContext,
                                initialDate: due ?? now,
                                firstDate: now.subtract(
                                  const Duration(days: 365),
                                ),
                                lastDate: now.add(const Duration(days: 730)),
                              );
                              if (d == null) return;
                              if (!sheetContext.mounted) return;
                              final t = await showTimePicker(
                                context: sheetContext,
                                initialTime: TimeOfDay.fromDateTime(due ?? now),
                              );
                              if (!sheetContext.mounted) return;
                              setSheet(
                                () => due = DateTime(
                                  d.year,
                                  d.month,
                                  d.day,
                                  t?.hour ?? 23,
                                  t?.minute ?? 59,
                                ),
                              );
                            },
                            child: const Text('选择时间'),
                          ),
                          if (due != null)
                            IconButton(
                              tooltip: '清除截止时间',
                              icon: const Icon(Icons.close_rounded, size: 18),
                              onPressed: () => setSheet(() => due = null),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                child: SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: FilledButton(
                    onPressed: () {
                      final title = titleCtrl.text.trim();
                      if (title.isEmpty) return;
                      final course = courseCtrl.text.trim();
                      final note = noteCtrl.text.trim();
                      if (edit == null) {
                        state.addManualHomework(
                          course: course,
                          title: title,
                          dueAt: due,
                          note: note,
                        );
                      } else {
                        state.updateManualHomework(
                          HomeworkItem(
                            id: edit.id,
                            platform: PlatformKind.manual,
                            course: course,
                            title: title,
                            dueAt: due,
                            status: edit.status,
                            url: edit.url,
                            score: edit.score,
                            note: note,
                            sourceKey: edit.sourceKey,
                          ),
                        );
                      }
                      Navigator.of(sheetContext).pop();
                    },
                    child: Text(edit == null ? '添加' : '保存'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  ).whenComplete(() {
    // 等退场动画走完再释放：立即 dispose 会炸 _dependents 断言
    Future<void>.delayed(const Duration(milliseconds: 500), () {
      courseCtrl.dispose();
      titleCtrl.dispose();
      noteCtrl.dispose();
    });
  });
}

InputDecoration _homeworkInput(BuildContext sheetContext, String hint) =>
    (!isCleanStyle(sheetContext) || paletteOf(sheetContext).sunny)
    ? themedInputDecoration(sheetContext, hintText: hint)
    : InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(fontSize: 13.5, color: textFaint(sheetContext)),
        isDense: true,
        filled: true,
        fillColor: bgColor(sheetContext),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
      );
