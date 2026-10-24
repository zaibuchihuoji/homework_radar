/// 首页：作业列表。倒计时按紧迫度分级着色（红→橙→琥珀→灰），已完成绿色；
/// 各样式保留自己的分组标题。视图：按时间分段（默认）/ 按课程分组；
/// 支持搜索、学期范围切换、左滑隐藏。
library;

import 'package:flutter/material.dart';

import 'dart:async';

import '../app_state.dart';
import '../models/homework.dart';
import '../models/homework_draft.dart';
import '../services/stable_hash.dart';
import '../services/storage.dart';
import '../ui/adaptive.dart';
import '../ui/hw_card.dart';
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

class _HomePageState extends State<HomePage> {
  String _filter = 'todo';
  bool _todayOnly = false;

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
    super.dispose();
  }

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
  Widget build(BuildContext context) {
    final state = widget.state;
    return StyleBackground(
      // 带底衬的样式下透明化 Scaffold，露出主题底衬
      //（2026-10-05 复盘：不透明底色曾把莫兰迪色雾/像素点阵整个盖住）
      child: Scaffold(
        backgroundColor: scaffoldBgOf(context),
        floatingActionButton: paletteOf(context).sunny
            ? null
            : Padding(
                // 液态玻璃底栏悬浮在内容之上，FAB 需抬到玻璃栏上方
                padding: EdgeInsets.zero,
                child: DecoratedBox(
                  // 按钮落影随样式走：漫画=白边贴纸+硬投影，水墨=墨影（印章
                  // 不发光），其余=品牌光晕
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(
                      isComicStyle(context)
                          ? 18
                          : (isEditorialStyle(context) ||
                                    isTerminalStyle(context)
                                ? 4
                                : 14),
                    ),
                    border: isComicStyle(context)
                        ? Border.all(color: Colors.white, width: 2)
                        : isTerminalStyle(context)
                        ? Border.all(color: cardBorderColor(context), width: 1)
                        : null,
                    boxShadow: primaryButtonShadow(context),
                  ),
                  child: FloatingActionButton(
                    tooltip: '添加作业',
                    backgroundColor: paletteOf(context).accentFill,
                    child: Icon(
                      Icons.add_rounded,
                      color: onAccentColor(context),
                    ),
                    onPressed: () => _openAddMenu(context),
                  ),
                ),
              ),
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
                  SliverToBoxAdapter(child: _buildFilters()),
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

  Decoration? _actionDecoration() {
    final p = paletteOf(context);
    if (p.clean) return null;
    final square = p.pixel || p.editorial || p.terminal || p.receipt;
    return BoxDecoration(
      color: p.card,
      borderRadius: BorderRadius.circular(
        square
            ? 2
            : p.morandi
            ? 22
            : p.comic
            ? 10
            : 6,
      ),
      border: p.morandi
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
  }) {
    return Container(
      decoration: _actionDecoration(),
      child: IconButton(
        onPressed: onTap,
        icon: child ?? Icon(icon, size: 21),
        color: color,
        tooltip: tooltip,
      ),
    );
  }

  Widget _buildHeader(AppState state) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, isCleanStyle(context) ? 8 : 14, 20, 0),
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
              const SizedBox(width: 4),
              if (!paletteOf(context).sunny) _buildSortMenu(),
              const SizedBox(width: 4),
              _iconBtn(
                icon: Icons.refresh_rounded,
                tooltip: '同步作业',
                onTap: state.syncing ? null : () => state.syncAll(),
                color: state.syncing
                    ? textFaint(context)
                    : accentColor(context),
              ),
              if (paletteOf(context).sunny) ...[
                const SizedBox(width: 6),
                IconButton.filledTonal(
                  tooltip: '添加作业',
                  onPressed: () => _openAddMenu(context),
                  style: IconButton.styleFrom(
                    backgroundColor: paletteOf(context).accentFill,
                    foregroundColor: paletteOf(context).onAccent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: const Icon(Icons.add_rounded, size: 24),
                ),
              ],
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
    if (paletteOf(context).sunny && today > 0) return const SizedBox.shrink();
    return StudyOverview(
      pending: pending.length,
      today: today,
      todaySelected: _todayOnly,
      onPendingTap: () => setState(() {
        _todayOnly = false;
        _filter = 'todo';
      }),
      onTodayTap: () => setState(() {
        _todayOnly = !_todayOnly;
        _filter = 'todo';
      }),
    );
  }

  Widget _buildFilters() {
    final filters = SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: EdgeInsets.fromLTRB(
        20,
        isCleanStyle(context) ? 4 : 12,
        paletteOf(context).sunny ? 0 : 20,
        4,
      ),
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
    return paletteOf(context).sunny
        ? Row(
            children: [
              Expanded(child: filters),
              _buildSortMenu(),
              const SizedBox(width: 12),
            ],
          )
        : filters;
  }

  Widget _pill(String label, String value) {
    final selected = _filter == value;
    final p = paletteOf(context);
    if (p.sunny) {
      return Semantics(
        button: true,
        selected: selected,
        child: Container(
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
            onPressed: () => setState(() {
              _filter = value;
              _todayOnly = false;
            }),
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
    final square = p.pixel || p.terminal || p.receipt || p.editorial;
    final radius = square
        ? 2.0
        : p.morandi
        ? 18.0
        : p.paper || p.journal
        ? 6.0
        : 10.0;
    final filled =
        selected &&
        (p.sunny || p.comic || p.pixel || p.terminal || p.editorial);
    final fill = filled
        ? (p.terminal || p.editorial ? p.ink : p.accentFill)
        : selected
        ? p.card
        : Colors.transparent;
    final foreground = filled
        ? (p.terminal || p.editorial ? p.card : p.onAccent)
        : selected
        ? p.accent
        : p.ink2;
    return Semantics(
      button: true,
      selected: selected,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(radius),
            border:
                selected ||
                    p.pixel ||
                    p.comic ||
                    p.paper ||
                    p.receipt ||
                    p.terminal
                ? Border.all(
                    color: p.comic || p.pixel
                        ? p.cardBorder
                        : selected && !p.clean
                        ? p.accentFill.withValues(alpha: 0.6)
                        : p.hairline,
                    width: p.comic || p.pixel ? 1.5 : 1,
                  )
                : null,
            boxShadow: selected && (p.comic || p.pixel)
                ? [BoxShadow(color: p.cardBorder, offset: const Offset(2, 2))]
                : null,
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: () => setState(() {
                _filter = value;
                _todayOnly = false;
              }),
              borderRadius: BorderRadius.circular(radius),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontFamily: p.terminal || p.receipt || p.pixel
                        ? 'monospace'
                        : p.paper
                        ? 'serif'
                        : null,
                    fontWeight: selected || p.comic
                        ? FontWeight.w700
                        : FontWeight.w400,
                    color: foreground,
                  ),
                ),
              ),
            ),
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
        child: _empty(
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
      );
    }

    if (paletteOf(context).sunny && _sort == 'time') {
      return _focusList(filtered);
    }

    final children = <Widget>[];
    if (_sort == 'course') {
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
      for (final g in entries) {
        final undone = g.value.where((h) => !_isDone(h)).length;
        children.add(
          _sectionBlock(
            color: isInkStyle(context)
                ? textPrimary(context).withValues(alpha: 0.45)
                : avatarColorFor(g.key),
            header: _groupHeader(g.key, g.value.length, undone),
            rows: [for (final hw in g.value) _hwRow(hw, showCourse: false)],
          ),
        );
      }
    } else {
      for (final (i, section) in _timeSections(filtered).indexed) {
        children.add(
          _sectionBlock(
            color: isInkStyle(context)
                ? _inkSectionBar(section.$1)
                : section.$2,
            header: _sectionHeader(section.$1, section.$3.length, index: i),
            rows: [for (final hw in section.$3) _hwRow(hw)],
          ),
        );
      }
    }

    return SliverPadding(
      padding: EdgeInsets.fromLTRB(20, 4, 20, 96),
      sliver: SliverList(delegate: SliverChildListDelegate(children)),
    );
  }

  Widget _focusList(List<HomeworkItem> filtered) {
    final n = DateTime.now();
    bool today(HomeworkItem h) =>
        !_isDone(h) && h.dueAt != null && DateUtils.isSameDay(h.dueAt, n);
    final urgent = filtered.where(today).toList();
    final rest = filtered.where((h) => !today(h)).toList();
    final overdue = rest.where((h) => !_isDone(h) && _isOverdue(h)).toList();
    final upcoming = rest.where((h) => !_isDone(h) && !_isOverdue(h)).toList();
    final submitted = rest
        .where((h) => h.status == HwStatus.submitted)
        .toList();
    final done = rest
        .where((h) => h.status != HwStatus.submitted && _isDone(h))
        .toList();
    final p = paletteOf(context);
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      sliver: SliverList(
        delegate: SliverChildListDelegate([
          if (urgent.isNotEmpty)
            Container(
              key: const ValueKey('focus_today'),
              decoration: BoxDecoration(
                color: p.accentFill,
                borderRadius: BorderRadius.circular(12),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Tooltip(
                    message: '今天截止 ${urgent.length} 项',
                    child: InkWell(
                      onTap: () => setState(() {
                        _todayOnly = !_todayOnly;
                        _filter = 'todo';
                      }),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(15, 14, 15, 12),
                        child: Row(
                          children: [
                            Icon(
                              Icons.schedule_outlined,
                              size: 20,
                              color: p.onAccent,
                            ),
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
                              '${urgent.length} 项',
                              style: TextStyle(fontSize: 12, color: p.onAccent),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  for (var i = 0; i < urgent.length; i++) ...[
                    Divider(
                      height: 1,
                      thickness: .5,
                      indent: 15,
                      endIndent: 15,
                      color: p.onAccent.withValues(alpha: .12),
                    ),
                    _hwRow(urgent[i], priority: true),
                  ],
                ],
              ),
            ),
          for (final section in [
            ('已截止', overdue),
            ('接下来', upcoming),
            ('已提交', submitted),
            ('已完成', done),
          ])
            if (section.$2.isNotEmpty)
              _sectionBlock(
                color: p.hairline,
                header: _sectionHeader(section.$1, section.$2.length, index: 0),
                rows: [for (final hw in section.$2) _hwRow(hw)],
              ),
        ]),
      ),
    );
  }

  /// 时间分段。返回 (标题, 颜色, 条目) 列表，空段不出现。
  List<(String, Color, List<HomeworkItem>)> _timeSections(
    List<HomeworkItem> items,
  ) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final overdue = <HomeworkItem>[];
    final todayList = <HomeworkItem>[];
    final tomorrow = <HomeworkItem>[];
    final in3 = <HomeworkItem>[];
    final in7 = <HomeworkItem>[];
    final later = <HomeworkItem>[];
    final noDue = <HomeworkItem>[];
    // 已提交与已完成分开成段：此前混进一个「已完成」桶，
    // 已提交页签下的分组标题会错标成已完成
    final submitted = <HomeworkItem>[];
    final done = <HomeworkItem>[];

    for (final hw in items) {
      if (hw.status == HwStatus.submitted) {
        submitted.add(hw);
        continue;
      }
      if (_isDone(hw)) {
        done.add(hw);
        continue;
      }
      final d = hw.dueAt;
      if (d == null) {
        noDue.add(hw);
      } else if (_isOverdue(hw)) {
        overdue.add(hw);
      } else {
        final day = DateTime(d.year, d.month, d.day);
        final days = day.difference(today).inDays;
        if (days == 0) {
          todayList.add(hw);
        } else if (days == 1) {
          tomorrow.add(hw);
        } else if (days <= 3) {
          in3.add(hw);
        } else if (days <= 7) {
          in7.add(hw);
        } else {
          later.add(hw);
        }
      }
    }

    return [
      if (overdue.isNotEmpty) ('已截止', Tokens.danger, overdue),
      if (todayList.isNotEmpty) ('今天截止', const Color(0xFFF97316), todayList),
      if (tomorrow.isNotEmpty) ('明天截止', const Color(0xFFF59E0B), tomorrow),
      if (in3.isNotEmpty) ('三天内', const Color(0xFF3B82F6), in3),
      if (in7.isNotEmpty) ('一周内', const Color(0xFF14B8A6), in7),
      if (later.isNotEmpty) ('之后', const Color(0xFF8B5CF6), later),
      if (noDue.isNotEmpty) ('未设截止', const Color(0xFF9CA3AF), noDue),
      if (submitted.isNotEmpty) ('已提交', const Color(0xFF0D9488), submitted),
      if (done.isNotEmpty) ('已完成', const Color(0xFF16A34A), done),
    ];
  }

  /// 水墨下时间段的紧迫度用「墨阶」表达：越急墨越浓，唯已截止保留朱砂
  /// （红只出现在印章与危局）——与其它样式的彩色语义条构成差异。
  Color _inkSectionBar(String title) {
    final inkC = textPrimary(context);
    return switch (title) {
      '已截止' => accentColor(context),
      '今天截止' => inkC.withValues(alpha: 0.90),
      '明天截止' => inkC.withValues(alpha: 0.74),
      '三天内' => inkC.withValues(alpha: 0.58),
      '一周内' => inkC.withValues(alpha: 0.44),
      '之后' => inkC.withValues(alpha: 0.30),
      '未设截止' => inkC.withValues(alpha: 0.20),
      '已提交' => inkC.withValues(alpha: 0.42),
      '已完成' => inkC.withValues(alpha: 0.28),
      _ => inkC.withValues(alpha: 0.44),
    };
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
      child: Dismissible(
        key: ValueKey(hw.id),
        direction: DismissDirection.endToStart,
        background: Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 22),
          decoration: BoxDecoration(
            color: Tokens.danger,
            borderRadius: BorderRadius.circular(18),
          ),
          child: const Icon(
            Icons.delete_outline_rounded,
            color: Colors.white,
            size: 24,
          ),
        ),
        onDismissed: (_) => _dismissHw(hw),
        child: card,
      ),
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
                            content: Text('「${hw.title}」删除后无法恢复。'),
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
                          widget.state.deleteManualHomework(hw.id);
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
                          fontWeight: FontWeight.w800,
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
    await widget.state.dismissHomework(hw);
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
  Widget _sectionBlock({
    required Color color,
    required Widget header,
    required List<Widget> rows,
  }) {
    return Padding(
      padding: EdgeInsets.only(
        top: isCleanStyle(context)
            ? 12
            : isJournalStyle(context)
            ? 22
            : 18,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: isReceiptStyle(context) ? 12 : 10,
        children: [header, ...rows],
      ),
    );
  }

  Widget _sectionHeader(String title, int count, {int index = 0}) {
    // 终端：段头是一次列目录命令——> ls 已截止/ …… N item(s)
    if (isTerminalStyle(context)) {
      return Row(
        children: [
          Text(
            '>',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              fontFamily: 'monospace',
              color: accentColor(context),
            ),
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              'ls $title/',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                fontFamily: 'monospace',
                letterSpacing: 0.5,
                color: textPrimary(context),
              ),
            ),
          ),
          Text(
            '$count item(s)',
            style: TextStyle(
              fontSize: 11,
              fontFamily: 'monospace',
              color: textFaint(context),
            ),
          ),
        ],
      );
    }
    // 杂志：段头是编号版块题——大号 01 + 标题，压一道粗印刷规则线
    //（卡片自带 Oxford 双线，段头若也用双线会叠成过重的黑带）
    if (isEditorialStyle(context)) {
      final rule = paletteOf(context).cardBorder;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                (index + 1).toString().padLeft(2, '0'),
                style: TextStyle(
                  fontSize: 27,
                  height: 1,
                  fontWeight: FontWeight.w900,
                  color: accentColor(context),
                ),
              ),
              const SizedBox(width: 7),
              Text(
                ' / ',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: textSecondary(context),
                ),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 2,
                    color: textPrimary(context),
                  ),
                ),
              ),
              Text(
                '$count 项',
                style: TextStyle(fontSize: 11, color: textFaint(context)),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Container(height: 2.6, color: rule),
        ],
      );
    }
    // 小票：段头是收据抬头——标题居中卡在两段双细线之间
    if (isReceiptStyle(context)) {
      final rule = textPrimary(context).withValues(alpha: 0.40);
      Widget rules() => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(height: 1, color: rule),
          const SizedBox(height: 2),
          Container(height: 1, color: rule),
        ],
      );
      return Row(
        children: [
          Expanded(child: rules()),
          const SizedBox(width: 12),
          Text(
            title,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 2.5,
              color: textPrimary(context),
            ),
          ),
          const SizedBox(width: 7),
          Text(
            '$count 件',
            style: TextStyle(
              fontSize: 10.5,
              fontFamily: 'monospace',
              color: textFaint(context),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: rules()),
        ],
      );
    }
    // 胶带先绘制，文字最后绘制，保留拼贴感但不盖住字形。
    if (isJournalStyle(context)) {
      return Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            top: -8,
            left: 22,
            child: journalTape(context, 'sec:$title', width: 46),
          ),
          Row(
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: textPrimary(context),
                ),
              ),
              const Spacer(),
              Text(
                '$count 项',
                style: TextStyle(fontSize: 11.5, color: textFaint(context)),
              ),
            ],
          ),
        ],
      );
    }
    // 像素：段头是 HUD 标签——黑底白字的像素牌
    if (isPixelStyle(context)) {
      return Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: paletteOf(context).cardBorder,
              borderRadius: BorderRadius.circular(2),
            ),
            child: Text(
              title,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 1,
                color: isDark(context)
                    ? const Color(0xFF10131C)
                    : const Color(0xFFDDE3EA),
              ),
            ),
          ),
          const Spacer(),
          Text(
            '$count 项',
            style: TextStyle(fontSize: 11.5, color: textFaint(context)),
          ),
        ],
      );
    }
    // 莫兰迪：段头是一条奶油胶囊——标题挤在一条奶油里
    if (isMorandiStyle(context)) {
      return Row(
        children: [
          Container(
            padding: const EdgeInsets.only(
              left: 12,
              right: 12,
              top: 5,
              bottom: 5,
            ),
            decoration: BoxDecoration(
              color: paletteOf(context).hairline,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  margin: const EdgeInsets.only(right: 6),
                  decoration: BoxDecoration(
                    color: const [
                      Color(0xFFC9AFA4), // 灰粉
                      Color(0xFFA3B18A), // 灰绿
                      Color(0xFFC9B8D8), // 灰紫
                      Color(0xFFD9CFC4), // 燕麦
                    ][stableHash(title).abs() % 4],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                _sectionTitleText(title),
              ],
            ),
          ),
          const Spacer(),
          Text(
            '$count 项',
            style: TextStyle(fontSize: 11.5, color: textFaint(context)),
          ),
        ],
      );
    }
    // 水墨：段头一枚「顿笔」墨点；漫画：标题是一张斜贴的小贴纸标签
    if (isInkStyle(context)) {
      return Row(
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: textPrimary(context).withValues(alpha: 0.82),
            ),
          ),
          const SizedBox(width: 8),
          _sectionTitleText(title),
          const Spacer(),
          Text(
            '$count 项',
            style: TextStyle(fontSize: 11.5, color: textFaint(context)),
          ),
        ],
      );
    }
    if (isComicStyle(context)) {
      return Row(
        children: [
          Transform.rotate(
            angle: -0.014,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: cardColor(context),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: paletteOf(context).cardBorder,
                  width: 1.3,
                ),
                boxShadow: [
                  BoxShadow(
                    color: paletteOf(context).cardBorder,
                    blurRadius: 0,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: textPrimary(context),
                ),
              ),
            ),
          ),
          const Spacer(),
          Text(
            '$count 项',
            style: TextStyle(fontSize: 11.5, color: textFaint(context)),
          ),
        ],
      );
    }
    return Row(
      children: [
        _sectionTitleText(title),
        const Spacer(),
        Text(
          '$count 项',
          style: TextStyle(fontSize: 11.5, color: textFaint(context)),
        ),
      ],
    );
  }

  Widget _sectionTitleText(String title) {
    return Text(
      title,
      style: serifTitle(
        context,
        TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: textPrimary(context),
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
