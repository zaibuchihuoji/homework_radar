/// 账号管理：学习通 / 中国大学MOOC / 教务系统的登录态与 WebView 登录入口。
library;

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../ui/theme_forms.dart';
import '../models/course.dart';
import '../models/homework.dart';
import '../services/jw_config.dart';
import '../services/platform_cookie.dart';
import '../services/stable_hash.dart';
import '../services/storage.dart';
import '../ui/adaptive.dart';
import '../ui/account_platform_icon.dart';
import '../ui/dashed_line.dart';
import '../ui/ink_wash.dart';
import '../ui/style_background.dart';
import '../ui/theme_page_parts.dart';
import '../ui/tokens.dart';
import '../ui/focus_parts.dart';
import '../ui/focus_account_row.dart';
import 'jw_preview_page.dart';
import 'timetable_import_confirmation.dart';
import 'webview_login_page.dart';
import 'zf_login_page.dart';

class AccountsPage extends StatelessWidget {
  const AccountsPage({super.key, required this.state});

  final AppState state;

  Future<void> _clearCookiesFor(String loggingOut) async {
    final config = loggingOut == 'zf' ? JwStore.load() : null;
    await PlatformCookie.clearPlatformCookies(
      loggingOut,
      origins: config == null ? const [] : [config.url],
    );
  }

