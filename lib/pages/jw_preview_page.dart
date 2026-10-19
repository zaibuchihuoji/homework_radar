/// 课表导入预览页：解析结果先过目，逐条可勾选/编辑，再决定入库。
/// 教务抓取、文本粘贴、截图 OCR 三条导入路都汇到这里。
library;

import 'package:flutter/material.dart';

import '../models/course.dart';
import '../ui/adaptive.dart';
import 'course_edit_sheet.dart';

class JwPreviewPage extends StatefulWidget {
  const JwPreviewPage({
    super.key,
    required this.courses,
    required this.sourceLabel,
  });

  /// 解析出的候选课程（weekday 为 0 表示星期未知）
  final List<Course> courses;
  final String sourceLabel;

  @override
  State<JwPreviewPage> createState() => _JwPreviewPageState();
}

class _Row {
  _Row(this.course, {required this.checked});
  Course course;
  bool checked;
}

class _JwPreviewPageState extends State<JwPreviewPage> {
  late final List<_Row> _rows;
  String _filter = '';

  bool _selectable(Course c) =>
      c.weekday >= 1 &&
      c.weekday <= 7 &&
      c.weeks.isNotEmpty &&
      c.weeks.every((w) => w >= 1 && w <= 30) &&
      !c.sectionsProvisional &&
      c.startSection >= 1 &&
      c.endSection >= c.startSection &&
      c.endSection <= 16;

  @override
  void initState() {
    super.initState();
    _rows = [for (final c in widget.courses) _Row(c, checked: _selectable(c))];
  }

  int get _checkedCount => _rows.where((r) => r.checked).length;

  /// 可勾选的行数（星期未知/节次待定的行复选框是禁用的，永远选不上）
  int get _selectableCount => _rows.where((r) => _selectable(r.course)).length;

  Future<void> _editRow(int index) async {
    final row = _rows[index];
    final updated = await CourseEditSheet(course: row.course).show(context);
    if (!mounted || updated == null) return;
    setState(() {
      row.course = updated;
      row.checked = _selectable(updated);
    });
  }

  @override
  Widget build(BuildContext context) {
    final weekdayUnknown = _rows.where((r) => r.course.weekday < 1).length;
    final visible = [
      for (final r in _rows)
        if (_filter.isEmpty ||
            r.course.name.contains(_filter) ||
            r.course.room.contains(_filter) ||
            r.course.teacher.contains(_filter))
          r,
    ];
    return Scaffold(
      appBar: AppBar(
        title: Text('确认课表 · ${widget.sourceLabel}'),
        actions: [
          // 顶部保存入口：底部按钮在某些机型/流程下会被残留的
          // WebView 平台视图挡住触摸，顶部操作始终可靠
          TextButton.icon(
            onPressed: _checkedCount == 0 ? null : _save,
            icon: const Icon(Icons.save_rounded, size: 18),
            label: Text('保存 $_checkedCount'),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '解析出 ${_rows.length} 条，已选 $_checkedCount 条'
                    '${weekdayUnknown > 0 ? '；$weekdayUnknown 条星期未知，点开可修正' : ''}',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: textSecondary(context),
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () {
                    // 以「可选行」为基准：存在星期未知行时按总行数比较，
                    // 全选按钮会永远显示「全选」且无法一键全不选
                    final target = _checkedCount < _selectableCount;
                    setState(() {
                      for (final r in _rows) {
                        r.checked = target && _selectable(r.course);
                      }
                    });
                  },
                  child: Text(_checkedCount < _selectableCount ? '全选' : '全不选'),
                ),
              ],
            ),
          ),
          if (_rows.length > 8)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
              child: TextField(
                decoration: const InputDecoration(
                  isDense: true,
                  prefixIcon: Icon(Icons.search_rounded),
                  hintText: '按课程名/教师/教室过滤',
                  border: OutlineInputBorder(),
                ),
                onChanged: (v) => setState(() => _filter = v.trim()),
              ),
            ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 12),
              itemCount: visible.length,
              itemBuilder: (context, i) {
                final row = visible[i];
                return _rowTile(context, row);
              },
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton.icon(
            onPressed: _checkedCount == 0 ? null : _save,
            icon: const Icon(Icons.save_rounded),
            label: Text('导入所选 $_checkedCount 节课'),
          ),
        ),
      ),
    );
  }

  Widget _rowTile(BuildContext context, _Row row) {
    final c = row.course;
    const dayNames = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    final time = c.weekday < 1
        ? '星期未知'
        : c.sectionsProvisional
            ? '${dayNames[c.weekday - 1]} 节次待定（点开编辑）'
            : '${dayNames[c.weekday - 1]} 第${c.startSection}-${c.endSection}节';
    final detail = [
      c.teacher,
      c.room,
      c.weeks.isEmpty ? '周次未知' : c.weeksText,
    ].where((s) => s.isNotEmpty).join(' · ');
    return CheckboxListTile(
      value: row.checked,
      onChanged: !_selectable(c)
          ? null
          : (v) => setState(() => row.checked = v ?? false),
      controlAffinity: ListTileControlAffinity.leading,
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      title: GestureDetector(
        onTap: () => _editRow(_rows.indexOf(row)),
        child: Text(
          c.name.isEmpty ? '（未命名课程）' : c.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 14.5,
            fontWeight: FontWeight.w700,
            color: c.weekday < 1 ? textFaint(context) : textPrimary(context),
          ),
        ),
      ),
      subtitle: GestureDetector(
        onTap: () => _editRow(_rows.indexOf(row)),
        child: Text(
          '$time\n$detail',
          style: TextStyle(
            fontSize: 12,
            height: 1.5,
            color: textSecondary(context),
          ),
        ),
      ),
      isThreeLine: true,
      secondary: IconButton(
        icon: const Icon(Icons.edit_outlined, size: 20),
        tooltip: '编辑',
        onPressed: () => _editRow(_rows.indexOf(row)),
      ),
    );
  }

  Future<void> _save() async {
    final selected = [
      for (final r in _rows)
        if (r.checked && _selectable(r.course)) r.course,
    ];
    Navigator.of(context).pop(selected);
  }
}
