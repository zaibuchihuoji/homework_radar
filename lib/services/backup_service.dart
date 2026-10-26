/// 本地数据备份：课表/学期校准/作息/隐藏作业/偏好 → 单个 JSON 文件。
/// 有意不包含账号 Cookie 等敏感凭据——导出文件里没有登录态。
library;

import 'dart:convert';

import '../models/course.dart';
import '../models/homework.dart';
import 'storage.dart';

class BackupService {
  BackupService._();

  static const _magic = 'homework_radar';
  static const _version = 2;

  static Map<String, dynamic> exportMap() => {
    'app': _magic,
    'version': _version,
    'exportedAt': DateTime.now().toIso8601String(),
    'courses': [for (final c in Storage.courses()) c.toJson()],
    // 作业列表（含手动添加与用户备注）——换机不丢手动作业
    'homework': [for (final h in Storage.homework()) h.toJson()],
    'semesterStart': Storage.semesterStart()?.millisecondsSinceEpoch,
    // 手动校准标记不随备份走的话，换机后校准值会被下次抓取的
    // 自动检测覆盖（代码注释里明说要防的事故）
    'semesterStartManual': Storage.flag('semester_start_manual'),
    // 学期文本缺失会让下次重抓的合并判断走错分支
    'timetableSemester': Storage.timetableSemester(),
    'sectionTimes': [
      for (final (a, b) in (Storage.sectionTimes() ?? const <(int, int)>[]))
        [a, b],
    ],
    'hiddenItems': Storage.hiddenItems(),
    'courseColors': Storage.courseColors(),
    'timetableSource': Storage.timetableSource(),
    'accountArchives': Storage.accountArchives(),
    'settings': {
      'themeMode': Storage.themeMode(),
      'uiStyle': Storage.uiStyle(),
      'sortMode': Storage.sortMode(),
      'classReminder': Storage.classReminder(),
      'classReminderMinutes': Storage.classReminderMinutes(),
      'reminders': Storage.reminders().toJson(),
      'jwConfig': Storage.jwConfigRaw() ?? '',
    },
  };

  static String encode() => jsonEncode(exportMap());

  /// 从备份 JSON 恢复。返回给用户看的结果描述；格式不对抛 FormatException。
  ///
  /// 恢复是「先全部解析、解析完才落库」：此前边解析边写盘，中途一个坏
  /// sectionTimes 元素就留下半恢复状态（课表/作业已覆盖、作息还是旧值）。
  static Future<String> importJson(String raw) async {
    final dynamic decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      throw const FormatException('文件不是合法 JSON');
    }
    if (decoded is! Map || decoded['app'] != _magic) {
      throw const FormatException('不是作业通的备份文件');
    }
    // 版本校验：高版本备份的低版本应用多半解析不全，静默半解析并谎报
    // 成功会把「少数据」伪装成「恢复完成」
    final version = (decoded['version'] as num?)?.toInt() ?? 1;
    if (version > _version) {
      throw FormatException(
        '备份来自更新版本的作业通（v$version），'
        '请先升级 App 再导入',
      );
    }

