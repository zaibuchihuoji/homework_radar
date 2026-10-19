/// WebView 登录页：加载平台真实登录页，登录成功后捕获 Cookie。
/// HttpOnly Cookie 无法用 document.cookie 读取，走原生 CookieManager 通道。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../app_state.dart';
import '../models/homework.dart';
import '../services/mooc_service.dart';
import '../services/platform_cookie.dart';
import '../services/xuetangx_service.dart';
import '../services/yuketang_service.dart';
import '../services/zhihuishu_service.dart';
import '../ui/adaptive.dart';
import '../ui/ink_wash.dart';
import '../ui/style_background.dart';
import '../ui/theme_page_parts.dart';
import '../ui/tokens.dart';

class WebviewLoginPage extends StatefulWidget {
  const WebviewLoginPage({
    super.key,
    required this.platform,
    required this.state,
  });

  final PlatformKind platform;
  final AppState state;

  @override
  State<WebviewLoginPage> createState() => _WebviewLoginPageState();
}

class _WebviewLoginPageState extends State<WebviewLoginPage> {
  late final WebViewController _controller;
  bool _captured = false;
  bool _saveFailed = false;

  /// 捕获防重入：守卫检查与置位之间隔着 getCookie 的通道往返，
  /// onPageFinished 与「检测」按钮并发时能同时越过守卫、重复 pop
  bool _trying = false;
  String _status = '请在页面中登录你的账号';

