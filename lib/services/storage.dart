/// 本地持久化：账号凭据、作业列表、提醒设置、调试日志。
library;

import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/course.dart';
import '../models/homework.dart';
import 'secure_store.dart';
import 'safe_http.dart';
import 'sync_policy.dart';

class ReminderSettings {
  ReminderSettings({
    this.before24h = true,
    this.before6h = true,
    this.before1h = true,
  });

  bool before24h;
  bool before6h;
  bool before1h;

  List<int> get enabledHours => [
    if (before24h) 24,
    if (before6h) 6,
    if (before1h) 1,
  ];

  Map<String, dynamic> toJson() => {
    '24': before24h,
    '6': before6h,
    '1': before1h,
  };

  static ReminderSettings fromJson(Map<String, dynamic> j) => ReminderSettings(
    before24h: j['24'] is bool ? j['24'] as bool : true,
    before6h: j['6'] is bool ? j['6'] as bool : true,
    before1h: j['1'] is bool ? j['1'] as bool : true,
  );
}

class Storage {
  static late SharedPreferences _sp;

  /// 进程内数据世代。用户编辑、账号切换或恢复备份后旧抓取不得提交。
  static int _syncEpoch = 0;
  static int get syncEpoch => _syncEpoch;
  static void invalidateSync() => _syncEpoch++;

  static Future<void> _setString(String key, String value) async {
    if (!await _sp.setString(key, value)) throw StateError('本地保存失败：$key');
  }

  static Future<void> _setInt(String key, int value) async {
    if (!await _sp.setInt(key, value)) throw StateError('本地保存失败：$key');
  }

  static Future<void> _setBool(String key, bool value) async {
    if (!await _sp.setBool(key, value)) throw StateError('本地保存失败：$key');
  }

  static Future<void> _setStringList(String key, List<String> value) async {
    if (!await _sp.setStringList(key, value)) throw StateError('本地保存失败：$key');
  }

  static Future<void> _remove(String key) async {
    if (!await _sp.remove(key)) throw StateError('本地保存失败：$key');
  }

  static const _businessKeys = [
    'sync_status_v1',
    'homework_json',
    'courses_json',
    'semester_start',
    'semester_start_manual',
    'timetable_semester',
    'section_times',
    'hidden_items',
    'dismissed_ids',
    'course_colors',
    'theme_mode',
    'ui_style',
    'sort_mode',
    'class_reminder',
    'reminders',
    'jw_config',
    'timetable_source',
    'account_archives',
    'zf_raw_page',
    'zf_xh',
  ];

  static SyncConfig syncConfig() {
    try {
      return SyncConfig.fromJson(
        jsonDecode(_sp.getString('sync_config_v1') ?? '{}')
            as Map<String, dynamic>,
      );
    } catch (_) {
      return const SyncConfig();
    }
  }

  static Future<void> saveSyncConfig(SyncConfig value) =>
      _setString('sync_config_v1', jsonEncode(value.toJson()));

  static Map<PlatformKind, PlatformSyncStatus> syncStatuses() {
    try {
      final raw = jsonDecode(_sp.getString('sync_status_v1') ?? '{}') as Map;
      return {
        for (final p in PlatformKind.values)
          if (raw[p.name] is Map)
            p: PlatformSyncStatus.fromJson(
              Map<String, dynamic>.from(raw[p.name] as Map),
            ),
      };
    } catch (_) {
      return {};
    }
  }

  static Future<void> saveSyncStatuses(
    Map<PlatformKind, PlatformSyncStatus> value,
  ) => _setString(
    'sync_status_v1',
    jsonEncode(value.map((p, s) => MapEntry(p.name, s.toJson()))),
  );
  static Future<void> resetSyncStatus(PlatformKind platform) async {
    final statuses = syncStatuses()..remove(platform);
    await saveSyncStatuses(statuses);
  }