    // ---- 解析阶段（不写任何存储）----
    for (final key in [
      'courses',
      'homework',
      'sectionTimes',
      'accountArchives',
    ]) {
      if (decoded.containsKey(key) && decoded[key] is! List) {
        throw FormatException('备份字段 $key 格式损坏，未覆盖当前数据');
      }
    }
    for (final key in ['hiddenItems', 'courseColors', 'settings']) {
      if (decoded.containsKey(key) && decoded[key] is! Map) {
        throw FormatException('备份字段 $key 格式损坏，未覆盖当前数据');
      }
    }
    final courses = <Course>[];
    var badCourses = 0;
    for (final c in (decoded['courses'] as List? ?? [])) {
      if (c is! Map) {
        badCourses++;
        continue;
      }
      try {
        courses.add(Course.fromJson(c.cast<String, dynamic>()));
      } catch (_) {
        badCourses++; // 一条坏课不再毁掉整份备份（与作业的逐条容错对齐）
      }
    }
    final hw = decoded['homework'];
    final items = <HomeworkItem>[];
    var badHomework = 0;
    if (hw is List) {
      for (final e in hw) {
        if (e is! Map) {
          badHomework++;
          continue;
        }
        try {
          items.add(HomeworkItem.fromJson(e.cast<String, dynamic>()));
        } catch (_) {
          badHomework++;
        }
      }
    }
    final startMs = decoded['semesterStart'];
    if (badCourses > 0 || badHomework > 0) {
      throw FormatException(
        '备份包含损坏的课程或作业（课表$badCourses条、作业$badHomework条），未覆盖当前数据。请先修复备份。',
      );
    }
    final start = startMs is num
        ? DateTime.fromMillisecondsSinceEpoch(startMs.toInt())
        : null;
    final manualFlag = decoded['semesterStartManual'];
    final sem = decoded['timetableSemester'];
    final st = decoded['sectionTimes'];
    if (st is List && st.isNotEmpty && (st.length < 8 || st.length > 16)) {
      throw const FormatException('作息必须包含8至16节，未覆盖当前数据');
    }
    List<(int, int)>? times;
    if (st is List && st.length >= 8) {
      if (st.length > 16) throw const FormatException('作息节数不能超过16节');
      times = <(int, int)>[];
      for (var i = 0; i < st.length; i++) {
        final p = st[i];
        if (p is List && p.length >= 2 && p[0] is num && p[1] is num) {
          times.add(((p[0] as num).toInt(), (p[1] as num).toInt()));
        } else if (i < Course.sectionTimes.length) {
          times.add(Course.sectionTimes[i]);
        } else {
          throw FormatException('第${i + 1}节作息损坏，未恢复任何数据');
        }
      }
    }
    final hidden = <String, String>{};
    final hraw = decoded['hiddenItems'];
    if (hraw is Map) {
      for (final e in hraw.entries) {
        if (e.key is String && e.value is String) {
          try {
            final body = HomeworkItem.fromJson(
              Map<String, dynamic>.from(jsonDecode(e.value as String) as Map),
            );
            if (body.id != e.key) throw const FormatException('隐藏作业标识不匹配');
          } catch (_) {
            throw const FormatException('备份的隐藏作业损坏，未覆盖当前数据');
          }
          hidden[e.key as String] = e.value as String;
        } else {
          throw const FormatException('备份的隐藏作业损坏，未覆盖当前数据');
        }
      }
    }
    final colors = decoded['courseColors'];
    final colorMap = <String, int>{
      if (colors is Map)
        for (final e in colors.entries)
          if (e.key is String && e.value is int)
            e.key as String: e.value as int,
    };

    final archived = decoded['accountArchives'];
    final parsedArchives = <Map<String, dynamic>>[];
    if (archived is List) {
      for (final a in archived) {
        if (a is! Map ||
            a['id'] is! String ||
            a['platform'] is! String ||
            a['homework'] is! List ||
            a['hiddenItems'] is! Map) {
          throw const FormatException('账号归档格式损坏，未恢复任何数据');
        }
        parsedArchives.add({
          'id': a['id'],
          'createdAt': a['createdAt'],
          'platform': a['platform'],
          'homework': [
            for (final h in a['homework'] as List)
              HomeworkItem.fromJson(Map<String, dynamic>.from(h as Map))
                  .toJson(),
          ],
          'hiddenItems': Map<String, String>.from(a['hiddenItems'] as Map),
          if (a['courses'] is List)
            'courses': [
              for (final c in a['courses'] as List)
                Course.fromJson(Map<String, dynamic>.from(c as Map)).toJson(),
            ],
          if (a['semesterStart'] is num) 'semesterStart': a['semesterStart'],
          if (a['timetableSemester'] is String)
            'timetableSemester': a['timetableSemester'],
          if (a['timetableSource'] is String)
            'timetableSource': a['timetableSource'],
        });
      }
    }
    final settings = decoded['settings'];
    final classMinutes = settings is Map
        ? settings['classReminderMinutes']
        : null;
    if (settings is Map &&
        settings.containsKey('classReminderMinutes') &&
        (classMinutes is! int || classMinutes < 1 || classMinutes > 180)) {
      throw const FormatException('课前提醒时间格式损坏，未覆盖当前数据');
    }
    final reminder = settings is Map && settings['reminders'] is Map
        ? ReminderSettings.fromJson(
            Map<String, dynamic>.from(settings['reminders'] as Map),
          )
        : null;

    // 备份没有可核验的账号归属。已有登录会话的平台只导入只读归档，
    // 不能让备份中的备注/完成状态/隐藏ID挂到当前另一个账号。
    bool loggedIn(PlatformKind p) => switch (p) {
      PlatformKind.chaoxing => Storage.chaoxingCookie()?.isNotEmpty == true,
      PlatformKind.mooc => Storage.moocCookie()?.isNotEmpty == true,
      PlatformKind.zhihuishu => Storage.zhihuishuCookie()?.isNotEmpty == true,
      PlatformKind.xuetangx => Storage.xuetangxCookie()?.isNotEmpty == true,
      PlatformKind.yuketang => Storage.yuketangCookie()?.isNotEmpty == true,
      PlatformKind.manual => false,
    };
    final isolated = <Map<String, dynamic>>[];

