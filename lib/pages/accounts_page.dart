/// 账号管理：学习通 / 中国大学MOOC / 教务系统的登录态与 WebView 登录入口。
library;

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models/course.dart';
import '../models/homework.dart';
import '../services/jw_config.dart';
import '../services/platform_cookie.dart';
import '../services/stable_hash.dart';
import '../services/storage.dart';
import '../ui/adaptive.dart';
import '../ui/dashed_line.dart';
import '../ui/ink_wash.dart';
import '../ui/style_background.dart';
import '../ui/tokens.dart';
import 'jw_preview_page.dart';
import 'webview_login_page.dart';
import 'zf_login_page.dart';

class AccountsPage extends StatelessWidget {
  const AccountsPage({super.key, required this.state});

  final AppState state;

  /// 各平台共用一个 WebView Cookie 罐：退出任一平台时把其它仍在登录中的
  /// 平台会话备份并装回，只真正清掉自己这份。
  /// [loggingOut] ∈ cx/mooc/zhs/xtx/ykt/zf。
  Future<void> _clearCookiesFor(String loggingOut) async {
    final keep = <String>{};
    if (loggingOut != 'cx') keep.add('https://www.chaoxing.com/');
    if (loggingOut != 'mooc') keep.add('https://www.icourse163.org/');
    if (loggingOut != 'ykt') {
      // 雨课堂会话 Cookie 落 *.yuketang.cn（学校子域/pro/父域均可能），
      // 主站与长江两个 origin 整串带回
      keep.add('https://www.yuketang.cn/');
      keep.add('https://pro.yuketang.cn/');
    }
    if (loggingOut != 'xtx') {
      // 学堂在线会话 Cookie 落 .xuetangx.com 父域（www/裸域都可能），整串带回
      keep.add('https://www.xuetangx.com/');
      keep.add('https://xuetangx.com/');
    }
    if (loggingOut != 'zhs') {
      // 智慧树会话 Cookie 的实际落域未经抓包确认（父域/host-only 均可能，
      // 捕获 origin 是 onlineservice-api）：备份 CAS 入口、service 落点、
      // API 网关与在线学堂四个 origin，整串带回不漏域
      keep.add('https://passport.zhihuishu.com/');
      keep.add('https://onlineservice.zhihuishu.com/');
      keep.add('https://onlineservice-api.zhihuishu.com/');
      keep.add('https://onlineweb.zhihuishu.com/');
    }
    if (loggingOut != 'zf') {
      final zfConfig = JwStore.load();
      final uri = zfConfig == null ? null : Uri.tryParse(zfConfig.url);
      if (uri != null && uri.host.isNotEmpty) {
        keep.add('${uri.scheme}://${uri.host}/');
      }
    }
    await PlatformCookie.clearCookiesExcept(keep);
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
          children: [
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
              title: PlatformKind.chaoxing.label,
              state: state.chaoxingState,
              extra: Storage.chaoxingUid() == null ? null : 'UID ${Storage.chaoxingUid()}',
              icon: Icons.school_rounded,
              gradient: const [Color(0xFF3B82F6), Color(0xFF6366F1)],
              onLogin: () => _openLogin(context, PlatformKind.chaoxing),
              onLogout: () async {
                await state.logoutChaoxing();
                await _clearCookiesFor('cx');
              },
            ),
            const SizedBox(height: 14),
            _accountCard(
              context,
              title: PlatformKind.mooc.label,
              state: state.moocState,
              icon: Icons.menu_book_rounded,
              gradient: const [Color(0xFFF43F5E), Color(0xFFF97316)],
              onLogin: () => _openLogin(context, PlatformKind.mooc),
              onLogout: () async {
                await state.logoutMooc();
                await _clearCookiesFor('mooc');
              },
            ),
            const SizedBox(height: 14),
            _accountCard(
              context,
              title: PlatformKind.zhihuishu.label,
              state: state.zhihuishuState,
              icon: Icons.park_rounded,
              gradient: const [Color(0xFF16A34A), Color(0xFF22C55E)],
              onLogin: () => _openLogin(context, PlatformKind.zhihuishu),
              onLogout: () async {
                await state.logoutZhihuishu();
                await _clearCookiesFor('zhs');
              },
            ),
            const SizedBox(height: 14),
            _accountCard(
              context,
              title: PlatformKind.xuetangx.label,
              state: state.xuetangxState,
              icon: Icons.auto_stories_rounded,
              gradient: const [Color(0xFF0EA5E9), Color(0xFF0284C7)],
              onLogin: () => _openLogin(context, PlatformKind.xuetangx),
              onLogout: () async {
                await state.logoutXuetangx();
                await _clearCookiesFor('xtx');
              },
            ),
            const SizedBox(height: 14),
            _accountCard(
              context,
              title: PlatformKind.yuketang.label,
              state: state.yuketangState,
              icon: Icons.cloud_rounded,
              gradient: const [Color(0xFF6366F1), Color(0xFF8B5CF6)],
              onLogin: () => _openLogin(context, PlatformKind.yuketang),
              onLogout: () async {
                await state.logoutYuketang();
                await _clearCookiesFor('ykt');
              },
            ),
            const SizedBox(height: 14),
            _accountCard(
              context,
              title: JwStore.hasConfig
                  ? '教务系统 · ${JwStore.load()!.name}'
                  : '教务系统',
              state: state.zfState,
              extra: Storage.zfXh() == null ? null : '学号 ${Storage.zfXh()}',
              icon: Icons.view_timeline_rounded,
              gradient: const [Color(0xFF0F6B54), Color(0xFF17997A)],
              onLogin: () async {
                // 接住抓取结果：此前 push 返回值被丢弃，登录+抓取全流程
                // 走完 cookie 不落盘、课表不入库、卡片仍显示「未登录」
                final result = await Navigator.of(context).push<Object?>(
                  MaterialPageRoute(builder: (_) => const ZfLoginPage()),
                );
                if (result is! ZfCapture || !context.mounted) return;
                final selected = await Navigator.of(context).push<List<Course>>(
                  MaterialPageRoute(
                    builder: (_) => JwPreviewPage(
                      courses: result.parsed.courses,
                      sourceLabel: result.sourceName,
                    ),
                  ),
                );
                if (selected == null || selected.isEmpty || !context.mounted) {
                  return;
                }
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
                  fullImport: true,
                );
              },
              onLogout: () async {
                // 退出会清掉整张课表，必须先确认（含手动课豁免说明）
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (dialogContext) => AlertDialog(
                    title: const Text('退出教务系统'),
                    content: const Text(
                        '将清除教务登录状态、已导入的课表和开学日期校准；'
                        '手动添加的课程会保留（颜色恢复默认）。确定退出？'),
                    actions: [
                      TextButton(
                          onPressed: () =>
                              Navigator.of(dialogContext).pop(false),
                          child: const Text('取消')),
                      FilledButton(
                          onPressed: () =>
                              Navigator.of(dialogContext).pop(true),
                          child: const Text('退出')),
                    ],
                  ),
                );
                if (ok != true) return;
                await state.logoutZf();
                await _clearCookiesFor('zf');
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
              '登录在 App 内嵌的官方页面中完成，Cookie 仅保存在本机。\n'
              '作业通只读取你自己账号的作业列表，不会提交任何数据。\n'
              '教务系统需校园网或学校 VPN 环境。',
              style: TextStyle(
                fontSize: 12.5,
                color: Colors.grey.shade500,
                height: 1.7,
              ),
            ),
          ],
        ),
      ),
        ),
    );
  }

  Future<void> _openLogin(BuildContext context, PlatformKind platform) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => WebviewLoginPage(platform: platform, state: state),
    ));
  }

  Widget _accountCard(
    BuildContext context, {
    required String title,
    required AccountState state,
    String? extra,
    required IconData icon,
    required List<Color> gradient,
    required VoidCallback onLogin,
    required VoidCallback onLogout,
  }) {
    final pal = paletteOf(context);
    final (label, statusColor) = switch (state) {
      AccountState.ok => ('已登录', const Color(0xFF16A34A)),
      AccountState.needRelogin => ('登录已失效，请重新登录', const Color(0xFFF59E0B)),
      AccountState.notLoggedIn => ('未登录', Colors.grey.shade500),
    };

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: inkWashFill(context, cardRadius(context)) ??
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
                          borderRadius:
                              BorderRadius.circular(cardRadius(context)),
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
              Container(
                width: 46,
                height: 46,
                // 水墨：平台图标是一方墨石（墨线描边的淡墨板块 + 焦墨图标），
                // 平台彩色渐变不上墨面；漫画：白底贴纸块 + 剪影描边。
                // 墨石不用笔锋圆角——对角大小圆在 46px 小盒+描边上读出来
                // 是一片叶子（用户实测），笔锋只留给大卡面
                decoration: BoxDecoration(
                  borderRadius: (isPixelStyle(context) ||
                          isReceiptStyle(context))
                      ? BorderRadius.circular(2)
                      : BorderRadius.circular(14),
                  gradient: (isInkStyle(context) ||
                          isComicStyle(context) ||
                          isPixelStyle(context))
                      ? null
                      : LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: gradient,
                        ),
                  color: isInkStyle(context)
                      ? (isDark(context)
                          ? Colors.white.withValues(alpha: 0.10)
                          : Colors.black.withValues(alpha: 0.08))
                      : isComicStyle(context) || isPixelStyle(context)
                          ? (isDark(context)
                              ? const Color(0xFF2E1E26)
                              : Colors.white)
                          : null,
                  border: isInkStyle(context)
                      ? Border.all(
                          color: (isDark(context)
                                  ? Colors.white
                                  : Colors.black)
                              .withValues(alpha: 0.25))
                      : isComicStyle(context) || isPixelStyle(context)
                          ? Border.all(
                              color: paletteOf(context).cardBorder, width: 1.4)
                          : isReceiptStyle(context)
                              ? Border.all(
                                  color: paletteOf(context)
                                      .cardBorder
                                      .withValues(alpha: 0.6),
                                  width: 1)
                              : null,
                  boxShadow: isComicStyle(context) || isPixelStyle(context)
                      ? [
                          BoxShadow(
                            color: paletteOf(context).cardBorder,
                            blurRadius: 0,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                child: Icon(
                  icon,
                  color: isInkStyle(context) || isPixelStyle(context)
                      ? textPrimary(context)
                      : (isComicStyle(context) ? gradient.first : Colors.white),
                  size: 22,
                ),
              ),
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
                                  borderRadius: BorderRadius.circular(1.5))
                              : BoxDecoration(
                                  color: statusColor, shape: BoxShape.circle),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            extra == null ? label : '$label · $extra',
                            overflow: TextOverflow.ellipsis,
                            style: monoText(
                              context,
                              TextStyle(
                                  fontSize: 12.5, color: statusColor),
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
              color: textPrimary(context).withValues(alpha: isDark(context) ? 0.30 : 0.28),
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
                        color: textSecondary(context)),
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
