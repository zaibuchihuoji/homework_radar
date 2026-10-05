/// 课表文本导入解析：把用户从教务页面复制、或手动整理的课表文本解析成课程。
/// 支持两类输入：
///  1. 块式：「星期一」单独一行，其后跟该天的课程行（课程名/教师/周次/教室 各一行）；
///  2. 行内式：「周一 1-2节 高等数学 王一 1-16周 3-301」一行一门课。
/// 星期识别不到时课程 weekday=0（预览页里人工指定）。
/// 文本里出现的「2025-2026学年第X学期」会被扫出随结果返回（见
/// parseWithSemester），页面传给入库接口做换学期整体替换判断。
/// URP 花括号格式 {课程名;教师;周次;教室} 复制出来也兼容。
library;

import '../models/course.dart';
import 'timetable_parser.dart';

class TimetableTextParser {
  TimetableTextParser._();

  static final _dayLine =
      RegExp(r'^[（(]?\s*(?:星期|周|礼拜)\s*([一二三四五六日天])\s*[)）]?$');
  /// 行内星期前缀：星期字后面必须是空白/「第」/数字/行尾才算前缀，
  /// 否则「周一鸣 高等数学」这类课名/人名会被当成星期吞掉。
  static final _dayPrefix =
      RegExp(r'^(?:星期|周|礼拜)\s*([一二三四五六日天])(?=\s|第|\d|$)');

  /// 星期词（不限行首）：用于识别网页复制的整行星期表头。
  static final _dayWord = RegExp(r'(?:星期|周|礼拜)[一二三四五六日天]');

  /// 表头行除星期词外还可能夹的列头词/空白（「节次/时间/上午/下午/午/中午/
  /// 晚上」）。靠「剔除后整行为空」兜底，多列几个词不会误伤含真实内容的行。
  static final _headerFiller =
      RegExp(r'节次|时间|上午|下午|中午|晚上|午|\s');

  /// 学期文本（与 timetable_parser.dart extractJs 的正则同口径）。
  static final _semester =
      RegExp(r'\d{4}-\d{4}学年第[一二三四]学期');

  /// 节次行（「3-4节」「第3,4节」）：行内式整行课程的开头标志。
  static final _leadingSections =
      RegExp(r'^第?\s*\d{1,2}\s*[-–—,，]\s*\d{1,2}\s*节$');

  static int _dayNum(String cn) {
    const map = {'一': 1, '二': 2, '三': 3, '四': 4, '五': 5, '六': 6, '日': 7, '天': 7};
    return map[cn] ?? 0;
  }

  static List<Course> parse(String text) =>
      parseWithSemester(text).courses;

  /// 解析并附带扫出的学期文本（「2025-2026学年第一学期」）。
  /// 页面把 semesterText 传给 onTimetableCaptured 后，换学期贴整表
  /// 才会走整体替换而不是 union 合并，避免两学期课程混排。
  static ({List<Course> courses, String semesterText}) parseWithSemester(
      String text) {
    var t = text.replaceAll('\r', '');
    // URP 花括号字段 → 逐字段成行
    if (t.contains('{')) t = t.replaceAll(RegExp(r'[{};；|]'), '\n');

    final out = <Course>[];
    String? semester;
    var weekday = 0;
    var block = <String>[];

    void flush() {
      if (block.isEmpty) return;
      for (final e in TimetableParser.parseCellLines(block.join('\n'))) {
        // 块式格式（应用文档教用户的主格式）本就不含节次字段：兜底出的
        // 1-1 节不是真实数据，标「节次待定」让预览页不预勾选，否则一键
        // 入库后上课提醒全按第 1 节排
        out.add(TimetableParser.entryToCourse(e, weekday,
            provisionalSections: e.start <= 0));
      }
      block = [];
    }

    for (final rawLine in t.split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;

      // 网页复制的表头行「星期一 星期二 … 星期日」（可能夹「时间/上午/下午」
      // 列头）：必须先于行内前缀判断整行跳过，否则只剥掉行首一个星期词，
      // 其余星期词会被当课名/教师，甚至让整页解析为空。要求 ≥3 个星期词
      // 且剔除后无残留，避免误伤「周一 高等数学 周三 大学英语」这类行。
      final dayWordCount = _dayWord.allMatches(line).length;
      if (dayWordCount >= 3 &&
          line.replaceAll(_dayWord, '').replaceAll(_headerFiller, '').isEmpty) {
        continue;
      }

      // 学期行：扫出来随结果返回（首个出现的为准）。把学期文本从行里
      // 剥掉再走后续判断——不剥的话「2025-2026学年第一学期」会被当
      // 课名/教室污染条目；剩余内容非空时继续按星期行/前缀行/普通行处理
      var workLine = line;
      final mSem = _semester.firstMatch(workLine);
      if (mSem != null) {
        semester ??= mSem.group(0);
        workLine = workLine.replaceRange(mSem.start, mSem.end, '').trim();
        if (workLine.isEmpty) continue;
      }

      // 独立星期行 → 块边界：结算上一块，切换当前星期
      final mLine = _dayLine.firstMatch(workLine);
      if (mLine != null) {
        flush();
        weekday = _dayNum(mLine.group(1)!);
        continue;
      }

      // 行内星期前缀：剥掉前缀后按 token 进当前块
      final mPre = _dayPrefix.firstMatch(workLine);
      if (mPre != null) {
        flush();
        weekday = _dayNum(mPre.group(1)!);
        final rest = workLine.substring(mPre.end).trim();
        if (rest.isNotEmpty) {
          block.addAll(rest.split(RegExp(r'\s+')).where((s) => s.isNotEmpty));
        }
        continue;
      }

      // 无前缀行与行内式一致按空白分词：同一天第二门课省略「周X」前缀时
      //（如「3-4节 大学物理 王二 2-17周 5-102」），整行入块会成课名、
      // 因无周次被 parseCellLines 静默丢弃
      final tokens =
          workLine.split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
      // 「1-16周 第1-2节」周次+节次同行的粘贴形态：拆开的纯节次 token 会被
      // parseCellLines 当独立节次行误开新条目（本门丢节次、教室成幽灵），
      // 合并回前面的周次 token 恢复整行语义
      final merged = <String>[];
      for (final tok in tokens) {
        if (merged.isNotEmpty &&
            _leadingSections.hasMatch(tok) &&
            merged.last.contains('周') &&
            merged.last.startsWith(RegExp(r'\d'))) {
          merged[merged.length - 1] = '${merged.last} $tok';
        } else {
          merged.add(tok);
        }
      }
      // 节次开头的多词行是完整的一门课：先结算上一块。不结算的话它的
      // 节次行会挂到上一门课上，把上一门已确定的节次改写掉
      //（单 token 的独立节次行是块式的字段行，仍归当前块）
      if (merged.length > 1 && _leadingSections.hasMatch(merged.first)) {
        flush();
      }
      block.addAll(merged);
    }
    flush();
    return (courses: out, semesterText: semester ?? '');
  }
}
