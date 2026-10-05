/// 首页：作业列表。倒计时按紧迫度分级着色（红→橙→琥珀→灰），已完成绿色；
/// 分段块以左侧色条标识。视图：按时间分段（默认）/ 按课程分组；
/// 支持搜索、学期范围切换、左滑隐藏。
library;

import 'package:flutter/material.dart';

import 'dart:async';

import '../app_state.dart';
import '../models/homework.dart';
import '../services/stable_hash.dart';
import '../services/storage.dart';
import '../ui/adaptive.dart';
import '../ui/hw_card.dart';
import '../ui/ink_wash.dart';
import '../ui/receipt_tear.dart';
import '../ui/style_background.dart';
import '../ui/tokens.dart';
import 'detail_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.state, required this.onGoAccounts});

  final AppState state;
  final VoidCallback onGoAccounts;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String _filter = 'todo';

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

  /// 杂志主视觉：两位数的「今天」
  String _heroDay() => DateTime.now().day.toString().padLeft(2, '0');

  /// 杂志主视觉：日期数字旁边的小注
  String _heroMonthWeek() {
    final now = DateTime.now();
    const weeks = ['一', '二', '三', '四', '五', '六', '日'];
    return '${now.month}月 · 周${weeks[now.weekday - 1]}';
  }

  /// 杂志期号：当年第几天
  int get _issueNo => DateTime.now().difference(DateTime(DateTime.now().year, 1, 1)).inDays + 1;

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
      floatingActionButton: state.hasAnyAccount
          ? Padding(
              // 液态玻璃底栏悬浮在内容之上，FAB 需抬到玻璃栏上方
              padding: const EdgeInsets.only(bottom: 84),
              child: DecoratedBox(
                // 按钮落影随样式走：漫画=白边贴纸+硬投影，水墨=墨影（印章
                // 不发光），其余=品牌光晕
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(isComicStyle(context)
                      ? 18
                      : (isEditorialStyle(context) || isTerminalStyle(context)
                          ? 4
                          : 14)),
                  border: isComicStyle(context)
                      ? Border.all(color: Colors.white, width: 2)
                      : isTerminalStyle(context)
                          ? Border.all(
                              color: cardBorderColor(context), width: 1)
                          : null,
                  boxShadow: primaryButtonShadow(context),
                ),
                child: FloatingActionButton(
                  backgroundColor: accentColor(context),
                  child: Icon(Icons.add_rounded, color: onAccentColor(context)),
                  onPressed: () => _openManualEditor(context),
                ),
              ),
            )
          : null,
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
              if (_searching) SliverToBoxAdapter(child: _buildSearchBar()),
              if (state.syncing)
                SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const LinearProgressIndicator(minHeight: 2),
                      if (state.syncProgress.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                          child: Text(
                            '正在同步课程 ${state.syncProgress}…',
                            style: TextStyle(
                              fontSize: 11,
                              color: textSecondary(context),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              if (state.hasAnyAccount)
                SliverToBoxAdapter(child: _buildFilters()),
              if (state.lastSyncMessage.isNotEmpty)
                SliverToBoxAdapter(child: _warnBanner(state.lastSyncMessage)),
              _buildList(context, state),
            ],
          ),
        ),
      ),
        ),
    );
  }

  Widget _iconBtn({
    Widget? child,
    IconData? icon,
    VoidCallback? onTap,
    Color? color,
    String? tooltip,
  }) {
    final button = IconButton(
      onPressed: onTap,
      icon: child ?? Icon(icon, size: 22),
      color: color,
      tooltip: tooltip,
    );
    // 杂志/终端：方形按钮（印刷版块的直角 / 窗格的直角），无浮影
    final square = isEditorialStyle(context) || isTerminalStyle(context);
    return Container(
      decoration: BoxDecoration(
        color: cardColor(context),
        shape: square ? BoxShape.rectangle : BoxShape.circle,
        borderRadius:
            square ? BorderRadius.circular(isTerminalStyle(context) ? 3 : 0) : null,
        border: isTerminalStyle(context)
            ? Border.all(color: cardBorderColor(context), width: 1)
            : null,
        boxShadow: square
            ? null
            : const [
                BoxShadow(
                  color: Color(0x14101828),
                  blurRadius: 10,
                  offset: Offset(0, 3),
                ),
              ],
      ),
      child: button,
    );
  }

  Widget _buildHeader(AppState state) {
    final ink = isInkStyle(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
      // 水墨：标题后面铺一层远山淡墨+飞鸟（出血到屏幕边，雾脚漫进列表区，
      // 被后面的卡片自然盖住，只留缝隙里的山影）
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          if (ink)
            Positioned(
              top: -14,
              left: -20,
              right: -20,
              child: const InkMountains(height: 158),
            ),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 终端：头部是一次命令执行——提示符命令行 + 输出标题 +
                    // 光标块（方角色块，不用字符，零字形缺失风险）
                    if (isTerminalStyle(context)) ...[
                      Text('user@radar:~\$ today',
                          style: TextStyle(
                              fontSize: 12,
                              fontFamily: 'monospace',
                              color: textSecondary(context))),
                      const SizedBox(height: 5),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Text(
                            '作业通',
                            style: TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.w800,
                              fontFamily: 'monospace',
                              letterSpacing: 2,
                              color: textPrimary(context),
                            ),
                          ),
                          const SizedBox(width: 7),
                          Container(
                              width: 10,
                              height: 20, color: accentColor(context)),
                        ],
                      ),
                      const SizedBox(height: 5),
                      Text(_dateLine(),
                          style: TextStyle(
                              fontSize: 12,
                              fontFamily: 'monospace',
                              color: textSecondary(context))),
                    ] else if (isEditorialStyle(context)) ...[
                      // 杂志：巨大日期数字是版面主视觉，刊名退成一条眉线；
                      // 期号 = 当年第几天——期刊的身份签名
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text('作业通',
                              style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 6,
                                  color: textSecondary(context))),
                          const SizedBox(width: 8),
                          Text('· 第 $_issueNo 期',
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 2,
                                  color: accentColor(context))),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(_heroDay(),
                              style: TextStyle(
                                  fontSize: 54,
                                  height: 1.05,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: -2,
                                  color: textPrimary(context))),
                          const SizedBox(width: 9),
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                    width: 10,
                                    height: 10, color: accentColor(context)),
                                const SizedBox(height: 5),
                                Text(_heroMonthWeek(),
                                    style: TextStyle(
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w800,
                                        color: textPrimary(context))),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ] else ...[
                      // 水墨：题款式大标题（拉字距）+ 落款小印
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '作业通',
                            style: inkTitle(
                              context,
                              serifTitle(
                                context,
                                TextStyle(
                                  fontSize: 28,
                                  fontWeight: FontWeight.w800,
                                  color: textPrimary(context),
                                  height: 1.2,
                                ),
                              ),
                            ),
                          ),
                          if (isInkStyle(context)) ...[
                            const SizedBox(width: 7),
                            const InkSealChip(),
                          ],
                        ],
                      ),
                      // 题字收笔：标题下一记横笔（水墨=飞白，黑板=粉笔）
                      if (ink) ...[
                        const SizedBox(height: 5),
                        SizedBox(
                          width: 132,
                          child: BrushLine(
                            color: textPrimary(context).withValues(alpha: 0.55),
                            thickness: 3.0,
                          ),
                        ),
                        const SizedBox(height: 2),
                      ] else
                        const SizedBox(height: 4),
                      Text(
                        _dateLine(),
                        style: monoText(
                          context,
                          TextStyle(
                              fontSize: 13, color: textSecondary(context)),
                        ),
                      ),
                      // 小票：抬头下一道双细线——收据的抬头分隔
                      if (isReceiptStyle(context)) ...[
                        const SizedBox(height: 7),
                        SizedBox(
                          width: 196,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                  height: 1,
                                  width: double.infinity,
                                  color: textPrimary(context)
                                      .withValues(alpha: 0.45)),
                              const SizedBox(height: 2.5),
                              Container(
                                  height: 1,
                                  width: double.infinity,
                                  color: textPrimary(context)
                                      .withValues(alpha: 0.45)),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ],
                ),
              ),
          _iconBtn(
            icon: _searching ? Icons.search_off_rounded : Icons.search_rounded,
            color: _searching ? accentColor(context) : textSecondary(context),
            tooltip: _searching ? '关闭搜索' : '搜索作业',
            onTap: () => setState(() {
              _searching = !_searching;
              if (!_searching) _searchCtrl.clear();
            }),
          ),
          const SizedBox(width: 10),
          // 排序按钮与左右两侧圆钮同一底妆：白圆+淡影——裸图标在浅色
          // 水墨的远山上会融进背景（用户实测），三颗必须成排一致
          Container(
            decoration: BoxDecoration(
              color: cardColor(context),
              shape: BoxShape.circle,
              boxShadow: const [
                BoxShadow(
                  color: Color(0x14101828),
                  blurRadius: 10,
                  offset: Offset(0, 3),
                ),
              ],
            ),
            child: PopupMenuButton<String>(
            tooltip: '排序方式',
            color: modalColor(context),
            elevation: 10,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            position: PopupMenuPosition.under,
            offset: const Offset(0, 8),
            icon: Icon(
              Icons.sort_rounded,
              size: 22,
              color: _sort == 'course' ? accentColor(context) : textSecondary(context),
            ),
            onSelected: (value) {
              setState(() {
                _sort = value;
                Storage.saveSortMode(value);
              });
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'time',
                child: _menuRow(
                  icon: Icons.schedule_rounded,
                  color: const Color(0xFF6366F1),
                  title: '按截止时间',
                  subtitle: '分成今天/本周等段落',
                  value: 'time',
                ),
              ),
              PopupMenuItem(
                value: 'course',
                child: _menuRow(
                  icon: Icons.category_rounded,
                  color: const Color(0xFF10B981),
                  title: '按课程分组',
                  subtitle: '同一门课的作业放在一起',
                  value: 'course',
                ),
              ),
            ],
          ),
          ),
          const SizedBox(width: 10),
          // 同步进行中的进度统一显示在下拉刷新那条进度条上，按钮只置灰防重复触发
          _iconBtn(
            child: Icon(
              Icons.refresh_rounded,
              size: 22,
              color: state.syncing ? Colors.grey : null,
            ),
            tooltip: '同步作业',
            onTap: state.syncing ? null : () => state.syncAll(),
            color: accentColor(context),
          ),
          ],
        ),
        ],
      ),
    );
  }

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

  Widget _buildFilters() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
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
  }

  Widget _pill(String label, String value) {
    final selected = _filter == value;
    // 每套样式的选中态有自己的语言：暖纸="章"（墨线描边+微墨染底，方角）；
    // 水墨="朱笔圈阅"（透明底+朱砂描边+朱砂字）；
    // 漫画=贴纸（白底/彩底方贴+剪影描边+硬投影+按压果冻）；
    // 小票/杂志/终端=方角印刷片（票据和印刷品没有胶囊）。
    final paper = isPaperStyle(context);
    final ink = isInkStyle(context);
    final comic = isComicStyle(context);
    final square =
        isReceiptStyle(context) || isEditorialStyle(context) || isTerminalStyle(context);
    final outline = paletteOf(context).cardBorder;
    return GestureDetector(
      onTap: () => setState(() => _filter = value),
      child: JellyPress(
        enabled: comic,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: selected
                ? (paper
                    ? textPrimary(context).withValues(alpha: 0.08)
                    : ink
                        ? Colors.transparent
                        : accentColor(context))
                : cardColor(context),
            borderRadius: BorderRadius.circular(
                comic ? 12 : square ? 2 : (paper ? 8 : 999)),
            border: selected
                ? (comic
                    ? Border.all(color: outline, width: 1.4)
                    : paper
                        ? Border.all(
                            color: textPrimary(context).withValues(alpha: 0.6),
                            width: 1.2)
                        : ink
                            ? Border.all(
                                color: accentColor(context), width: 1.3)
                            : null)
                : comic
                    ? Border.all(
                        color: outline.withValues(alpha: 0.75), width: 1.2)
                    : Border.all(color: chipBorder(context)),
          boxShadow: comic
              ? [
                  BoxShadow(
                    color: outline.withValues(alpha: selected ? 1 : 0.5),
                    blurRadius: 0,
                    offset: const Offset(0, 2),
                  ),
                ]
              // 选中的筛选片也是"光源"：微微照亮邻近卡面（暖纸/水墨用描边说话，
              // 方角印刷片不发滑光）
              : selected && !paper && !ink && !square
                  ? Tokens.glow(Tokens.brandOf(context), dark: isDark(context))
                  : null,
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: selected && comic ? FontWeight.w800 : FontWeight.w600,
              color: selected
                  ? (paper
                      ? textPrimary(context)
                      : ink
                          ? accentColor(context)
                          : onAccentColor(context))
                  : textSecondary(context),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildList(BuildContext context, AppState state) {
    if (!state.hasAnyAccount) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: _empty(
          icon: Icons.link_rounded,
          title: '还没有绑定账号',
          subtitle: '绑定学习通 / 中国大学MOOC / 智慧树\n作业截止时间一目了然',
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
              : '这里空空的',
          subtitle: state.syncing
              ? '第一次同步要拉取全部课程，稍等片刻'
              : _query.isEmpty
              ? '右下角 + 可以手动添加作业'
              : null,
        ),
      );
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
            color: isInkStyle(context) ? _inkSectionBar(section.$1) : section.$2,
            header: _sectionHeader(section.$1, section.$3.length,
                index: i),
            rows: [for (final hw in section.$3) _hwRow(hw)],
          ),
        );
      }
    }

    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 88),
      sliver: SliverList(delegate: SliverChildListDelegate(children)),
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
      MaterialPageRoute(builder: (_) => HomeworkDetailPage(homeworkId: hw.id)),
    );
  }

  Widget _hwRow(HomeworkItem hw, {bool showCourse = true}) {
    final card = buildHwCard(
      context,
      hw,
      showCourse: showCourse,
      platformPill: _filter != 'all',
    );
    // 小票：删除不走滑动——撕纸动画要当着面撕，入口在长按菜单
    //「撕掉这张小票」；句柄按作业 id 缓存，动画中列表重建不打断
    if (isReceiptStyle(context)) {
      final tearKey =
          _tearKeys.putIfAbsent(hw.id, () => GlobalKey<ReceiptTearOutState>());
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
      builder: (dialogContext) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
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
                        color: Tokens.danger),
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
                        builder: (confirmContext) => AlertDialog(
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
    );
  }

  void _openNoteEditor(HomeworkItem hw) {
    final ctrl = TextEditingController(text: hw.note ?? '');
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: cardColor(context),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text(
          '备注',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
        ),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLines: 3,
          style: TextStyle(fontSize: 14, color: textPrimary(context)),
          decoration: InputDecoration(
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
              widget.state.updateNote(hw.id, ctrl.text.trim());
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

  void _openManualEditor(BuildContext context, {HomeworkItem? edit}) {
    final courseCtrl = TextEditingController(text: edit?.course ?? '');
    final titleCtrl = TextEditingController(text: edit?.title ?? '');
    final noteCtrl = TextEditingController(text: edit?.note ?? '');
    DateTime? due = edit?.dueAt;
    final existingCourses = widget.state.homework
        .map((h) => h.course.trim())
        .where((c) => c.isNotEmpty)
        .toSet()
        .toList();

    showDialog<void>(
      context: context,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheet) => Dialog(
          backgroundColor: cardColor(sheetContext),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420, maxHeight: 560),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    edit == null ? '添加作业' : '编辑作业',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: textPrimary(sheetContext),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: courseCtrl,
                    style: TextStyle(
                      fontSize: 14.5,
                      color: textPrimary(sheetContext),
                    ),
                    decoration: _editorInput(sheetContext, '课程名称'),
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
                              onTap: () => setSheet(() => courseCtrl.text = c),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  color:
                                      accentColor(sheetContext).withValues(alpha: 0.08),
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
                  TextField(
                    controller: titleCtrl,
                    style: TextStyle(
                      fontSize: 14.5,
                      color: textPrimary(sheetContext),
                    ),
                    decoration: _editorInput(sheetContext, '作业标题（必填）'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: noteCtrl,
                    style: TextStyle(
                      fontSize: 14.5,
                      color: textPrimary(sheetContext),
                    ),
                    maxLines: 2,
                    decoration: _editorInput(sheetContext, '备注（选填）：需要交纸质版等'),
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
                            firstDate: now.subtract(const Duration(days: 365)),
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
                          icon: const Icon(Icons.close_rounded, size: 18),
                          onPressed: () => setSheet(() => due = null),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 46,
                    child: FilledButton(
                      onPressed: () {
                        final title = titleCtrl.text.trim();
                        if (title.isEmpty) return;
                        final course = courseCtrl.text.trim();
                        final note = noteCtrl.text.trim();
                        if (edit == null) {
                          widget.state.addManualHomework(
                            course: course,
                            title: title,
                            dueAt: due,
                            note: note,
                          );
                        } else {
                          widget.state.updateManualHomework(
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
                            ),
                          );
                        }
                        Navigator.of(sheetContext).pop();
                      },
                      child: Text(edit == null ? '添加' : '保存'),
                    ),
                  ),
                ],
              ),
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

  InputDecoration _editorInput(BuildContext sheetContext, String hint) =>
      InputDecoration(
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
    return Container(
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.only(left: 10),
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(color: color.withValues(alpha: 0.55), width: 3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 10,
        children: [header, ...rows],
      ),
    );
  }

  Widget _sectionHeader(String title, int count, {int index = 0}) {
    // 终端：段头是一次列目录命令——> ls 已截止/ …… N item(s)
    if (isTerminalStyle(context)) {
      return Row(
        children: [
          Text('>',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  fontFamily: 'monospace',
                  color: accentColor(context))),
          const SizedBox(width: 7),
          Expanded(
            child: Text('ls $title/',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'monospace',
                    letterSpacing: 0.5,
                    color: textPrimary(context))),
          ),
          Text('$count item(s)',
              style: TextStyle(
                  fontSize: 11,
                  fontFamily: 'monospace',
                  color: textFaint(context))),
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
              Text((index + 1).toString().padLeft(2, '0'),
                  style: TextStyle(
                      fontSize: 27,
                      height: 1,
                      fontWeight: FontWeight.w900,
                      color: accentColor(context))),
              const SizedBox(width: 7),
              Text(' / ',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: textSecondary(context))),
              const SizedBox(width: 7),
              Expanded(
                child: Text(title,
                    style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 2,
                        color: textPrimary(context))),
              ),
              Text('$count 项',
                  style: TextStyle(
                      fontSize: 11, color: textFaint(context))),
            ],
          ),
          const SizedBox(height: 5),
          Container(height: 2.6, color: rule),
        ],
      );
    }
    // 小票：段头是收据抬头——标题居中卡在两段双细线之间
    if (isReceiptStyle(context)) {
      final rule =
          textPrimary(context).withValues(alpha: 0.40);
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
          Text(title,
              style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 2.5,
                  color: textPrimary(context))),
          const SizedBox(width: 7),
          Text('$count 件',
              style: TextStyle(
                  fontSize: 10.5,
                  fontFamily: 'monospace',
                  color: textFaint(context))),
          const SizedBox(width: 12),
          Expanded(child: rules()),
        ],
      );
    }
    // 手账：段头是贴了一截胶带的标签（胶带压在标题上方，微透）
    if (isJournalStyle(context)) {
      return Stack(
        clipBehavior: Clip.none,
        children: [
          Row(
            children: [
              Text(title,
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: textPrimary(context))),
              const Spacer(),
              Text('$count 项',
                  style: TextStyle(
                      fontSize: 11.5, color: textFaint(context))),
            ],
          ),
          Positioned(
            top: -8,
            left: 22,
            child: journalTape(context, 'sec:$title', width: 46),
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
            padding: const EdgeInsets.only(left: 12, right: 12, top: 5, bottom: 5),
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
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: cardColor(context),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: paletteOf(context).cardBorder, width: 1.3),
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
    final dark = isDark(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 10, 20, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF2A2313) : const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: dark ? const Color(0xFF5C4A1A) : const Color(0xFFFDE68A)),
      ),
      child: Row(
        children: [
          Icon(
            Icons.info_outline_rounded,
            size: 16,
            color: Colors.amber.shade800,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              msg,
              style: TextStyle(
                  fontSize: 12,
                  color: dark ? const Color(0xFFE8C878) : const Color(0xFF92400E)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _empty({
    required IconData icon,
    required String title,
    String? subtitle,
    Widget? action,
  }) {
    return Center(
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
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: accentColor(context).withValues(alpha: 0.08),
              ),
              child: Icon(icon, size: 36, color: accentColor(context)),
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
    );
  }
}
