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
  static const _version = 1;

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
        'settings': {
          'themeMode': Storage.themeMode(),
          'uiStyle': Storage.uiStyle(),
          'sortMode': Storage.sortMode(),
          'classReminder': Storage.classReminder(),
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
      throw FormatException('备份来自更新版本的作业通（v$version），'
          '请先升级 App 再导入');
    }

    // ---- 解析阶段（不写任何存储）----
    final courses = <Course>[];
    var badCourses = 0;
    for (final c in (decoded['courses'] as List? ?? [])) {
      if (c is! Map) continue;
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
        if (e is! Map) continue;
        try {
          items.add(HomeworkItem.fromJson(e.cast<String, dynamic>()));
        } catch (_) {
          badHomework++;
        }
      }
    }
    final startMs = decoded['semesterStart'];
    final start =
        startMs is num ? DateTime.fromMillisecondsSinceEpoch(startMs.toInt()) : null;
    final manualFlag = decoded['semesterStartManual'];
    final sem = decoded['timetableSemester'];
    final st = decoded['sectionTimes'];
    List<(int, int)>? times;
    if (st is List && st.length >= 8) {
      times = <(int, int)>[
        // 元素非数字此前直接 (p[0] as num) 抛 TypeError 毁掉导入
        for (final p in st)
          if (p is List && p.length >= 2 && p[0] is num && p[1] is num)
            ((p[0] as num).toInt(), (p[1] as num).toInt()),
      ];
      if (times.length < 8) times = null;
    }
    final hidden = <String, String>{};
    final hraw = decoded['hiddenItems'];
    if (hraw is Map) {
      for (final e in hraw.entries) {
        if (e.key is String && e.value is String) {
          hidden[e.key as String] = e.value as String;
        }
      }
    }
    final colors = decoded['courseColors'];
    final colorMap = <String, int>{
      if (colors is Map)
        for (final e in colors.entries)
          if (e.key is String && e.value is int) e.key as String: e.value as int,
    };

    // ---- 落库阶段（解析全部成功后才开始）----
    if (courses.isNotEmpty) await Storage.saveCourses(courses);
    // 作业：与课表同语义——备份里没有这个字段（旧版备份）才不动当前作业；
    // 有字段但为空（有意导出的空备份/导出端损坏）不把健康设备的作业清空
    if (hw is List && items.isNotEmpty) {
      await Storage.saveHomework(items);
    }
    if (start != null) await Storage.saveSemesterStart(start);
    if (manualFlag is bool) {
      await Storage.setFlag('semester_start_manual', manualFlag);
    }
    if (sem is String && sem.isNotEmpty) {
      await Storage.saveTimetableSemester(sem);
    }
    if (times != null) await Storage.saveSectionTimes(times);
    // 隐藏名单整体替换：导入弹窗承诺「覆盖」，追加合并与承诺不符
    if (hraw is Map) {
      await Storage.restoreHiddenItems(hidden);
    }
    if (colors is Map) await Storage.saveCourseColors(colorMap);

    final s = decoded['settings'];
    if (s is Map) {
      if (s['themeMode'] is String) await Storage.saveThemeMode(s['themeMode']);
      if (s['uiStyle'] is String) await Storage.saveUiStyle(s['uiStyle']);
      if (s['sortMode'] is String) await Storage.saveSortMode(s['sortMode']);
      if (s['classReminder'] is bool) {
        await Storage.saveClassReminder(s['classReminder']);
      }
      if (s['reminders'] is Map) {
        await Storage.saveReminders(ReminderSettings.fromJson(
            (s['reminders'] as Map).cast<String, dynamic>()));
      }
      if (s['jwConfig'] is String) await Storage.saveJwConfigRaw(s['jwConfig']);
    }

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
    return warnings.isEmpty ? base : '$base（${warnings.join('、')}）';
  }
}
