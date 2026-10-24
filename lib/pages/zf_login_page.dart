/// 教务课表抓取页：加载用户配置的教务平台（任意学校，金智青果/正方/强智/URP 等），
/// 用户在真实页面里完成登录、进入课表页面后，检测到课表表格自动抓取解析，
/// 解析结果先进预览页人工确认再入库。
/// 教务系统通常仅校园网/VPN 可达，外网打不开时提示用户切换网络。
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../services/jw_config.dart';
import '../services/platform_cookie.dart';
import '../services/storage.dart';
import '../services/timetable_parser.dart';
import '../ui/adaptive.dart';
import '../ui/ink_wash.dart';
import '../ui/style_background.dart';
import '../ui/tokens.dart';
import 'jw_setup_page.dart';

/// 抓取成功带回给课表页的结果。校对与入库由课表页接手——校对页绝不能
/// 垫在 WebView 平台视图之上，否则其原生视图残留会拦截底部按钮触摸。
class ZfCapture {
  const ZfCapture({
    required this.parsed,
    required this.cookie,
    required this.sourceName,
  });

  final ParsedTimetable parsed;
  final String? cookie;
  final String sourceName;
}

/// 抓取页的退出意图：转去文本粘贴导入（同样脱离 WebView 再继续）。
enum ZfExit { openTextImport }

class ZfLoginPage extends StatefulWidget {
  const ZfLoginPage({super.key});

  @override
  State<ZfLoginPage> createState() => _ZfLoginPageState();
}

class _ZfLoginPageState extends State<ZfLoginPage> {
  late final WebViewController _controller;
  bool _captured = false;