  static Set<PlatformKind> syncAccounts() => {
    if (chaoxingCookie()?.isNotEmpty == true) PlatformKind.chaoxing,
    if (moocCookie()?.isNotEmpty == true) PlatformKind.mooc,
    if (zhihuishuCookie()?.isNotEmpty == true) PlatformKind.zhihuishu,
    if (xuetangxCookie()?.isNotEmpty == true) PlatformKind.xuetangx,
    if (yuketangCookie()?.isNotEmpty == true) PlatformKind.yuketang,
  };
  static Future<void>? _transactionTail;
  static bool _recoveryPending = false;
  static Future<void> waitForBusinessTransaction() async {
    final pending = _transactionTail;
    if (pending != null) await pending;
    if (_recoveryPending || _sp.containsKey('business_transaction')) {
      throw StateError('上次数据写入尚未恢复，请重启应用后重试');
    }
  }

  /// 写入前留恢复日志；异常或进程中断后可恢复整组原值，不保留半份备份。
  static Future<T> businessTransaction<T>(
    Future<T> Function() action, {
    bool credentials = false,
  }) {
    invalidateSync();
    final task = (_transactionTail ?? Future<void>.value()).then((_) async {
      if (_recoveryPending || _sp.containsKey('business_transaction')) {
        throw StateError('上次数据写入尚未恢复，请重启应用');
      }
      if (credentials) await SecureStore.finishTransaction(rollback: false);
      final before = {for (final key in _businessKeys) key: _sp.get(key)};
      _recoveryPending = true;
      await _setString(
        'business_transaction',
        jsonEncode({...before, '_credentials': credentials}),
      );
      try {
        if (credentials) await SecureStore.beginTransaction();
        final value = await action();
        await _remove('business_transaction');
        _recoveryPending = false;
        // 此处开始已提交。残留加密日志在下次事务/启动清理，不再回滚业务。
        if (credentials) {
          try {
            await SecureStore.finishTransaction(rollback: false);
          } catch (_) {
            /* 提交结果仍有效。 */
          }
        }
        return value;
      } catch (_) {
        await _restorePreferences(before);
        if (credentials) await SecureStore.finishTransaction(rollback: true);
        await _remove('business_transaction');
        _recoveryPending = false;
        rethrow;
      } finally {
        invalidateSync();
      }
    });
    final tail = task.then<void>(
      (_) {},
      onError: (Object _, StackTrace stack) {},
    );
    _transactionTail = tail;
    unawaited(
      tail.then((_) {
        if (identical(_transactionTail, tail)) _transactionTail = null;
      }),
    );
    return task;
  }

  static Future<void> _restorePreferences(Map<String, dynamic> values) async {
    for (final key in _businessKeys) {
      final value = values[key];
      if (value == null) {
        await _remove(key);
      } else if (value is String) {
        await _setString(key, value);
      } else if (value is bool) {
        await _setBool(key, value);
      } else if (value is int) {
        await _setInt(key, value);
      } else if (value is List) {
        await _setStringList(key, value.cast<String>());
      } else {
        throw StateError('恢复日志格式损坏：$key');
      }
    }
  }

