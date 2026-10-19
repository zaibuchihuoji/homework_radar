/// 教务课表课程数据模型：与作业（HomeworkItem）平行存储，互不影响。
library;

class Course {
  Course({
    required this.id,
    required this.name,
    this.teacher = '',
    this.room = '',
    required this.weekday,
    required this.startSection,
    required this.endSection,
    required this.weeks,
    this.edited = false,
    this.sectionsProvisional = false,
    this.anchorKey,
  });

  /// 稳定 id：课程名+时间+周次一致即为同一节课（跨同步不重复）
  final String id;
  final String name;

  /// 教师；解析不到时为空串
  final String teacher;

  /// 教室；解析不到时为空串
  final String room;

  /// 1=周一 … 7=周日
  final int weekday;

  /// 开始节次（1 起）
  final int startSection;

  /// 结束节次（含）
  final int endSection;

  /// 上课周列表（1 起，如 [1,2,3,...,16]）
  final List<int> weeks;

  /// 用户在预览页人工修正过；重新抓取/导入时同 id 优先保留修正值
  final bool edited;

  /// 节次是解析器的兜底值（如块式文本导入本就不含节次字段）而非真实数据。
  /// 仅用于预览页把这类条目标成「节次待定」且不预勾选；不落盘。
  final bool sectionsProvisional;

  /// 人工修正锚点：该课**编辑前**的匹配键（[editKey]，名字+星期+起始节次）。
  /// 为什么需要：用户用编辑表单改名/挪课后，这条课的 key 变了，教务重抓
  /// 结果按当前 key 匹配不到它，修正会静默丢失、union 合并还会把旧槽位的
  /// 原课保留成同槽双份。有锚点时合并按「incoming 的 key == anchorKey」
  /// 兜底找回修正。只在编辑保存处首次写入、已有值不覆盖（保留最初锚点）；
  /// null = 从未跨 key 编辑过（含旧版本落盘的数据，完全向后兼容）。
  final String? anchorKey;

  /// 人工修正匹配键：课程名+星期+起始节次。不用 id——id 一旦编入周次，
  /// 教务微调周次就会换 id，让修正失联（AppState 合并与编辑表单共用）。
  String get editKey => '$name#$weekday#$startSection';

  bool inWeek(int w) => weeks.contains(w);

  /// 默认作息：每节的 (开始, 结束) 距 0 点的分钟数。
  /// 按河南高校常见作息（上午 8:00 起、下午 14:30 起、晚上 19:00 起）。
  static const List<(int, int)> sectionTimes = [
    (8 * 60, 8 * 60 + 45),
    (8 * 60 + 55, 9 * 60 + 40),
    (10 * 60, 10 * 60 + 45),
    (10 * 60 + 55, 11 * 60 + 40),
    (14 * 60 + 30, 15 * 60 + 15),
    (15 * 60 + 25, 16 * 60 + 10),
    (16 * 60 + 20, 17 * 60 + 5),
    (17 * 60 + 15, 18 * 60),
    (19 * 60, 19 * 60 + 45),
    (19 * 60 + 55, 20 * 60 + 40),
    (20 * 60 + 50, 21 * 60 + 35),
    (21 * 60 + 45, 22 * 60 + 30),
  ];

  /// 由学期第一周的周一推算 day 所在周次（1 起）。
  static int weekNumberOf(DateTime firstMonday, DateTime day) {
    final a = DateTime(firstMonday.year, firstMonday.month, firstMonday.day);
    final b = DateTime(day.year, day.month, day.day);
    final mondayA = a.subtract(Duration(days: a.weekday - 1));
    final mondayB = b.subtract(Duration(days: b.weekday - 1));
    return (mondayB.difference(mondayA).inDays / 7).floor() + 1;
  }

  /// 周次显示，如「1-16周」「1-15(单)」「1-8,10-16周」。
  /// 全单/全双且区间内无缺口时压缩成「min-max(单/双)」，否则逐段列出。
  String get weeksText {
    if (weeks.isEmpty) return '周次未知';
    final sorted = [...weeks]..sort();
    final odd = sorted.every((w) => w.isOdd);
    final even = sorted.every((w) => w.isEven);
    if (sorted.length >= 2 && (odd || even)) {
      final first = sorted.first;
      final last = sorted.last;
      var complete = true;
      for (var w = first; w <= last; w++) {
        if (odd == w.isOdd && !sorted.contains(w)) {
          complete = false;
          break;
        }
      }
      if (complete) return '$first-$last${odd ? '(单)' : '(双)'}';
    }
    // 连续区间可压缩
    final runs = <List<int>>[];
    for (final w in sorted) {
      if (runs.isNotEmpty && w == runs.last.last + 1) {
        runs.last.add(w);
      } else {
        runs.add([w]);
      }
    }
    final text = runs
        .map((r) => r.length == 1 ? '${r.first}' : '${r.first}-${r.last}')
        .join(',');
    return '$text周';
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'teacher': teacher,
        'room': room,
        'weekday': weekday,
        'start': startSection,
        'end': endSection,
        'weeks': weeks,
        if (edited) 'edited': true,
        // 锚点只在有值时落盘，老数据（无该键）读回为 null
        if (anchorKey != null) 'anchorKey': anchorKey,
      };