  @override
  Widget build(BuildContext context) {
    return StyleBackground(
      // 玻璃样式下透明化 Scaffold，露出渐变磨砂底衬
      child: Scaffold(
        backgroundColor: scaffoldBgOf(context),
        appBar: AppBar(title: appBarTitle(context, '账号')),
        body: ListenableBuilder(
          listenable: state,
          builder: (context, _) => ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            children: _layoutAccounts(context, [
              if (!paletteOf(context).clean) ...[
                ThemePageHeader(
                  compact: true,
                  title: '平台账号',
                  kicker: 'ACCOUNTS / 06 PLATFORMS',
                  summary: _connectionSummary,
                  icon: Icons.link_rounded,
                ),
                const SizedBox(height: 20),
              ],
              if (state.lastSync != null)
                Padding(
                  padding: const EdgeInsets.only(left: 4, bottom: 10),
                  child: Text(
                    // 小票：同步时间就是收据的打印时间
                    '${isReceiptStyle(context) ? '打印于' : '上次同步：'}'
                    '${state.lastSync!.month}月${state.lastSync!.day}日 '
                    '${state.lastSync!.hour.toString().padLeft(2, '0')}:'
                    '${state.lastSync!.minute.toString().padLeft(2, '0')}',
                    style: monoText(
                      context,
                      TextStyle(fontSize: 12, color: textFaint(context)),
                    ),
                  ),
                ),
              _accountCard(
                context,
                index: 1,
                title: PlatformKind.chaoxing.label,
                state: state.chaoxingState,
                extra: Storage.chaoxingUid() == null
                    ? null
                    : 'UID ${Storage.chaoxingUid()}',
                onLogin: () => _openLogin(context, PlatformKind.chaoxing),
                onLogout: () async {
                  await state.logoutChaoxing();
                  await _clearCookiesFor('cx');
                },
              ),
              const SizedBox(height: 14),
              _accountCard(
                context,
                index: 2,
                title: PlatformKind.mooc.label,
                state: state.moocState,
                onLogin: () => _openLogin(context, PlatformKind.mooc),
                onLogout: () async {
                  await state.logoutMooc();
                  await _clearCookiesFor('mooc');
                },
              ),
              const SizedBox(height: 14),
              _accountCard(
                context,
                index: 3,
                title: PlatformKind.zhihuishu.label,
                state: state.zhihuishuState,
                onLogin: () => _openLogin(context, PlatformKind.zhihuishu),
                onLogout: () async {
                  await state.logoutZhihuishu();
                  await _clearCookiesFor('zhs');
                },
              ),
              const SizedBox(height: 14),
              _accountCard(
                context,
                index: 4,
                title: PlatformKind.xuetangx.label,
                state: state.xuetangxState,
                onLogin: () => _openLogin(context, PlatformKind.xuetangx),
                onLogout: () async {
                  await state.logoutXuetangx();
                  await _clearCookiesFor('xtx');
                },
              ),
              const SizedBox(height: 14),
              _accountCard(
                context,
                index: 5,
                title: PlatformKind.yuketang.label,
                state: state.yuketangState,
                onLogin: () => _openLogin(context, PlatformKind.yuketang),
                onLogout: () async {
                  await state.logoutYuketang();
                  await _clearCookiesFor('ykt');
                },
              ),
              const SizedBox(height: 14),
              _accountCard(
                context,
                index: 6,
                title: JwStore.hasConfig
                    ? '教务系统 · ${JwStore.load()!.name}'
                    : '教务系统',
                state: state.zfState,
                extra: Storage.zfXh() == null ? null : '学号 ${Storage.zfXh()}',
                onLogin: () async {
                  // 接住抓取结果：此前 push 返回值被丢弃，登录+抓取全流程
                  // 走完 cookie 不落盘、课表不入库、卡片仍显示「未登录」
                  final result = await Navigator.of(context).push<Object?>(
                    MaterialPageRoute(builder: (_) => const ZfLoginPage()),
                  );
                  if (result is! ZfCapture || !context.mounted) return;
                  final selected = await Navigator.of(context)
                      .push<List<Course>>(
                        MaterialPageRoute(
                          builder: (_) => JwPreviewPage(
                            courses: result.parsed.courses,
                            sourceLabel: result.sourceName,
                          ),
                        ),
                      );
                  if (selected == null ||
                      selected.isEmpty ||
                      !context.mounted) {
                    return;
                  }
                  final fullImport = await confirmTimetableImport(
                    context,
                    selected: selected,
                    existing: Storage.courses(),
                    sourceLabel: result.sourceName,
                    requiresReplacement: state.timetableRequiresReplacement(
                      xh: result.parsed.xh,
                      semesterText: result.parsed.semesterText,
                    ),
                    replacementPreview: state.timetableReplacement(
                      selected,
                      xh: result.parsed.xh,
                      semesterText: result.parsed.semesterText,
                    ),
                  );
                  if (fullImport == null || !context.mounted) return;
                  await state.onTimetableCaptured(
                    cookie: result.cookie,
                    xh: result.parsed.xh,
                    courses: selected,
                    rawPage: result.parsed.rawPage,
                    semesterText: result.parsed.semesterText,
                    detectedWeek: result.parsed.detectedWeek,
                    source: result.sourceName,
                    // 教务抓取是整表导入：整表替换而非同学期补课式合并
                    //（文本/截图兜底导入才走 union）
                    fullImport: fullImport,
                  );
                },
                onLogout: () async {
                  // 退出会清掉整张课表，必须先确认（含手动课豁免说明）
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (dialogContext) => ThemedAlertDialog(
                      title: const Text('退出教务系统'),
                      content: const Text(
                        '将清除教务登录状态、已导入的课表和开学日期校准；'
                        '手动添加的课程会保留（颜色恢复默认）。确定退出？',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () =>
                              Navigator.of(dialogContext).pop(false),
                          child: const Text('取消'),
                        ),
                        FilledButton(
                          onPressed: () =>
                              Navigator.of(dialogContext).pop(true),
                          child: const Text('退出'),
                        ),
                      ],
                    ),
                  );
                  if (ok != true) return;
                  // logoutZf 清除配置前保留目标域，不能在退出后才查到空域。
                  final targetUrl = JwStore.load()?.url;
                  await state.logoutZf();
                  await PlatformCookie.clearPlatformCookies(
                    'zf',
                    origins: targetUrl == null ? const [] : [targetUrl],
                  );
                },
              ),
              const SizedBox(height: 20),
              // 水墨：卡列与落款之间一笔飞白收束
              if (isInkStyle(context))
                Padding(
                  padding: const EdgeInsets.only(left: 4, right: 4, bottom: 14),
                  child: BrushLine(
                    color: textSecondary(context).withValues(alpha: 0.30),
                    thickness: 2.4,
                  ),
                ),
              Text(
                '通过平台官方页面登录，账号信息仅保存在本机。\n'
                '教务系统可能需要校园网或学校 VPN。',
                style: TextStyle(
                  fontSize: 12.5,
                  color: Colors.grey.shade500,
                  height: 1.7,
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  List<Widget> _layoutAccounts(BuildContext context, List<Widget> original) {
    if (!paletteOf(context).sunny) return original;
    final rows = original.whereType<FocusAccountRow>().toList();
    final connected = rows.where((r) => r.state == AccountState.ok).length;
    final expired = rows
        .where((r) => r.state == AccountState.needRelogin)
        .length;
    return [
      FocusSummary(
        eyebrow: '已连接的平台',
        title: '$connected / ${rows.length}',
        detail: expired > 0
            ? '$expired 个平台需要重新登录，原有作业仍保留。'
            : connected == 0
            ? '连接学习平台，自动获取你的课程作业。'
            : _connectionSummary,
        trailing: Icon(
          Icons.link_rounded,
          size: 30,
          color: paletteOf(context).onAccent,
        ),
        child: connected == 0
            ? null
            : SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: state.syncing ? null : () => state.syncAll(),
                  icon: const Icon(Icons.sync_rounded, size: 18),
                  label: Text(state.syncing ? '正在同步…' : '同步已连接平台'),
                ),
              ),
      ),
      for (final (value, title) in [
        (AccountState.needRelogin, '需要重新登录'),
        (AccountState.ok, '已连接'),
        (AccountState.notLoggedIn, '可连接的平台'),
      ]) ...[
        if (rows.any((r) => r.state == value))
          FocusSectionTitle(
            title,
            detail: '${rows.where((r) => r.state == value).length} 个',
          ),
        ...rows.where((r) => r.state == value),
      ],
      if (state.lastSync != null)
        Padding(
          padding: const EdgeInsets.only(top: 20),
          child: Text(
            '最近同步 ${state.lastSync!.month}月${state.lastSync!.day}日 '
            '${state.lastSync!.hour.toString().padLeft(2, '0')}:${state.lastSync!.minute.toString().padLeft(2, '0')}',
            style: TextStyle(fontSize: 12, color: textSecondary(context)),
          ),
        ),
      const SizedBox(height: 20),
      original.last,
    ];
  }

  Future<void> _openLogin(BuildContext context, PlatformKind platform) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => WebviewLoginPage(platform: platform, state: state),
      ),
    );
  }

  String get _connectionSummary {
    final accounts = [
      state.chaoxingState,
      state.moocState,
      state.zhihuishuState,
      state.xuetangxState,
      state.yuketangState,
      state.zfState,
    ];
    final connected = accounts.where((s) => s == AccountState.ok).length;
    final expired = accounts.where((s) => s == AccountState.needRelogin).length;
    return '已连接 $connected / 6 · 待重新登录 $expired';
  }

  Widget _themedAccountCard(
    BuildContext context, {
    required int index,
    required String title,
    required String label,
    required Color statusColor,
    required AccountState state,
    required String? extra,
    required VoidCallback onLogin,
    required VoidCallback onLogout,
  }) {
    final pal = paletteOf(context);
    final number = index.toString().padLeft(2, '0');
    final swatch = Color.lerp(
      pal.card,
      Tokens.avatarSoftColor(title),
      isDark(context) ? 0.24 : 0.16,
    )!;
    final titleStyle = TextStyle(
      color: pal.ink,
      fontWeight: FontWeight.w800,
      fontSize: pal.editorial || pal.inkWash ? 22 : 18,
      height: 1.4,
      fontFamily: pal.paper || pal.inkWash ? 'serif' : null,
    );
    Widget caption(String value, {Color? color}) => Text(
      value,
      style: monoText(
        context,
        TextStyle(
          color: color ?? pal.ink2,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.7,
          height: 1.6,
        ),
      ),
    );
    Widget platform({bool centered = false, bool showIcon = true}) {
      final name = Text(
        title,
        style: titleStyle,
        textAlign: centered ? TextAlign.center : TextAlign.start,
      );
      if (centered) {
        return Column(
          children: [
            if (showIcon) ...[
              AccountPlatformIcon(index: index, size: 46),
              const SizedBox(height: 8),
            ],
            name,
          ],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showIcon) ...[
            AccountPlatformIcon(index: index, size: 42),
            const SizedBox(width: 12),
          ],
          Expanded(child: name),
        ],
      );
    }

    // A status always wraps independently from the identity. Long school names,
    // UID values and an expired session must all stay readable at large text.
    Widget status({bool centered = false, bool bracketed = false}) => Column(
      crossAxisAlignment: centered
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.start,
      children: [
        Text(
          bracketed ? '[ $label ]' : label,
          textAlign: centered ? TextAlign.center : TextAlign.start,
          style: monoText(
            context,
            TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              height: 1.6,
              color: statusColor,
            ),
          ),
        ),
        if (extra != null) ...[
          const SizedBox(height: 4),
          Text(
            extra,
            textAlign: centered ? TextAlign.center : TextAlign.start,
            style: monoText(
              context,
              TextStyle(fontSize: 12, height: 1.6, color: pal.ink2),
            ),
          ),
        ],
      ],
    );