  static List<Map<String, dynamic>> accountArchives() {
    final raw = _sp.getString('account_archives');
    if (raw == null) return [];
    final decoded = jsonDecode(raw) as List;
    return decoded.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  static Future<void> mergeAccountArchives(
    List<Map<String, dynamic>> incoming,
  ) async {
    final merged = {for (final a in accountArchives()) a['id'] as String: a};
    for (final a in incoming) {
      if (a['id'] is String) merged.putIfAbsent(a['id'] as String, () => a);
    }
    await _setString('account_archives', jsonEncode(merged.values.toList()));
  }

  static Future<void> archiveCourses() async {
    final list = courses();
    if (list.isEmpty) return;
    final now = DateTime.now();
    await mergeAccountArchives([
      {
        'id': '${now.microsecondsSinceEpoch}_timetable',
        'createdAt': now.toIso8601String(),
        'platform': 'timetable',
        'homework': <Map<String, dynamic>>[],
        'hiddenItems': <String, String>{},
        'courses': [for (final c in list) c.toJson()],
        'semesterStart': semesterStart()?.millisecondsSinceEpoch,
        'timetableSemester': timetableSemester(),
        'timetableSource': timetableSource(),
      },
    ]);
  }

  static Future<void> updateHiddenBody(String id, HomeworkItem item) async {
    final hidden = hiddenItems();
    if (!hidden.containsKey(id)) return;
    hidden[id] = jsonEncode(item.toJson());
    await _setString('hidden_items', jsonEncode(hidden));
  }

  /// 无法确认同一账号时保留无凭据归档，活动数据不跨账号继承。
  static Future<void> archivePlatform(PlatformKind platform) async {
    invalidateSync();
    final old = homework().where((h) => h.platform == platform).toList();
    final hidden = hiddenItems();
    bool belongs(String id, String raw) {
      try {
        return HomeworkItem.fromJson(jsonDecode(raw) as Map<String, dynamic>)
                .platform ==
            platform;
      } catch (_) {
        final prefix = switch (platform) {
          PlatformKind.chaoxing => 'cx_',
          PlatformKind.mooc => 'mooc_',
          PlatformKind.zhihuishu => 'zhs_',
          PlatformKind.xuetangx => 'xtx_',
          PlatformKind.yuketang => 'ykt_',
          PlatformKind.manual => 'manual_',
        };
        return id.startsWith(prefix);
      }
    }

    final removed = <String, String>{
      for (final e in hidden.entries)
        if (belongs(e.key, e.value)) e.key: e.value,
    };
    if (old.isEmpty && removed.isEmpty) return;
    final archives = accountArchives();
    final now = DateTime.now();
    archives.add({
      'id': '${now.microsecondsSinceEpoch}_${platform.key}',
      'createdAt': now.toIso8601String(),
      'platform': platform.key,
      'homework': [for (final h in old) h.toJson()],
      'hiddenItems': removed,
    });
    // 归档确认保存后才删除活动副本；中断最多重复，不会只剩空表。
    await _setString('account_archives', jsonEncode(archives));
    await saveHomework(
      homework().where((h) => h.platform != platform).toList(),
    );
    await restoreHiddenItems(
      hidden..removeWhere((id, _) => removed.containsKey(id)),
    );
  }

  static String timetableSource() => _sp.getString('timetable_source') ?? '';
  static Future<void> saveTimetableSource(String value) =>
      _setString('timetable_source', value);
  static Future<void> clearSemesterStart() => _remove('semester_start');

  /// 凭据相关键：迁移进安全存储，不再落明文。
  static const _secureKeys = [
    'cx_cookie',
    'cx_uid',
    'mooc_cookie',
    'mooc_csrf',
    'zhs_cookie',
    'xtx_cookie',
    'ykt_cookie',
    'zf_cookie',
  ];

  static Future<void> init() async {
    final pending = _transactionTail;
    if (pending != null) await pending;
    invalidateSync();
    _sp = await SharedPreferences.getInstance();
    await _sp.reload();
    final journal = _sp.getString('business_transaction');
    if (journal != null) {
      _recoveryPending = true;
      final before = Map<String, dynamic>.from(jsonDecode(journal) as Map);
      await _restorePreferences(before);
      if (before['_credentials'] == true) {
        await SecureStore.finishTransaction(rollback: true);
      }
      await _remove('business_transaction');
    }
    _recoveryPending = false;
    // 老版本把 Cookie 明文存在 prefs；迁入安全存储后删除明文。
    // 只删「已确认写入安全存储」的键——写失败就删明文会把用户仅有的
    // 凭据副本毁掉且无法重试（Keystore 损坏/换机还原时必现）。
    final legacy = {for (final k in _secureKeys) k: _sp.getString(k) ?? ''};
    final confirmed = await SecureStore.preloadAndMigrate(legacy);
    for (final key in confirmed) {
      await _remove(key);
    }
  }

  // ---- 账号凭据 ----
  static String? chaoxingCookie() => SecureStore.get('cx_cookie');
  static String? chaoxingUid() => SecureStore.get('cx_uid');
  static Future<void> saveChaoxing({
    required String cookie,
    String? uid,
  }) async {
    invalidateSync();
    await SecureStore.writeAll({'cx_cookie': cookie, 'cx_uid': uid});
  }

  static String? moocCookie() => SecureStore.get('mooc_cookie');
  static String? moocCsrf() => SecureStore.get('mooc_csrf');
  static Future<void> saveMooc({
    required String cookie,
    required String csrf,
  }) async {
    invalidateSync();
    await SecureStore.writeAll({'mooc_cookie': cookie, 'mooc_csrf': csrf});
  }

  static Future<void> clearChaoxing() async {
    invalidateSync();
    await SecureStore.writeAll({'cx_cookie': null, 'cx_uid': null});
  }

  static Future<void> clearMooc() async {
    invalidateSync();
    await SecureStore.writeAll({'mooc_cookie': null, 'mooc_csrf': null});
  }

  static String? zhihuishuCookie() => SecureStore.get('zhs_cookie');

  static Future<void> saveZhihuishu({required String cookie}) async {
    invalidateSync();
    await SecureStore.write('zhs_cookie', cookie);
  }

  static Future<void> clearZhihuishu() async {
    invalidateSync();
    await SecureStore.delete('zhs_cookie');
  }

  static String? xuetangxCookie() => SecureStore.get('xtx_cookie');

  static Future<void> saveXuetangx({required String cookie}) async {
    invalidateSync();
    await SecureStore.write('xtx_cookie', cookie);
  }

  static Future<void> clearXuetangx() async {
    invalidateSync();
    await SecureStore.delete('xtx_cookie');
  }

  static String? yuketangCookie() => SecureStore.get('ykt_cookie');

  static Future<void> saveYuketang({required String cookie}) async {
    invalidateSync();
    await SecureStore.write('ykt_cookie', cookie);
  }

  static Future<void> clearYuketang() async {
    invalidateSync();
    await SecureStore.delete('ykt_cookie');
  }

  // ---- 教务平台配置（可任意学校，超级课程表式导入）----
  static String? jwConfigRaw() => _sp.getString('jw_config');

  static Future<void> saveJwConfigRaw(String v) => _setString('jw_config', v);

  // ---- 教务（正方）账号 ----
  static String? zfCookie() => SecureStore.get('zf_cookie');
  static String? zfXh() => _sp.getString('zf_xh');

  static Future<void> saveZf({required String cookie, String? xh}) async {
    invalidateSync();
    await SecureStore.write('zf_cookie', cookie);
    if (xh != null && xh.isNotEmpty) await _setString('zf_xh', xh);
  }

  /// 退出教务：清登录态、整张课表与学期校准。
  /// - 手动添加的课程（manual_ 前缀）与教务无关，保留（其配色恢复默认——
  ///   颜色按课程名存储，随教务课表一并清掉）；
  /// - timetable_semester/zf_raw_page/course_colors 必须清：残留学期文本会
  ///   干扰下次合并判断，残留在已删课表上的颜色键没有意义。
  static Future<void> clearZf() async {
    invalidateSync();
    final manual = [
      for (final c in courses())
        if (c.id.startsWith('manual_')) c,
    ];
    await SecureStore.delete('zf_cookie');
    await _remove('zf_xh');
    await _remove('courses_json');
    await _remove('semester_start');
    await _remove('timetable_semester');
    await _remove('zf_raw_page');
    await _remove('course_colors');
    await _remove('timetable_source');
    await _remove('semester_start_manual');
    if (manual.isNotEmpty) await saveCourses(manual);
  }

  // ---- 课表 ----
  static List<Course> courses() => _parseList('courses_json', Course.fromJson);

  static Future<void> saveCourses(List<Course> list) => _setString(
    'courses_json',
    jsonEncode(list.map((e) => e.toJson()).toList()),
  );

  /// 最近一次课表对应的学期文本，用于判断重新抓取是否同一学期（决定合并策略）。
  static String timetableSemester() =>
      _sp.getString('timetable_semester') ?? '';

  static Future<void> saveTimetableSemester(String v) =>
      _setString('timetable_semester', v);

  /// 学期第一周的周一。null = 未校准。
  static DateTime? semesterStart() {
    final ms = _sp.getInt('semester_start');
    if (ms == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(ms);
  }

  static Future<void> saveSemesterStart(DateTime monday) => _setInt(
    'semester_start',
    DateTime(monday.year, monday.month, monday.day).millisecondsSinceEpoch,
  );

  /// 上课提醒开关（课前 15 分钟）
  static bool classReminder() => _sp.getBool('class_reminder') ?? true;

  static Future<void> saveClassReminder(bool v) =>
      _setBool('class_reminder', v);

  /// 自定义作息时间表：每节 [开始, 结束] 距 0 点的分钟数。null = 用默认表。
  /// 读取时按索引自愈（索引=节次；**不可排序**——排序会把单点污染放大成
  /// 全表节次错位）：区间非法（start>=end、越界 [0,1440]）或与前一节重叠
  /// （start < 前一条 end，首尾相接允许）的条目，用默认表同节原地替换；
  /// 形状畸形的条目（非 List / 长度<2 / 元素非数字）同样按原索引占位自愈——
  /// 直接丢掉会让其后所有节次索引前移一位（第4节的值被当成第3节用）；
  /// 默认表长度内的自愈替换值若仍与前一节重叠，说明整表已不可信，整体回退
  /// 默认表（否则坏数据每次启动都自愈一轮，UI 与实际生效时间持续分叉）。
  /// 超出默认表的节次（13-16 节晚课）没有默认值可替换，改为合成接得上
  /// 前节的占位节——此前整表回退会把 16 节制学校前 12 节的自定义时刻
  /// 全部连带丢掉，表长也从 16 缩回 12。
  // 作息表读取被放进「天×课程」的提醒循环和周视图每个时间轴格里反复调用
  // （每次都是 prefs 读串 + jsonDecode + 12 条自愈校验），按原始串做一层
  // memo：串没变（没保存过新作息）直接返回上次结果。
  static String? _stRaw;
  static List<(int, int)>? _stParsed;

  static List<(int, int)>? sectionTimes() {
    final raw = _sp.getString('section_times');
    if (raw == null || raw.isEmpty) return null;
    if (raw == _stRaw) return _stParsed;
    final parsed = _parseSectionTimes(raw);
    _stRaw = raw;
    _stParsed = parsed;
    return parsed;
  }

  static List<(int, int)>? _parseSectionTimes(String raw) {
    try {
      final list = jsonDecode(raw) as List;
      if (list.length < 8) return null;
      final defaults = Course.sectionTimes;
      final entries = List<(int, int)?>.filled(list.length, null);
      for (var i = 0; i < list.length; i++) {
        final e = list[i];
        if (e is List && e.length >= 2 && e[0] is num && e[1] is num) {
          entries[i] = ((e[0] as num).toInt(), (e[1] as num).toInt());
        }
      }
      final out = <(int, int)>[];
      var prevEnd = -1;
      var healed = false;
      for (var i = 0; i < entries.length; i++) {
        final p = entries[i];
        final bad =
            p == null ||
            p.$1 >= p.$2 ||
            p.$1 < 0 ||
            p.$2 > 24 * 60 ||
            p.$1 < prevEnd;
        if (!bad) {
          prevEnd = p.$2;
          out.add(p);
          continue;
        }
        if (i >= defaults.length) {
          // 超出默认表又非法：不能整表回退——16 节制学校前 12 节的自定义
          // 时刻会被一条晚课坏数据全灭（表长还从 16 缩回 12）。合成一个
          // 接得上前节的占位节（45 分钟、封顶 23:59），保住表长与其余
          // 合法节次；后续节次若因占位重叠也被判坏，同样按此合成。
          // prevEnd 已顶到 23:59/24:00 时直接 +45 会产出零长/倒挂区间
          //（1439→(1439,1439)、1440→(1440,1439)），整节平移到 23:14-23:59
          var s = prevEnd < 0 ? 0 : prevEnd;
          if (s + 45 > 23 * 60 + 59) s = 23 * 60 + 59 - 45;
          final e = s + 45;
          out.add((s, e));
          prevEnd = e;
          healed = true;
          continue;
        }
        final d = defaults[i];
        if (d.$1 < prevEnd) return null; // 默认表也接不上：整体回退
        out.add(d);
        prevEnd = d.$2;
        healed = true;
      }
      if (healed) unawaited(saveSectionTimes(out));
      return out;
    } catch (_) {
      return null;
    }
  }

  static Future<void> saveSectionTimes(List<(int, int)> times) => _setString(
    'section_times',
    jsonEncode([
      for (final (a, b) in times) [a, b],
    ]),
  );

  static Future<void> clearSectionTimes() => _remove('section_times');

  // ---- 课表个性化（颜色 / 显示选项）----

  /// 课程名 → 调色板序号（用户长按课程块自选的颜色）。
  /// 按课程名生效：同一门课的所有节次/周次一起变色。
  /// 作业卡现在也按卡片读这里，列表重建高频——按原始串 memo。
  static String? _ccRaw;
  static Map<String, int> _ccParsed = {};

  static Map<String, int> courseColors() {
    final raw = _sp.getString('course_colors');
    if (raw == null || raw.isEmpty) return const {};
    if (raw == _ccRaw) return _ccParsed;
    Map<String, int> parsed = const {};
    try {
      final m = jsonDecode(raw) as Map;
      parsed = {
        for (final e in m.entries)
          if (e.value is int) e.key: e.value as int,
      };
    } catch (_) {
      parsed = const {};
    }
    _ccRaw = raw;
    _ccParsed = parsed;
    return parsed;
  }

  static Future<void> saveCourseColors(Map<String, int> map) =>
      _setString('course_colors', jsonEncode(map));

  /// 周视图是否淡化显示非本周课程（默认开）。
  static bool showNonWeekCourses() => _sp.getBool('show_non_week') ?? true;

  static Future<void> saveShowNonWeekCourses(bool v) =>
      _setBool('show_non_week', v);

  /// 最近一次拉到的课表页原文（调试：排查解析问题用；文本/截图导入也可存）
  static String zfRawPage() => _sp.getString('zf_raw_page') ?? '';

  static Future<void> saveZfRawPage(String page) => _setString(
    'zf_raw_page',
    page.length > 400000 ? page.substring(0, 400000) : page,
  );

  // ---- 作业 ----
  static List<HomeworkItem> homework() =>
      _parseList('homework_json', HomeworkItem.fromJson);

  /// A hidden platform task may retain its body only in hidden_items after sync.
  /// Include it for import warnings without restoring it to the active list.
  static List<HomeworkItem> homeworkForDuplicateCheck() =>
      _withHiddenHomework(homework());

  static List<HomeworkItem> _withHiddenHomework(List<HomeworkItem> items) {
    final ids = items.map((h) => h.id).toSet();
    for (final body in hiddenItems().values) {
      try {
        final item = HomeworkItem.fromJson(
          (jsonDecode(body) as Map).cast<String, dynamic>(),
        );
        if (ids.add(item.id)) items.add(item);
      } catch (_) {
        /* Keep unrecognized hidden bodies untouched. */
      }
    }
    return items;
  }

  /// Append-only import: keep every original JSON row and unknown field.
  /// The pure builder runs against the latest disk data inside the transaction.
  static Future<int> appendManualHomeworkBatch(
    List<HomeworkItem> Function(List<HomeworkItem> existing, Set<String> ids)
    create,
  ) => businessTransaction(() async {
    final raw = _sp.getString('homework_json');
    final List<dynamic> rows;
    try {
      final decoded = raw == null || raw.trim().isEmpty
          ? <dynamic>[]
          : jsonDecode(raw);
      if (decoded is! List) throw const FormatException();
      rows = List<dynamic>.of(decoded);
    } catch (_) {
      throw StateError('原有作业数据无法读取，已停止添加以保留原数据');
    }
    final existing = <HomeworkItem>[];
    final ids = <String>{};
    for (final row in rows) {
      if (row is! Map) continue;
      if (row['id'] is String) ids.add(row['id'] as String);
      try {
        existing.add(HomeworkItem.fromJson(row.cast<String, dynamic>()));
      } catch (_) {
        /* Preserve the original row even if this version cannot read it. */
      }
    }
    final additions = create(
      List.unmodifiable(_withHiddenHomework(existing)),
      Set.unmodifiable(ids),
    );
    final allIds = {...ids};
    for (final item in additions) {
      if (item.platform != PlatformKind.manual ||
          item.title.trim().isEmpty ||
          !allIds.add(item.id)) {
        throw StateError('新增作业无效，未写入任何内容');
      }
    }
    if (additions.isNotEmpty) {
      await _setString(
        'homework_json',
        jsonEncode([...rows, ...additions.map((item) => item.toJson())]),
      );
    }
    return additions.length;
  });

  /// 作业列表顶层损坏只备份一次：homework() 是高频读，不能每次都写 prefs；
  /// raw 变了（新的损坏形态）才再备一份。
  static final Set<String> _corruptRawBackedUp = {};

  /// 逐条解析列表数据：一条记录损坏只跳过那一条，
  /// 不让整张列表报废后被下次保存固化清空。
  static List<T> _parseList<T>(
    String key,
    T Function(Map<String, dynamic>) fromJson,
  ) {
    final raw = _sp.getString(key);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List;
      final out = <T>[];
      for (final e in list) {
        if (e is! Map) continue;
        try {
          out.add(fromJson(e.cast<String, dynamic>()));
        } catch (_) {
          // 单条损坏跳过，保住其余数据
        }
      }
      return out;
    } catch (_) {
      // 顶层损坏：先把原文备份到独立键再返回空——否则下一次同步回写
      // 会用空列表把唯一可恢复的副本固化掉（逐条自愈救不了顶层断裂）。
      final bakKey = '${key}_corrupt_bak';
      if (_corruptRawBackedUp.add('$bakKey\x1F$raw')) {
        unawaited(_setString(bakKey, raw));
      }
      return [];
    }
  }

  static Future<void> saveHomework(
    List<HomeworkItem> items, {
    bool fromSync = false,
  }) {
    if (!fromSync) invalidateSync();
    return _setString(
      'homework_json',
      jsonEncode(items.map((e) => e.toJson()).toList()),
    );
  }

  // ---- 排序偏好 ----
  static String sortMode() => _sp.getString('sort_mode') ?? 'time';

  static Future<void> saveSortMode(String mode) =>
      _setString('sort_mode', mode);

  // ---- 外观 ----
  static String themeMode() => _sp.getString('theme_mode') ?? 'system';

  static Future<void> saveThemeMode(String v) => _setString('theme_mode', v);

  /// 界面样式：clean 为默认晴黄，green 为原清夏；保留旧持久化键。
  static String uiStyle() => _sp.getString('ui_style') ?? 'clean';

  static Future<void> saveUiStyle(String v) => _setString('ui_style', v);

  // ---- 平台登录有效性标志（用于失效提醒去重）----
  static bool flag(String key) => _sp.getBool(key) ?? false;

  static Future<void> setFlag(String key, bool v) => _setBool(key, v);

  // ---- 手动隐藏（老师撤回/不需要提交的作业）----
  static Set<String> dismissedIds() =>
      (_sp.getStringList('dismissed_ids') ?? []).toSet();

  static Map<String, String> hiddenItems() {
    final raw = _sp.getString('hidden_items');
    if (raw == null || raw.isEmpty) return {};
    try {
      final m = jsonDecode(raw) as Map;
      // 逐条校验后即刻物化：惰性 cast 会把损坏条目拖到遍历时才炸
      return {
        for (final e in m.entries)
          if (e.key is String && e.value is String)
            e.key as String: e.value as String,
      };
    } catch (_) {
      return {};
    }
  }

  static Future<void> dismiss(String id, String itemJson) async {
    invalidateSync();
    // 先写条目数据、再记隐藏名单：两写之间崩溃时最多退化成「没隐藏」，
    // 反过来会让 id 进了名单而条目数据缺失——隐藏变永久删除。
    final map = hiddenItems()..[id] = itemJson;
    await _setString('hidden_items', jsonEncode(map));
    final ids = _sp.getStringList('dismissed_ids') ?? [];
    if (!ids.contains(id)) {
      await _setStringList('dismissed_ids', [...ids, id]);
    }
  }

  /// 备份导入用：整体替换隐藏名单（导入弹窗承诺「覆盖」，追加合并与承诺不符）。
  static Future<void> restoreHiddenItems(Map<String, String> items) async {
    invalidateSync();
    await _setString('hidden_items', jsonEncode(items));
    await _setStringList('dismissed_ids', items.keys.toList());
  }

  static Future<void> restoreDismissed(String id) async {
    invalidateSync();
    final ids = (_sp.getStringList('dismissed_ids') ?? [])..remove(id);
    await _setStringList('dismissed_ids', ids);
    final map = hiddenItems()..remove(id);
    await _setString('hidden_items', jsonEncode(map));
  }

  // ---- 提醒设置 ----
  static ReminderSettings reminders() {
    final raw = _sp.getString('reminders');
    if (raw == null) return ReminderSettings();
    try {
      return ReminderSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return ReminderSettings();
    }
  }

  static Future<void> saveReminders(ReminderSettings r) =>
      _setString('reminders', jsonEncode(r.toJson()));

  // ---- 调试日志 ----
  static List<SafeHttpLogEntry> debugLog() {
    final raw = _sp.getString('debug_log');
    if (raw == null) return [];
    return DebugLogCodec.decode(raw);
  }

  /// 日志脱敏：URL 与 body 里的 csrfKey/token/password 等键值打码，body
  /// 再过一遍「长 token」形状正则，最后截到 600 字。落盘（saveDebugLog）
  /// 与调试页「复制全部」（DebugPage 导出内存 SafeHttp.log 到剪贴板）
  /// 共用这一份规则——内存日志保留原文是记录在案的排查取舍，但凡是
  /// 离开 App 的副本（prefs / 剪贴板）都不允许带会话密钥原文。
  static SafeHttpLogEntry redactLogEntry(SafeHttpLogEntry e) {
    final kv = RegExp(
      r'(csrfKey|token|pwd|password|httpSessionId|sessionKey|sessionid|enc|stuenc|cookie|authorization)=([^&\s"<>]+)',
      caseSensitive: false,
    );
    final url = e.url.replaceAllMapped(kv, (m) => '${m.group(1)}=***');
    var body = e.bodySnippet;
    body = body.replaceAllMapped(kv, (m) => '${m.group(1)}=***');
    body = body.replaceAllMapped(
      RegExp(
        r'''(["'](?:csrfKey|token|pwd|password|httpSessionId|sessionKey|sessionid|enc|stuenc|cookie|authorization)["']\s*:\s*)(?:"(?:\\.|[^"\\])*(?:"|\\?$)|'(?:\\.|[^'\\])*(?:'|\\?$))''',
        caseSensitive: false,
      ),
      (m) => '${m.group(1)}"***"',
    );
    // 长 token（≥24 位、字母数字混合的连续串，形如会话密钥/base64）只留
    // 前 4 位保形；纯数字串（时间戳/contentId）与纯字母串（HTML 类名等）
    // 不动，保住排查价值
    body = body.replaceAllMapped(RegExp(r'[A-Za-z0-9+/=_-]{24,}'), (m) {
      final t = m.group(0)!;
      final mixed =
          RegExp(r'[A-Za-z]').hasMatch(t) && RegExp(r'\d').hasMatch(t);
      return mixed ? '${t.substring(0, 4)}***' : t;
    });
    if (body.length > 600) body = body.substring(0, 600);
    return SafeHttpLogEntry(e.time, e.method, url, e.status, body);
  }

  static Future<void> saveDebugLog(List<SafeHttpLogEntry> entries) async {
    // 持久化前脱敏：URL 里的 csrfKey/token 等不落明文 prefs（调试页可见
    // 的内存日志保持原样，落盘副本只留排查必需的形状）。
    final redacted = entries.take(200).map(redactLogEntry).toList();
    await _setString('debug_log', DebugLogCodec.encode(redacted));
  }
}
