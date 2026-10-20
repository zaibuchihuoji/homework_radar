/// 应用内更新：Gitee 优先，检查或下载失败回退 GitHub。
library;

import 'dart:convert';

import 'safe_http.dart';

/// 两个发布源使用相同的仓库路径和版本标签。
const String kGithubRepo = 'zaibuchihuoji/homework_radar';

class UpdateInfo {
  const UpdateInfo({
    required this.version,
    required this.releaseUrl,
    required this.apkUrl,
    required this.notes,
    this.apkName = '',
    this.apkSize = 0,
    this.apkSha256,
    this.fallbackApkUrl = '',
  });

  /// 最新版本号（不含 v 前缀）
  final String version;
  final String releaseUrl;
  final String apkUrl;
  final String notes;
  final String apkName;
  final int apkSize;
  final String? apkSha256;
  final String fallbackApkUrl;
  String get source =>
      Uri.tryParse(apkUrl)?.host == 'gitee.com' ? 'Gitee' : 'GitHub';

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

/// 国内优先；镜像还没发布新版本时再查 GitHub，避免误报「已是最新」。
Future<UpdateInfo?> fetchLatestRelease({
  List<String> supportedAbis = const [],
  String? localVersion,
}) async {
  final mirror = await _fetchGiteeRelease(supportedAbis)
      .timeout(const Duration(seconds: 8), onTimeout: () => null);
  if (mirror != null &&
      (localVersion == null || mirror.isNewerThan(localVersion))) {
    return mirror;
  }
  final github = await _fetchGithubRelease(supportedAbis)
      .timeout(const Duration(seconds: 10), onTimeout: () => null);
  if (mirror == null) return github;
  return github != null && github.isNewerThan(mirror.version) ? github : mirror;
}

Future<UpdateInfo?> _fetchGiteeRelease(List<String> supportedAbis) async {
  try {
    final response = await SafeHttp.get(
      'https://gitee.com/api/v5/repos/$kGithubRepo/releases/latest',
    );
    if (response?.statusCode != 200) return null;
    final release = jsonDecode(response!.body) as Map<String, dynamic>;
    final tag = release['tag_name'] as String? ?? '';
    if (!RegExp(r'^v?\d+\.\d+\.\d+$').hasMatch(tag)) return null;
    // Gitee assets have neither size nor digest. Require the published checksum
    // manifest rather than accepting an unchecked mirror download.
    String? manifestUrl;
    for (final asset in (release['assets'] as List? ?? const [])) {
      if (asset is Map &&
          asset['name'] == 'SHA256SUMS' &&
          _assetUrl(
            asset['browser_download_url'],
            'gitee.com',
            tag,
            'SHA256SUMS',
          )) {
        manifestUrl = asset['browser_download_url'] as String;
        break;
      }
    }
    if (manifestUrl == null) return null;
    final manifest = await SafeHttp.get(manifestUrl);
    if (manifest?.statusCode != 200) return null;
    final checksums = <String, String>{};
    for (final line in const LineSplitter().convert(manifest!.body)) {
      final match = RegExp(r'^([a-fA-F0-9]{64})\s+\*?(app-[\w-]+\.apk)\s*$')
          .firstMatch(line);
      if (match == null) continue;
      final name = match[2]!;
      // Duplicate entries are ambiguous; do not guess which digest is correct.
      if (checksums.containsKey(name)) return null;
      checksums[name] = match[1]!.toLowerCase();
    }
    final info = _parseRelease(
      release,
      supportedAbis: supportedAbis,
      host: 'gitee.com',
      checksums: checksums,
    );
    return info?.apkUrl.isNotEmpty == true ? info : null;
  } catch (_) {
    return null;
  }
}

Future<UpdateInfo?> _fetchGithubRelease(List<String> supportedAbis) async {
  final resp = await SafeHttp.get(
    'https://api.github.com/repos/$kGithubRepo/releases/latest',
    headers: {
      'Accept': 'application/vnd.github+json',
      // SafeHttp 默认 UA 是移动浏览器，GitHub API 要求显式 UA 也能过，
      // 但带上语义化 UA 更稳
      'X-GitHub-Api-Version': '2022-11-28',
    },
  );
  if (resp == null || resp.statusCode != 200) return null;
  try {
    return parseGithubRelease(
      jsonDecode(resp.body) as Map<String, dynamic>,
      supportedAbis: supportedAbis,
    );
  } catch (_) {
    return null;
  }
}

/// Only a matching architecture or the explicitly named legacy universal APK.
UpdateInfo? parseGithubRelease(
  Map<String, dynamic> release, {
  required List<String> supportedAbis,
}) => _parseRelease(release, supportedAbis: supportedAbis, host: 'github.com');

bool _assetUrl(dynamic value, String host, String tag, String name) {
  if (value is! String) return false;
  final uri = Uri.tryParse(value);
  return uri != null &&
      uri.scheme == 'https' &&
      uri.host == host &&
      uri.userInfo.isEmpty &&
      !uri.hasFragment &&
      !uri.hasQuery &&
      uri.port == 443 &&
      uri.path == '/$kGithubRepo/releases/download/$tag/$name';
}

UpdateInfo? _parseRelease(
  Map<String, dynamic> release, {
  required List<String> supportedAbis,
  required String host,
  Map<String, String>? checksums,
}) {
  final tag = (release['tag_name'] as String? ?? '').trim();
  if (!RegExp(r'^v?\d+\.\d+\.\d+$').hasMatch(tag) ||
      release['draft'] == true ||
      release['prerelease'] == true) {
    return null;
  }
  final names = [
    for (final abi in supportedAbis)
      if (const ['arm64-v8a', 'armeabi-v7a', 'x86_64'].contains(abi))
        'app-$abi-release.apk',
    'app-release.apk',
  ];
  Map? selected;
  String? hash;
  for (final name in names) {
    for (final asset in (release['assets'] as List? ?? const [])) {
      if (asset is! Map || asset['name'] != name) continue;
      if (!_assetUrl(asset['browser_download_url'], host, tag, name)) {
        continue;
      }
      final digest = asset['digest'];
      if (digest != null &&
          (digest is! String ||
              !RegExp(r'^sha256:[a-fA-F0-9]{64}$').hasMatch(digest))) {
        continue;
      }
      if (checksums != null && checksums[name] == null) continue;
      selected = asset;
      hash =
          checksums?[name] ??
          (digest == null
              ? null
              : (digest as String).substring(7).toLowerCase());
      break;
    }
    if (selected != null) break;
  }
  return UpdateInfo(
    version: tag.replaceFirst(RegExp('^v'), ''),
    releaseUrl: 'https://$host/$kGithubRepo/releases/tag/$tag',
    apkUrl: selected?['browser_download_url'] as String? ?? '',
    apkName: selected?['name'] as String? ?? '',
    apkSize: (selected?['size'] as num?)?.toInt() ?? 0,
    apkSha256: hash,
    fallbackApkUrl: host == 'gitee.com' && selected != null
        ? 'https://github.com/$kGithubRepo/releases/download/$tag/${selected['name']}'
        : '',
    notes: (release['body'] as String? ?? '').trim(),
  );
}