    // ---- 落库阶段（解析全部成功；日志保护整组写入）----
    await Storage.businessTransaction(() async {
      final imported = items.where((h) => !loggedIn(h.platform)).toList();
      final activeHidden = Map<String, String>.from(hidden)
        ..removeWhere(
          (id, raw) => loggedIn(
            HomeworkItem.fromJson(jsonDecode(raw) as Map<String, dynamic>)
                .platform,
          ),
        );
      for (final p in PlatformKind.values.where(loggedIn)) {
        final platformItems = items.where((h) => h.platform == p).toList();
        final platformHidden = <String, String>{
          for (final e in hidden.entries)
            if (HomeworkItem.fromJson(
                  jsonDecode(e.value) as Map<String, dynamic>,
                ).platform ==
                p)
              e.key: e.value,
        };
        if (platformItems.isNotEmpty || platformHidden.isNotEmpty) {
          final now = DateTime.now();
          isolated.add({
            'id': '${now.microsecondsSinceEpoch}_backup_${p.key}',
            'createdAt': now.toIso8601String(),
            'platform': p.key,
            'homework': [for (final h in platformItems) h.toJson()],
            'hiddenItems': platformHidden,
          });
        }
      }
      imported.addAll(Storage.homework().where((h) => loggedIn(h.platform)));
      for (final e in Storage.hiddenItems().entries) {
        try {
          if (loggedIn(
            HomeworkItem.fromJson(jsonDecode(e.value) as Map<String, dynamic>)
                .platform,
          )) {
            activeHidden[e.key] = e.value;
          }
        } catch (_) {
          throw const FormatException('当前隐藏作业损坏，请先导出数据再恢复备份');
        }
      }
      if (decoded['courses'] is List) await Storage.saveCourses(courses);
      // 作业：与课表同语义——备份里没有这个字段（旧版备份）才不动当前作业；
      // 有字段且合法的空列表也恢复为空，避免混入目标设备的旧数据。
      if (hw is List) {
        await Storage.saveHomework(imported);
      }
      if (start != null) await Storage.saveSemesterStart(start);
      if (decoded.containsKey('semesterStart') && start == null) {
        await Storage.clearSemesterStart();
      }
      if (manualFlag is bool) {
        await Storage.setFlag('semester_start_manual', manualFlag);
      }
      if (sem is String) {
        await Storage.saveTimetableSemester(sem);
      }
      if (times != null) await Storage.saveSectionTimes(times);
      if (st is List && st.isEmpty) await Storage.clearSectionTimes();
      if (decoded['timetableSource'] is String) {
        await Storage.saveTimetableSource(decoded['timetableSource'] as String);
      }
      await Storage.mergeAccountArchives([...parsedArchives, ...isolated]);
      // 隐藏名单整体替换：导入弹窗承诺「覆盖」，追加合并与承诺不符
      if (hraw is Map) {
        await Storage.restoreHiddenItems(activeHidden);
      }
      if (colors is Map) await Storage.saveCourseColors(colorMap);

      final s = decoded['settings'];
      if (s is Map) {
        if (s['themeMode'] is String) {
          await Storage.saveThemeMode(s['themeMode']);
        }
        if (s['uiStyle'] is String) await Storage.saveUiStyle(s['uiStyle']);
        if (s['sortMode'] is String) await Storage.saveSortMode(s['sortMode']);
        if (s['classReminder'] is bool) {
          await Storage.saveClassReminder(s['classReminder']);
        }
        if (classMinutes is int) {
          await Storage.saveClassReminderMinutes(classMinutes);
        }
        if (reminder != null) await Storage.saveReminders(reminder);
        if (s['jwConfig'] is String) {
          await Storage.saveJwConfigRaw(s['jwConfig']);
        }
      }
    });

    // 汇总用「实际导入」条数：按文件原始条数虚报会掩盖坏条目被跳过
    final parts = <String>[
      if (courses.isNotEmpty) '课表 ${courses.length} 节',
      if (items.isNotEmpty) '作业 ${items.length} 条',
      if (start != null) '学期校准',
      if (hidden.isNotEmpty) '隐藏作业 ${hidden.length} 条',
    ];
    final warnings = <String>[
      if (badCourses > 0) '$badCourses 条坏课表数据被跳过',
      if (badHomework > 0) '$badHomework 条坏作业数据被跳过',
    ];
    if (parts.isEmpty && warnings.isEmpty) return '备份为空，没有可恢复的数据';
    final base = parts.isEmpty ? '没有可恢复的数据' : '已恢复：${parts.join('、')}';
    final ownership = isolated.isEmpty ? '' : '；已登录平台的备份记录已放入只读归档，未关联当前账号';
    return (warnings.isEmpty ? base : '$base（${warnings.join('、')}）') +
        ownership;
  }
}
