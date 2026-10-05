/// 课程编辑表单：预览页逐条修正、课表页编辑已有课程、手动添加新课三处共用。
/// 弹出后 pop(Course?)；保存时带 edited 标记（重新抓取同一 id 保留修正）。
/// 周次用文本框编辑，语法与解析器一致（「1-16周」「3-17(单)」「1-8,10-16」）。
library;

import 'package:flutter/material.dart';

import '../models/course.dart';
import '../ui/adaptive.dart';

class CourseEditSheet extends StatefulWidget {
  const CourseEditSheet({super.key, this.course, this.initialWeekday});

  /// 传入 = 编辑已有课程；null = 手动添加新课。
  final Course? course;

  /// 新课的默认星期（取今天，手动添加时大概率在补最近的课）。
  final int? initialWeekday;

  Future<Course?> show(BuildContext context) => showDialog<Course>(
        context: context,
        builder: (_) => Dialog(
          backgroundColor: cardColor(context),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420, maxHeight: 560),
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: this,
            ),
          ),
        ),
      );

  @override
  State<CourseEditSheet> createState() => _CourseEditSheetState();
}

class _CourseEditSheetState extends State<CourseEditSheet> {
  late final TextEditingController _name;
  late final TextEditingController _teacher;
  late final TextEditingController _room;
  late final TextEditingController _weeks;
  late int _weekday;
  late int _start;
  late int _end;

  bool get _isNew => widget.course == null;

  @override
  void initState() {
    super.initState();
    final c = widget.course;
    _name = TextEditingController(text: c?.name ?? '');
    _teacher = TextEditingController(text: c?.teacher ?? '');
    _room = TextEditingController(text: c?.room ?? '');
    _weeks = TextEditingController(
        text: c == null || c.weeks.isEmpty ? '1-20周' : c.weeksText);
    _weekday = (c?.weekday ?? widget.initialWeekday ?? 1).clamp(1, 7);
    // 不做静默钳位：13-16 节的晚课被改写成 12/12 是把错误数据当保存结果。
    // 下拉已支持 1-16，越界值原样展示让用户自己决定怎么改
    _start = c?.startSection ?? 1;
    _end = c?.endSection ?? _start + 1;
    if (_start < 1) _start = 1;
    if (_end < _start) _end = _start;
  }

  @override
  void dispose() {
    _name.dispose();
    _teacher.dispose();
    _room.dispose();
    _weeks.dispose();
    super.dispose();
  }

  /// 解析周次输入；空输入表示不动原有周次（仅编辑已有课程时）。
  List<int>? get _parsedWeeks {
    final raw = _weeks.text.trim();
    if (raw.isEmpty && !_isNew) {
      // 原有周次为空的课（OCR/文本漏读周次）清空后保存会产出永不显示的
      // weeks=[] 课程——按「没认出来」处理，逼用户补一个有效值
      final w = widget.course!.weeks;
      return w.isEmpty ? null : w;
    }
    final weeks = Course.parseWeeks(raw);
    return weeks.isEmpty ? null : weeks;
  }

  bool get _canSave =>
      _name.text.trim().isNotEmpty && _parsedWeeks != null;

  @override
  Widget build(BuildContext context) {
    const dayNames = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    final weeks = _parsedWeeks;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_isNew ? '添加课程' : '编辑课程',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: textPrimary(context))),
            const SizedBox(height: 14),
            TextField(
              controller: _name,
              autofocus: _isNew,
              decoration: const InputDecoration(
                labelText: '课程名',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _teacher,
                    decoration: const InputDecoration(
                      labelText: '教师',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _room,
                    decoration: const InputDecoration(
                      labelText: '教室',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (var d = 1; d <= 7; d++)
                  ChoiceChip(
                    label: Text(dayNames[d - 1]),
                    selected: _weekday == d,
                    onSelected: (_) => setState(() => _weekday = d),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Text('节次',
                    style: TextStyle(
                        fontSize: 13, color: textSecondary(context))),
                const SizedBox(width: 10),
                DropdownButton<int>(
                  value: _start,
                  items: [
                    for (var s = 1; s <= 16; s++)
                      DropdownMenuItem(value: s, child: Text('第$s节')),
                  ],
                  onChanged: (v) => setState(() {
                    _start = v ?? _start;
                    if (_end < _start) _end = _start;
                  }),
                ),
                const SizedBox(width: 6),
                Text('至', style: TextStyle(fontSize: 13, color: textSecondary(context))),
                const SizedBox(width: 6),
                DropdownButton<int>(
                  value: _end,
                  items: [
                    for (var s = _start; s <= 16; s++)
                      DropdownMenuItem(value: s, child: Text('第$s节')),
                  ],
                  onChanged: (v) => setState(() => _end = v ?? _end),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _weeks,
              decoration: const InputDecoration(
                labelText: '周次',
                hintText: '如 1-16周、3-17(单)、1-8,10-16',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 6),
            Text(
              _name.text.trim().isEmpty
                  ? '填一下课程名'
                  : weeks == null
                      ? '周次没认出来，检查一下格式'
                      : '识别为：${Course(id: '', name: '', weekday: 1, startSection: 1, endSection: 1, weeks: weeks).weeksText}',
              style: TextStyle(
                  fontSize: 12,
                  color: _canSave ? textFaint(context) : Theme.of(context).colorScheme.error),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _canSave ? _save : null,
                child: Text(_isNew ? '添加到课表' : '保存修改'),
              ),
            ),
          ],
        ),
      );
  }

  void _save() {
    final old = widget.course;
    final weeks = _parsedWeeks;
    if (weeks == null) return;
    Navigator.of(context).pop(Course(
      id: old?.id ?? 'manual_${DateTime.now().millisecondsSinceEpoch}',
      name: _name.text.trim(),
      teacher: _teacher.text.trim(),
      room: _room.text.trim(),
      weekday: _weekday,
      startSection: _start,
      endSection: _end,
      weeks: weeks,
      edited: true,
      // 锚点记下编辑前的匹配键：改名/挪课后这条课的 key 变了，重抓合并按
      // anchorKey 兜底找回修正。已有锚点不覆盖——保留最初的锚点，链式编辑
      // （改过一次再改）不会把锚点漂移到最近一次的 key 上。
      anchorKey: old == null ? null : (old.anchorKey ?? old.editKey),
    ));
  }
}
