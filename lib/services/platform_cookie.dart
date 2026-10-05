/// 与原生层通信读取/清除 WebView Cookie。
/// Android: android.webkit.CookieManager（能拿到 HttpOnly Cookie）
/// iOS:     WKWebsiteDataStore.httpCookieStore
library;

import 'package:flutter/services.dart';

class PlatformCookie {
  static const _channel = MethodChannel('homework_radar/platform');

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

  static Future<void> clearCookies() async {
    try {
      await _channel.invokeMethod('clearCookies');
    } on PlatformException {
      // ignore
    } on MissingPluginException {
      // ignore
    }
  }

  static Future<void> setCookie(String url, String pair) async {
    try {
      await _channel.invokeMethod(
          'setCookie', {'url': url, 'cookie': pair});
    } on PlatformException {
      // ignore
    } on MissingPluginException {
      // ignore
    }
  }

  /// 清空 WebView Cookie 罐，但把 [keepOrigins] 列出的会话原样装回去。
  /// 原生 CookieManager 只有「全清」没有按域清除——直接全清的话退出任一
  /// 平台会把其他平台的登录会话连带销毁（学习通/MOOC/智慧树/教务共用
  /// 一个 Cookie 罐）。
  static Future<void> clearCookiesExcept(Set<String> keepOrigins) async {
    final keep = <(String, String)>[];
    for (final origin in keepOrigins) {
      final raw = await getCookie(origin);
      if (raw == null) continue;
      for (final pair in raw.split(';')) {
        final p = pair.trim();
        if (p.contains('=')) keep.add((origin, p));
      }
    }
    await clearCookies();
    for (final (origin, pair) in keep) {
      await setCookie(origin, pair);
    }
  }
}
