/// 文本粘贴导入：教务解析失败（或没有教务入口）时的兜底。
/// 用户把课表文本粘进来 → 解析 → 进预览页确认入库。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import '../ui/focus_parts.dart';
import '../ui/adaptive.dart';
import '../models/course.dart';
import '../services/timetable_text_parser.dart';
import 'jw_preview_page.dart';
import 'timetable_import_confirmation.dart';

class JwTextImportPage extends StatefulWidget {
  const JwTextImportPage({super.key, required this.state});

  final AppState state;

  @override
  State<JwTextImportPage> createState() => _JwTextImportPageState();
}

class _JwTextImportPageState extends State<JwTextImportPage> {
  final _ctrl = TextEditingController();
  bool _parsing = false;
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData('text/plain');
    if (!mounted) return;
    if (data?.text?.isNotEmpty == true) {
      setState(() {
        _ctrl.text = data!.text!;
        _error = null;
      });
    } else {
      setState(() => _error = '剪贴板是空的，先去复制课表文本');
    }
  }

  Future<void> _parseAndPreview() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty) {
      setState(() => _error = '先粘贴课表文本');
      return;
    }
    setState(() {
      _parsing = true;
      _error = null;
    });
    // 解析放一个微任务里：两个 setState 之间没有 await 的话加载指示器
    // 永远渲染不出来，按钮防重也是死代码
    List<Course> courses;
    String semesterText = '';
    try {
      final parsed = await Future(
        () => TimetableTextParser.parseWithSemester(text),
      );
      courses = parsed.courses;
      semesterText = parsed.semesterText;
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _parsing = false;
        _error = '解析出错了：$e';
      });
      return;
    }
    if (!mounted) return;
    setState(() => _parsing = false);
    if (courses.isEmpty) {
      setState(
        () => _error =
            '没解析出课程。每门课至少要有名称和周次（如「1-16周」），'
            '行首写「周一」这类星期更佳。',
      );
      return;
    }
    final List<Course>? selected;
    try {
      selected = await Navigator.of(context).push<List<Course>>(
        MaterialPageRoute(
          builder: (_) => JwPreviewPage(courses: courses, sourceLabel: '文本导入'),
        ),
      );
      if (selected == null || selected.isEmpty || !mounted) return;
      final replace = await confirmTimetableImport(
        context,
        selected: selected,
        existing: widget.state.courses,
        requiresReplacement: widget.state.timetableRequiresReplacement(
          semesterText: semesterText,
        ),
        replacementPreview: widget.state.timetableReplacement(
          selected,
          semesterText: semesterText,
        ),
        sourceLabel: '文本导入',
      );
      if (replace == null || !mounted) return;
      // 学期归属由入库侧判断，是否替换由本次明确的导入方式决定。
      await widget.state.onTimetableCaptured(
        courses: selected,
        rawPage: '',
        semesterText: semesterText,
        source: '文本导入',
        fullImport: replace,
      );
    } catch (e) {
      // 入库链路抛错此前零反馈、页面不返回
      if (!mounted) return;
      setState(() => _error = '导入失败：$e');
      return;
    }
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final guide = Text(
      '支持两种写法：\n'
      '① 块式 —— 「星期一」单独一行，其后贴上该天的课程行；\n'
      '② 行内式 —— 每行一门课，如：周一 1-2节 高等数学 王一 1-16周 3-301。\n'
      '从教务网页全选复制也可以，解析完在预览里核对。',
      style: TextStyle(
        fontSize: 12.5,
        height: 1.7,
        color: textSecondary(context),
      ),
    );
    return Scaffold(
      backgroundColor: scaffoldBgOf(context),
      appBar: AppBar(title: const Text('粘贴文本导入')),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
              children: [
                ...[
                  const FocusSummary(
                    eyebrow: '文本导入',
                    title: '粘贴课表，核对后添加',
                    detail: '每门课的名称、星期、节次和周次都可以在预览中修改。',
                  ),
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: const Text('使用说明'),
                    children: [guide],
                  ),
                ],
                const SizedBox(height: 12),
                TextField(
                  controller: _ctrl,
                  maxLines: 14,
                  minLines: 8,
                  decoration: InputDecoration(
                    hintText: '把课表文本粘贴到这里…',
                    border: const OutlineInputBorder(),
                    errorText: _error,
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  OutlinedButton.icon(
                    onPressed: _paste,
                    icon: const Icon(Icons.content_paste_rounded, size: 18),
                    label: const Text('从剪贴板粘贴'),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _parsing ? null : _parseAndPreview,
                      icon: _parsing
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.manage_search_rounded, size: 18),
                      label: const Text('解析并预览'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
