/// 导入方式由用户明确选择。默认补充合并；整表替换先显示原课程移除影响。
library;

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../ui/theme_forms.dart';
import '../models/course.dart';

/// null = 取消，false = 补充合并，true = 明确选择整表替换。
Future<bool?> confirmTimetableImport(
  BuildContext context, {
  required List<Course> selected,
  required List<Course> existing,
  List<Course>? replacementPreview,
  bool requiresReplacement = false,
  String sourceLabel = '课表',
}) {
  // 学校/学期切换可由调用者传入该归属分支的实际替换预览。
  final replacement =
      replacementPreview ??
      AppState.mergeEdited(selected, existing, union: false);
  bool covers(Course incoming, Course old) =>
      incoming.id == old.id &&
      incoming.weeks.length == old.weeks.length &&
      incoming.weeks.every(old.weeks.contains);
  final removed = existing
      .where(
        (old) =>
            !old.id.startsWith('manual_') &&
            !replacement.any((incoming) => covers(incoming, old)),
      )
      .toList();
  var replace = requiresReplacement;
  return showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => ThemedAlertDialog(
        title: Text('导入${selected.length}条课程 · $sourceLabel'),
        content: SizedBox(
          width: 360,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RadioGroup<bool>(
                  groupValue: replace,
                  onChanged: (v) => setState(() => replace = v ?? false),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      RadioListTile<bool>(
                        value: false,
                        enabled: !requiresReplacement,
                        title: const Text('补充合并（推荐）'),
                        subtitle: Text(
                          requiresReplacement
                              ? '学校或学期已变化，请确认替换；原课表会先归档。'
                              : '保留本次结果中未包含的原课程。',
                        ),
                      ),
                      RadioListTile<bool>(
                        value: true,
                        title: const Text('整表替换'),
                        subtitle: Text(
                          '将移除 ${removed.length} 条本次未包含的原课程。手动课程保留。',
                        ),
                      ),
                    ],
                  ),
                ),
                if (replace && removed.isNotEmpty) ...[
                  const Text('以下原课程将移除：'),
                  const SizedBox(height: 6),
                  for (final c in removed)
                    Text(
                      '• ${c.name} · 周${'一二三四五六日'[(c.weekday - 1).clamp(0, 6)]}'
                      ' 第${c.startSection}-${c.endSection}节 · ${c.weeksText}',
                    ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(replace),
            child: Text(replace ? '确认替换课表' : '确认补充导入'),
          ),
        ],
      ),
    ),
  );
}
