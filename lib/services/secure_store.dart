/// 敏感凭据（各平台 Cookie / uid / csrf）的安全存取。
/// Android：Keystore AES-GCM 加密后存独立 SharedPreferences；iOS：Keychain。
/// 读取走启动时预加载的内存缓存（Storage.init 完成迁移与加载），
/// 业务代码同步取值，避免到处 await 通道调用。
library;

import 'package:flutter/services.dart';

class SecureStore {
  SecureStore._();

  static const _channel = MethodChannel('homework_radar/platform');
  static final _cache = <String, String>{};

  static String? get(String key) => _cache[key];

  /// 启动时调用：把旧版本明文 prefs 里的凭据迁入安全存储，并加载到缓存。
  /// [legacyPlain] 为 全部候选键与其明文值（空串表示没有）。
  ///
  /// 返回「已确认写入安全存储」的键集合：写失败被吞掉的老实现会配合
  /// Storage.init 无条件删明文，把用户仅有的凭据副本毁掉——现在逐键
  /// 回读校验，只有确认落盘的键才允许删明文，失败的键下次启动重试。
  static Future<Set<String>> preloadAndMigrate(
      Map<String, String> legacyPlain) async {
    final confirmed = <String>{};
    for (final entry in legacyPlain.entries) {
      if (entry.value.isEmpty) continue;
      final ok = await _write(entry.key, entry.value) &&
          await _readBackEquals(entry.key, entry.value);
      if (ok) {
        confirmed.add(entry.key);
        // 迁移成功也要进内存缓存：私有 _write 不碰缓存，漏了这行的话
        // 升级用户首次启动三平台全部显示「未登录」，要重启才恢复
        _cache[entry.key] = entry.value;
      }
    }
    for (final key in legacyPlain.keys) {
      if (confirmed.contains(key)) continue;
      try {
        final v = await _channel.invokeMethod<String>(
            'secureRead', {'key': key});
        if (v != null && v.isNotEmpty) _cache[key] = v;
      } catch (_) {
        // 原生侧不可用（老版本升级/测试环境）：凭据按缺失处理，
        // 用户重新登录即可恢复
      }
    }
    return confirmed;
  }

  static Future<bool> _readBackEquals(String key, String value) async {
    try {
      final v = await _channel.invokeMethod<String>('secureRead', {'key': key});
      return v == value;
    } catch (_) {
      return false;
    }
  }

  static Future<void> write(String key, String value) async {
    _cache[key] = value;
    await _write(key, value);
  }

  static Future<bool> _write(String key, String value) async {
    try {
      await _channel.invokeMethod('secureWrite', {'key': key, 'value': value});
      return true;
    } catch (_) {
      // 写失败保留内存值，本次会话内功能不受影响；明文源不删，下次启动重试
      return false;
    }
  }

  static Future<void> delete(String key) async {
    _cache.remove(key);
    try {
      await _channel.invokeMethod('secureDelete', {'key': key});
    } catch (_) {
      // ignore
    }
  }
}
