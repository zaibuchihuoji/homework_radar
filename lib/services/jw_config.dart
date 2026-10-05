/// 教务平台配置：让课表导入不再绑定单一学校（超级课程表式导入的前提）。
/// 用户手输教务网址；旧版本写死的郑州轻工业大学配置作为迁移默认值保留。
library;

import 'dart:convert';

import 'storage.dart';
import 'zf_host.dart';

class JwConfig {
  const JwConfig({required this.name, required this.url});

  /// 学校名/备注名（仅展示用）
  final String name;

  /// 教务平台首页完整 URL（含 http/https）
  final String url;

  String get host {
    final uri = Uri.tryParse(url);
    return uri?.host ?? url;
  }

  Map<String, dynamic> toJson() => {'name': name, 'url': url};

  factory JwConfig.fromJson(Map<String, dynamic> j) => JwConfig(
        name: (j['name'] ?? '').toString(),
        url: (j['url'] ?? '').toString(),
      );

  String encode() => jsonEncode(toJson());

  static JwConfig? decode(String raw) {
    if (raw.isEmpty) return null;
    try {
      final j = jsonDecode(raw);
      if (j is! Map) return null;
      final c = JwConfig.fromJson(j.cast<String, dynamic>());
      return c.url.isEmpty ? null : c;
    } catch (_) {
      return null;
    }
  }
}

class JwStore {
  /// 读取当前教务配置。
  /// - 键不存在（null）：老版本用户（存过教务 Cookie）迁移为默认值；
  /// - 键为空串：用户明确删除过配置，**不复活**——此前删除后 load() 一看
  ///   zf_cookie 还在就把配置弹回写死的郑州轻工业大学，删除形同虚设；
  /// - 键有值但损坏：落回迁移默认（保持既有容错行为）。
  static JwConfig? load() {
    final raw = Storage.jwConfigRaw();
    if (raw != null && raw.isNotEmpty) {
      final c = JwConfig.decode(raw);
      if (c != null) return c;
    }
    // 迁移：老版本只有郑州轻工业大学（金智青果）。
    // 显式删除过（空串）不迁移——否则删除配置会被这里立即复活。
    final migrated = raw == null || raw.isNotEmpty;
    if (migrated && Storage.zfCookie()?.isNotEmpty == true) {
      return const JwConfig(name: '郑州轻工业大学', url: ZfHost.origin);
    }
    return null;
  }

  static bool get hasConfig => load() != null;

  static Future<void> save(JwConfig c) => Storage.saveJwConfigRaw(c.encode());

  static Future<void> clear() => Storage.saveJwConfigRaw('');

  /// 用户输入 → 规范 URL：补协议、去空白；无法解析出合法域名时返回 null。
  /// 无协议输入默认按 https 处理（抓取页打不开时会自动回落 http 一次），
  /// 登录凭据尽量不走明文信道；协议判断大小写不敏感。
  static String? normalizeUrl(String input) {
    var s = input.trim();
    if (s.isEmpty) return null;
    final lower = s.toLowerCase();
    if (!lower.startsWith('http://') && !lower.startsWith('https://')) {
      s = 'https://$s';
    }
    final uri = Uri.tryParse(s);
    if (uri == null || uri.host.isEmpty || !uri.host.contains('.')) {
      return null;
    }
    return uri.toString();
  }
}