  static Course fromJson(Map<String, dynamic> j) => Course(
        id: (j['id'] ?? '').toString(),
        name: j['name'] as String? ?? '',
        teacher: j['teacher'] as String? ?? '',
        room: j['room'] as String? ?? '',
        // 越界值钳回 1-7：不钳的话课程在任何一列都不渲染（换机导入后静默消失）
        weekday: ((j['weekday'] as num?)?.toInt() ?? 1).clamp(1, 7),
        startSection: (j['start'] as num?)?.toInt() ?? 1,
        endSection: (j['end'] as num?)?.toInt() ?? 1,
        weeks: ((j['weeks'] as List?) ?? const [])
            .map((e) => (e as num).toInt())
            .toList(),
        edited: j['edited'] as bool? ?? false,
        anchorKey: j['anchorKey'] as String?,
      );

  /// 稳定 id：课程名+星期+节次一致即为同一节课（跨同步不重复）。
  /// 周次不编入 id——教务微调周次不应换 id；endSection 编入，同槽不互撞。
  static String makeId({
    required String name,
    required int weekday,
    required int startSection,
    required int endSection,
  }) =>
      '$name#$weekday#$startSection-$endSection';

  // ---- 解析工具：周次/节次文本 ----

  /// 解析周次文本。调用方须保证 raw 只含周次上下文（不含教室号、节次等数字）。
  /// 支持格式：「1-16周」「1,3-5,8周」「3-16周(单)」「1-8周,9-16周」
  /// 「1-5,8,14双」（青果：段级单双只作用于所在段）。
  /// 括号全局「(单)/(双)」作用于全部段；无法解析时返回空列表。
  static List<int> parseWeeks(String raw) {
    final s = raw.replaceAll(RegExp(r'\s'), '');
    if (s.isEmpty) return const [];
    if (!RegExp(
      r'^第?\d{1,2}(?:[-–—~]\d{1,2})?[单双]?周?'
      r'(?:[,，、]第?\d{1,2}(?:[-–—~]\d{1,2})?[单双]?周?)*'
      r'(?:[(（][单双]周?[)）])?$',
    ).hasMatch(s)) {
      return const [];
    }
    final globalOdd = RegExp(r'[(（]单周?[)）]').hasMatch(s);
    final globalEven = RegExp(r'[(（]双周?[)）]').hasMatch(s);
    final cleaned =
        s.replaceAll(RegExp(r'[(（][单双]周?[)）]'), '').replaceAll('第', '');
    final out = <int>{};
    final segRe = RegExp(r'(\d+)(?:[-–—~](\d+))?(单|双)?');
    for (final m in segRe.allMatches(cleaned)) {
      final a = int.parse(m.group(1)!);
      final b = int.tryParse(m.group(2) ?? '') ?? a;
      if (a < 1 || b < a || b > 30) return const [];
      final odd = globalOdd || m.group(3) == '单';
      final even = globalEven || m.group(3) == '双';
      for (var w = a; w <= b; w++) {
        if (odd && w.isEven) continue;
        if (even && w.isOdd) continue;
        out.add(w);
      }
    }
    final list = out.toList()..sort();
    return list;
  }

  static final _sectionToken = RegExp(
    r'第?\s*(\d{1,2})\s*[-–—,，、~到]\s*(\d{1,2})\s*节',
  );
  static final _sectionSingle = RegExp(r'第?\s*(\d{1,2})\s*节');

  /// 解析节次文本，返回 (start, end)；解析不到返回 null。
  static (int, int)? parseSections(String raw) {
    final m = _sectionToken.firstMatch(raw);
    if (m != null) {
      final a = int.parse(m.group(1)!);
      final b = int.parse(m.group(2)!);
      if (a >= 1 && b >= a && b <= 16) return (a, b);
    }
    final single = _sectionSingle.firstMatch(raw);
    if (single != null) {
      final a = int.parse(single.group(1)!);
      if (a >= 1 && a <= 16) return (a, a);
    }
    return null;
  }
}
