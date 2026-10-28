/// 首页：作业列表。倒计时按紧迫度分级着色（红→橙→琥珀→灰），已完成绿色；
/// 各样式保留自己的分组标题。视图：按时间分段（默认）/ 按课程分组；
/// 支持搜索、状态筛选与列表滑动切换；删除或隐藏通过长按操作。
library;

import 'package:flutter/material.dart';

import '../ui/activity_icon.dart';

import 'dart:async';

import '../app_state.dart';
import '../models/homework.dart';
import '../models/homework_draft.dart';
import '../services/stable_hash.dart';
import '../services/storage.dart';
import '../ui/adaptive.dart';
import '../ui/hw_card.dart';
import '../ui/focus_parts.dart';
import '../ui/ink_wash.dart';
import '../ui/receipt_tear.dart';
import '../ui/style_background.dart';
import '../ui/tokens.dart';
import '../ui/theme_forms.dart';
import '../ui/themed_masthead.dart';
import '../ui/study_overview.dart';
import '../ui/sync_status_parts.dart';
import 'background_sync_settings_page.dart';
import 'detail_page.dart';
import 'homework_edit_dialogs.dart';
import 'homework_recognition_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.state, required this.onGoAccounts});

  final AppState state;
  final VoidCallback onGoAccounts;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with SingleTickerProviderStateMixin {
  static const _filters = ['todo', 'submitted', 'done', 'all'];
  String _filter = 'todo';
  bool _todayOnly = false;
  final _filterScroll = ScrollController();
  final _filterViewportKey = GlobalKey();
  final _filterKeys = {for (final value in _filters) value: GlobalKey()};
  late final AnimationController _filterTransition;
  late final CurvedAnimation _filterCurve;
  late final Animation<double> _filterOpacity;
  late Animation<Offset> _filterSlide;
  double _horizontalDrag = 0;

  /// 'time' 按截止时间分段；'course' 按课程分组
  String _sort = 'time';
  bool _searching = false;
  final _searchCtrl = TextEditingController();
  String _query = '';

  /// 倒计时/已截止状态依赖 build 时刻的 DateTime.now()，没有定时重建的话
  /// 停留页面时信息会变陈旧（跨过截止点也不翻转）
  Timer? _clock;

  /// 小票撕纸动画句柄，按作业 id 缓存（key 稳定，动画中列表重建不打断）
  final Map<String, GlobalKey<ReceiptTearOutState>> _tearKeys = {};

  /// 正在撕的作业（防重复触发）
  final Set<String> _tearing = {};
  @override
  void initState() {
    super.initState();
    _filterTransition = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
      value: 1,
    );
    _filterCurve = CurvedAnimation(
      parent: _filterTransition,
      curve: Curves.easeOutCubic,
    );
    _filterOpacity = Tween<double>(begin: .72, end: 1).animate(_filterCurve);
    _filterSlide = Tween<Offset>(
      begin: Offset.zero,
      end: Offset.zero,
    ).animate(_filterCurve);
    _sort = Storage.sortMode();
    _searchCtrl.addListener(
      () => setState(() => _query = _searchCtrl.text.trim()),
    );
    _clock = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    _searchCtrl.dispose();
    _filterScroll.dispose();
    _filterCurve.dispose();
    _filterTransition.dispose();
    super.dispose();
  }

  void _selectFilter(String value, {bool todayOnly = false}) {
    if (_filter == value && _todayOnly == todayOnly) return;
    final direction = _filters.indexOf(value) - _filters.indexOf(_filter);
    setState(() {
      _filter = value;
      _todayOnly = todayOnly;
      _filterSlide = Tween<Offset>(
        begin: Offset(direction >= 0 ? -.035 : .035, 0),
        end: Offset.zero,
      ).animate(_filterCurve);
    });
    if (MediaQuery.disableAnimationsOf(context)) {
      _filterTransition.value = 1;
    } else {
      _filterTransition.forward(from: 0);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _revealFilter(value));
  }

  void _revealFilter(String value) {
    if (!mounted || !_filterScroll.hasClients || _filter != value) return;
    final viewport = _filterViewportKey.currentContext?.findRenderObject();
    final selected = _filterKeys[value]?.currentContext?.findRenderObject();
    if (viewport is! RenderBox ||
        selected is! RenderBox ||
        !viewport.hasSize ||
        !selected.hasSize) {
      return;
    }
    final left = viewport.globalToLocal(selected.localToGlobal(Offset.zero)).dx;
    final right = left + selected.size.width;
    final adjustment = left < 8
        ? left - 8
        : right > viewport.size.width - 8
        ? right - viewport.size.width + 8
        : 0.0;
    if (adjustment == 0) return;
    final position = _filterScroll.position;
    final target = (position.pixels + adjustment).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if (MediaQuery.disableAnimationsOf(context)) {
      _filterScroll.jumpTo(target);
    } else {
      _filterScroll.animateTo(
        target,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    }
  }

  Widget _swipeFilterArea(Widget child) => GestureDetector(
    behavior: HitTestBehavior.translucent,
    onHorizontalDragStart: (_) => _horizontalDrag = 0,
    onHorizontalDragUpdate: (details) => _horizontalDrag += details.delta.dx,
    onHorizontalDragEnd: (details) {
      final distance = _horizontalDrag;
      final velocity = details.primaryVelocity ?? 0;
      if (distance.abs() < 48 &&
          (distance.abs() < 16 || velocity.abs() < 600)) {
        return;
      }
      final direction = distance > 0 ? 1 : -1;
      final next = (_filters.indexOf(_filter) + direction).clamp(
        0,
        _filters.length - 1,
      );
      _selectFilter(_filters[next]);
    },
    child: child,
  );

  Widget _animateFilterContent(Widget child) => FadeTransition(
    opacity: _filterOpacity,
    child: SlideTransition(position: _filterSlide, child: child),
  );

  bool _isDone(HomeworkItem hw) => hwIsDone(hw);
  bool _isOverdue(HomeworkItem hw) => hwIsOverdue(hw);

  String _dateLine() {
    final now = DateTime.now();
    const weeks = ['一', '二', '三', '四', '五', '六', '日'];
    return '${now.month}月${now.day}日 · 周${weeks[now.weekday - 1]}';
  }

  /// 旧学期作业没有跟进意义，列表固定只看当前学期
  bool _inSemester(HomeworkItem hw) => hw.inCurrentSemester;

  bool _matchQuery(HomeworkItem hw) {
    if (_query.isEmpty) return true;
    final q = _query.toLowerCase();
    return hw.title.toLowerCase().contains(q) ||
        hw.course.toLowerCase().contains(q) ||
        (hw.note?.toLowerCase().contains(q) ?? false);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.state,
    builder: (context, _) => _buildPage(context),
  );

  Widget _buildPage(BuildContext context) {
    final state = widget.state;
    return StyleBackground(
      // 带底衬的样式下透明化 Scaffold，露出主题底衬
      //（2026-10-05 复盘：不透明底色曾把莫兰迪色雾/像素点阵整个盖住）
      child: Scaffold(
        backgroundColor: scaffoldBgOf(context),
        body: SafeArea(
          bottom: false,
          child: RefreshIndicator(
            color: accentColor(context),
            backgroundColor: cardColor(context),
            onRefresh: () => state.syncAll(),
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(child: _buildHeader(state)),
                SliverToBoxAdapter(child: _buildOverview(state)),
                if (_searching) SliverToBoxAdapter(child: _buildSearchBar()),
                if (state.syncing)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                      child: SyncProgressNotice(
                        busy: true,
                        progress: state.syncProgress,
                      ),
                    ),
                  ),
                if (state.hasAnyAccount || state.homework.isNotEmpty)
                  PinnedHeaderSliver(
                    child: Material(
                      color: bgColor(context),
                      child: _buildFilters(),
                    ),
                  ),
                if (!state.syncing && state.lastSyncMessage.isNotEmpty)
                  SliverToBoxAdapter(child: _warnBanner(state.lastSyncMessage)),
                _buildList(context, state),
              ],
            ),
          ),
        ),
      ),
    );
  }

  BoxDecoration? _actionDecoration({bool primary = false}) {
    final p = paletteOf(context);
    if (p.clean && !primary) return null;
    final square = p.pixel || p.editorial || p.terminal || p.receipt;
    return BoxDecoration(
      color: primary ? p.accentFill : p.card,
      borderRadius: BorderRadius.circular(
        p.clean
            ? 12
            : square
            ? 2
            : p.morandi
            ? 22
            : p.comic
            ? 10
            : 6,
      ),
      border: p.clean || p.morandi
          ? null
          : Border.all(
              color: p.inkWash ? p.ink.withValues(alpha: 0.12) : p.cardBorder,
              width: p.comic || p.pixel ? 1.5 : 1,
            ),
      boxShadow: p.comic || p.pixel
          ? [BoxShadow(color: p.cardBorder, offset: const Offset(2, 2))]
          : null,
    );
  }

  Widget _iconBtn({
    Widget? child,
    IconData? icon,
    VoidCallback? onTap,
    Color? color,
    String? tooltip,
    bool primary = false,
  }) {
    final decoration = _actionDecoration(primary: primary);
    return SizedBox.square(
      dimension: 48,
      child: DecoratedBox(
        decoration: decoration ?? const BoxDecoration(),
        child: IconButton(
          onPressed: onTap,
          icon: child ?? Icon(icon, size: 22),
          color: color,
          tooltip: tooltip,
          style: IconButton.styleFrom(
            fixedSize: const Size.square(48),
            padding: EdgeInsets.zero,
            visualDensity: VisualDensity.standard,
            shape: RoundedRectangleBorder(
              borderRadius:
                  decoration?.borderRadius ?? BorderRadius.circular(12),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(AppState state) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          if (isInkStyle(context))
            const Positioned(
              top: -14,
              left: -20,
              right: -20,
              child: InkMountains(height: 110),
            ),
          Row(
            children: [
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: ThemedMasthead(dateLine: _dateLine()),
                  ),
                ),
              ),
              _iconBtn(
                icon: _searching
                    ? Icons.search_off_rounded
                    : Icons.search_rounded,
                color: _searching
                    ? accentColor(context)
                    : textSecondary(context),
                tooltip: _searching ? '关闭搜索' : '搜索作业',
                onTap: () => setState(() {
                  _searching = !_searching;
                  if (!_searching) _searchCtrl.clear();
                }),
              ),
              const SizedBox(width: 8),
              _iconBtn(
                child: ActivityIcon(
                  Icons.refresh_rounded,
                  active: state.syncing,
                  size: 22,
                ),
                tooltip: '同步作业',
                onTap: state.syncing ? null : () => state.syncAll(),
                color: state.syncing
                    ? textFaint(context)
                    : accentColor(context),
              ),
              const SizedBox(width: 8),
              _iconBtn(
                tooltip: '添加作业',
                onTap: () => _openAddMenu(context),
                primary: true,
                color: paletteOf(context).onAccent,
                icon: Icons.add_rounded,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSortMenu() => Container(
    decoration: _actionDecoration(),
    child: PopupMenuButton<String>(
      tooltip: '排序方式',
      color: modalColor(context),
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      position: PopupMenuPosition.under,
      offset: const Offset(0, 8),
      icon: Icon(
        Icons.sort_rounded,
        size: 21,
        color: _sort == 'course'
            ? accentColor(context)
            : textSecondary(context),
      ),
      onSelected: (value) => setState(() {
        _sort = value;
        Storage.saveSortMode(value);
      }),
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'time',
          child: _menuRow(
            icon: Icons.schedule_rounded,
            color: accentColor(context),
            title: '按截止时间',
            subtitle: '分成今天/本周等段落',
            value: 'time',
          ),
        ),
        PopupMenuItem(
          value: 'course',
          child: _menuRow(
            icon: Icons.category_rounded,
            color: accentColor(context),
            title: '按课程分组',
            subtitle: '同一门课的作业放在一起',
            value: 'course',
          ),
        ),
      ],
    ),
  );

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 2),
      child: TextField(
        controller: _searchCtrl,
        autofocus: true,
        style: TextStyle(fontSize: 14.5, color: textPrimary(context)),
        decoration: InputDecoration(
          hintText: '搜索作业标题、课程或备注…',
          hintStyle: TextStyle(fontSize: 13.5, color: textFaint(context)),
          prefixIcon: const Icon(Icons.search_rounded, size: 20),
          isDense: true,
          filled: true,
          fillColor: cardColor(context),
          contentPadding: const EdgeInsets.symmetric(vertical: 10),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }

  Widget _buildOverview(AppState state) {
    final now = DateTime.now();
    final pending = state.homework
        .where(_inSemester)
        .where((hw) => !_isDone(hw));
    final today = pending.where((hw) {
      final d = hw.dueAt;
      return d != null &&
          d.year == now.year &&
          d.month == now.month &&
          d.day == now.day;
    }).length;
    if (today > 0) return const SizedBox.shrink();
    return StudyOverview(
      pending: pending.length,
      today: today,
      todaySelected: _todayOnly,
      onPendingTap: () => _selectFilter('todo'),
      onTodayTap: () => _selectFilter('todo', todayOnly: !_todayOnly),
    );
  }

  Widget _buildFilters() {
    final filters = SingleChildScrollView(
      key: _filterViewportKey,
      controller: _filterScroll,
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(20, 4, 0, 4),
      child: Row(
        children: [
          _pill('未完成', 'todo'),
          const SizedBox(width: 8),
          _pill('已提交', 'submitted'),
          const SizedBox(width: 8),
          _pill('已完成', 'done'),
          const SizedBox(width: 8),
          _pill('全部', 'all'),
        ],
      ),
    );
    return Row(
      children: [
        Expanded(child: filters),
        _buildSortMenu(),
        const SizedBox(width: 12),
      ],
    );
  }

  Widget _pill(String label, String value) {
    final selected = _filter == value;
    final p = paletteOf(context);

    return Semantics(
      button: true,
      selected: selected,
      child: AnimatedContainer(
        key: _filterKeys[value],
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        margin: const EdgeInsets.only(right: 12),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: selected ? p.accentFill : Colors.transparent,
              width: 3,
            ),
          ),
        ),
        child: TextButton(
          onPressed: () => _selectFilter(value),
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
            foregroundColor: selected ? p.ink : p.ink2,
            minimumSize: const Size(48, 48),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
              if (value == 'todo') ...[
                const SizedBox(width: 4),
                Text(
                  '${widget.state.homework.where(_inSemester).where((h) => !_isDone(h)).length}',
                  style: const TextStyle(fontSize: 12),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildList(BuildContext context, AppState state) {
    if (!state.hasAnyAccount && state.homework.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: _empty(
          icon: Icons.link_rounded,
          title: '还没有绑定账号',
          subtitle: '点 + 添加手动作业，也可绑定平台自动同步',
          action: FilledButton(
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 14),
            ),
            onPressed: widget.onGoAccounts,
            child: const Text('去绑定账号'),
          ),
        ),
      );
    }

    var filtered = state.homework.where(_inSemester).where(_matchQuery).where((
      hw,
    ) {
      if (_todayOnly) {
        final due = hw.dueAt;
        final now = DateTime.now();
        if (_isDone(hw) ||
            due == null ||
            due.year != now.year ||
            due.month != now.month ||
            due.day != now.day) {
          return false;
        }
      }
      return switch (_filter) {
        'todo' => !_isDone(hw),
        'submitted' => hw.status == HwStatus.submitted,
        'done' => hw.status == HwStatus.done,
        _ => true,
      };
    }).toList()..sort(_byDue);

    if (filtered.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: _swipeFilterArea(
          _animateFilterContent(
            _empty(
              icon: state.syncing
                  ? Icons.hourglass_top_rounded
                  : _query.isNotEmpty
                  ? Icons.search_off_rounded
                  : Icons.task_alt_rounded,
              title: state.syncing
                  ? '正在同步…'
                  : _query.isNotEmpty
                  ? '没有匹配「$_query」的作业'
                  : _todayOnly
                  ? '今天没有待完成的截止作业'
                  : '这里空空的',
              subtitle: state.syncing
                  ? '第一次同步要拉取全部课程，稍等片刻'
                  : _query.isEmpty
                  ? (_todayOnly ? '点待完成数量或任意状态标签，查看其他作业' : '点 + 可以手动添加作业')
                  : null,
            ),
          ),
        ),
      );
    }

    if (_sort == 'time') {
      return _focusList(filtered);
    }

    final groups = <String, List<HomeworkItem>>{};
    for (final hw in filtered) {
      groups
          .putIfAbsent(
            hw.course.trim().isEmpty ? '其他课程' : hw.course.trim(),
            () => [],
          )
          .add(hw);
    }
    final entries = groups.entries.toList()
      ..sort((a, b) => _earliest(a.value).compareTo(_earliest(b.value)));
    return _homeSections([
      for (final e in entries) (e.key, e.value),
    ], courseHeaders: true);
  }

  Widget _focusList(List<HomeworkItem> filtered) {
    final n = DateTime.now();
    bool today(HomeworkItem h) =>
        !_isDone(h) && h.dueAt != null && DateUtils.isSameDay(h.dueAt, n);
    final urgent = filtered.where(today).toList();
    final rest = filtered.where((h) => !today(h)).toList();
    return _homeSections([
      ('已截止', rest.where((h) => !_isDone(h) && _isOverdue(h)).toList()),
      ('接下来', rest.where((h) => !_isDone(h) && !_isOverdue(h)).toList()),
      ('已提交', rest.where((h) => h.status == HwStatus.submitted).toList()),
      (
        '已完成',
        rest
            .where((h) => h.status != HwStatus.submitted && _isDone(h))
            .toList(),
      ),
    ], urgent: urgent);
  }

  Widget _lazyRows(
    List<HomeworkItem> rows, {
    bool priority = false,
    bool showCourse = true,
  }) {
    final indexes = {
      for (var i = 0; i < rows.length; i++)
        ValueKey('home-row-${rows[i].id}'): i,
    };
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, i) => Padding(
          key: ValueKey('home-row-${rows[i].id}'),
          padding: EdgeInsets.only(bottom: priority ? 0 : 10),
          child: _swipeFilterArea(
            _animateFilterContent(
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (priority)
                    Divider(
                      height: 1,
                      thickness: .5,
                      indent: 15,
                      endIndent: 15,
                      color: paletteOf(context).onAccent.withValues(alpha: .12),
                    ),
                  _hwRow(rows[i], priority: priority, showCourse: showCourse),
                ],
              ),
            ),
          ),
        ),
        childCount: rows.length,
        findChildIndexCallback: (key) => indexes[key],
      ),
    );
  }

  Widget _todayHeader(int count) {
    final p = paletteOf(context);
    final header = Tooltip(
      message: '今天截止 $count 项',
      child: InkWell(
        onTap: () => _selectFilter('todo', todayOnly: !_todayOnly),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(15, 12, 15, 10),
          child: Row(
            children: [
              Icon(Icons.schedule_outlined, size: 20, color: p.onAccent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '今天截止',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: p.onAccent,
                  ),
                ),
              ),
              Text(
                '$count 项',
                style: TextStyle(fontSize: 12, color: p.onAccent),
              ),
              const SizedBox(width: 8),
              Text(
                _todayOnly ? '已筛选' : '筛选',
                style: TextStyle(
                  fontSize: 12,
                  color: p.onAccent,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Icon(Icons.filter_list_rounded, size: 18, color: p.onAccent),
            ],
          ),
        ),
      ),
    );
    return p.journal
        ? Stack(
            clipBehavior: Clip.none,
            children: [
              header,
              Positioned(
                top: -5,
                right: 16,
                child: ExcludeSemantics(
                  child: journalTape(context, 'workbench', width: 46),
                ),
              ),
            ],
          )
        : header;
  }

  Widget _homeSections(
    List<(String, List<HomeworkItem>)> groups, {
    List<HomeworkItem> urgent = const [],
    bool courseHeaders = false,
  }) {
    final p = paletteOf(context);
    Widget? priority;
    if (urgent.isNotEmpty) {
      priority = DecoratedSliver(
        decoration: workbenchDecoration(context, accent: true),
        sliver: SliverMainAxisGroup(
          slivers: [
            SliverToBoxAdapter(
              child: _swipeFilterArea(
                _animateFilterContent(_todayHeader(urgent.length)),
              ),
            ),
            _lazyRows(urgent, priority: true),
          ],
        ),
      );
      if (p.pixel) {
        priority = DecoratedSliver(
          decoration: pixelFrame(context, 1)!,
          position: DecorationPosition.foreground,
          sliver: priority,
        );
      }
      priority = SliverMainAxisGroup(
        key: const ValueKey('focus_today'),
        slivers: [priority],
      );
    }
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      sliver: SliverMainAxisGroup(
        slivers: [
          ?priority,
          for (final group in groups)
            if (group.$2.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: _swipeFilterArea(
                  _animateFilterContent(
                    Padding(
                      padding: const EdgeInsets.only(top: 12, bottom: 10),
                      child: courseHeaders
                          ? _groupHeader(
                              group.$1,
                              group.$2.length,
                              group.$2.where((h) => !_isDone(h)).length,
                            )
                          : _sectionHeader(group.$1, group.$2.length),
                    ),
                  ),
                ),
              ),
              _lazyRows(group.$2, showCourse: !courseHeaders),
            ],
        ],
      ),
    );
  }

  int _byDue(HomeworkItem a, HomeworkItem b) {
    final ad = a.dueAt, bd = b.dueAt;
    if (ad == null && bd == null) return 0;
    if (ad == null) return 1;
    if (bd == null) return -1;
    return ad.compareTo(bd);
  }

  DateTime _earliest(List<HomeworkItem> list) {
    DateTime? best;
    for (final h in list) {
      final d = h.dueAt;
      if (d != null && (best == null || d.isBefore(best))) best = d;
    }
    return best ?? DateTime(9999);
  }

  void _openHw(HomeworkItem hw) {
    // 网页版做作业体验差，点击只看详情，完成操作去官方 App
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            HomeworkDetailPage(homeworkId: hw.id, state: widget.state),
      ),
    );
  }

  Widget _hwRow(
    HomeworkItem hw, {
    bool showCourse = true,
    bool priority = false,
  }) {
    final card = priority
        ? buildFocusHomeworkRow(
            context,
            hw,
            priority: true,
            showCourse: showCourse,
          )
        : buildHwCard(
            context,
            hw,
            showCourse: showCourse,
            platformPill: _filter != 'all',
          );
    // 小票：删除不走滑动——撕纸动画要当着面撕，入口在长按菜单
    //「撕掉这张小票」；句柄按作业 id 缓存，动画中列表重建不打断
    if (isReceiptStyle(context)) {
      final tearKey = _tearKeys.putIfAbsent(
        hw.id,
        () => GlobalKey<ReceiptTearOutState>(),
      );
      return GestureDetector(
        onTap: () => _openHw(hw),
        onLongPress: () => _openHwOptions(hw),
        child: ReceiptTearOut(
          key: tearKey,
          seed: stableHash(hw.id),
          onTorn: () {
            _tearing.remove(hw.id);
            _dismissHw(hw);
          },
          child: card,
        ),
      );
    }
    return GestureDetector(
      onTap: () => _openHw(hw),
      onLongPress: () => _openHwOptions(hw),
      child: card,
    );
  }

  /// 长按菜单的「撕掉这张小票」：当面撕完再移除；行不在树上时直接移除
  void _tearOff(HomeworkItem hw) {
    final key = _tearKeys[hw.id];
    if (key?.currentState != null && _tearing.add(hw.id)) {
      key!.currentState!.play(DismissDirection.endToStart);
    } else {
      _dismissHw(hw);
    }
  }

  void _openHwOptions(HomeworkItem hw) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => ThemedDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420, maxHeight: 560),
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 小票：撕是头号动作，摆在最上面
                  if (isReceiptStyle(context))
                    ListTile(
                      leading: const Icon(
                        Icons.content_cut_rounded,
                        color: Tokens.danger,
                      ),
                      title: const Text(
                        '撕掉这张小票',
                        style: TextStyle(color: Tokens.danger),
                      ),
                      onTap: () {
                        Navigator.of(dialogContext).pop();
                        _tearOff(hw);
                      },
                    ),
                  ListTile(
                    leading: const Icon(Icons.open_in_new_rounded),
                    title: const Text('打开作业'),
                    onTap: () {
                      Navigator.of(dialogContext).pop();
                      _openHw(hw);
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.sticky_note_2_outlined),
                    title: Text(hw.note?.isNotEmpty == true ? '编辑备注' : '添加备注'),
                    onTap: () {
                      Navigator.of(dialogContext).pop();
                      _openNoteEditor(hw);
                    },
                  ),
                  if (hw.platform == PlatformKind.manual)
                    ListTile(
                      leading: Icon(
                        hwIsDone(hw)
                            ? Icons.undo_rounded
                            : Icons.check_circle_outline,
                      ),
                      title: Text(hwIsDone(hw) ? '标记未完成' : '标记完成'),
                      onTap: () {
                        Navigator.of(dialogContext).pop();
                        widget.state.setHomeworkStatus(
                          hw.id,
                          hwIsDone(hw) ? HwStatus.todo : HwStatus.done,
                        );
                      },
                    ),
                  if (hw.platform == PlatformKind.manual)
                    ListTile(
                      leading: const Icon(Icons.edit_outlined),
                      title: const Text('编辑作业'),
                      onTap: () {
                        Navigator.of(dialogContext).pop();
                        _openManualEditor(context, edit: hw);
                      },
                    ),
                  if (hw.platform == PlatformKind.manual)
                    ListTile(
                      leading: const Icon(
                        Icons.delete_outline_rounded,
                        color: Tokens.danger,
                      ),
                      title: const Text(
                        '删除',
                        style: TextStyle(color: Tokens.danger),
                      ),
                      onTap: () async {
                        Navigator.of(dialogContext).pop();
                        // 无二次确认的删除是误触即永久丢失，手动作业没有平台源可回
                        final ok = await showDialog<bool>(
                          context: context,
                          builder: (confirmContext) => ThemedAlertDialog(
                            title: const Text('删除这条作业？'),
                            content: Text(
                              '「${hw.title}」将移入回收站，可在设置的“本地恢复”中找回。',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () =>
                                    Navigator.of(confirmContext).pop(false),
                                child: const Text('取消'),
                              ),
                              FilledButton(
                                onPressed: () =>
                                    Navigator.of(confirmContext).pop(true),
                                child: const Text('删除'),
                              ),
                            ],
                          ),
                        );
                        if (ok == true) {
                          try {
                            await widget.state.deleteManualHomework(hw.id);
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('「${hw.title}」已移入回收站'),
                                action: SnackBarAction(
                                  label: '撤销',
                                  onPressed: () async {
                                    try {
                                      await widget.state.restoreDeletedHomework(
                                        hw.id,
                                      );
                                    } catch (_) {
                                      if (mounted) {
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          const SnackBar(
                                            content: Text('请在“本地恢复”中查看恢复结果'),
                                          ),
                                        );
                                      }
                                    }
                                  },
                                ),
                              ),
                            );
                          } catch (_) {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('删除未完成，请核对作业列表和回收站后重试'),
                                ),
                              );
                            }
                          }
                        }
                      },
                    )
                  else
                    ListTile(
                      leading: const Icon(Icons.visibility_off_outlined),
                      title: const Text('隐藏这条作业'),
                      subtitle: const Text('不再提醒，可在设置的「已隐藏」中恢复'),
                      onTap: () {
                        Navigator.of(dialogContext).pop();
                        _dismissHw(hw);
                      },
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _openNoteEditor(HomeworkItem hw) =>
      showHomeworkNoteEditor(context, widget.state, hw);

  Future<void> _openAddMenu(BuildContext context) async {
    final choice = await showDialog<String>(
      context: context,
      builder: (dialogContext) => ThemedDialog(
        backgroundColor: cardColor(dialogContext),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 14, 22, 22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '添加作业',
                        style: TextStyle(
                          fontSize: 22,
                          fontFamily: paletteOf(dialogContext).clay
                              ? 'StudySerif'
                              : null,
                          fontWeight: paletteOf(dialogContext).clay
                              ? FontWeight.w400
                              : FontWeight.w800,
                          color: textPrimary(dialogContext),
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: '关闭',
                      onPressed: () => Navigator.pop(dialogContext),
                      icon: const Icon(Icons.close_rounded, size: 21),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _AddHomeworkOption(
                  icon: Icons.edit_note_rounded,
                  title: '手动添加',
                  subtitle: '填写课程、内容和截止时间',
                  onTap: () => Navigator.pop(dialogContext, 'manual'),
                ),
                const SizedBox(height: 12),
                _AddHomeworkOption(
                  icon: Icons.document_scanner_rounded,
                  title: '识别添加',
                  subtitle: '导入截图或粘贴文字',
                  onTap: () => Navigator.pop(dialogContext, 'recognition'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (!context.mounted || choice == null) return;
    if (choice == 'manual') {
      _openManualEditor(context);
      return;
    }
    final result = await Navigator.of(context).push<HomeworkImportResult>(
      MaterialPageRoute(
        builder: (_) => HomeworkRecognitionPage(state: widget.state),
      ),
    );
    if (!context.mounted || result == null) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '已添加 ${result.count} 项作业${result.outputsDelayed ? '，提醒或小组件刷新稍有延迟，请勿重复添加' : ''}',
        ),
      ),
    );
  }

  void _openManualEditor(BuildContext context, {HomeworkItem? edit}) =>
      showManualHomeworkEditor(context, widget.state, edit: edit);

  Future<void> _dismissHw(HomeworkItem hw) async {
    // A finished receipt tear cannot be reused if saving fails.
    _tearKeys.remove(hw.id);
    try {
      await widget.state.dismissHomework(hw);
    } catch (_) {
      if (mounted) {
        final retained = widget.state.homework.any((h) => h.id == hw.id);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              retained ? '隐藏未完成，作业已保留，请重试。' : '作业已隐藏，提醒或小组件刷新稍有延迟。',
            ),
          ),
        );
      }
      return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已隐藏「${hw.title}」'),
        action: SnackBarAction(
          label: '撤销',
          onPressed: () => widget.state.restoreHomework(hw.id),
        ),
      ),
    );
  }

  /// 分段块：左侧 3px 色条贯穿标题与卡片，色条颜色即分段语义
  Widget _sectionHeader(String title, int count) => Row(
    children: [
      if (title == '已截止') ...[
        Icon(
          Icons.error_outline_rounded,
          size: 18,
          color: Theme.of(context).colorScheme.error,
        ),
        const SizedBox(width: 6),
      ],
      Expanded(child: _sectionTitleText(title)),
      Text(
        '$count 项',
        style: TextStyle(fontSize: 11.5, color: textFaint(context)),
      ),
    ],
  );

  Widget _sectionTitleText(String title) {
    return Text(
      title,
      style: serifTitle(
        context,
        TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: title == '已截止'
              ? Theme.of(context).colorScheme.error
              : textPrimary(context),
        ),
      ),
    );
  }

  Widget _groupHeader(String course, int total, int undone) {
    return Row(
      children: [
        if (isInkStyle(context)) ...[
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: textPrimary(context).withValues(alpha: 0.82),
            ),
          ),
          const SizedBox(width: 8),
        ],
        Expanded(
          child: Text(
            course,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: textPrimary(context),
            ),
          ),
        ),
        Text(
          undone > 0 ? '未完成 $undone · 共 $total' : '共 $total',
          style: TextStyle(fontSize: 11.5, color: textFaint(context)),
        ),
      ],
    );
  }

  Widget _menuRow({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required String value,
  }) {
    final selected = _sort == value;
    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Icon(icon, size: 18, color: color),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600,
                  color: textPrimary(context),
                ),
              ),
              const SizedBox(height: 1),
              Text(
                subtitle,
                style: TextStyle(fontSize: 11.5, color: textFaint(context)),
              ),
            ],
          ),
        ),
        if (selected)
          Icon(Icons.check_rounded, size: 20, color: accentColor(context)),
      ],
    );
  }

  Widget _warnBanner(String msg) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
      child: SyncProgressNotice(
        message: msg,
        onDetails: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => BackgroundSyncSettingsPage(state: widget.state),
          ),
        ),
      ),
    );
  }

  Widget _empty({
    required IconData icon,
    required String title,
    String? subtitle,
    Widget? action,
  }) {
    return Padding(
      padding: EdgeInsets.fromLTRB(24, 24, 24, 100),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 水墨：空态不画彩色圆图标，留白处挂一幅远山
            if (isInkStyle(context))
              const SizedBox(
                width: 300,
                height: 110,
                child: InkMountains(height: 110),
              )
            else
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: accentColor(context).withValues(alpha: 0.08),
                ),
                child: Icon(icon, size: 28, color: accentColor(context)),
              ),
            const SizedBox(height: 14),
            Text(
              title,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: textPrimary(context),
              ),
            ),
            if (subtitle != null) const SizedBox(height: 6),
            if (subtitle != null)
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12.5,
                  color: textSecondary(context),
                  height: 1.5,
                ),
              ),
            if (action != null) const SizedBox(height: 18),
            ?action,
          ],
        ),
      ),
    );
  }
}

/// A full-width, keyboard/semantics-friendly choice inside the centered dialog.
class _AddHomeworkOption extends StatelessWidget {
  const _AddHomeworkOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
  final IconData icon;
  final String title, subtitle;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final p = paletteOf(context);
    final radius = p.pixel || p.receipt || p.terminal
        ? 3.0
        : p.paper || p.journal
        ? 8.0
        : 16.0;
    return Material(
      color: Color.alphaBlend(p.accentFill.withValues(alpha: .045), p.modal),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius),
        side: BorderSide(color: p.cardBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: p.accentFill.withValues(alpha: p.sunny ? .36 : .10),
                  borderRadius: BorderRadius.circular(radius * .7),
                ),
                child: Icon(icon, color: p.sunny ? p.ink : p.accent, size: 25),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: p.ink,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: p.ink2,
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Icon(Icons.chevron_right_rounded, color: p.ink3, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
