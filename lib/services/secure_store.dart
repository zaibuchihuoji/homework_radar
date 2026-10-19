/// 敏感凭据（各平台 Cookie / uid / csrf）的安全存取。
/// Android：Keystore AES-GCM 加密后存独立 SharedPreferences；iOS：Keychain。
/// 读取走启动时预加载的内存缓存（Storage.init 完成迁移与加载），
/// 业务代码同步取值，避免到处 await 通道调用。
library;

import 'dart:convert';

import 'package:flutter/services.dart';

class SecureStore {
  SecureStore._();

  static const _channel = MethodChannel('homework_radar/platform');
  static final _cache = <String, String>{};
  static const _bundleKey = 'account_credentials_v2';
  static const _journalKey = 'account_credentials_transaction_v2';
  static Future<void> _tail = Future.value();
  static bool _loaded = true;
  static const _legacyKeys = [
    'cx_cookie',
    'cx_uid',
    'mooc_cookie',
    'mooc_csrf',
    'zhs_cookie',
    'xtx_cookie',
    'ykt_cookie',
    'zf_cookie',
  ];

  static Future<void> _clearLegacy() async {
    for (final key in _legacyKeys) {
      await _channel.invokeMethod('secureDelete', {'key': key});
    }
  }

  static Map<String, String> _decode(String raw) =>
      Map<String, String>.from(jsonDecode(raw) as Map);

  static Future<void> _persist(String key, String value) async {
    if (!await _write(key, value) || !await _readBackEquals(key, value)) {
      throw StateError('登录凭据保存失败，请重试；本次未确认登录成功');
    }
  }

  /// 同一个加密项提交整组值，Cookie/uid/csrf 不会各自成功一半。
  static Future<void> writeAll(Map<String, String?> changes) {
    final operation = _tail.then((_) async {
      if (!_loaded) throw StateError('安全存储尚未完整读取，请重启后重试');
      final next = Map<String, String>.from(_cache);
      for (final e in changes.entries) {
        if (e.value == null) {
          next.remove(e.key);
        } else {
          next[e.key] = e.value!;
        }
      }
      await _persist(_bundleKey, jsonEncode(next));
      try {
        await _clearLegacy();
      } catch (_) {
        // 旧键删除失败不谎报退出成功，也不留下缓存/加密集合两种账号。
        await _persist(_bundleKey, jsonEncode(_cache));
        rethrow;
      }
      _cache
        ..clear()
        ..addAll(next);
    });
    _tail = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace stack) {},
    );
    return operation;
  }

  /// 恢复日志也只进加密存储，业务 prefs 中不写凭据。
  static Future<void> beginTransaction() async {
    await _tail;
    await _persist(_journalKey, jsonEncode(_cache));
  }

  static Future<void> finishTransaction({required bool rollback}) async {
    await _tail;
    final raw = await _channel.invokeMethod<String>('secureRead', {
      'key': _journalKey,
    });
    if (raw == null) return;
    if (rollback) {
      final before = _decode(raw);
      await _persist(_bundleKey, jsonEncode(before));
      _cache
        ..clear()
        ..addAll(before);
    }
    await _channel.invokeMethod('secureDelete', {'key': _journalKey});
    if (await _channel.invokeMethod<String>('secureRead', {
          'key': _journalKey,
        }) !=
        null) {
      throw StateError('账号恢复日志清理失败，请重试');
    }
  }

  static String? get(String key) => _cache[key];

  /// 启动时调用：把旧版本明文 prefs 里的凭据迁入安全存储，并加载到缓存。
  /// [legacyPlain] 为 全部候选键与其明文值（空串表示没有）。
  ///
  /// 返回「已确认写入安全存储」的键集合：写失败被吞掉的老实现会配合
  /// Storage.init 无条件删明文，把用户仅有的凭据副本毁掉——现在逐键
  /// 回读校验，只有确认落盘的键才允许删明文，失败的键下次启动重试。
  static Future<Set<String>> preloadAndMigrate(
    Map<String, String> legacyPlain,
  ) async {
    final confirmed = <String>{};
    _loaded = false;
    String? bundle;
    try {
      bundle = await _channel.invokeMethod<String>('secureRead', {
        'key': _bundleKey,
      });
    } on MissingPluginException {
      /* 测试或不支持的宿主，无安全存储。 */
    }
    _cache.clear();
    if (bundle != null) {
      _cache.addAll(_decode(bundle));
      await _clearLegacy();
      _loaded = true;
      // v2 的缺失键也是权威值，不能回退到退出前残留的 v1 Cookie。
      return legacyPlain.entries
          .where((e) => e.value.isNotEmpty)
          .map((e) => e.key)
          .toSet();
    }
    for (final entry in legacyPlain.entries) {
      if (entry.value.isEmpty) continue;
      final ok =
          await _write(entry.key, entry.value) &&
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
        final v = await _channel.invokeMethod<String>('secureRead', {
          'key': key,
        });
        if (v != null && v.isNotEmpty) _cache[key] = v;
        if ((v == null || v.isEmpty) && legacyPlain[key]?.isNotEmpty == true) {
          // 明文源仍未确认迁移，不得在后续创建v2集合时把它遗漏。
          _cache[key] = legacyPlain[key]!;
        }
      } on MissingPluginException {
        // 未实现安全通道的宿主；后续写入仍会明确失败。
      }
    }
    _loaded = true;
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
    await writeAll({key: value});
  }

  static Future<bool> _write(String key, String value) async {
    try {
      await _channel.invokeMethod('secureWrite', {'key': key, 'value': value});
      return true;
    } catch (_) {
      // 失败不修改缓存；调用者必须看到失败，迁移明文源也必须保留。
      return false;
    }
  }

  static Future<void> delete(String key) async {
    await writeAll({key: null});
  }
}
