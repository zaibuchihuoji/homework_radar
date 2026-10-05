/// 应用内检查更新：走 GitHub Releases（无自有后端）。
/// 首次发布前把 [kGithubRepo] 改成自己的仓库（owner/repo）；
/// 打 tag（如 v1.0.1）由 GitHub Actions 构建并把 APK 挂到 Release，
/// 客户端比对 tag 与本地版本号提示升级。
library;

import 'dart:convert';

import 'safe_http.dart';

/// GitHub 仓库（owner/repo）。发布前必须改成真实仓库路径。
const String kGithubRepo = 'zaibuchihuoji/homework_radar';

class UpdateInfo {
  const UpdateInfo({
    required this.version,
    required this.releaseUrl,
    required this.apkUrl,
    required this.notes,
  });

  /// 最新版本号（不含 v 前缀）
  final String version;
  final String releaseUrl;
  final String apkUrl;
  final String notes;

  /// 有新版本（相对本地 [local]）
  bool isNewerThan(String local) => compareVersions(version, local) > 0;
}

/// 语义化比较：按 '.' 分段逐段数值比较，缺段补 0。
/// 返回负/0/正 = a 小于/等于/大于 b；解析失败的段按 0 处理。
int compareVersions(String a, String b) {
  List<int> parse(String v) {
    final t = v.trim().replaceFirst(RegExp('^v'), '');
    return t
        .split('.')
        .map((s) => int.tryParse(s.trim()) ?? 0)
        .toList(growable: false);
  }

  final pa = parse(a);
  final pb = parse(b);
  final n = pa.length > pb.length ? pa.length : pb.length;
  for (var i = 0; i < n; i++) {
    final x = i < pa.length ? pa[i] : 0;
    final y = i < pb.length ? pb[i] : 0;
    if (x != y) return x.compareTo(y);
  }
  return 0;
}

/// 查询 GitHub 最新 Release；网络失败/被墙/仓库不存在返回 null
///（调用方给出「检查失败」反馈，绝不能抛异常）。
/// 单独压 10s 超时：GitHub 被墙时 DNS/TCP 会黑洞挂很久，
/// 不等 SafeHttp 的 30s——更新检查不值得让用户等半个分钟。
Future<UpdateInfo?> fetchLatestRelease() async {
  final resp = await SafeHttp.get(
    'https://api.github.com/repos/$kGithubRepo/releases/latest',
    headers: {
      'Accept': 'application/vnd.github+json',
      // SafeHttp 默认 UA 是移动浏览器，GitHub API 要求显式 UA 也能过，
      // 但带上语义化 UA 更稳
      'X-GitHub-Api-Version': '2022-11-28',
    },
  ).timeout(
    const Duration(seconds: 10),
    onTimeout: () => null,
  );
  if (resp == null || resp.statusCode != 200) return null;
  try {
    final j = jsonDecode(resp.body) as Map<String, dynamic>;
    final tag = (j['tag_name'] as String?)?.trim() ?? '';
    if (tag.isEmpty) return null;
    final assets = (j['assets'] as List? ?? const []).cast<Map<String, dynamic>>();
    String apkUrl = '';
    for (final a in assets) {
      final name = (a['name'] as String? ?? '').toLowerCase();
      final url = a['browser_download_url'] as String? ?? '';
      if (url.isNotEmpty && name.endsWith('.apk')) {
        apkUrl = url;
        break;
      }
    }
    return UpdateInfo(
      version: tag.replaceFirst(RegExp('^v'), ''),
      releaseUrl: j['html_url'] as String? ??
          'https://github.com/$kGithubRepo/releases',
      apkUrl: apkUrl,
      notes: (j['body'] as String? ?? '').trim(),
    );
  } catch (_) {
    return null;
  }
}