  /// 探测防重入：_captured 置位在多个 await 之后，onPageFinished 的
  /// 周期探测与「检测」按钮并发时能同时越过守卫，各自走完 pop 把
  /// 登录页底下的页面也弹掉
  bool _probing = false;
  int _probe = 0;
  bool _triedHttps = false;
  bool _loadedAnyPage = false;
  String _status = '正在打开教务平台…';
  JwConfig? _config;
  final _timers = <Timer>[];
  Timer? _autoTimer;
  bool _hideWebview = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            _loadedAnyPage = true;
            // http→https 回落真正加载成功：把升级后的 origin 写回配置，
            // 否则迁移默认用户每次登录都先走一跳明文 http（内存里的升级
            // 随页面销毁丢失）。回落只是尝试，加载成功一帧后才持久化
            final base = _upgradeBase;
            final upgraded = _config;
            if (!_originPersisted && base != null && upgraded != null) {
              _originPersisted = true;
              unawaited(_persistUpgradedOrigin(upgraded, base));
            }
            _scheduleProbes();
          },
          onWebResourceError: (e) {
            // 子资源（图片/脚本/字体）失败是常态，只有主文档打不开才提示
            if (e.isForMainFrame == false) return;
            if (_captured) return;
            // http 打不开时自动换 https 试一次（可能部署了 TLS）；
            // https 打不开也回落 http 试一次（大量校内教务只有 http）。
            // 只在首个页面都没加载出来时才转：登录中途的跳转失败不能强转，
            // 否则会打断正在进行的登录流程
            final url = _config?.url ?? '';
            final lower = url.toLowerCase();
            if (!_triedHttps && !_loadedAnyPage) {
              if (lower.startsWith('http://')) {
                _triedHttps = true;
                _setActiveUrl(url.replaceFirst('http://', 'https://'));
                return;
              }
              if (lower.startsWith('https://')) {
                _triedHttps = true;
                _setActiveUrl(url.replaceFirst('https://', 'http://'));
                return;
              }
            }
            if (mounted && !_captured) {
              setState(() {
                _status = '教务平台打不开：需要校园网或学校 VPN 环境，连上后再试';
              });
            }
          },
        ),
      );
    _bootstrap();
  }

  /// 实际加载的地址（含协议回落后的切换）。取 Cookie 要用它对应的 origin：
  /// https 回落加载成功后会话在 https 域上，还按配置里的 http origin 取
  /// Cookie 会拿不到带 Secure 属性的会话键。
  JwConfig? _active;

  /// http→https 回落的升级前配置；升级后的地址**加载成功**时写回持久层
  /// （见 onPageFinished），失败则丢弃——不能把没打通的地址存进配置。
  JwConfig? _upgradeBase;
  bool _originPersisted = false;

  void _setActiveUrl(String url) {
    final old = _config;
    if (old == null) return;
    final cfg = JwConfig(name: old.name, url: url);
    _config = cfg;
    _active = cfg;
    if (url.startsWith('https://') && old.url.startsWith('http://')) {
      _upgradeBase = old;
    }
    _controller.loadRequest(Uri.parse(url));
  }

  /// https 升级成功后写回配置：显式删除过配置（空串）不复活；已存配置
  /// 被用户改过（url 对不上升级前的值）不覆盖。
  Future<void> _persistUpgradedOrigin(JwConfig cfg, JwConfig original) async {
    try {
      final raw = Storage.jwConfigRaw();
      if (raw == '') return;
      if (raw != null) {
        final stored = JwConfig.decode(raw);
        if (stored != null && stored.url != original.url) return;
      }
      await JwStore.save(cfg);
    } catch (_) {
      // 持久化失败不影响登录流程，下次登录会再触发一次升级
    }
  }

  /// 读配置 → 没有则先弹设置页 → 加载教务首页。
  Future<void> _bootstrap() async {
    var cfg = JwStore.load();
    if (cfg == null) {
      // initState 的同步调用栈里 push 会在构建期触发 setState 断言
      // （debug 构建下该入口直接坏掉），挪到首帧之后
      JwConfig? pushed;
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      pushed = await Navigator.of(
        context,
      ).push<JwConfig>(MaterialPageRoute(builder: (_) => const JwSetupPage()));
      if (!mounted) return;
      if (pushed == null) {
        Navigator.of(context).pop(false);
        return;
      }
      cfg = pushed;
    }
    final c = cfg;
    _active = c;
    if (!mounted) return;
    setState(() {
      _config = c;
      _status = '正在打开 ${c.name} …';
    });
    final previousHost = Storage.timetableSource().split('#').first;
    final changedSchool =
        previousHost.isNotEmpty && previousHost != c.host.toLowerCase();
    if (Storage.zfCookie()?.isNotEmpty != true || changedSchool) {
      try {
        await PlatformCookie.clearPlatformCookies('zf', origins: [c.url]);
      } catch (_) {
        if (mounted) setState(() => _status = '清理旧教务会话失败，请退出后重试');
        return;
      }
      if (!mounted) return;
    }
    await _controller.loadRequest(Uri.parse(c.url));
  }

  @override
  void dispose() {
    for (final t in _timers) {
      t.cancel();
    }
    _autoTimer?.cancel();
    super.dispose();
  }

  /// 课表表格可能是页面加载后 JS 渲染的，错开几次快探测；
  /// 再挂一个慢速周期探测兜底——登录慢、菜单点击后 AJAX 渲染都不触发
  /// onPageFinished，只有周期探测能接住。
  void _scheduleProbes() {
    for (final t in _timers) {
      t.cancel();
    }
    _timers.clear();
    _probe = 0;
    for (final d in [600, 1800, 4000]) {
      _timers.add(
        Timer(Duration(milliseconds: d), () {
          if (mounted && !_captured) _probeOnce();
        }),
      );
    }
    _autoTimer?.cancel();
    _autoTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (mounted && !_captured) _probeOnce();
    });
  }

  Future<void> _probeOnce() async {
    if (_probing || _captured || !mounted) return;
    _probing = true;
    _probe++;
    try {
      final has = await _controller
          .runJavaScriptReturningResult(TimetableParser.hasTimetableJs)
          .then((v) => v.toString() == '1' || v.toString() == '"1"');
      if (!has) {
        await _updateGuidance();
        return;
      }
      final raw = await _controller
          .runJavaScriptReturningResult(TimetableParser.extractJs)
          .then((v) => v.toString());
      final parsed = TimetableParser.parseExtracted(raw);
      if (parsed.isEmpty) {
        if (mounted) {
          setState(
            () => _status = parsed.error != null
                ? '课表解析失败：${parsed.error}。请切换到单张课表页面或使用文本导入。'
                : '已看到课表，但解析失败：请点「检测」重试，'
                      '或用底部「粘贴文本 / 换个页面」兜底',
          );
        }
        return;
      }
      final origin = _originOf(_active?.url ?? _config?.url ?? '');
      final cookie = origin.isEmpty
          ? null
          : await PlatformCookie.getCookie(origin);
      _captured = true;
      for (final t in _timers) {
        t.cancel();
      }
      if (!mounted) return;
      setState(() {
        _status = '抓到 ${parsed.courses.length} 条，请确认…';
        // 关页前先摘掉 WebView 平台视图，避免关闭动画期间原生视图残留
        _hideWebview = true;
      });
      await Future.delayed(const Duration(milliseconds: 150));
      // 直接关掉抓取页、把抓取结果带回给课表页：校对页绝不能垫在
      // WebView 平台视图之上——其原生视图残留在原位置会拦截校对页
      // 底部按钮的触摸（模拟器真机均复现）
      if (mounted) {
        Navigator.of(context).pop(
          ZfCapture(
            parsed: parsed,
            cookie: cookie,
            sourceName: _config?.name ?? '教务抓取',
          ),
        );
      }
    } catch (_) {
      // JS 未就绪，等下一次探测
    } finally {
      _probing = false;
    }
  }

  /// 用户选择「粘贴文本导入」兜底：关掉抓取页，由课表页接手（同为脱离 WebView）。
  void _exitToTextImport() {
    Navigator.of(context).pop(ZfExit.openTextImport);
  }

  /// 把当前页面完整 HTML（含递归所有同源 iframe）复制到剪贴板：解析有问题时发给开发者排查。
  Future<void> _copyPageHtml() async {
    try {
      var html = await _controller
          .runJavaScriptReturningResult('''
(function() {
  var out = [];
  var seen = [];
  var stack = [document];
  while (stack.length) {
    var d = stack.pop();
    if (seen.indexOf(d) >= 0) continue;
    seen.push(d);
    out.push(d.documentElement ? d.documentElement.outerHTML : '');
    var fs = d.querySelectorAll('iframe,frame');
    for (var i = 0; i < fs.length; i++) {
      try { var c = fs[i].contentDocument; if (c) stack.push(c); } catch (e) {}
    }
  }
  return out.join('\\n\\n<!-- ===== frame 分隔 ===== -->\\n\\n');
})()''')
          .then((v) => v.toString());
      // Android 对字符串返回值可能包一层（或两层）JSON 引号
      for (var i = 0; i < 2 && html.length >= 2; i++) {
        if (!html.startsWith('"') || !html.endsWith('"')) break;
        html = jsonDecode(html) as String;
      }
      if (html.trim().isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('页面还没有内容，等加载完再复制')));
        }
        return;
      }
      await Clipboard.setData(ClipboardData(text: html));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已复制本页 HTML（${html.length} 字符），可粘贴发给开发者排查')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('复制失败：页面还没加载好')));
      }
    }
  }

  /// url → scheme://host/（取 Cookie 用）。
  static String _originOf(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty) return '';
    return '${uri.scheme}://${uri.host}/';
  }

  /// 没看到课表时给出分步引导（页面本身没打开时保留原有错误提示）。
  Future<void> _updateGuidance() async {
    if (_probe < 3 || !mounted) return;
    try {
      // 主文档 + 递归所有同源 iframe 的正文都算（课表常在多层 iframe 里）
      final text = await _controller
          .runJavaScriptReturningResult('''
(function() {
  var t = '';
  var out = [document];
  var stack = [document];
  while (stack.length) {
    var d = stack.pop();
    var fs = d.querySelectorAll('iframe,frame');
    for (var i = 0; i < fs.length; i++) {
      try {
        var c = fs[i].contentDocument;
        if (c && out.indexOf(c) < 0) { out.push(c); stack.push(c); }
      } catch (e) {}
    }
  }
  for (var i = 0; i < out.length; i++) {
    t += (out[i].body ? out[i].body.innerText : '') + '\\n';
  }
  return t;
})()''')
          .then((v) => v.toString());
      final failed =
          text.contains('无法打开') ||
          text.contains('ERR_') ||
          text.trim().length < 20;
      if (failed || !mounted) return;
      final navHints = ['课表', '课程表', '教学安排', '个人课表', '学生课表'];
      final loggedIn = navHints.any(text.contains);
      setState(() {
        _status = loggedIn
            ? '检测到教务菜单：请进入「个人课表 / 学生课表」页面，出现课表后自动抓取'
            : '请先在页面中完成登录（统一身份认证 / 教务账号，需校园网/VPN）';
      });
    } catch (_) {}
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
              ? Text(_config == null ? '导入教务课表' : '导入课表 · ${_config!.name}')
              : appBarTitle(
                  context,
                  _config == null ? '导入教务课表' : '导入课表 · ${_config!.name}',
                ),
          actions: [
            IconButton(
              tooltip: '复制本页 HTML（排查解析用）',
              onPressed: _copyPageHtml,
              icon: const Icon(Icons.copy_all_rounded, size: 20),
            ),
            TextButton(
              onPressed: () async {
                setState(() => _status = '正在检测课表…');
                await _probeOnce();
                if (mounted && !_captured && !_status.startsWith('抓到')) {
                  setState(() => _status = '未抓到课表。$_status');
                }
              },
              child: const Text('检测'),
            ),
          ],
        ),
        body: Column(
          children: [
            Expanded(
              child: _config == null
                  ? const Center(
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : _hideWebview
                  ? const SizedBox.expand()
                  : WebViewWidget(controller: _controller),
            ),
            SafeArea(
              top: false,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight:
                      (MediaQuery.sizeOf(context).height -
                          MediaQuery.viewInsetsOf(context).bottom -
                          kToolbarHeight) *
                      .45,
                ),
                child: SingleChildScrollView(
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
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            if (_status.startsWith('正在') ||
                                _status.startsWith('抓到') ||
                                _status.startsWith('课表抓取成功'))
                              const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            else
                              Icon(
                                Icons.info_outline_rounded,
                                size: 15,
                                color: Colors.grey.shade500,
                              ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                _status,
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color: textSecondary(context),
                                ),
                              ),
                            ),
                          ],
                        ),
                        // 解析失败 → 兜底导入入口
                        if (_status.contains('解析失败')) ...[
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: _exitToTextImport,
                                  icon: const Icon(
                                    Icons.content_paste_rounded,
                                    size: 16,
                                  ),
                                  label: const Text('粘贴文本导入'),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          '试试在教务里切到「表格视图/周课表」页面再点检测',
                                        ),
                                      ),
                                    );
                                  },
                                  icon: const Icon(
                                    Icons.explore_outlined,
                                    size: 16,
                                  ),
                                  label: const Text('换个页面'),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
