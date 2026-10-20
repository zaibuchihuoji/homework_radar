/// 安全 HTTP 封装：
/// - 只允许 http/https；
/// - 请求前校验 host，只放行 chaoxing.com / icourse163.org / zhihuishu.com
///   及其子域；
/// - 拒绝 localhost、环回、私有/保留 IP 与原始 IP 地址；
/// - 全部请求写入调试日志（debug 页可见）。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io' show HttpClient;

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart' as http_io;

class SafeHttpLogEntry {
  SafeHttpLogEntry(
    this.time,
    this.method,
    this.url,
    this.status,
    this.bodySnippet,
  );

  final DateTime time;
  final String method;
  final String url;
  final int? status;
  final String bodySnippet;

  Map<String, dynamic> toJson() => {
    'time': time.toIso8601String(),
    'method': method,
    'url': url,
    'status': status,
    'body': bodySnippet,
  };
}

class SafeHttp {
  SafeHttp._();

  static const List<String> _allowedSuffixes = [
    'chaoxing.com',
    'icourse163.org',
    'zhihuishu.com',
    'xuetangx.com',
    'yuketang.cn',
    'zzuli.edu.cn',
    // 应用内检查更新走 GitHub Releases（无自有后端）：
    // api.github.com 查最新版，release 下载重定向到 objects.githubusercontent.com
    'github.com',
    'githubusercontent.com',
    // Gitee release API and checksum downloads (foruda.gitee.com redirects).
    'gitee.com',
  ];

  /// 保留主机名（RFC 6761/6762 等）一律拒绝。
  static const List<String> _reservedNames = [
    'localhost',
    'localhost.localdomain',
    'invalid',
    'test',
    'example',
    'example.com',
    'example.net',
    'example.org',
  ];

  /// 连接 15s / 整体 30s 超时：此前全程无超时，一条 TCP 假死连接会让
  /// allHomework 的 Future.wait 永不返回，同步永久卡死（syncing 锁死）。
  static final http.Client _client = http_io.IOClient(
    HttpClient()..connectionTimeout = const Duration(seconds: 15),
  );
  static const _requestTimeout = Duration(seconds: 30);
  static final List<SafeHttpLogEntry> log = [];
  static const int maxLogEntries = 200;

  /// 校验并解析 URL；不合法返回 null。
  static Uri? validate(String url) {
    final u = Uri.tryParse(url);
    if (u == null) return null;
    if (u.scheme != 'https' && u.scheme != 'http') return null;
    final host = u.host.toLowerCase();
    if (host.isEmpty) return null;
    if (_reservedNames.contains(host)) return null;
    if (host.endsWith('.localhost') ||
        host.endsWith('.invalid') ||
        host.endsWith('.test') ||
        host.endsWith('.local')) {
      return null;
    }
    // 任何形式的原始 IP（含环回/私有/保留网段）都不允许。
    if (RegExp(r'^\d{1,3}(\.\d{1,3}){3}$').hasMatch(host)) return null;
    if (host.contains(':')) return null; // IPv6 字面量
    final ok = _allowedSuffixes.any((s) => host == s || host.endsWith('.$s'));
    if (!ok) return null;
    return u;
  }

  static String get _ua =>
      'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/124.0.0.0 Mobile Safari/537.36';

  static void _record(String method, String url, int? status, String body) {
    log.insert(
      0,
      SafeHttpLogEntry(
        DateTime.now(),
        method,
        url,
        status,
        body.length > 1500 ? body.substring(0, 1500) : body,
      ),
    );
    if (log.length > maxLogEntries) log.removeRange(maxLogEntries, log.length);
  }

