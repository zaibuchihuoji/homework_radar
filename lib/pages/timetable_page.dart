/// 课表：周视图网格，周一~周日 × 12 节。
/// 数据来自教务同步/文本/截图/Excel 导入/手动添加；周次由开学日期推算，可手动校准。
/// 左右滑动切周；非本周课程淡化显示；重叠课程按泳道并排。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import '../ui/theme_forms.dart';
import '../models/course.dart';
import '../services/jw_config.dart';
import '../services/section_times.dart';
import '../services/stable_hash.dart';
import '../services/storage.dart';
import '../ui/adaptive.dart';
import '../ui/ink_wash.dart';
import '../ui/style_background.dart';
import '../ui/theme_page_parts.dart';
import '../ui/tokens.dart';
import 'course_edit_sheet.dart';
import 'jw_ocr_import_page.dart';
import 'jw_preview_page.dart';
import 'jw_setup_page.dart';
import 'jw_text_import_page.dart';
import 'jw_xls_import_page.dart';
import 'timetable_import_confirmation.dart';
import 'zf_login_page.dart';

Color _brand(BuildContext c) => Tokens.brandOf(c);

const _gutterWidth = 34.0;
const _rowHeight = 52.0;
const _headerHeight = 40.0;

/// 解析器允许到第 16 节（晚课/小学期存在 13-16 节），网格此前固定 12 节，
/// 超出部分被整块裁剪到页面上完全不可见。跟随解析器上限放到 16。
const _sections = 16;
const _weekdayNames = ['一', '二', '三', '四', '五', '六', '日'];
const _maxWeeks = 30; // 与 Course.parseWeeks 的周次上限一致

/// 泳道排版结果：一门课 + 它所在的泳道号 / 所在重叠簇的泳道总数。
class PlacedCourse {
  const PlacedCourse(this.course, this.lane, this.lanes);
  final Course course;
  final int lane;

  /// 该课所在重叠簇共分几列（同簇所有课一致，宽度按它等分）。
  final int lanes;
}

/// 一天内的课程泳道排版：按开始节次排序，时间重叠的课分列并排
/// （超级课程表式）。相接不重叠（前一门 1-2 节、后一门 3-4 节）共占一列。
/// 泳道总数按「重叠簇」统计，簇内所有课等分列宽——分两遍算，
/// 因为入位时簇还没长全，先来的课不能锁定当时偏小的泳道数。
List<PlacedCourse> placeInLanes(List<Course> dayCourses) {
  final sorted = [...dayCourses]
    ..sort((a, b) {
      if (a.startSection != b.startSection) {
        return a.startSection.compareTo(b.startSection);
      }
      return a.endSection.compareTo(b.endSection);
    });
  final laneEnds = <int>[]; // 每条已开泳道的结束节次
  final laneOf = <(Course, int)>[];
  for (final c in sorted) {
    // 所有泳道都在它前面结束 => 新的重叠簇开始
    if (laneEnds.isNotEmpty && laneEnds.every((e) => e < c.startSection)) {
      laneEnds.clear();
    }
    var lane = laneEnds.indexWhere((e) => e < c.startSection);
    if (lane < 0) {
      lane = laneEnds.length;
      laneEnds.add(0);
    }
    laneEnds[lane] = c.endSection;
    laneOf.add((c, lane));
  }
  // 第二遍：把每门课归入重叠簇（开始节次 ≤ 簇内已有课程的最大结束节次），
  // 簇内统一用最大泳道数等分列宽。
  final out = <PlacedCourse>[];
  var i = 0;
  while (i < laneOf.length) {
    var maxEnd = laneOf[i].$1.endSection;
    var maxLane = 0;
    var j = i;
    while (j < laneOf.length &&
        (j == i || laneOf[j].$1.startSection <= maxEnd)) {
      if (laneOf[j].$1.endSection > maxEnd) maxEnd = laneOf[j].$1.endSection;
      if (laneOf[j].$2 > maxLane) maxLane = laneOf[j].$2;
      j++;
    }
    for (var k = i; k < j; k++) {
      out.add(PlacedCourse(laneOf[k].$1, laneOf[k].$2, maxLane + 1));
    }
    i = j;
  }
  return out;
}

class TimetablePage extends StatefulWidget {
  const TimetablePage({super.key, required this.state});

  final AppState state;

  @override
  State<TimetablePage> createState() => _TimetablePageState();
}

class _TimetablePageState extends State<TimetablePage> {
  int? _week; // 当前查看的周次；null = 跟随本周
  PageController? _pageController;