    Widget actions() => Row(
      children: [
        Expanded(
          child: state == AccountState.ok
              ? OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(44),
                  ),
                  onPressed: onLogin,
                  child: const Text('重新登录'),
                )
              : FilledButton(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(44),
                  ),
                  onPressed: onLogin,
                  child: Text(
                    state == AccountState.needRelogin ? '重新登录' : '登录',
                  ),
                ),
        ),
        if (state != AccountState.notLoggedIn) ...[
          const SizedBox(width: 6),
          TextButton(onPressed: onLogout, child: const Text('退出')),
        ],
      ],
    );

    Widget rule() => Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Divider(height: 1, thickness: pal.editorial ? 2 : 1),
    );
    Widget dash() => Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: DashedLine(color: pal.ink2.withValues(alpha: 0.5)),
    );
    Widget tag(String value, {bool solid = false}) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: solid ? pal.accentFill : null,
        border: Border.all(color: pal.accent),
        borderRadius: BorderRadius.circular(pal.morandi ? 20 : 1),
      ),
      child: caption(value, color: solid ? pal.onAccent : pal.accent),
    );

    late final Widget content;
    if (pal.morandi) {
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: swatch,
              borderRadius: BorderRadius.circular(22),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                caption('PLATFORM $number / 06'),
                const SizedBox(height: 14),
                platform(),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
            child: status(),
          ),
          actions(),
        ],
      );
    } else if (pal.pixel) {
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            color: pal.ink,
            padding: const EdgeInsets.all(9),
            child: caption('ACCOUNT_$number.EXE  [ + ]', color: pal.card),
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                color: swatch,
                child: AccountPlatformIcon(index: index, size: 44),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    caption('PLAYER LINK $number'),
                    platform(showIcon: false),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              border: Border.all(color: pal.ink, width: 2),
            ),
            child: status(bracketed: true),
          ),
          const SizedBox(height: 12),
          actions(),
        ],
      );
    } else if (pal.inkWash) {
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    caption('平台 · $number'),
                    const SizedBox(height: 14),
                    platform(showIcon: false),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              tag('账号\n$number', solid: true),
            ],
          ),
          const SizedBox(height: 10),
          BrushLine(color: pal.ink.withValues(alpha: 0.35), thickness: 2.3),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.only(left: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AccountPlatformIcon(index: index, size: 34),
                const SizedBox(width: 14),
                Expanded(child: status()),
              ],
            ),
          ),
          const SizedBox(height: 14),
          actions(),
        ],
      );
    } else if (pal.paper) {
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          caption('账号档案  /  FILE $number'),
          dash(),
          platform(),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
            decoration: BoxDecoration(
              border: Border(left: BorderSide(color: pal.ink2, width: 2)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [caption('连接记录'), const SizedBox(height: 4), status()],
            ),
          ),
          dash(),
          actions(),
        ],
      );
    } else if (pal.comic) {
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Align(alignment: Alignment.centerRight, child: tag('LINK!  $number')),
          const SizedBox(height: 12),
          platform(),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: swatch,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(18),
                topRight: Radius.circular(18),
                bottomRight: Radius.circular(18),
              ),
              border: Border.all(color: pal.cardBorder, width: 2),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [caption('连接小报'), status()],
            ),
          ),
          const SizedBox(height: 12),
          actions(),
        ],
      );
    } else if (pal.receipt) {
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(child: caption('CONNECTION RECEIPT')),
          const SizedBox(height: 6),
          Center(child: caption('平台凭单 $number / 06')),
          const SizedBox(height: 10),
          platform(centered: true),
          dash(),
          Center(child: caption('连接状态 / STATUS')),
          const SizedBox(height: 6),
          status(centered: true),
          dash(),
          actions(),
          const SizedBox(height: 12),
          SizedBox(
            height: 22,
            child: CustomPaint(
              painter: ReceiptBarcodePainter(
                color: pal.ink,
                seed: stableHash(title),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Center(child: caption('NO.${stableHash(title).abs() % 9000 + 1000}')),
        ],
      );
    } else if (pal.editorial) {
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            number,
            style: TextStyle(
              fontSize: 42,
              height: 1,
              fontWeight: FontWeight.w900,
              color: pal.ink,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.only(left: 12),
            decoration: BoxDecoration(
              border: Border(left: BorderSide(color: pal.accent, width: 4)),
            ),
            child: platform(showIcon: false),
          ),
          rule(),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AccountPlatformIcon(index: index, size: 34),
              const SizedBox(width: 10),
              Expanded(child: status()),
            ],
          ),
          rule(),
          actions(),
        ],
      );
    } else if (pal.terminal) {
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.terminal, size: 16, color: pal.accent),
              const SizedBox(width: 8),
              Expanded(child: caption('account_$number.sh')),
              caption('─ □ ×'),
            ],
          ),
          rule(),
          caption(r'$ connect --platform'),
          const SizedBox(height: 10),
          platform(),
          const SizedBox(height: 10),
          caption('> session.status'),
          const SizedBox(height: 6),
          status(bracketed: true),
          const SizedBox(height: 12),
          caption(r'$ action'),
          const SizedBox(height: 8),
          actions(),
        ],
      );
    } else {
      // Journal: tape, blue-ink ruling and paired stamps make each connection
      // read as a notebook entry rather than another generic settings card.
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Align(
            alignment: Alignment.center,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 5),
              color: pal.accentFill.withValues(alpha: 0.12),
              child: caption('账号手记 · $number'),
            ),
          ),
          const SizedBox(height: 12),
          platform(),
          rule(),
          status(),
          rule(),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [tag('平台 $number'), tag('本机保存')],
          ),
          const SizedBox(height: 10),
          actions(),
        ],
      );
    }
    return ThemePanel(
      key: ValueKey('account-$index'),
      seed: 'account-$index',
      padding: EdgeInsets.all(pal.morandi ? 12 : 14),
      child: content,
    );
  }

  Widget _accountCard(
    BuildContext context, {
    required int index,
    required String title,
    required AccountState state,
    String? extra,
    required VoidCallback onLogin,
    required VoidCallback onLogout,
  }) {
    final pal = paletteOf(context);
    final (label, statusColor) = switch (state) {
      AccountState.ok => ('已登录', const Color(0xFF16A34A)),
      AccountState.needRelogin => ('登录已失效，请重新登录', const Color(0xFFF59E0B)),
      AccountState.notLoggedIn => ('未登录', Colors.grey.shade500),
    };

    if (pal.sunny) {
      return FocusAccountRow(
        index: index,
        title: title,
        state: state,
        label: label,
        extra: extra,
        onLogin: onLogin,
        onLogout: onLogout,
      );
    }

    if (!pal.clean) {
      return _themedAccountCard(
        context,
        index: index,
        title: title,
        label: label,
        statusColor: statusColor,
        state: state,
        extra: extra,
        onLogin: onLogin,
        onLogout: onLogout,
      );
    }

    return Container(
      padding: const EdgeInsets.all(18),
      decoration:
          inkWashFill(context, cardRadius(context)) ??
          (pal.pixel
              // 像素：素面方形卡，勾线交给 pixelFrame 窗框
              ? BoxDecoration(color: cardColor(context))
              : pal.receipt
              // 小票：整卡是一张热敏收据（撕纸底边）
              ? receiptTear(context)
              : pal.editorial
              // 杂志：去盒化版块，规则线画在前景
              ? BoxDecoration(color: cardColor(context))
              : BoxDecoration(
                  color: cardColor(context),
                  borderRadius: BorderRadius.circular(cardRadius(context)),
                  border: cardBorderOf(context),
                )),
      foregroundDecoration: pal.pixel
          ? pixelFrame(context, cardRadius(context))
          : paperInnerRing(context, cardRadius(context)) ??
                morandiCream(context, cardRadius(context)) ??
                editorialRules(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AccountPlatformIcon(index: index, size: 50),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        // 小票：抬头拉字距，像收据顶部的店名
                        letterSpacing: isReceiptStyle(context) ? 2 : null,
                        color: textPrimary(context),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Container(
                          width: 7,
                          height: 7,
                          // 小票：状态是打印的方点，不是圆点
                          decoration: isReceiptStyle(context)
                              ? BoxDecoration(
                                  color: statusColor,
                                  borderRadius: BorderRadius.circular(1.5),
                                )
                              : BoxDecoration(
                                  color: statusColor,
                                  shape: BoxShape.circle,
                                ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            extra == null ? label : '$label · $extra',
                            overflow: TextOverflow.ellipsis,
                            style: monoText(
                              context,
                              TextStyle(fontSize: 12.5, color: statusColor),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                // 主按钮（品牌绿填充）只留给未登录/失效的账号——
                // 它们才是需要用户行动的；已登录降为描边次级按钮
                child: state == AccountState.ok
                    ? OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(44),
                          side: BorderSide(
                            color: isDark(context)
                                ? cardBorderColor(context)
                                : const Color(0xFFE5E7EB),
                          ),
                        ),
                        onPressed: onLogin,
                        child: Text(
                          '重新登录',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: textPrimary(context),
                          ),
                        ),
                      )
                    : FilledButton(
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(44),
                        ),
                        onPressed: onLogin,
                        child: Text(
                          state == AccountState.needRelogin ? '重新登录' : '登录',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
              ),
              if (state != AccountState.notLoggedIn) ...[
                const SizedBox(width: 8),
                TextButton(
                  onPressed: onLogout,
                  child: const Text('退出', style: TextStyle(fontSize: 14)),
                ),
              ],
            ],
          ),
          // 小票：凭单脚注——虚线分区 + 条码 + 单号（同平台恒定）
          if (isReceiptStyle(context)) ...[
            const SizedBox(height: 12),
            DashedLine(
              color: textPrimary(context)
                  .withValues(alpha: isDark(context) ? 0.30 : 0.28),
              thickness: 1,
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: SizedBox(
                    height: 14,
                    child: CustomPaint(
                      painter: ReceiptBarcodePainter(
                        color: textPrimary(context)
                            .withValues(alpha: isDark(context) ? 0.65 : 0.75),
                        seed: stableHash(title),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  'NO.${stableHash(title).abs() % 9000 + 1000}',
                  style: monoText(
                    context,
                    TextStyle(
                      fontSize: 9.5,
                      letterSpacing: 1.2,
                      fontWeight: FontWeight.w600,
                      color: textSecondary(context),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