  String get _startUrl => switch (widget.platform) {
    PlatformKind.chaoxing => 'https://passport2.chaoxing.com/login',
    PlatformKind.zhihuishu =>
      // CAS 流：登录成功后 service 跳转回 onlineservice，并在
      // *.zhihuishu.com 父域种下会话 Cookie（无需知道具体 Cookie 名）
      'https://passport.zhihuishu.com/login'
          '?service=https://onlineservice.zhihuishu.com/login/gologin',
    // 学堂在线登录页路径随版本变动过，直接进首页让用户点「登录」最稳
    PlatformKind.xuetangx => 'https://www.xuetangx.com/',
    // 雨课堂主站根路径是营销官网（无登录入口）；/web 才是「雨课堂
    // 网页版-登录」页，各学校通用，登录后 *.yuketang.cn 父域种会话
    PlatformKind.yuketang => 'https://www.yuketang.cn/web',
    _ => 'https://www.icourse163.org/home.htm',
  };

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(onPageFinished: (_) => _tryCapture()),
      );
    unawaited(_startLogin());
  }

  Future<void> _startLogin() async {
    try {
      await PlatformCookie.clearPlatformCookies(widget.platform.name);
      if (mounted) await _controller.loadRequest(Uri.parse(_startUrl));
    } catch (_) {
      if (mounted) setState(() => _status = '无法清理旧登录状态，请返回后重试');
    }
  }

  Future<void> _commitLogin(Future<void> Function() save) async {
    if (!mounted) return;
    setState(() => _status = '正在保存登录状态…');
    try {
      // 持久凭据和旧账号归档均确认成功后才离开页面。
      await save();
    } catch (_) {
      _captured = false;
      _saveFailed = true;
      if (mounted) {
        setState(() => _status = '本地保存或归档失败，尚未完成登录，请点击「检测」重试');
      }
      return;
    }
    _captured = true;
    if (mounted) Navigator.of(context).pop(true);
    // 同步与持久提交分开，慢网络不会阻塞成功返回；同步失败不冒充保存失败。
    unawaited(widget.state.syncAll());
  }

  Future<void> _tryCapture() async {
    if (!mounted || _trying || _captured) return;
    setState(() {
      _trying = true;
      _saveFailed = false;
    });
    try {
      if (widget.platform == PlatformKind.chaoxing) {
        // 还停在登录页时不捕获：残留在 Cookie 罐里的旧账号会话会被当成
        // 「登录成功」立即弹回——服务端已失效的旧 Cookie 进不了登录表单、
        // 想换号的用户也被静默吞掉
        final url = await _controller.currentUrl();
        if (url != null &&
            Uri.parse(url).host.endsWith('passport2.chaoxing.com')) {
          return;
        }
        final cookie = await PlatformCookie.getCookie(
          'https://www.chaoxing.com/',
        );
        if (cookie != null &&
            cookie.contains('UID=') &&
            cookie.contains('_uid=')) {
          final uid = RegExp(r'UID=(\d+)').firstMatch(cookie)?.group(1);
          await _commitLogin(
            () => widget.state.onChaoxingLogin(cookie, uid, sync: false),
          );
        }
      } else if (widget.platform == PlatformKind.zhihuishu) {
        // 还停在 CAS 登录页不捕获：对齐学习通——残留旧账号会话会被当成
        // 「登录成功」立即弹回，想换号的用户也被静默吞掉
        final url = await _controller.currentUrl();
        if (url == null) return;
        final host = Uri.parse(url).host;
        if (!host.endsWith('zhihuishu.com') || host.contains('passport')) {
          return;
        }
        // 会话 Cookie 的落域未经抓包确认（父域/host-only 均可能）：
        // 从三个 origin 依序收集、按 Cookie 名合并（先到先得）。只查
        // onlineservice-api 单点的话，host-only 落在别的域会取到空，
        // 登录成功也永远捕获不到
        final merged = <String, String>{};
        for (final origin in const [
          'https://onlineservice-api.zhihuishu.com/',
          'https://onlineservice.zhihuishu.com/',
          'https://onlineweb.zhihuishu.com/',
        ]) {
          final raw = await PlatformCookie.getCookie(origin);
          if (raw == null) continue;
          for (final pair in raw.split(';')) {
            final i = pair.indexOf('=');
            if (i <= 0) continue;
            final name = pair.substring(0, i).trim();
            if (name.isEmpty || merged.containsKey(name)) continue;
            final v = pair.substring(i + 1).trim();
            if (v.isNotEmpty) merged[name] = v;
          }
        }
        if (merged.isEmpty) return;
        final cookie = merged.entries
            .map((e) => '${e.key}=${e.value}')
            .join('; ');
        // 罐里有 Cookie ≠ 已登录（营销/追踪 Cookie 也算「有」）：拿网关
        // 探一次真会话，==true 才算捕获成功——对齐 cx 的 UID= 检查与
        // mooc 的 csrfKey 预检。null（网络失败）/false 都不捕获，用户
        // 可再点「检测」
        final ok = await ZhihuishuService(cookie: cookie).checkLogin();
        if (ok != ZhsSessionState.ok) return;
        await _commitLogin(
          () => widget.state.loginZhihuishu(cookie, sync: false),
        );
      } else if (widget.platform == PlatformKind.xuetangx) {
        // 还停在登录/passport 页不捕获：对齐学习通/智慧树——残留旧账号
        // 会话会被当成「登录成功」立即弹回
        final url = await _controller.currentUrl();
        if (url == null) return;
        final host = Uri.parse(url).host;
        if (!host.endsWith('xuetangx.com') ||
            host.contains('login') ||
            host.contains('passport')) {
          return;
        }
        // 会话 Cookie 落在 .xuetangx.com 父域（www 与裸域都可能取到）：
        // 两个 origin 依序收集、按 Cookie 名合并（先到先得）
        final merged = <String, String>{};
        for (final origin in const [
          'https://www.xuetangx.com/',
          'https://xuetangx.com/',
        ]) {
          final raw = await PlatformCookie.getCookie(origin);
          if (raw == null) continue;
          for (final pair in raw.split(';')) {
            final i = pair.indexOf('=');
            if (i <= 0) continue;
            final name = pair.substring(0, i).trim();
            if (name.isEmpty || merged.containsKey(name)) continue;
            final v = pair.substring(i + 1).trim();
            if (v.isNotEmpty) merged[name] = v;
          }
        }
        if (merged.isEmpty) return;
        final cookie = merged.entries
            .map((e) => '${e.key}=${e.value}')
            .join('; ');
        // 罐里有 Cookie ≠ 已登录：拿课程列表候选端点探一次真会话，
        // ==ok 才算捕获成功——对齐 cx 的 UID= 检查与 zhs 的网关预检
        final ok = await XuetangxService(cookie: cookie).checkLogin();
        if (ok != XtSessionState.ok) return;
        await _commitLogin(
          () => widget.state.loginXuetangx(cookie, sync: false),
        );
      } else if (widget.platform == PlatformKind.yuketang) {
        // 还停在登录页不捕获：对齐学习通/智慧树——残留旧账号会话会被
        // 当成「登录成功」立即弹回
        final url = await _controller.currentUrl();
        if (url == null) return;
        final host = Uri.parse(url).host;
        if (!host.endsWith('yuketang.cn') || host.contains('passport')) {
          return;
        }
        // 会话 Cookie 落 *.yuketang.cn 哪个域未经抓包确认（学校子域/
        // pro/父域均可能）：主站、长江、当前页三个 origin 依序收集、
        // 按 Cookie 名合并（先到先得）
        final merged = <String, String>{};
        for (final origin in const [
          'https://www.yuketang.cn/',
          'https://pro.yuketang.cn/',
        ]) {
          final raw = await PlatformCookie.getCookie(origin);
          if (raw == null) continue;
          for (final pair in raw.split(';')) {
            final i = pair.indexOf('=');
            if (i <= 0) continue;
            final name = pair.substring(0, i).trim();
            if (name.isEmpty || merged.containsKey(name)) continue;
            final v = pair.substring(i + 1).trim();
            if (v.isNotEmpty) merged[name] = v;
          }
        }
        // 当前页若是学校子域，其 host-only Cookie 也要收进来
        if (host.endsWith('yuketang.cn')) {
          final raw = await PlatformCookie.getCookie('https://$host/');
          if (raw != null) {
            for (final pair in raw.split(';')) {
              final i = pair.indexOf('=');
              if (i <= 0) continue;
              final name = pair.substring(0, i).trim();
              if (name.isEmpty || merged.containsKey(name)) continue;
              final v = pair.substring(i + 1).trim();
              if (v.isNotEmpty) merged[name] = v;
            }
          }
        }
        if (merged.isEmpty) return;
        final cookie = merged.entries
            .map((e) => '${e.key}=${e.value}')
            .join('; ');
        // 罐里有 Cookie ≠ 已登录：拿课程列表探一次真会话，==ok 才算
        // 捕获成功——对齐 cx/zhs/xtx 的预检口径
        final ok = await YuketangService(cookie: cookie).checkLogin();
        if (ok != YktSessionState.ok) return;
        await _commitLogin(
          () => widget.state.loginYuketang(cookie, sync: false),
        );
      } else {
        // 会话 Cookie（NTESSTUDYSESSINFO）落域未经抓包确认：多 origin
        // 依序收集、按 Cookie 名合并（先到先得）——对齐 zhs/xtx/ykt 口径
        final merged = <String, String>{};
        for (final origin in const [
          'https://www.icourse163.org/',
          'https://icourse163.org/',
          'https://m.icourse163.org/',
          'https://passport.icourse163.org/',
        ]) {
          final raw = await PlatformCookie.getCookie(origin);
          if (raw == null) continue;
          for (final pair in raw.split(';')) {
            final i = pair.indexOf('=');
            if (i <= 0) continue;
            final name = pair.substring(0, i).trim();
            if (name.isEmpty || merged.containsKey(name)) continue;
            final v = pair.substring(i + 1).trim();
            if (v.isNotEmpty) merged[name] = v;
          }
        }
        final cookie = merged.isEmpty
            ? null
            : merged.entries.map((e) => '${e.key}=${e.value}').join('; ');
        // 会话 Cookie 新旧双名：社区文档口径 NTESSTUDYSESSINFO 已被平台
        // 下线，2026-10-06 真机实证现行会话是 STUDY_SESS（+STUDY_PERSIST）
        if (cookie != null &&
            (cookie.contains('NTESSTUDYSESSINFO=') ||
                cookie.contains('STUDY_SESS='))) {
          final svc = MoocService(cookie: cookie);
          final csrf = await svc.refreshCsrfKey();
          // csrfKey 抓不到 = Cookie 已失效或被服务端拒绝：不捕获，让用户
          // 真正完成登录。此前照存空 csrf 并谎报「已获取 Cookie」，
          // 同步从此静默停更、界面永远显示已登录
          if (csrf == null || csrf.isEmpty) {
            return;
          }
          if (await svc.checkLogin() != true) return;
          await _commitLogin(
            () => widget.state.onMoocLogin(cookie, csrf, sync: false),
          );
        }
      }
    } finally {
      if (mounted) {
        setState(() => _trying = false);
      } else {
        _trying = false;
      }
    }
  }

  Widget _themedBody(BuildContext context) {
    final p = paletteOf(context);
    return LayoutBuilder(
      builder: (context, constraints) => Column(
        children: [
          Expanded(
            child: Container(
              margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                color: p.card,
                border: cardBorderOf(context),
                borderRadius: BorderRadius.circular(
                  p.pixel || p.terminal || p.receipt || p.editorial ? 0 : 10,
                ),
              ),
              foregroundDecoration: pixelFrame(context, 0),
              child: WebViewWidget(controller: _controller),
            ),
          ),
          SafeArea(
            top: false,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: constraints.maxHeight * .42,
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                child: ThemePanel(
                  seed: 'login-status',
                  label: p.terminal
                      ? '~/login/status'
                      : p.pixel
                      ? 'LOGIN / STATUS'
                      : '账号登录 · 状态',
                  icon: Icons.lock_outline_rounded,
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_trying)
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: p.accent,
                          ),
                        )
                      else
                        Icon(
                          _saveFailed
                              ? Icons.error_outline_rounded
                              : Icons.info_outline_rounded,
                          size: 17,
                          color: p.accent,
                        ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _status,
                          style: TextStyle(
                            fontSize: 12.5,
                            height: 1.4,
                            color: p.ink2,
                            fontFamily: p.terminal || p.receipt || p.pixel
                                ? 'monospace'
                                : p.paper || p.journal
                                ? 'serif'
                                : null,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = paletteOf(context);
    return StyleBackground(
      child: Scaffold(
        backgroundColor: p.clean ? null : scaffoldBgOf(context),
        appBar: AppBar(
          backgroundColor: cardColor(context),
          elevation: 0.5,
          centerTitle: true,
          title: p.clean
              ? Text('登录${widget.platform.label}')
              : appBarTitle(context, '登录${widget.platform.label}'),
          actions: [
            TextButton(
              onPressed: _trying
                  ? null
                  : () async {
                      if (_trying || _captured) return;
                      setState(() => _status = '正在检测登录状态…');
                      await _tryCapture();
                      if (mounted && !_captured && !_saveFailed) {
                        setState(() => _status = '未检测到登录态，请先在页面中完成登录');
                      }
                    },
              child: const Text('检测'),
            ),
          ],
        ),
        body: p.clean
            ? Column(
                children: [
                  Expanded(child: WebViewWidget(controller: _controller)),
                  SafeArea(
                    top: false,
                    child: Container(
                      margin: const EdgeInsets.fromLTRB(16, 8, 16, 14),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: cardColor(context),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x14101828),
                            blurRadius: 14,
                            offset: Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _status,
                              style: TextStyle(
                                fontSize: 12.5,
                                color: Colors.grey.shade700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              )
            : _themedBody(context),
      ),
    );
  }
}
