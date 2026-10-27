/// 账号管理：学习通 / 中国大学MOOC / 教务系统的登录态与 WebView 登录入口。
library;

import 'package:flutter/material.dart';

import '../ui/activity_icon.dart';

import '../app_state.dart';
import '../ui/theme_forms.dart';
import '../models/course.dart';
import '../models/homework.dart';
import '../services/jw_config.dart';
import '../services/platform_cookie.dart';
import '../services/storage.dart';
import '../ui/adaptive.dart';
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
        appBar: AppBar(
          toolbarHeight: 68,
          titleSpacing: 20,
          title: appBarTitle(context, '账号', root: true),
        ),
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
    final rows = original.whereType<FocusAccountRow>().toList();
    final connected = rows.where((r) => r.state == AccountState.ok).length;
    final expired = rows
        .where((r) => r.state == AccountState.needRelogin)
        .length;
    return [
      FocusSummary(
        compact: true,
        yellow: false,
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
          color: paletteOf(context).accent,
        ),
        child: connected == 0
            ? null
            : SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: state.syncing ? null : () => state.syncAll(),
                  icon: ActivityIcon(
                    Icons.sync_rounded,
                    active: state.syncing,
                    size: 18,
                  ),
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

  Widget _accountCard(
    BuildContext context, {
    required int index,
    required String title,
    required AccountState state,
    String? extra,
    required VoidCallback onLogin,
    required VoidCallback onLogout,
  }) {
    final label = switch (state) {
      AccountState.ok => '已登录',
      AccountState.needRelogin => '登录已失效，请重新登录',
      AccountState.notLoggedIn => '未登录',
    };
    return FocusAccountRow(
      key: ValueKey('account-$index'),
      index: index,
      title: title,
      state: state,
      label: label,
      extra: extra,
      onLogin: onLogin,
      onLogout: onLogout,
    );
  }
}