  /// 页面常驻不销毁（KeepAlivePage）且无跨天刷新，「本周」标记/今日列高亮/
  /// 回到本周 FAB 会按旧日期显示——定时重建保持日期新鲜
  Timer? _clock;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(
      initialPage: (_displayWeek - 1).clamp(0, _maxWeeks - 1),
    );
    _clock = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    _pageController?.dispose();
    super.dispose();
  }

  int? _currentWeek() {
    final start = Storage.semesterStart();
    if (start == null) return null;
    return Course.weekNumberOf(start, DateTime.now());
  }

  int get _displayWeek {
    final w = _week ?? _currentWeek();
    if (w == null) return 1;
    // 学期开始前（≤0）与超出 _maxWeeks 时钳回可显示范围，
    // 否则「回到本周」原地不动永挂、标题与 PageView 内容错位
    return w.clamp(1, _maxWeeks);
  }

  DateTime? _mondayOf(int week) {
    final start = Storage.semesterStart();
    if (start == null) return null;
    final s0 = DateTime(start.year, start.month, start.day);
    return s0.add(Duration(days: (week - 1) * 7));
  }

  void _animateToWeek(int week) {
    final page = (week - 1).clamp(0, _maxWeeks - 1);
    _pageController?.animateToPage(
      page,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  /// 导入/校准后回到当前周（清除手动选中的周次）。
  void _resetToCurrentWeek() {
    setState(() => _week = null);
    final page = ((_currentWeek() ?? 1) - 1).clamp(0, _maxWeeks - 1);
    _pageController?.jumpToPage(page);
  }

  void _followCurrentWeek() {
    if (_week != null) return;
    final target = ((_currentWeek() ?? 1) - 1).clamp(0, _maxWeeks - 1);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final controller = _pageController;
      if (!mounted ||
          _week != null ||
          controller == null ||
          !controller.hasClients ||
          controller.position.isScrollingNotifier.value) {
        return;
      }
      if ((controller.page ?? 0).round() != target) {
        controller.jumpToPage(target);
      }
    });
  }

  /// 同步走抓取页：没配置教务地址先弹设置页；会话有效时进去几秒即自动抓完。
  /// 抓取页只负责抓取，抓到后关闭并把结果带回来——校对页由本页推入，
  /// 绝不能垫在 WebView 平台视图之上（其原生视图残留会吞掉底部按钮触摸）。
  Future<void> _sync() async {
    if (!JwStore.hasConfig) {
      final cfg = await Navigator.of(
        context,
      ).push<JwConfig>(MaterialPageRoute(builder: (_) => const JwSetupPage()));
      if (cfg == null || !mounted) return;
    }
    final result = await Navigator.of(context)
        .push<Object?>(MaterialPageRoute(builder: (_) => const ZfLoginPage()));
    if (!mounted) return;
    if (result == ZfExit.openTextImport) {
      await _fallbackImport(ocr: false);
      return;
    }
    if (result is! ZfCapture) return;
    final cap = result;
    final selected = await Navigator.of(context).push<List<Course>>(
      MaterialPageRoute(
        builder: (_) => JwPreviewPage(
          courses: cap.parsed.courses,
          sourceLabel: cap.sourceName,
        ),
      ),
    );
    if (!mounted) return;
    if (selected == null || selected.isEmpty) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('未导入。点右上角同步按钮可重新抓取')));
      return;
    }
    final fullImport = await confirmTimetableImport(
      context,
      selected: selected,
      existing: Storage.courses(),
      sourceLabel: cap.sourceName,
      requiresReplacement: widget.state.timetableRequiresReplacement(
        xh: cap.parsed.xh,
        semesterText: cap.parsed.semesterText,
      ),
      replacementPreview: widget.state.timetableReplacement(
        selected,
        xh: cap.parsed.xh,
        semesterText: cap.parsed.semesterText,
      ),
    );
    if (fullImport == null || !mounted) return;
    await widget.state.onTimetableCaptured(
      cookie: cap.cookie,
      xh: cap.parsed.xh,
      courses: selected,
      rawPage: cap.parsed.rawPage,
      semesterText: cap.parsed.semesterText,
      detectedWeek: cap.parsed.detectedWeek,
      source: cap.sourceName,
      fullImport: fullImport,
    );
    if (!mounted) return;
    _resetToCurrentWeek();
    final msg = widget.state.timetableMessage;
    if (msg.isNotEmpty) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  /// 更换教务平台：改地址后重新抓取。
  Future<void> _changeSchool() async {
    final cfg = await Navigator.of(context).push<JwConfig>(
      MaterialPageRoute(builder: (_) => JwSetupPage(initial: JwStore.load())),
    );
    if (cfg != null && mounted) _sync();
  }

  /// 打开导入页，成功后刷新视图并提示。
  Future<void> _openImportPage(Widget page) async {
    final ok = await Navigator.of(context)
        .push<bool>(MaterialPageRoute(builder: (_) => page));
    if (ok != true || !mounted) return;
    _resetToCurrentWeek();
    final msg = widget.state.timetableMessage;
    if (msg.isNotEmpty) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  /// 文本/截图兜底导入。
  Future<void> _fallbackImport({required bool ocr}) => _openImportPage(
    ocr
        ? JwOcrImportPage(state: widget.state)
        : JwTextImportPage(state: widget.state),
  );

  /// Excel 表格文件导入。
  Future<void> _xlsImport() =>
      _openImportPage(JwXlsImportPage(state: widget.state));

  /// 手动添加课程（选修课等教务里没有的）。
  Future<void> _addCourse() async {
    final c = await CourseEditSheet(initialWeekday: DateTime.now().weekday)
        .show(context);
    if (c == null || !mounted) return;
    await _courseChange(() => widget.state.addManualCourse(c));
  }

  Future<void> _editCourse(Course c) async {
    final updated = await CourseEditSheet(course: c).show(context);
    if (updated == null || !mounted) return;
    await _courseChange(() => widget.state.updateCourse(c, updated));
  }

  Future<bool> _courseChange(Future<void> Function() change) async {
    try {
      await change();
      return true;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('保存失败：$e')));
      }
      return false;
    }
  }

  Future<void> _deleteCourse(Course c) async {
    final manual = c.id.startsWith('manual_');
    if (!await _courseChange(() => widget.state.deleteCourse(c))) return;
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            manual ? '已删除手动添加的课程' : '已删除「${c.name}」，重新抓取同一学期的课表会恢复',
          ),
        ),
      );
  }

  /// 菜单开关：是否淡化显示非本周课程。
  Future<void> _toggleNonWeek() async {
    final v = !Storage.showNonWeekCourses();
    await Storage.saveShowNonWeekCourses(v);
    if (mounted) setState(() {});
  }

  Future<void> _pickSemesterStart() async {
    final base = _mondayOf(_displayWeek) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: base,
      firstDate: DateTime(base.year - 1),
      lastDate: DateTime(base.year + 1),
      helpText: '选开学第一周的任意一天',
    );
    if (picked == null) return;
    final monday = picked.subtract(Duration(days: picked.weekday - 1));
    await widget.state.setSemesterStart(monday);
    if (!mounted) return;
    _resetToCurrentWeek();
  }

  /// 长按标题：查看教务原始页面（排查解析问题，沿用应用的隐藏调试入口习惯）
  void _showRawPage() {
    final raw = Storage.zfRawPage();
    showDialog(
      context: context,
      builder: (context) => ThemedAlertDialog(
        title: const Text('教务原始页面'),
        scrollable: true,
        content: SizedBox(
          width: 400,
          child: raw.isEmpty
              ? const Text('还没有抓到过课表页面。')
              : Text(
                  '共 ${raw.length} 字符，前 600 字：\n\n${raw.substring(0, raw.length.clamp(0, 600))}',
                ),
        ),
        actions: [
          if (raw.isNotEmpty)
            TextButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: raw));
                Navigator.of(context).pop();
                ScaffoldMessenger.of(this.context)
                    .showSnackBar(const SnackBar(content: Text('原始页面已复制到剪贴板')));
              },
              child: const Text('复制全部'),
            ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  void _showCourseSheet(Course c, int week) {
    final start = _mondayOf(week);
    final day = start?.add(Duration(days: c.weekday - 1));
    String two(int n) => n.toString().padLeft(2, '0');
    // day 为 null = 周次未校准（保持原行为：不显示开始时刻）；
    // t0 为 null = 作息表没配到该节次：明说「时刻待配置」，不展示
    // 钳位来的假时刻（t0 的判空是防御性写法，兼容取时刻函数
    // 「表外节次返回 null」改造前后的两种返回形态）
    final t0 = day == null
        ? null
        : SectionTimes.startOfDay(day, c.startSection);
    final timeTail = day == null
        ? ''
        : t0 == null
        ? ' · 时刻待配置'
        : ' · ${two(t0.hour)}:${two(t0.minute)} 开始';
    showDialog(
      context: context,
      builder: (dialogContext) => ThemedDialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 22, 24, 10),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ThemeEditorHeading(
                    title: c.name,
                    kicker: 'COURSE DETAILS',
                    icon: Icons.school_outlined,
                  ),
                  const SizedBox(height: 12),
                  _sheetRow(
                    dialogContext,
                    Icons.person_outline_rounded,
                    '教师',
                    c.teacher,
                  ),
                  _sheetRow(dialogContext, Icons.place_outlined, '教室', c.room),
                  _sheetRow(
                    dialogContext,
                    Icons.view_week_outlined,
                    '周次',
                    c.weeksText,
                  ),
                  _sheetRow(
                    dialogContext,
                    Icons.schedule_rounded,
                    '时间',
                    '周${_weekdayNames[c.weekday - 1]} · 第${c.startSection}-${c.endSection}节'
                        '$timeTail',
                  ),
                  Row(
                    children: [
                      TextButton.icon(
                        onPressed: () {
                          Navigator.of(dialogContext).pop();
                          _editCourse(c);
                        },
                        icon: const Icon(Icons.edit_outlined, size: 18),
                        label: const Text('编辑'),
                      ),
                      const SizedBox(width: 8),
                      TextButton.icon(
                        onPressed: () {
                          Navigator.of(dialogContext).pop();
                          _deleteCourse(c);
                        },
                        icon: const Icon(
                          Icons.delete_outline_rounded,
                          size: 18,
                        ),
                        label: const Text('删除'),
                        style: TextButton.styleFrom(
                          foregroundColor: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _sheetRow(
    BuildContext context,
    IconData icon,
    String label,
    String value,
  ) {
    if (value.trim().isEmpty) value = '未知';
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 17, color: textSecondary(context)),
          const SizedBox(width: 10),
          SizedBox(
            width: 38,
            child: Text(
              label,
              style: TextStyle(fontSize: 13.5, color: textSecondary(context)),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(fontSize: 13.5, color: textPrimary(context)),
            ),
          ),
        ],
      ),
    );
  }

  /// 长按课程块：换颜色（按课程名生效）。居中弹窗。
  void _showColorSheet(Course c) {
    final current = Storage.courseColors()[c.name];
    showDialog(
      context: context,
      builder: (dialogContext) => ThemedDialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 22, 24, 18),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ThemeEditorHeading(
                    title: '课程颜色 · ${c.name}',
                    kicker: 'COURSE COLOR',
                    icon: Icons.palette_outlined,
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      _colorOption(
                        dialogContext,
                        null,
                        current == null,
                        null,
                        c,
                      ),
                      for (var i = 0; i < Tokens.coursePalette.length; i++)
                        _colorOption(
                          dialogContext,
                          i,
                          current == i,
                          Tokens.coursePalette[i],
                          c,
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '按课程名生效，同一门课的所有节次一起变色',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: textFaint(dialogContext),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _colorOption(
    BuildContext sheetContext,
    int? index,
    bool selected,
    Color? color,
    Course c,
  ) {
    return Semantics(
      label: index == null
          ? '跟随配色'
          : '颜色${index + 1}，当前${selected ? '已选中' : '未选中'}',
      button: true,
      selected: selected,
      child: GestureDetector(
        onTap: () async {
          final colors = Map<String, int>.of(Storage.courseColors());
          if (index == null) {
            colors.remove(c.name);
          } else {
            colors[c.name] = index;
          }
          await Storage.saveCourseColors(colors);
          if (sheetContext.mounted) Navigator.of(sheetContext).pop();
          if (mounted) setState(() {});
        },
        // 视觉仍是 38dp 色点，外扩到 44dp 保证可点击目标
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Center(
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? _brand(sheetContext) : Colors.transparent,
                  width: 2.5,
                ),
                // 有色的色点自带同色微光（光源感）；"跟随配色"那个不发光
                boxShadow: color == null
                    ? null
                    : Tokens.glow(color, dark: isDark(sheetContext)),
              ),
              child: selected
                  ? Icon(Icons.check_rounded, size: 18, color: Colors.white)
                  : index == null
                  ? Icon(
                      Icons.auto_awesome_outlined,
                      size: 16,
                      color: textSecondary(sheetContext),
                    )
                  : null,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        // 放在 builder 内：放外圈的话 state 通知重建也不会刷新周次/今日高亮
        final currentWeek = _currentWeek();
        _followCurrentWeek();
        return StyleBackground(
          // 带底衬的样式下透明化 Scaffold，露出主题底衬
          child: Scaffold(
            backgroundColor: scaffoldBgOf(context),
            appBar: AppBar(
              title: GestureDetector(
                onLongPress: _showRawPage,
                child: appBarTitle(context, '课表'),
              ),
              actions: [
                IconButton(
                  tooltip: '手动添加课程',
                  onPressed: _addCourse,
                  icon: const Icon(Icons.add_rounded),
                ),
                IconButton(
                  tooltip: '登录 / 同步课表',
                  onPressed: _sync,
                  icon: const Icon(Icons.sync_rounded),
                ),
                PopupMenuButton<String>(
                  tooltip: '更多',
                  position: PopupMenuPosition.under,
                  offset: const Offset(0, 8),
                  constraints: const BoxConstraints(
                    minWidth: 236,
                    maxWidth: 260,
                  ),
                  onSelected: (v) => switch (v) {
                    'school' => _changeSchool(),
                    'week' => _pickSemesterStart(),
                    'text' => _fallbackImport(ocr: false),
                    'ocr' => _fallbackImport(ocr: true),
                    'xls' => _xlsImport(),
                    'nonweek' => _toggleNonWeek(),
                    _ => null,
                  },
                  itemBuilder: (context) => [
                    _popupItem('school', Icons.school_outlined, '更换教务平台'),
                    _popupItem('text', Icons.content_paste_rounded, '粘贴文本导入'),
                    _popupItem(
                      'week',
                      Icons.event_repeat_rounded,
                      '设置开学日期（周次）',
                    ),
                    _popupItem('xls', Icons.table_view_rounded, '导入 Excel 文件'),
                    _popupItem('ocr', Icons.photo_outlined, '截图导入'),
                    _popupItem(
                      'nonweek',
                      Icons.visibility_outlined,
                      '显示非本周课程',
                      checked: Storage.showNonWeekCourses(),
                    ),
                  ],
                ),
                const SizedBox(width: 4),
              ],
            ),
            floatingActionButton:
                currentWeek != null &&
                    _displayWeek != currentWeek.clamp(1, _maxWeeks)
                ? Padding(
                    // 底栏已独立占位，回到本周按钮与新增按钮保持相同留白
                    padding: EdgeInsets.zero,
                    child: DecoratedBox(
                      // 落影随样式：漫画=白边贴纸+硬投影，水墨=墨影，其余=光晕
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(
                          isComicStyle(context) ? 18 : 14,
                        ),
                        border: isComicStyle(context)
                            ? Border.all(color: Colors.white, width: 2)
                            : null,
                        boxShadow: primaryButtonShadow(context),
                      ),
                      child: FloatingActionButton.extended(
                        heroTag: 'tt_back_week',
                        onPressed: () =>
                            _animateToWeek(currentWeek.clamp(1, _maxWeeks)),
                        icon: const Icon(Icons.today_rounded, size: 18),
                        label: const Text('回到本周'),
                      ),
                    ),
                  )
                : null,
            body: state.courses.isEmpty
                ? _emptyPrompt(context, state)
                : _buildWeekView(context, state, currentWeek),
          ),
        );
      },
    );
  }

  /// 空态的几何小构图：白卡上一颗品牌色圆点 + 两条灰线，纯形状不搞插画。
  Widget _emptyArt(BuildContext context) {
    final line = dividerColor(context);
    return Container(
      width: 76,
      height: 76,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cardColor(context),
        borderRadius: BorderRadius.circular(16),
        boxShadow: Tokens.cardShadow(context),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: _brand(context),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(height: 7),
          Container(
            width: 36,
            height: 6,
            decoration: BoxDecoration(
              color: line,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(height: 5),
          Container(
            width: 24,
            height: 6,
            decoration: BoxDecoration(
              color: line,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyPrompt(BuildContext context, AppState state) {
    final loggedIn = state.zfState != AccountState.notLoggedIn;
    if (!isCleanStyle(context)) {
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ThemePageHeader(
                title: loggedIn ? '还没有课表数据' : '导入教务课表',
                kicker: 'CLASS SCHEDULE',
                summary: loggedIn
                    ? (state.timetableMessage.isEmpty
                          ? '同步教务课表，或手动添加课程，开始安排每周的学习。'
                          : state.timetableMessage)
                    : '读取课程表，与作业截止一起看。教务需校园网或 VPN；打不开时可用文本、截图或 Excel 导入。',
                icon: Icons.calendar_view_week_outlined,
              ),
              const SizedBox(height: 20),
              if (!loggedIn)
                FilledButton(onPressed: _sync, child: const Text('导入教务课表')),
              TextButton.icon(
                onPressed: _addCourse,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('手动添加课程'),
              ),
            ],
          ),
        ),
      );
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 水墨：空态挂一幅远山，不用几何小卡
            if (isInkStyle(context))
              const SizedBox(
                width: 260,
                height: 100,
                child: InkMountains(height: 100),
              )
            else
              _emptyArt(context),
            const SizedBox(height: 16),
            Text(
              loggedIn ? '还没有课表数据' : '导入教务课表',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: textPrimary(context),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              loggedIn
                  ? (state.timetableMessage.isEmpty
                        ? '点右上角同步按钮重新抓取；\n也可以点右上角 + 手动添加课程。'
                        : state.timetableMessage)
                  : '像超级课程表一样，输入学校教务网址\n即可读取课程表，与作业截止一起看。\n教务需校园网或 VPN；打不开时可用文本/截图导入。',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                height: 1.7,
                color: textSecondary(context),
              ),
            ),
            const SizedBox(height: 20),
            if (!loggedIn)
              FilledButton(onPressed: _sync, child: const Text('导入教务课表')),
            const SizedBox(height: 4),
            TextButton.icon(
              onPressed: _addCourse,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('手动添加课程'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWeekView(
    BuildContext context,
    AppState state,
    int? currentWeek,
  ) {
    final now = DateTime.now();
    final calibrateNeeded = currentWeek == null;
    final monday = _mondayOf(_displayWeek);

    return Column(
      children: [
        // ---- 周切换条（大数字月份 + 箭头 + 周次胶囊）----
        if (!isCleanStyle(context))
          _themedWeekBar(context, state, currentWeek, monday)
        else
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              children: [
                SizedBox(
                  width: 52,
                  child: monday == null
                      ? null
                      : Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text: '${monday.month}',
                                style: TextStyle(
                                  fontSize: 26,
                                  height: 1.1,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: -0.5,
                                  color: textPrimary(context),
                                ),
                              ),
                              TextSpan(
                                text: '月',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: textSecondary(context),
                                ),
                              ),
                            ],
                          ),
                        ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: _displayWeek > 1
                      ? () => _animateToWeek(_displayWeek - 1)
                      : null,
                  icon: Icon(
                    Icons.chevron_left_rounded,
                    size: 22,
                    color: textSecondary(context),
                  ),
                ),
                Expanded(
                  child: GestureDetector(
                    onTap: currentWeek != null
                        ? () => _animateToWeek(currentWeek)
                        : _pickSemesterStart,
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            // 小票：周次是打印的方框单号，不是胶囊
                            borderRadius: BorderRadius.circular(
                              isReceiptStyle(context) ? 2 : 999,
                            ),
                            border: Border.all(
                              color: _brand(context),
                              width: currentWeek != null ? 1.2 : 0,
                            ),
                            color: currentWeek != null
                                ? Colors.transparent
                                : dividerColor(context),
                          ),
                          child: Text(
                            calibrateNeeded ? '周次未校准' : '第$_displayWeek周',
                            style: monoText(
                              context,
                              TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                letterSpacing: isReceiptStyle(context)
                                    ? 1
                                    : null,
                                color: currentWeek != null
                                    ? _brand(context)
                                    : textSecondary(context),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          monday == null
                              ? '点击设置开学时间'
                              : '${monday.month}/${monday.day} - '
                                    '${monday.add(const Duration(days: 6)).month}/'
                                    '${monday.add(const Duration(days: 6)).day}'
                                    '${currentWeek != null && _displayWeek == currentWeek ? ' · 本周' : ''}',
                          style: monoText(
                            context,
                            TextStyle(
                              fontSize: 11.5,
                              color: textSecondary(context),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: _displayWeek < _maxWeeks
                      ? () => _animateToWeek(_displayWeek + 1)
                      : null,
                  icon: Icon(
                    Icons.chevron_right_rounded,
                    size: 22,
                    color: textSecondary(context),
                  ),
                ),
                const SizedBox(width: 52),
              ],
            ),
          ),
        if (calibrateNeeded)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
            child: _calibrateBanner(context),
          ),
        // ---- 网格主体：整周一页（节次列随内容一起滚动），星期列随周次翻页 ----
        Expanded(
          child: Container(
            margin: const EdgeInsets.fromLTRB(10, 2, 10, 10),
            clipBehavior: Clip.antiAlias,
            // 水墨：整张课表是一张墨洗卡（笔锋圆角+浓淡墨渐变）；
            // 小票：整周课表是一张热敏大单（底边撕纸）
            decoration: _gridDecoration(context),
            child: PageView.builder(
              controller: _pageController,
              itemCount: _maxWeeks,
              onPageChanged: (page) => setState(
                () => _week =
                    page + 1 == (_currentWeek() ?? 1).clamp(1, _maxWeeks)
                    ? null
                    : page + 1,
              ),
              itemBuilder: (context, page) =>
                  _weekPage(context, state, page + 1, now, currentWeek),
            ),
          ),
        ),
      ],
    );
  }

  ThemeStyle _timetableStyle(BuildContext context) {
    final p = paletteOf(context);
    if (p.morandi) return ThemeStyle.morandi;
    if (p.pixel) return ThemeStyle.pixel;
    if (p.inkWash) return ThemeStyle.amoled;
    if (p.paper) return ThemeStyle.paper;
    if (p.comic) return ThemeStyle.comic;
    if (p.receipt) return ThemeStyle.receipt;
    if (p.editorial) return ThemeStyle.editorial;
    if (p.terminal) return ThemeStyle.terminal;
    if (p.journal) return ThemeStyle.journal;
    return p.sunny ? ThemeStyle.clean : ThemeStyle.green;
  }

  Decoration _gridDecoration(BuildContext context) {
    final p = paletteOf(context);
    if (p.inkWash) return inkWashFill(context, 12)!;
    if (p.receipt) return receiptTear(context)!;
    return BoxDecoration(
      color: cardColor(context),
      borderRadius: BorderRadius.circular(
        p.pixel || p.terminal || p.editorial
            ? 0
            : p.morandi
            ? 22
            : 12,
      ),
      border: p.clean || p.morandi
          ? null
          : Border.all(color: p.cardBorder, width: p.comic ? 2 : 1),
      boxShadow: Tokens.cardShadow(context),
    );
  }

  /// Keep the theme's identity in the control strip; all styles share the same
  /// paging callbacks and leave the timetable's section geometry untouched.
  Widget _themedWeekBar(
    BuildContext context,
    AppState state,
    int? currentWeek,
    DateTime? monday,
  ) {
    final style = _timetableStyle(context);
    final p = paletteOf(context);
    final count = state.courses
        .where((c) => c.inWeek(_displayWeek))
        .map((c) => c.name)
        .toSet()
        .length;
    final end = monday?.add(const Duration(days: 6));
    final date = monday == null
        ? '点击设置开学时间'
        : '${monday.month}/${monday.day} — ${end!.month}/${end.day}'
              '${_displayWeek == currentWeek ? ' · 本周' : ''}';
    final heading = switch (style) {
      ThemeStyle.morandi => 'WEEKLY PALETTE',
      ThemeStyle.pixel => 'STAGE / ${_displayWeek.toString().padLeft(2, '0')}',
      ThemeStyle.amoled => '课 · 记',
      ThemeStyle.paper => 'WEEKLY STUDY NOTES',
      ThemeStyle.comic => '这周的上课计划！',
      ThemeStyle.receipt => 'COURSE RECEIPT',
      ThemeStyle.editorial => 'THE WEEK / 课程编排',
      ThemeStyle.terminal => '> timetable --week $_displayWeek',
      ThemeStyle.journal => 'MY STUDY JOURNAL',
      ThemeStyle.clean || ThemeStyle.green => '',
    };
    final mono =
        style == ThemeStyle.pixel ||
        style == ThemeStyle.receipt ||
        style == ThemeStyle.terminal;
    final serif =
        style == ThemeStyle.paper ||
        style == ThemeStyle.amoled ||
        style == ThemeStyle.editorial;
    final ink = p.ink;
    final titleStyle = TextStyle(
      color: ink,
      fontSize: style == ThemeStyle.editorial ? 22 : 17,
      fontWeight: FontWeight.w800,
      fontFamily: mono
          ? 'monospace'
          : serif
          ? 'serif'
          : null,
      letterSpacing: style == ThemeStyle.receipt ? 2 : null,
      height: 1.15,
    );
    final title = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: currentWeek != null
          ? () => _animateToWeek(currentWeek)
          : _pickSemesterStart,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: style == ThemeStyle.receipt
            ? CrossAxisAlignment.center
            : CrossAxisAlignment.start,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              currentWeek == null ? '周次未校准' : '第$_displayWeek周',
              style: titleStyle,
            ),
          ),
          const SizedBox(height: 3),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              date,
              style: TextStyle(
                color: p.ink2,
                fontSize: 10,
                fontFamily: mono ? 'monospace' : null,
              ),
            ),
          ),
        ],
      ),
    );
    Widget arrow(bool next) => IconButton(
      tooltip: next ? '下一周' : '上一周',
      onPressed: (next ? _displayWeek < _maxWeeks : _displayWeek > 1)
          ? () => _animateToWeek(_displayWeek + (next ? 1 : -1))
          : null,
      icon: Icon(
        next ? Icons.chevron_right_rounded : Icons.chevron_left_rounded,
        color: p.ink2,
        size: 22,
      ),
    );
    final controls = Row(
      children: [
        arrow(false),
        Expanded(child: title),
        const SizedBox(width: 6),
        Flexible(
          flex: 0,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              '$count 门课程',
              style: TextStyle(
                fontSize: 10,
                fontFamily: mono ? 'monospace' : null,
                fontWeight: FontWeight.w600,
                color: p.ink2,
              ),
            ),
          ),
        ),
        arrow(true),
      ],
    );
    final frame = switch (style) {
      ThemeStyle.morandi => BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          colors: [p.card, p.accentFill.withValues(alpha: .09)],
        ),
      ),
      ThemeStyle.pixel => BoxDecoration(
        color: p.card,
        border: Border.all(color: p.ink, width: 2),
        boxShadow: [
          BoxShadow(
            color: p.ink.withValues(alpha: .18),
            offset: const Offset(3, 3),
          ),
        ],
      ),
      ThemeStyle.amoled => inkWashFill(context, 10)!,
      ThemeStyle.paper => BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: p.cardBorder),
      ),
      ThemeStyle.comic => BoxDecoration(
        color: Color.alphaBlend(p.accentFill.withValues(alpha: .13), p.card),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
          bottomRight: Radius.circular(20),
          bottomLeft: Radius.circular(3),
        ),
        border: Border.all(color: p.ink, width: 2),
        boxShadow: [BoxShadow(color: p.ink, offset: const Offset(2, 3))],
      ),
      ThemeStyle.receipt => receiptTear(context)!,
      ThemeStyle.editorial => BoxDecoration(
        color: p.card,
        border: Border(
          left: BorderSide(color: p.accent, width: 4),
          bottom: BorderSide(color: p.ink, width: 2),
        ),
      ),
      ThemeStyle.terminal => BoxDecoration(
        color: p.card,
        border: Border.all(color: p.accentFill.withValues(alpha: .6)),
      ),
      ThemeStyle.journal => BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: p.cardBorder),
        boxShadow: [
          BoxShadow(
            color: p.ink.withValues(alpha: .10),
            offset: const Offset(2, 3),
          ),
        ],
      ),
      ThemeStyle.clean || ThemeStyle.green => const BoxDecoration(),
    };
    final cap = Row(
      mainAxisAlignment: style == ThemeStyle.receipt
          ? MainAxisAlignment.center
          : MainAxisAlignment.start,
      children: [
        if (style == ThemeStyle.morandi) ...[
          for (final color in [p.accent, p.ink3, p.cardBorder])
            Container(
              width: 9,
              height: 9,
              margin: const EdgeInsets.only(right: 4),
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
          const SizedBox(width: 4),
        ],
        if (style == ThemeStyle.pixel || style == ThemeStyle.terminal) ...[
          Icon(
            style == ThemeStyle.pixel
                ? Icons.videogame_asset_outlined
                : Icons.terminal,
            color: style == ThemeStyle.pixel ? p.card : p.accent,
            size: 12,
          ),
          const SizedBox(width: 6),
        ],
        Flexible(
          child: Text(
            heading,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 9,
              height: 1.3,
              letterSpacing: mono ? .5 : 1,
              fontFamily: mono
                  ? 'monospace'
                  : serif
                  ? 'serif'
                  : null,
              fontWeight: FontWeight.w700,
              color: style == ThemeStyle.pixel ? p.card : p.ink2,
            ),
          ),
        ),
        if (style == ThemeStyle.amoled) ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.all(2),
            color: p.accent,
            child: Text('课', style: TextStyle(fontSize: 9, color: p.onAccent)),
          ),
        ],
      ],
    );
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 9),
      decoration: frame,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: double.infinity,
            margin: EdgeInsets.only(
              left: style == ThemeStyle.journal ? 28 : 0,
              right: style == ThemeStyle.journal ? 28 : 0,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: style == ThemeStyle.pixel
                  ? p.ink
                  : style == ThemeStyle.journal
                  ? p.accentFill.withValues(alpha: .13)
                  : null,
              border:
                  style == ThemeStyle.paper ||
                      style == ThemeStyle.receipt ||
                      style == ThemeStyle.terminal
                  ? Border(bottom: BorderSide(color: p.cardBorder))
                  : null,
            ),
            child: cap,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: controls,
          ),
        ],
      ),
    );
  }

  /// 一周的整页：星期表头 + 节次列 + 7 列网格（同一滚动容器，
  /// 左侧节次/时间栏与课程行永远对齐——固定栏的老实现不随网格滚动，
  /// 小屏第 9 节以后被 Stack 硬裁剪、滚动后与课程行错位）。
  Widget _weekPage(
    BuildContext context,
    AppState state,
    int week,
    DateTime now,
    int? currentWeek,
  ) {
    final monday = _mondayOf(week);
    final isCurrentWeek = currentWeek != null && week == currentWeek;
    return Column(
      children: [
        SizedBox(
          height: _headerHeight,
          child: Row(
            children: [
              SizedBox(width: _gutterWidth),
              for (var d = 1; d <= 7; d++)
                Expanded(
                  child: _dayHeader(context, d, monday, now, isCurrentWeek),
                ),
            ],
          ),
        ),
        const SizedBox(height: 2),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 12),
            child: SizedBox(
              height: _sections * _rowHeight,
              child: LayoutBuilder(
                builder: (context, cons) {
                  final dayWidth = (cons.maxWidth - _gutterWidth) / 7;
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: _gutterWidth,
                        child: Column(
                          children: [
                            for (var s = 1; s <= _sections; s++)
                              _gutterCell(context, s),
                          ],
                        ),
                      ),
                      for (var d = 1; d <= 7; d++)
                        SizedBox(
                          width: dayWidth,
                          height: _sections * _rowHeight,
                          child: _dayColumn(
                            context,
                            state,
                            d,
                            week,
                            dayWidth,
                            now,
                            isCurrentWeek,
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _dayColumn(
    BuildContext context,
    AppState state,
    int d,
    int week,
    double dayWidth,
    DateTime now,
    bool isCurrentWeek,
  ) {
    final isToday = isCurrentWeek && now.weekday == d;
    // 关掉「显示非本周」时非本周课不参与泳道分配：否则本周课会被
    // 不可见的课挤成半列宽、留出空白
    final showNonWeek = Storage.showNonWeekCourses();
    final dayCourses = state.courses
        .where((c) => c.weekday == d && (showNonWeek || c.inWeek(week)))
        .toList();
    // 重叠的课分泳道并排；非本周课程同样参与分道，画在下层淡化显示
    final placed = placeInLanes(dayCourses);
    // 消费端聚簇（判定与 placeInLanes 第二遍一致：start ≤ 簇内最大 end 即同簇）
    final clusters = <List<PlacedCourse>>[];
    var clusterMaxEnd = -1;
    for (final p in placed) {
      if (clusters.isEmpty || p.course.startSection > clusterMaxEnd) {
        clusters.add([p]);
        clusterMaxEnd = p.course.endSection;
      } else {
        clusters.last.add(p);
        if (p.course.endSection > clusterMaxEnd) {
          clusterMaxEnd = p.course.endSection;
        }
      }
    }
    final weekBlocks = <Widget>[];
    final fadedBlocks = <Widget>[];
    for (final cluster in clusters) {
      final laneW = dayWidth / cluster.first.lanes;
      // 窄车道（<40dp）收成单列宽卡 + [+N] 徽标，点击走同槽选择 sheet——
      // 物理上没有可读的最小车道宽，收拢是唯一正解
      if (laneW >= 40) {
        for (final p in cluster) {
          final block = _courseBlock(
            context,
            p,
            dayWidth,
            week,
            faded: p.course.inWeek(week) != true,
          );
          if (p.course.inWeek(week)) {
            weekBlocks.add(block);
          } else if (showNonWeek) {
            fadedBlocks.add(block);
          }
        }
        continue;
      }
      // 本周有课的优先当代表；整簇全不在本周才画淡化卡。
      // 簇内其余课不再单独绘制（同区域会叠画），全部收进选择 sheet。
      final inWeekPs = [
        for (final p in cluster)
          if (p.course.inWeek(week)) p,
      ];
      final shown = inWeekPs.isNotEmpty ? inWeekPs : cluster;
      final rep = shown.first;
      final block = _courseBlock(
        context,
        rep,
        dayWidth,
        week,
        faded: inWeekPs.isEmpty,
        clusterCourses: [for (final p in cluster) p.course],
      );
      if (inWeekPs.isNotEmpty) {
        weekBlocks.add(block);
      } else if (showNonWeek) {
        fadedBlocks.add(block);
      }
    }
    return Stack(
      children: [
        if (!isCleanStyle(context))
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _TimetableRulePainter(
                  _timetableStyle(context),
                  paletteOf(context).hairline,
                ),
              ),
            ),
          ),
        // 今日列底色（唯一的底色变化，不再画斑马纹）
        if (isToday)
          Positioned.fill(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 1),
              decoration: BoxDecoration(
                color: _brand(context)
                    .withValues(alpha: isDark(context) ? 0.06 : 0.045),
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ...fadedBlocks,
        ...weekBlocks,
        // 时刻线只画在空档：此刻落在课程块上时线会横穿块面（用户实测
        // 观感很差），课块本身已表达「此刻在上课」，线让位
        if (isToday && !_nowOverCourse(placed, now)) ?_nowLine(context, now),
      ],
    );
  }

  /// 今日列的当前时刻指示线。品牌绿是 tokens 明许场景之一（当前时刻指示线）。
  /// 节次间空档（课间/午休）吸附到下一节顶部；作息表外不画；
  /// 此刻压在课程块上也不画（见 _nowOverCourse）。
  Positioned? _nowLine(BuildContext context, DateTime now) {
    final y = _nowY(now);
    if (y == null) return null;
    return Positioned(
      top: y - 3.5,
      left: 2,
      right: 3,
      child: SizedBox(
        height: 7,
        child: Row(
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: _brand(context),
                shape: BoxShape.circle,
                border: Border.all(color: cardColor(context), width: 1.5),
              ),
            ),
            Expanded(
              child: Center(
                child: Container(height: 2, color: _brand(context)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 当前时刻对应的列内纵向位置；作息表外为 null（与 _nowLine 同一算法）。
  double? _nowY(DateTime now) {
    final m = now.hour * 60 + now.minute;
    int? firstStart;
    int? lastEnd;
    for (var s = 1; s <= _sections; s++) {
      final slot = SectionTimes.slotOf(s);
      if (slot == null) continue;
      firstStart ??= slot.$1;
      lastEnd = slot.$2;
    }
    if (firstStart == null || lastEnd == null) return null;
    if (m < firstStart || m > lastEnd) return null;
    var y = 0.0;
    for (var s = 1; s <= _sections; s++) {
      final slot = SectionTimes.slotOf(s);
      if (slot == null) continue;
      if (m < slot.$1) {
        y = (s - 1) * _rowHeight;
        break;
      }
      if (m <= slot.$2) {
        y =
            (s - 1) * _rowHeight +
            _rowHeight * (m - slot.$1) / (slot.$2 - slot.$1);
        break;
      }
    }
    return y;
  }

  /// 此刻是否落在该列任一课程块的纵向跨度内——是则不画时刻线：
  /// 线画在 Stack 最上层，会横穿课块（包括淡化显示的非本周块）。
  /// 判定用整节跨度而非块的视觉边界：贴着块边的线与穿过一样难看。
  bool _nowOverCourse(List<PlacedCourse> placed, DateTime now) {
    final y = _nowY(now);
    if (y == null) return false;
    return placed.any(
      (p) =>
          y >= (p.course.startSection - 1) * _rowHeight &&
          y <= p.course.endSection * _rowHeight,
    );
  }

  /// 弹出菜单项：灰阶图标容器 + 标题，开关项尾部品牌色勾。
  /// 替换 ListTile/CheckedPopupMenuItem 默认样式——那套组合行高参差、
  /// 开关项文字缩进与普通项不对齐，底色还是 M3 的灰绿，与白卡风格脱节。
  PopupMenuItem<String> _popupItem(
    String value,
    IconData icon,
    String title, {
    bool checked = false,
  }) {
    return PopupMenuItem(
      value: value,
      height: 48,
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: isDark(context)
                  ? Colors.white.withValues(alpha: 0.06)
                  : dividerColor(context),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, size: 18, color: textSecondary(context)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w500,
                color: textPrimary(context),
              ),
            ),
          ),
          if (checked)
            Icon(Icons.check_rounded, size: 20, color: _brand(context)),
        ],
      ),
    );
  }

  Widget _calibrateBanner(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: _brand(context).withValues(alpha: isDark(context) ? 0.12 : 0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline_rounded, size: 15, color: _brand(context)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '不确定是不是本周？设置开学时间即可校准周次',
              style: TextStyle(fontSize: 12, color: textPrimary(context)),
            ),
          ),
          GestureDetector(
            onTap: _pickSemesterStart,
            behavior: HitTestBehavior.opaque,
            child: Container(
              // 点击目标扩到 ≥48dp 高：这是横幅出现时校准周次的唯一可见入口
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 15),
              child: Text(
                '设置',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: _brand(context),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dayHeader(
    BuildContext context,
    int d,
    DateTime? monday,
    DateTime now,
    bool isCurrentWeek,
  ) {
    final isToday = isCurrentWeek && now.weekday == d;
    final dateText = monday == null
        ? ''
        : '${monday.add(Duration(days: d - 1)).day}';
    if (!isCleanStyle(context)) {
      final p = paletteOf(context);
      final mono = p.pixel || p.receipt || p.terminal;
      final dateFirst = p.editorial || p.paper || p.journal;
      final fg = isToday ? p.accent : p.ink2;
      final day = Text(
        p.terminal ? '[${_weekdayNames[d - 1]}]' : '周${_weekdayNames[d - 1]}',
        maxLines: 1,
        style: TextStyle(
          fontSize: 10,
          height: 1.1,
          fontFamily: mono
              ? 'monospace'
              : p.paper
              ? 'serif'
              : null,
          fontWeight: isToday ? FontWeight.w800 : FontWeight.w500,
          color: fg,
        ),
      );
      final date = Container(
        constraints: const BoxConstraints(minWidth: 20),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
        decoration: BoxDecoration(
          color: isToday && !p.editorial ? p.accentFill : null,
          border: isToday && (p.journal || p.comic)
              ? Border.all(color: p.ink, width: 1)
              : null,
          borderRadius: BorderRadius.circular(
            p.pixel || p.receipt || p.terminal || p.inkWash
                ? 1
                : p.morandi
                ? 99
                : 4,
          ),
        ),
        child: Text(
          dateText.isEmpty ? '·' : dateText,
          style: TextStyle(
            fontSize: p.editorial ? 17 : 13,
            height: 1.0,
            fontFamily: mono
                ? 'monospace'
                : p.paper || p.inkWash
                ? 'serif'
                : null,
            fontWeight: FontWeight.w700,
            color: isToday && !p.editorial ? p.onAccent : p.ink,
          ),
        ),
      );
      return Container(
        alignment: Alignment.center,
        margin: const EdgeInsets.symmetric(horizontal: 1),
        decoration: BoxDecoration(
          color: p.pixel || p.terminal ? p.ink.withValues(alpha: .05) : null,
          border: p.editorial || p.paper || p.receipt || p.journal
              ? Border(
                  bottom: BorderSide(
                    color: isToday ? p.accent : p.cardBorder,
                    width: isToday ? 2 : 1,
                  ),
                )
              : null,
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (dateFirst) date else day,
              const SizedBox(height: 2),
              if (dateFirst) day else date,
            ],
          ),
        ),
      );
    }
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '周${_weekdayNames[d - 1]}',
            style: TextStyle(
              fontSize: 11,
              fontWeight: isToday ? FontWeight.w700 : FontWeight.w500,
              color: isToday ? _brand(context) : textSecondary(context),
            ),
          ),
          const SizedBox(height: 2),
          if (dateText.isNotEmpty)
            Container(
              width: 22,
              height: 20,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: isToday ? paletteOf(context).accentFill : null,
                shape: BoxShape.circle,
              ),
              child: Text(
                dateText,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  height: 1.0,
                  color: isToday
                      ? paletteOf(context).onAccent
                      : textPrimary(context),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _gutterCell(BuildContext context, int s) {
    // 契约：表外节次（网格固定 16 节、常见作息表 12 节）取不到时刻，
    // 沟槽显示「—」而不是钳位来的假时刻——钳位会把晚课标成 21:45 误导用户
    final startM = SectionTimes.slotOf(s)?.$1;
    String two(int n) => n.toString().padLeft(2, '0');
    final style = _timetableStyle(context);
    final p = paletteOf(context);
    return Container(
      height: _rowHeight,
      decoration: isCleanStyle(context)
          ? null
          : BoxDecoration(
              color: p.pixel || p.terminal
                  ? p.ink.withValues(alpha: .04)
                  : null,
              border: p.paper || p.journal || p.receipt || p.editorial
                  ? Border(
                      right: BorderSide(color: p.cardBorder),
                      bottom: BorderSide(color: p.hairline),
                    )
                  : null,
            ),
      alignment: Alignment.center,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              p.pixel || p.terminal ? s.toString().padLeft(2, '0') : '$s',
              style: TextStyle(
                fontSize: p.editorial ? 14 : 10.5,
                fontFamily: p.pixel || p.terminal || p.receipt
                    ? 'monospace'
                    : style == ThemeStyle.paper
                    ? 'serif'
                    : null,
                fontWeight: p.editorial ? FontWeight.w800 : FontWeight.w600,
                color: textSecondary(context),
              ),
            ),
            Text(
              startM == null ? '—' : '${startM ~/ 60}:${two(startM % 60)}',
              // 小票：时刻列是打印时刻表
              style: monoText(
                context,
                TextStyle(fontSize: 8.5, color: textFaint(context)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _courseBlock(
    BuildContext context,
    PlacedCourse p,
    double dayWidth,
    int week, {
    required bool faded,
    List<Course>? clusterCourses,
  }) {
    final c = p.course;
    final custom = Storage.courseColors()[c.name];
    final accent = Tokens.courseColor(c.name, override: custom);
    // 水墨：课程块是「墨块」——浓淡按课程名哈希分五档（墨分五色），
    // 课与课靠墨阶深浅区分，字用焦墨/白墨，整张课表保持黑白灰。
    // 漫画：色块保留，但加贴纸剪影描边。
    final inkBlock = isInkStyle(context);
    final blockFg = inkBlock
        ? (isDark(context) ? const Color(0xFFEDEAE2) : const Color(0xFF161613))
        : Colors.white;
    final blockColor = inkBlock
        ? (isDark(context) ? Colors.white : Colors.black).withValues(
            alpha: 0.10 + (stableHash(c.name) % 5) * 0.045,
          )
        : accent;
    final collapsed = clusterCourses != null && clusterCourses.length > 1;
    final occupied = collapsed ? clusterCourses : [c];
    final firstSection = occupied
        .map((e) => e.startSection)
        .reduce((a, b) => a < b ? a : b);
    final lastSection = occupied
        .map((e) => e.endSection)
        .reduce((a, b) => a > b ? a : b);
    final span = (lastSection - firstSection + 1).clamp(1, _sections);
    // 仅 1 节的收拢卡（49px 高）放不下「课名+教室+徽标」三行，退化为
    // 徽标内联在课名行尾、不显示教室；≥2 节的收拢卡三行全展示，
    // 徽标独占最后一行，不和课名抢宽度。
    final inlineBadge = collapsed && span <= 1;
    final laneW = collapsed ? dayWidth : dayWidth / p.lanes;
    final textScale = laneW < 44 ? 0.85 : 1.0;
    // 动态行数兜底：矮卡片装不下固定 4 行，按高度算
    final innerH = span * _rowHeight - 3 - 8;
    final nameLineH = 11 * textScale * 1.25;
    final chipLineH = collapsed && !inlineBadge ? 13.0 : 0.0;
    final roomLineH = c.room.isEmpty || inlineBadge
        ? 0.0
        : 9 * textScale * 1.2 + 2;
    final nameMax = ((innerH - roomLineH - chipLineH) / nameLineH)
        .floor()
        .clamp(1, 4);
    Widget badge() => Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: blockFg.withValues(alpha: 0.20),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '+${clusterCourses!.length - 1}',
        style: TextStyle(
          fontSize: 8.5,
          height: 1.2,
          fontWeight: FontWeight.w800,
          color: blockFg,
        ),
      ),
    );
    // 满色块课程卡：整卡 = 课程强调色，白字（超课式；色板统一 700 档
    // 深度，白字对比度全部 ≥4.5:1，见 tokens.dart coursePalette）；
    // 水墨下整卡 = 墨块 + 焦墨/白墨字
    final nameStyle = TextStyle(
      fontSize: 11 * textScale,
      height: 1.25,
      fontWeight: FontWeight.w700,
      fontFamily:
          isPixelStyle(context) ||
              isTerminalStyle(context) ||
              isReceiptStyle(context)
          ? 'monospace'
          : isPaperStyle(context) ||
                isInkStyle(context) ||
                isEditorialStyle(context)
          ? 'serif'
          : null,
      color: blockFg,
    );
    final style = _timetableStyle(context);
    final blockRadius = switch (style) {
      ThemeStyle.pixel ||
      ThemeStyle.receipt ||
      ThemeStyle.editorial ||
      ThemeStyle.terminal => BorderRadius.circular(1),
      ThemeStyle.morandi => BorderRadius.circular(13),
      ThemeStyle.amoled => brushRadiusOf(context, 8),
      ThemeStyle.paper => BorderRadius.circular(3),
      ThemeStyle.journal => const BorderRadius.only(
        topLeft: Radius.circular(3),
        topRight: Radius.circular(9),
        bottomLeft: Radius.circular(3),
        bottomRight: Radius.circular(9),
      ),
      _ => BorderRadius.circular(8),
    };
    final inner = Material(
      color: blockColor,
      shape: isComicStyle(context)
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: BorderSide(
                color: paletteOf(context).cardBorder,
                width: 1.3,
              ),
            )
          : isPixelStyle(context)
          ? const _SteppedCourseShape()
          : null,
      borderRadius: isComicStyle(context) || isPixelStyle(context)
          ? null
          : blockRadius,
      clipBehavior: Clip.hardEdge,
      elevation: isDark(context) ? 0 : 1,
      shadowColor: Colors.black26,
      child: InkWell(
        borderRadius: blockRadius,
        onTap: () => collapsed
            ? _showClusterSheet(clusterCourses, week)
            : _showCourseSheet(c, week),
        onLongPress: () => _showColorSheet(c),
        child: CustomPaint(
          painter: _CourseMaterialPainter(style, blockFg),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(6, 4, 4, 3),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Flexible(
                  child: inlineBadge
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(
                              child: Text(
                                c.name,
                                maxLines: nameMax,
                                overflow: TextOverflow.ellipsis,
                                style: nameStyle,
                              ),
                            ),
                            const SizedBox(width: 3),
                            badge(),
                          ],
                        )
                      : Text(
                          c.name,
                          maxLines: nameMax,
                          overflow: TextOverflow.ellipsis,
                          style: nameStyle,
                        ),
                ),
                // 教室用 FittedBox 整体缩放：格子再窄也完整一行展示，不省略不断行
                if (c.room.isNotEmpty && !inlineBadge)
                  Flexible(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          c.room,
                          maxLines: 1,
                          style: TextStyle(
                            fontSize: 9 * textScale,
                            height: 1.2,
                            color: blockFg.withValues(alpha: 0.8),
                          ),
                        ),
                      ),
                    ),
                  ),
                if (collapsed && !inlineBadge) ...[
                  const SizedBox(height: 2),
                  badge(),
                ],
              ],
            ),
          ),
        ),
      ),
    );
    // Positioned 必须是 Stack 的直接子级；淡化效果包在 child 里
    return Positioned(
      top: (firstSection - 1) * _rowHeight + 1.5,
      height: span * _rowHeight - 3,
      left: collapsed ? 1.5 : p.lane * laneW + 1.5,
      width: laneW - 3,
      child: faded ? Opacity(opacity: 0.45, child: inner) : inner,
    );
  }

  /// 窄车道收拢后的同槽选择：列簇内全部课程，选中进现有详情（编辑/删除），
  /// 长按进换色。居中弹窗，不再用底部弹层。
  void _showClusterSheet(List<Course> courses, int week) {
    showDialog(
      context: context,
      builder: (dialogContext) => ThemedDialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420, maxHeight: 480),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
                child: ThemeEditorHeading(
                  title: '本时段有 ${courses.length} 门课，选择查看',
                  kicker: 'COURSE CHOICES',
                  icon: Icons.layers_outlined,
                ),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(8, 4, 8, 10),
                  children: [
                    for (final c in courses)
                      ListTile(
                        dense: true,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        title: Text(
                          c.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          [
                            '第${c.startSection}-${c.endSection}节',
                            if (c.room.isNotEmpty) c.room,
                            if (!c.inWeek(week)) '非本周',
                          ].join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: const Icon(
                          Icons.chevron_right_rounded,
                          size: 20,
                        ),
                        onTap: () {
                          Navigator.of(dialogContext).pop();
                          _showCourseSheet(c, week);
                        },
                        onLongPress: () {
                          Navigator.of(dialogContext).pop();
                          _showColorSheet(c);
                        },
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SteppedCourseShape extends ShapeBorder {
  const _SteppedCourseShape();

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.zero;

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) {
    final step = (rect.shortestSide / 4).clamp(0.0, 3.0);
    return Path()
      ..moveTo(rect.left + step, rect.top)
      ..lineTo(rect.right - step, rect.top)
      ..lineTo(rect.right - step, rect.top + step)
      ..lineTo(rect.right, rect.top + step)
      ..lineTo(rect.right, rect.bottom - step)
      ..lineTo(rect.right - step, rect.bottom - step)
      ..lineTo(rect.right - step, rect.bottom)
      ..lineTo(rect.left + step, rect.bottom)
      ..lineTo(rect.left + step, rect.bottom - step)
      ..lineTo(rect.left, rect.bottom - step)
      ..lineTo(rect.left, rect.top + step)
      ..lineTo(rect.left + step, rect.top + step)
      ..close();
  }

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      getOuterPath(rect, textDirection: textDirection);

  @override
  ShapeBorder scale(double t) => this;

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {}
}

/// Decorative surfaces live behind content and never participate in layout or
/// gestures. Course colors and text contrast remain the user's chosen palette.
class _CourseMaterialPainter extends CustomPainter {
  const _CourseMaterialPainter(this.style, this.ink);
  final ThemeStyle style;
  final Color ink;

  @override
  void paint(Canvas canvas, Size size) {
    if (style == ThemeStyle.clean ||
        style == ThemeStyle.green ||
        size.isEmpty) {
      return;
    }
    // A wash behind white course text may only darken the course fill, so a
    // custom color keeps at least its original text contrast.
    final faint = Paint()
      ..color = (ink == Colors.white ? Colors.black : ink).withValues(
        alpha: .14,
      );
    final line = Paint()
      ..color = ink.withValues(alpha: .42)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    void dash(double y, {double inset = 3}) {
      for (var x = inset; x < size.width - inset; x += 5) {
        canvas.drawLine(
          Offset(x, y),
          Offset((x + 2).clamp(0, size.width - inset), y),
          line,
        );
      }
    }

    switch (style) {
      case ThemeStyle.morandi:
        canvas.drawOval(
          Rect.fromLTWH(size.width * .4, -12, size.width, 30),
          faint,
        );
        canvas.drawCircle(Offset(size.width - 7, size.height - 7), 3, faint);
      case ThemeStyle.pixel:
        canvas.drawRect(
          Rect.fromLTWH(0, 0, size.width, 2),
          Paint()..color = Colors.black.withValues(alpha: .3),
        );
        for (var x = 3.0; x < size.width - 3; x += 6) {
          canvas.drawRect(Rect.fromLTWH(x, size.height - 5, 3, 2), faint);
        }
        canvas.drawLine(Offset(1, 3), Offset(1, size.height - 3), line);
      case ThemeStyle.amoled:
        for (var i = 0; i < 4; i++) {
          canvas.drawLine(
            Offset(size.width - 3 - i, 4 + i * 3),
            Offset(size.width - 3 - i, size.height - 9 - i * 2),
            Paint()..color = ink.withValues(alpha: .04 + i * .015),
          );
        }
      case ThemeStyle.paper:
        dash(3);
        dash(size.height - 3);
        canvas.drawLine(const Offset(3, 6), Offset(3, size.height - 6), faint);
      case ThemeStyle.comic:
        for (var y = size.height - 18; y < size.height; y += 5) {
          for (var x = size.width - 13; x < size.width; x += 5) {
            canvas.drawCircle(Offset(x, y), .8, faint);
          }
        }
        canvas.drawLine(
          Offset(size.width - 8, 3),
          Offset(size.width - 3, 7),
          line,
        );
      case ThemeStyle.receipt:
        dash(3);
        dash(size.height - 7);
        for (var x = 3.0; x < size.width - 3; x += 3) {
          canvas.drawRect(
            Rect.fromLTWH(x, size.height - 4, x % 2 == 0 ? 1 : 2, 2),
            faint,
          );
        }
      case ThemeStyle.editorial:
        canvas.drawRect(
          Rect.fromLTWH(0, 0, 2, size.height),
          Paint()..color = ink.withValues(alpha: .4),
        );
        canvas.drawLine(
          Offset(6, size.height - 4),
          Offset(size.width - 4, size.height - 4),
          line,
        );
      case ThemeStyle.terminal:
        final bracket = Path()
          ..moveTo(5, 2)
          ..lineTo(2, 2)
          ..lineTo(2, 9)
          ..moveTo(size.width - 5, size.height - 2)
          ..lineTo(size.width - 2, size.height - 2)
          ..lineTo(size.width - 2, size.height - 9);
        canvas.drawPath(bracket, line);
        canvas.drawRect(
          Rect.fromLTWH(size.width - 8, size.height - 5, 3, 1),
          Paint()..color = ink,
        );
      case ThemeStyle.journal:
        for (var y = 20.0; y < size.height - 3; y += 15) {
          canvas.drawLine(Offset(4, y), Offset(size.width - 3, y), faint);
        }
        canvas.drawRect(
          Rect.fromLTWH(size.width * .25, 0, size.width * .5, 3),
          faint,
        );
        canvas.drawCircle(Offset(size.width - 7, size.height - 7), 3, line);
      case ThemeStyle.clean:
      case ThemeStyle.green:
        break;
    }
  }

  @override
  bool shouldRepaint(_CourseMaterialPainter oldDelegate) =>
      oldDelegate.style != style || oldDelegate.ink != ink;
}

class _TimetableRulePainter extends CustomPainter {
  const _TimetableRulePainter(this.style, this.color);
  final ThemeStyle style;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = .6;
    for (var section = 1; section <= _sections; section++) {
      final y = section * _rowHeight;
      if (style == ThemeStyle.receipt || style == ThemeStyle.terminal) {
        for (var x = 2.0; x < size.width - 2; x += 5) {
          canvas.drawLine(
            Offset(x, y),
            Offset((x + 2).clamp(0, size.width), y),
            paint,
          );
        }
      } else if (style == ThemeStyle.paper ||
          style == ThemeStyle.journal ||
          style == ThemeStyle.editorial ||
          style == ThemeStyle.pixel) {
        canvas.drawLine(Offset(1, y), Offset(size.width - 1, y), paint);
      }
    }
    if (style == ThemeStyle.pixel || style == ThemeStyle.terminal) {
      canvas.drawLine(const Offset(0, 0), Offset(0, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(_TimetableRulePainter oldDelegate) =>
      oldDelegate.style != style || oldDelegate.color != color;
}