  /// The socket client must never follow redirects itself: it knows nothing
  /// about our destination allowlist. Keep one outer timeout for this entire
  /// chain, including every response header and body.
  static Future<http.Response> _sendRedirectChain(
    http.Request initial, {
    required bool followRedirects,
  }) async {
    var request = initial;
    final visited = <Uri>{initial.url};
    var redirects = 0;
    while (true) {
      request.followRedirects = false;
      final response = await _client.send(request).then(http.Response.fromStream);
      final code = response.statusCode;
      // Match Dart HttpClient's automatic redirect semantics. In particular,
      // POST 301/302/307/308 must not start replaying a sensitive request body.
      final canRedirect = request.method == 'GET' || request.method == 'HEAD'
          ? const [301, 302, 303, 307, 308].contains(code)
          : request.method == 'POST' && code == 303;
      if (!followRedirects || !canRedirect) return response;

      final location = response.headers['location'];
      if (location == null) {
        throw http.ClientException('重定向响应缺少目标地址');
      }
      final target = validate(request.url.resolve(location).toString());
      if (target == null || target.userInfo.isNotEmpty ||
          (request.url.scheme == 'https' && target.scheme != 'https')) {
        throw http.ClientException('重定向目标未通过安全校验');
      }
      if (redirects >= 5 || !visited.add(target)) {
        throw http.ClientException('重定向循环或超过上限');
      }
      redirects++;

      final method = request.method == 'POST' ? 'GET' : request.method;
      final next = http.Request(method, target);
      final sameOrigin = request.url.scheme == target.scheme &&
          request.url.host == target.host && request.url.port == target.port;
      if (sameOrigin) {
        next.headers.addAll(request.headers);
      } else {
        // Credential-bearing headers include caller-defined CSRF/session
        // headers, not just Cookie/Authorization. Do not forward any caller
        // headers or private Referer across origins, even between allowed sites.
        next.headers['User-Agent'] = _ua;
      }
      if (method != request.method) {
        next.headers.removeWhere((name, _) => const [
          'content-type', 'content-length', 'transfer-encoding',
        ].contains(name.toLowerCase()));
      }
      // Automatic POST redirects become GET; no body is ever replayed.
      request = next;
    }
  }

  static Future<http.Response?> get(
    String url, {
    Map<String, String>? headers,
    bool followRedirects = true,
  }) async {
    final u = validate(url);
    if (u == null) {
      _record('GET', url, null, '[blocked] 目标地址未通过白名单校验');
      return null;
    }
    try {
      final req = http.Request('GET', u)
        ..followRedirects = followRedirects
        ..headers.addAll({'User-Agent': _ua, ...?headers});
      final resp = await _sendRedirectChain(req, followRedirects: followRedirects)
          .timeout(_requestTimeout);
      _record('GET', url, resp.statusCode, resp.body);
      return resp;
    } catch (e) {
      _record('GET', url, null, '[error] $e');
      return null;
    }
  }

  static Future<http.Response?> postForm(
    String url, {
    Map<String, String> body = const {},
    Map<String, String>? headers,
    bool followRedirects = true,
  }) async {
    final u = validate(url);
    if (u == null) {
      _record('POST', url, null, '[blocked] 目标地址未通过白名单校验');
      return null;
    }
    try {
      final req = http.Request('POST', u)
        ..followRedirects = followRedirects
        ..bodyFields = body
        ..headers.addAll({
          'User-Agent': _ua,
          'Content-Type': 'application/x-www-form-urlencoded',
          ...?headers,
        });
      final resp = await _sendRedirectChain(req, followRedirects: followRedirects)
          .timeout(_requestTimeout);
      _record('POST', url, resp.statusCode, resp.body);
      return resp;
    } catch (e) {
      _record('POST', url, null, '[error] $e');
      return null;
    }
  }

  /// JSON 体 POST：智慧树 onlineservice-api 网关按前端 axios 惯例走
  /// application/json；与 postForm 同一套白名单/超时/日志。
  static Future<http.Response?> postJson(
    String url, {
    String body = '',
    Map<String, String>? headers,
    bool followRedirects = true,
  }) async {
    final u = validate(url);
    if (u == null) {
      _record('POST', url, null, '[blocked] 目标地址未通过白名单校验');
      return null;
    }
    try {
      final req = http.Request('POST', u)
        ..followRedirects = followRedirects
        ..body = body
        ..headers.addAll({
          'User-Agent': _ua,
          'Content-Type': 'application/json; charset=utf-8',
          ...?headers,
        });
      final resp = await _sendRedirectChain(req, followRedirects: followRedirects)
          .timeout(_requestTimeout);
      _record('POST', url, resp.statusCode, resp.body);
      return resp;
    } catch (e) {
      _record('POST', url, null, '[error] $e');
      return null;
    }
  }

  static String cookieHeader(String? cookie) => cookie ?? '';

  static Map<String, String> authedHeaders(String? cookie) =>
      cookie == null || cookie.isEmpty
      ? {}
      : {'Cookie': cookie, 'Referer': 'https://mooc1.chaoxing.com/'};
}

class DebugLogCodec {
  static String encode(List<SafeHttpLogEntry> entries) =>
      jsonEncode(entries.map((e) => e.toJson()).toList());

  static List<SafeHttpLogEntry> decode(String s) {
    try {
      final list = (jsonDecode(s) as List).cast<Map<String, dynamic>>();
      return list
          .map(
            (j) => SafeHttpLogEntry(
              DateTime.tryParse(j['time'] as String? ?? '') ?? DateTime.now(),
              j['method'] as String? ?? '?',
              j['url'] as String? ?? '',
              j['status'] as int?,
              j['body'] as String? ?? '',
            ),
          )
          .toList();
    } catch (_) {
      return [];
    }
  }
}
