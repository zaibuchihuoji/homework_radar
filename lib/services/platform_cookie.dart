/// 与原生层通信读取/清除 WebView Cookie。
/// Android: android.webkit.CookieManager（能拿到 HttpOnly Cookie）
/// iOS:     WKWebsiteDataStore.httpCookieStore
library;

import 'package:flutter/services.dart';

class PlatformCookie {
  static const _channel = MethodChannel('homework_radar/platform');

  /// 只删除目标平台的会话，保留其他平台原 Cookie 的全部属性。
  /// Android 只能删除探测 URL 可见的 Cookie，不代表注销了服务器会话。
  static Future<void> clearPlatformCookies(
    String platform, {
    List<String> origins = const [],
  }) async {
    final domains = switch (platform) {
      'cx' || 'chaoxing' => ['chaoxing.com'],
      'mooc' => ['icourse163.org'],
      'zhs' || 'zhihuishu' => ['zhihuishu.com'],
      'xtx' || 'xuetangx' => ['xuetangx.com'],
      'ykt' || 'yuketang' => ['yuketang.cn'],
      'zf' =>
        origins
            .map(Uri.tryParse)
            .whereType<Uri>()
            .map((u) => u.host.toLowerCase())
            .where((h) => h.isNotEmpty)
            .toSet()
            .toList(),
      _ => throw ArgumentError.value(platform, 'platform'),
    };
    final probes = <String>{...origins};
    for (final domain in domains) {
      probes.add('https://$domain/');
      probes.add('https://www.$domain/');
    }
    if (platform == 'cx' || platform == 'chaoxing') {
      probes.addAll([
        'https://passport2.chaoxing.com/',
        'https://mooc1.chaoxing.com/',
      ]);
    } else if (platform == 'ykt' || platform == 'yuketang') {
      probes.add('https://pro.yuketang.cn/');
    } else if (platform == 'zhs' || platform == 'zhihuishu') {
      probes.addAll([
        'https://passport.zhihuishu.com/',
        'https://onlineservice-api.zhihuishu.com/',
        'https://onlineweb.zhihuishu.com/',
        'https://onlineservice.zhihuishu.com/',
      ]);
    }
    await _channel.invokeMethod<bool>('clearDomainCookies', {
      'domains': domains,
      'origins': probes.toList(),
    });
  }

  /// 读取指定 url 对应域下的全部 Cookie（含 HttpOnly），返回 "k=v; k2=v2"。
  static Future<String?> getCookie(String url) async {
    try {
      return await _channel.invokeMethod<String>('getCookie', {'url': url});
    } on PlatformException {
      return null;
    } on MissingPluginException {
      // 通道未注册（热重载/测试环境）：同平台异常待遇，不打断捕获链
      return null;
    }
  }

}
