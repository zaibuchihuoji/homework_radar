/// 教务课表抓取辅助：WebView 内注入 JS 提取课表表格，回到 Dart 解析。
/// 解析内核为通用网格解析器，兼容国内常见教务系统的课表页：
///  - 金智青果（KINGOSOFT）二维表：格子「课程名/教师/周次[节次]/教室」，行头大节号；
///  - 正方（ZFSoft）个人课表：格子「课程名/1-16周/教室/教师」，周次行不带节次括号；
///  - 强智（QiangZhi）学生课表：格子「课程名/周次/教室/教师」，行头常为空；
///  - URP：格子为花括号字段「{课程名;教师;周次;教室}」。
/// 表头「星期X」「周X」两种写法都认。抓取与解析解耦：检测到含星期表头的
/// 表格后取其 outerHTML，回到 Dart 逐格解析；多个课表候选必须人工选择。
library;

import 'dart:convert';

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

import '../models/course.dart';

/// 教务系统厂商类型（用于界面展示识别结果；解析不依赖它）。
enum JwKind { kingosoft, zsoft, qiangzhi, urp, unknown }

extension JwKindLabel on JwKind {
  String get label => switch (this) {
    JwKind.kingosoft => '金智青果',
    JwKind.zsoft => '正方',
    JwKind.qiangzhi => '强智',
    JwKind.urp => 'URP',
    JwKind.unknown => '未知类型',
  };
}

/// 按页面特征猜测教务系统类型（只用于展示，解析是通用的）。
JwKind sniffJwKind(String url, String pageText) {
  final u = url.toLowerCase();
  final t = pageText.toLowerCase();
  bool has(String s) => u.contains(s) || t.contains(s);
  if (has('kingosoft') || t.contains('青果')) return JwKind.kingosoft;
  if (has('zfsoft') || t.contains('正方') || has('zfpj')) return JwKind.zsoft;
  if (t.contains('强智') || has('qzsoft') || has('qzkj')) return JwKind.qiangzhi;
  if (has('urp')) return JwKind.urp;
  return JwKind.unknown;
}

class ParsedTimetable {
  ParsedTimetable({
    required this.courses,
    this.xh = '',
    this.semesterText = '',
    this.detectedWeek,
    this.rawPage = '',
    this.error,
  });

  final List<Course> courses;

  /// 学号（页面文本里抓的）
  final String xh;

  /// 学期文本，如「2026-2027学年第一学期」
  final String semesterText;

  /// 页面里检测到的当前周次（部分系统没有，可能为 null）
  final int? detectedWeek;

  /// 原始表格 HTML（调试用）
  final String rawPage;

  final String? error;

  bool get isEmpty => courses.isEmpty;
}

/// 解析产物中间条目：一条 = 一门课在某天某节次的一段安排。
class CourseEntry {
  String name = '';
  String teacher = '';
  String room = '';
  int start = 0;
  int end = 0;
  List<int> weeks = const [];
}

class TimetableParser {
  TimetableParser._();

  /// WebView 内执行的提取脚本：保留含「星期一/周一」的独立最外层表格，
  /// 连同学号/学期/周次文本一起打包成 JSON 返回。
  static const extractJs = r'''
(function() {
  function has(text) {
    // 注意：这里必须是真实汉字或单反斜杠 \uXXXX——双反斜杠在 JS 里是字面量，永远匹配不上。
    // 只要求出现周一列：强制周日的话 5 天课表的学校主抓取整体失效
    return text.indexOf('星期一') >= 0 || text.indexOf('周一') >= 0;
  }
  // 课表常嵌在同源 iframe/frame 里（正方/青果常见），且常是多层嵌套
  // （外壳 frame → 内容 frame → 课表 frame），必须递归走查
  function docs() {
    var out = [document];
    var stack = [document];
    while (stack.length) {
      var d = stack.pop();
      var fs = d.querySelectorAll('iframe,frame');
      for (var i = 0; i < fs.length; i++) {
        try {
          var c = fs[i].contentDocument;
          if (c && out.indexOf(c) < 0) { out.push(c); stack.push(c); }
        } catch (e) {}
      }
    }
    return out;
  }
  var best = '';
  var roots = [];
  var ds = docs();
  for (var k = 0; k < ds.length; k++) {
    var tables = ds[k].querySelectorAll('table');
    for (var i = 0; i < tables.length; i++) {
      var h = tables[i].outerHTML || '';
      if (has(h)) {
        // 祖先表格的outerHTML已包含子表格，不重复打包；独立兄弟表必须保留，
        // 不能先按大小丢掉一张，再让Dart误认为已获得完整课表。
        var p = tables[i].parentElement;
        var nested = false;
        while (p) {
          if (roots.indexOf(p) >= 0) { nested = true; break; }
          p = p.parentElement;
        }
        if (!nested) roots.push(tables[i]);
      }
    }
  }
  best = roots.map(function(t) { return t.outerHTML || ''; }).join('\n');
  var text = '';
  for (var k = 0; k < ds.length; k++) {
    text += (ds[k].body ? ds[k].body.innerText : '') + '\n';
  }
  var xh = '';
  var m = text.match(/学号[：:]\s*(\d{6,15})/);
  if (m) xh = m[1];
  var week = '';
  // 通知、课程安排中的「第N周」不是当前周，不得用于校准开学日期。
  m = text.match(/(?:当前|本周|现在|今日)[：:\s]*(?:为|是)?\s*第?\s*(\d{1,2})\s*周/);
  if (m) week = m[1];
  var sem = '';
  m = text.match(/\d{4}-\d{4}学年第[一二三四]学期/);
  if (m) sem = m[0];
  return JSON.stringify({table: best, xh: xh, week: week, sem: sem});
})()
''';

  /// 解析 extractJs 的返回值（Android 会给外层多包一层（或两层）JSON 引号，
  /// 与抓取页 _copyPageHtml 的循环剥壳保持一致）。
  static ParsedTimetable parseExtracted(Object? result) {
    var s = result?.toString() ?? '';
    if (s.isEmpty) return ParsedTimetable(courses: const []);
    try {
      for (var i = 0; i < 2 && s.length >= 2; i++) {
        if (!s.startsWith('"') || !s.endsWith('"')) break;
        try {
          s = jsonDecode(s) as String;
        } catch (_) {
          break;
        }
      }
      final data = jsonDecode(s);
      if (data is! Map) return ParsedTimetable(courses: const []);
      final table = (data['table'] ?? '').toString();
      final weekText = (data['week'] ?? '').toString();
      return ParsedTimetable(
        courses: table.isEmpty ? const [] : parseTimetableGrid(table),
        xh: (data['xh'] ?? '').toString(),
        semesterText: (data['sem'] ?? '').toString(),
        detectedWeek: int.tryParse(weekText),
        rawPage: table,
      );
    } on FormatException catch (e) {
      return ParsedTimetable(courses: const [], error: e.message);
    } catch (_) {
      return ParsedTimetable(courses: const []);
    }
  }

  /// 页面文本里是否已出现课表（不用拉全 HTML 的轻量探测）。
  static const hasTimetableJs = r'''
(function() {
  function probe(d) {
    var t = d.body ? d.body.innerText : '';
    // 与 extractJs 同口径：只要求周一（5 天课表也要能探测到）
    return t.indexOf('星期一') >= 0 || t.indexOf('周一') >= 0;
  }
  var out = [document];
  var stack = [document];
  while (stack.length) {
    var d = stack.pop();
    var fs = d.querySelectorAll('iframe,frame');
    for (var i = 0; i < fs.length; i++) {
      try {
        var c = fs[i].contentDocument;
        if (c && out.indexOf(c) < 0) { out.push(c); stack.push(c); }
      } catch (e) {}
    }
  }
  for (var i = 0; i < out.length; i++) {
    if (probe(out[i])) return '1';
  }
  return '0';
})()
''';

  // ---------- 表格级解析 ----------

  /// 兼容旧调用名（青果二维表）。
  static List<Course> parseKingosoftTable(String tableHtml) =>
      parseTimetableGrid(tableHtml);

  /// 每张候选必须有自己的星期表头。多个非空课表可能是分时段表、
  /// 不同学期或重复视图，无法仅凭HTML安全确定归属时拒绝自动选表。
  static List<Course> parseTimetableGrid(String tableHtml) {
    final doc = html_parser.parse(tableHtml);
    final candidates = <dom.Element>[];
    for (final t in doc.querySelectorAll('table')) {
      if (_hasWeekdayHeaderRow(t)) candidates.add(t);
    }
    candidates.sort((a, b) => a.outerHtml.length.compareTo(b.outerHtml.length));
    List<Course>? selected;
    for (final t in candidates) {
      final courses = _parseGrid(t);
      if (courses.isEmpty) continue;
      if (selected != null) {
        throw const FormatException(
          '检测到多张课表，无法确认它们属于同一学期或不同视图。'
          '请在教务中只保留目标课表后重试，或按目标课表粘贴文本导入。',
        );
      }
      selected = courses;
    }
    return selected ?? const [];
  }

  static int _dayOfHeader(String text) {
    final m = RegExp(r'^\s*(?:星期|周|礼拜)\s*([一二三四五六日天])\s*$')
        .firstMatch(text.trim());
    if (m == null) return 0;
    const map = {
      '一': 1,
      '二': 2,
      '三': 3,
      '四': 4,
      '五': 5,
      '六': 6,
      '日': 7,
      '天': 7,
    };
    return map[m.group(1)!] ?? 0;
  }

  /// 嵌套表格防串列：个别教务模板的课程单元格里内嵌 `<table>`，
  /// querySelectorAll 会把内层的 tr/td 按文档序混进外层网格，列对齐全毁
  /// （rowspan 占位被幽灵内嵌行提前消费，后续行整体左移）。行只取
  /// 「祖先链上没有更内层 table」的 tr，格只取 tr 的直接子 td/th。
  static List<dom.Element> _tableRows(dom.Element table) {
    final out = <dom.Element>[];
    for (final tr in table.querySelectorAll('tr')) {
      var p = tr.parent;
      var nested = false;
      while (p != null && !identical(p, table)) {
        if (p.localName == 'table') {
          nested = true;
          break;
        }
        p = p.parent;
      }
      if (!nested) out.add(tr);
    }
    return out;
  }

  static List<dom.Element> _rowCells(dom.Element tr) => tr.children
      .where((e) => e.localName == 'td' || e.localName == 'th')
      .toList();

  static bool _hasWeekdayHeaderRow(dom.Element table) {
    for (final tr in _tableRows(table)) {
      if (_rowHeaderDays(tr).length >= 5) return true;
    }
    return false;
  }

  /// 一行里的「星期X」表头格：列下标 → 星期号。
  static Map<int, int> _rowHeaderDays(dom.Element tr) {
    final out = <int, int>{};
    final cells = _rowCells(tr);
    for (var i = 0; i < cells.length; i++) {
      final d = _dayOfHeader(_plainText(cells[i]));
      if (d > 0) out[i] = d;
    }
    return out;
  }

  /// 把表格展开成与列对齐的矩阵：colspan 横向复制占位，rowspan 向后续行
  /// 占位（用 null 表示「上方格子的延续」，解析时跳过即不重复出课）。
  /// 不展开的话，上一行一个 rowspan 格就会让下一行的星期列整体左移错位。
  /// 同时返回每格的源 rowspan：rowspan 连堂格的节次要延伸到被跨行带，
  /// 解析条目时靠它知道这格横跨了几个行带。
  static (List<List<dom.Element?>>, Map<(int, int), int>) _expandTable(
    dom.Element table,
  ) {
    final rows = _tableRows(table);
    final grid = <List<dom.Element?>>[];
    final spanAt = <(int, int), int>{}; // (行,列) → 该格源 rowspan
    final pending = <int, int>{}; // 列号 → 该列被上方 rowspan 占用的剩余行数
    for (final tr in rows) {
      final cells = _rowCells(tr);
      final row = <dom.Element?>[];
      final ri = grid.length;
      var ci = 0;
      var col = 0;
      while (ci < cells.length) {
        if (pending.containsKey(col)) {
          row.add(null);
          _consume(pending, col);
          col++;
          continue;
        }
        final cell = cells[ci++];
        var colspan = int.tryParse(cell.attributes['colspan'] ?? '') ?? 1;
        var rowspan = int.tryParse(cell.attributes['rowspan'] ?? '') ?? 1;
        colspan = colspan.clamp(1, 12);
        rowspan = rowspan.clamp(1, 20);
        row.add(cell);
        if (rowspan > 1) {
          // colspan+rowspan 复合格：每一列都要注册跨行占位与源 rowspan。
          // 只注册首列的话，下一行的内容会左移进被跨的列、归错星期列。
          for (var k = 0; k < colspan; k++) {
            spanAt[(ri, col + k)] = rowspan;
            pending[col + k] = rowspan - 1;
          }
        }
        for (var k = 1; k < colspan; k++) {
          row.add(cell);
        }
        col += colspan;
      }
      // 行尾仍有跨行占位（该行单元格比表头短）：只补齐到最远的占位列。
      // 不能无脑 pad——rowspan 组列（上午/下午）开启行上占位列在 col 0、
      // 当前行内容已到 col 9，盲目补齐会把行撑到 40 宽，fallback
      // dayStart = 行宽-天数 直接指到 null 区，整行课程静默丢失。
      if (pending.isNotEmpty) {
        final maxPending = pending.keys.reduce((a, b) => a > b ? a : b);
        while (col <= maxPending && col < 40) {
          if (pending.containsKey(col)) {
            row.add(null);
            _consume(pending, col);
          } else {
            row.add(null);
          }
          col++;
        }
      }
      grid.add(row);
    }
    return (grid, spanAt);
  }

  static void _consume(Map<int, int> pending, int col) {
    final left = pending[col]! - 1;
    if (left <= 0) {
      pending.remove(col);
    } else {
      pending[col] = left;
    }
  }

  static int _colspanOf(dom.Element cell) =>
      (int.tryParse(cell.attributes['colspan'] ?? '') ?? 1).clamp(1, 12);

  /// 一行（已展开）里的「星期X」表头格：列下标 → 星期号。
  static Map<int, int> _rowHeaderDaysOfRow(List<dom.Element?> row) {
    final out = <int, int>{};
    for (var i = 0; i < row.length; i++) {
      final cell = row[i];
      if (cell == null) continue;
      final d = _dayOfHeader(_plainText(cell));
      if (d > 0) out[i] = d;
    }
    return out;
  }

  static List<Course> _parseGrid(dom.Element table) {
    final (grid, spanAt) = _expandTable(table);
    if (grid.isEmpty) return const [];

    // 表头行：含 ≥5 个「星期X/周X」格
    var headerIndex = -1;
    var headerDayCount = 7;
    var headerDays = <int, int>{};
    for (var i = 0; i < grid.length; i++) {
      final days = _rowHeaderDaysOfRow(grid[i]);
      if (days.length >= 5) {
        headerIndex = i;
        headerDayCount = days.length;
        headerDays = days;
        break;
      }
    }
    if (headerIndex < 0) return const [];

    // 第一遍先算出每个行带的首列位置与节次区间：rowspan 连堂格要把结束
    // 节次延伸到最后一个被跨行带，而主循环逐行推进时后续行带还没解析，
    // 必须先备好。
    final dayStarts = List<int?>.filled(grid.length, null);
    final bandSections = List<(int, int)?>.filled(grid.length, null);
    for (var r = headerIndex + 1; r < grid.length; r++) {
      final row = grid[r];
      if (row.isEmpty) continue;

      // 行头：靠前的格子里找节次区间（「1,2」「第3-4节」「第3节」）或
      // 大节号（一~五 / 1~5）。节次模式要先于大节号判定——「第3节」
      // 走大节号正则会被烧成 5-6 节。
      var dayStart = -1;
      int? big;
      (int, int)? headSections;
      for (var c = 0; c < row.length && c < 4; c++) {
        final cell = row[c];
        if (cell == null) continue; // 上方 rowspan 格的延续
        // 组列文本常带内部空白（「上 午」「晚 上」），按紧凑形式判定，
        // 否则长度 >2 被误当课程内容提前 BREAK，行头识别整行失效
        final t = _plainText(cell);
        final tCompact = t.replaceAll(RegExp(r'\s'), '');
        final sec = _rowHeadSections(tCompact);
        if (sec != null) {
          headSections = sec;
          // 行头自身可能带 colspan（展开行里已复制占位），跨过的列数要算上
          dayStart = c + _colspanOf(cell);
          break;
        }
        final n = _bigSection(tCompact);
        if (n != null) {
          big = n;
          dayStart = c + _colspanOf(cell);
          break;
        }
        // 行头格不应有课程内容
        if (tCompact.isNotEmpty && tCompact.length > 2) break;
      }
      if (dayStart < 0) {
        // 无节次列的表（强智/URP/行头被 rowspan 吃掉的续行）：
        // 按表头认出的天数反推第一格位置，兼容 5/6/7 天课表
        dayStart = row.length - headerDayCount;
        if (dayStart < 0) continue;
      }
      dayStarts[r] = dayStart;
      bandSections[r] =
          headSections ?? (big != null ? _bigToSections(big) : null);
    }

    final out = <Course>[];
    var bigCounter = 0; // 行头解析不出节次时的递增兜底
    for (var r = headerIndex + 1; r < grid.length; r++) {
      final dayStart = dayStarts[r];
      if (dayStart == null) continue;
      final row = grid[r];
      final fallback = bandSections[r] ?? _bigToSections(++bigCounter);
      if (fallback == null) continue;

      final firstDayColumn = headerDays.keys.reduce((a, b) => a < b ? a : b);
      for (final day in headerDays.entries) {
        final d = day.value;
        final idx = dayStart + day.key - firstDayColumn;
        if (idx >= row.length) break;
        final cell = row[idx];
        if (cell == null) continue; // 跨行格延续：不重复解析
        final raw = _cellRichText(cell);
        if (raw.isEmpty) continue;
        // rowspan 连堂格（一格占「1,2」+「3,4」两个行带）：兜底区间要
        // 延伸到最后一个被跨行带的结束节次；该带行头解析不出时按每带
        // 2 节兜底（start + 2×span - 1），否则连堂课被截成单带节次
        var cellFallback = fallback;
        final span = spanAt[(r, idx)] ?? 1;
        if (span > 1 && r + span - 1 < grid.length) {
          final bandEnd =
              bandSections[r + span - 1]?.$2 ?? fallback.$1 + 2 * span - 1;
          if (bandEnd > fallback.$2) cellFallback = (fallback.$1, bandEnd);
        }
        out.addAll(_parseCell(raw, d, cellFallback));
      }
    }
    return out;
  }

  /// 大节号 → 全天小节区间：一→1-2、二→3-4 … 五→9-10。
  static (int, int)? _bigToSections(int big) {
    if (big < 1 || big > 8) return null;
    return (big * 2 - 1, big * 2);
  }

  static int? _bigSection(String text) {
    final t = text.trim();
    final m = RegExp(r'^第?([一二三四五六七八1-8])节?$').firstMatch(t);
    if (m == null) return null;
    const cn = {'一': 1, '二': 2, '三': 3, '四': 4, '五': 5, '六': 6, '七': 7, '八': 8};
    return cn[m.group(1)] ?? int.tryParse(m.group(1)!);
  }

  /// 行头的节次写法：「1,2」「1，2」「第3-4节」「3-4节」，以及单节的
  /// 「第3节」「3节」（必须带「节」字——裸数字仍按大节号走 _bigSection，
  /// 保持无行头表既有行为）。
  static (int, int)? _rowHeadSections(String text) {
    final t = text.trim();
    final mPair = RegExp(r'^第?\s*(\d{1,2})\s*[,，]\s*(\d{1,2})\s*节?$')
        .firstMatch(t);
    if (mPair != null) {
      final a = int.parse(mPair.group(1)!);
      final b = int.parse(mPair.group(2)!);
      if (a >= 1 && b >= a && b <= 16) return (a, b);
    }
    final mRange = RegExp(r'^第?\s*(\d{1,2})\s*[-–—]\s*(\d{1,2})\s*节$')
        .firstMatch(t);
    if (mRange != null) {
      final a = int.parse(mRange.group(1)!);
      final b = int.parse(mRange.group(2)!);
      if (a >= 1 && b >= a && b <= 16) return (a, b);
    }
    final mSingle = RegExp(r'^第?\s*(\d{1,2})\s*节$').firstMatch(t);
    if (mSingle != null) {
      final a = int.parse(mSingle.group(1)!);
      if (a >= 1 && a <= 16) return (a, a);
    }
    return null;
  }

  static String _plainText(dom.Element e) {
    final frag = html_parser.parseFragment(
      e.innerHtml.replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), ' '),
    );
    return (frag.text ?? '').trim();
  }

  /// 单元格富文本：<br> 与块级元素边界都转为换行。
  static String _cellRichText(dom.Element cell) {
    final withBreaks = cell.innerHtml.replaceAllMapped(
      RegExp(r'<br\s*/?>|</div>|</p>|</li>|</h[1-6]>', caseSensitive: false),
      (_) => '\n',
    );
    final frag = html_parser.parseFragment(withBreaks);
    return (frag.text ?? '').replaceAll(RegExp(r'\r'), '').trim();
  }

  // ---------- 单元格 → 课程条目 ----------

  /// 行文本 → (周次, 节次区间)。周次可能为空（纯节次行）。
  /// 兼容：青果「1-5,8-19[1-2]」；正方/强智「1-16周」「第1-16周」「1-16周(单)」
  /// 「1-16周 第1-2节」「1-2节」「第1-2节」等。
  static (List<int>, (int, int)?)? parseWeekLine(String line) {
    var rest = line.trim();
    if (rest.isEmpty) return null;
    (int, int)? sections;

    // 后缀括号节次：[1-2]
    final bracket = RegExp(r'\[(\d{1,2})\s*[-–—]?\s*(\d{1,2})?\]\s*$')
        .firstMatch(rest);
    // 后缀节次：(1-2)节 / (第1-2节) / 第1-2节 / 1-2节
    final jie = RegExp(
      r'[（(]?\s*第?\s*(\d{1,2})\s*[-–—]\s*(\d{1,2})\s*节\s*[）)]?\s*$',
    ).firstMatch(rest);
    // 独立节次行：第1-2节 / 1-2节
    final jieOnly = RegExp(r'^第?\s*(\d{1,2})\s*节$').firstMatch(rest);
    // 独立节次区间行：第1-2节 / 1-2节
    final jieRange = RegExp(r'^第?\s*(\d{1,2})\s*[-–—]\s*(\d{1,2})\s*节$')
        .firstMatch(rest);

    if (bracket != null) {
      final a = int.parse(bracket.group(1)!);
      final b = int.tryParse(bracket.group(2) ?? '') ?? a;
      if (a >= 1 && b >= a && b <= 16) sections = (a, b);
      rest = rest.substring(0, bracket.start).trim();
    } else if (jie != null) {
      final a = int.parse(jie.group(1)!);
      final b = int.parse(jie.group(2)!);
      if (a >= 1 && b >= a && b <= 16) sections = (a, b);
      rest = rest.substring(0, jie.start).trim();
    } else if (jieRange != null) {
      final a = int.parse(jieRange.group(1)!);
      final b = int.parse(jieRange.group(2)!);
      if (a >= 1 && b >= a && b <= 16) sections = (a, b);
      rest = '';
    } else if (jieOnly != null) {
      final a = int.parse(jieOnly.group(1)!);
      if (a < 1 || a > 16) return (const <int>[], null);
      sections = (a, a);
      rest = '';
    }

    if (rest.isEmpty) {
      return sections == null ? null : (const <int>[], sections);
    }
    // 带节次后缀但剩余部分不是周次表达式（「课程名(1-2节)」）：这不是
    // 周次/节次行——此前返回 ([], sections) 会让调用方把整行当纯节次行，
    // 课程名被静默丢弃、下一行教师名顶替成课名。交给名字归类处理。
    if (!_weeksExpr.hasMatch(rest)) return null;
    final weeks = Course.parseWeeks(rest);
    if (weeks.isEmpty) {
      return sections == null ? null : (const <int>[], sections);
    }
    return (weeks, sections);
  }

  /// 严格周次表达式：「1-16周」「第1-16周」「1,3-5,8周」「1-16周(单)」
  /// 「1-8周,9-16周」「1-5双,8-16周」（段中单双）「1-16」「1~16周」等。
  /// 字符类必须与 Course.parseWeeks（支持 ~）保持一致——门槛比解析器窄的话，
  /// 这类周次行整门课静默消失。
  static final _weeksExpr = RegExp(
    r'^第?\s*\d{1,2}\s*(?:[-–—~]\s*\d{1,2})?\s*[单双]?\s*周?'
    r'(?:\s*[,，]\s*第?\s*\d{1,2}\s*(?:[-–—~]\s*\d{1,2})?\s*[单双]?\s*周?)*'
    r'(?:\s*[（(]\s*[单双]周?\s*[）)])?$',
  );

  /// 中文教师名通常 2~3 字；4 字纯中文行更可能是课名，不认作教师
  ///（避免「操作系统」「大学物理」这类课名被吞进教师字段）。
  /// 分隔符允许空白：真实青果页多教师用空格分隔（「李建春 黄道颖」，
  /// 见 test/fixtures/zf_kingosoft_real.html），旧正则不认会整行静默丢弃。
  static final _teacherCjk = RegExp(
    r'^[\u4e00-\u9fa5]{2,3}(?:[\s,，、]+[\u4e00-\u9fa5]{2,3})*$',
  );
  static final _teacherSuffix = RegExp(
    r'^[\u4e00-\u9fa5]{1,4}(老师|教授|副教授|讲师|助教)$',
  );

  /// 2~3 字纯中文短行：条目完结后更可能是下一门短课名（「体育」「化学」）
  /// 而不是教师名。
  static final _shortCjk = RegExp(r'^[\u4e00-\u9fa5]{2,3}$');

  /// 纯星期词 token（「星期一」「周一」…）：文本/OCR 混入的表头残片，
  /// 分类前直接跳过，否则会顶替课名或被误认成教师。
  static final _weekdayToken = RegExp(r'^(?:星期|周)[一二三四五六日天]$');

  static final _roomHint = RegExp(r'[教楼馆室场区厅]|\d{3,4}|平台|机房|操场|公寓|基地|中心|实训');

  static bool _looksLikeRoom(String s) {
    if (s.length > 24 || s.contains('周') || s.contains('[')) return false;
    return _roomHint.hasMatch(s);
  }

  static bool _looksLikeTeacher(String s) {
    if (s.length > 16) return false;
    return _teacherCjk.hasMatch(s) || _teacherSuffix.hasMatch(s);
  }

  /// 把一格的富文本拆成条目列表（网格解析 / 文本导入 / 截图导入共用）。
  /// 注意：完全解析不出周次的行默认不产出条目（避免垃圾数据）；
  /// [keepWeekless] = true 时保留无周次但有名字的条目（截图导入的
  /// OCR 漏读周次行场景，交给预览页人工补），网格/文本导入保持严格。
  static List<CourseEntry> parseCellLines(
    String raw, {
    bool keepWeekless = false,
  }) {
    // URP 花括号字段：{课程名;教师;周次;教室} → 逐字段成行
    var text = raw;
    if (text.contains('{')) {
      text = text.replaceAll(RegExp(r'[{};；|]'), '\n');
    }
    final lines = text
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    final entries = <CourseEntry>[];
    var cur = CourseEntry();

    void push() {
      if (cur.name.isEmpty) return;
      if (cur.weeks.isNotEmpty || keepWeekless) entries.add(cur);
    }

    for (var lineIndex = 0; lineIndex < lines.length; lineIndex++) {
      final line = lines[lineIndex];
      // 纯星期词（星期一/周一…）：表头残片，分类前直接跳过
      if (_weekdayToken.hasMatch(line)) continue;
      final ws = parseWeekLine(line);
      if (ws != null) {
        if (ws.$1.isNotEmpty) {
          if (cur.weeks.isNotEmpty) {
            push();
            cur = CourseEntry();
          }
          cur.weeks = ws.$1;
        }
        final sec = ws.$2;
        if (sec != null) {
          if (ws.$1.isEmpty && cur.weeks.isNotEmpty) {
            // 纯节次行撞上已完结条目：这行节次属于下一门课（上一门的
            // 节次已由行头/括号给出）。无条件改写会把上一门课错标节次、
            // 下一门课退化成兜底 1-1。
            push();
            cur = CourseEntry();
          }
          cur.start = sec.$1;
          cur.end = sec.$2;
        }
        continue;
      }
      if (cur.name.isEmpty) {
        cur.name = line;
        continue;
      }
      if (_looksLikeRoom(line)) {
        cur.room = cur.room.isEmpty ? line : '${cur.room} $line';
        continue;
      }
      // 带「老师/教授」等后缀的必定是教师（强智块式把教师放在块尾，
      // 条目完结后仍要认教师），先于短课名判定
      if (_teacherSuffix.hasMatch(line)) {
        cur.teacher = cur.teacher.isEmpty ? line : '${cur.teacher},$line';
        continue;
      }
      // 条目已完结（有课名有周次）后的 2~3 字纯中文行更可能是下一门
      // 短课名而不是教师——吞进教师字段还会让紧跟的教室行变成幽灵
      // 课名条目
      if (cur.weeks.isNotEmpty && _shortCjk.hasMatch(line)) {
        final next = lineIndex + 1 < lines.length ? lines[lineIndex + 1] : null;
        // 块尾教师（课程/周次/教室/教师）：后接下一门长课名或块结束。
        // 「体育/王五/3-18周」则仍是新课程，不能吞成前课的教师。
        if (cur.teacher.isEmpty &&
            (next == null ||
                (parseWeekLine(next) == null &&
                    !_looksLikeTeacher(next) &&
                    !_looksLikeRoom(next)))) {
          cur.teacher = line;
          continue;
        }
        push();
        cur = CourseEntry()..name = line;
        continue;
      }
      if (_looksLikeTeacher(line)) {
        cur.teacher = cur.teacher.isEmpty ? line : '${cur.teacher},$line';
        continue;
      }
      // 归不进类的行：当前条目已带周次 → 是下一门课的名称
      if (cur.weeks.isNotEmpty) {
        push();
        cur = CourseEntry()..name = line;
      }
    }
    push();
    return entries;
  }

  /// 条目 → Course。节次缺失时用行头兜底区间（青果带 [1-2]，正方/强智常不带）。
  /// [provisionalSections] = 兜底出的节次不是真实数据（块式文本导入本就
  /// 没有节次字段），预览页据此标「节次待定」且不预勾选。
  static Course entryToCourse(
    CourseEntry e,
    int weekday, {
    (int, int)? fallbackSections,
    bool provisionalSections = false,
  }) {
    final start = e.start > 0 ? e.start : (fallbackSections?.$1 ?? 1);
    final end = e.start > 0
        ? (e.end >= e.start ? e.end : e.start)
        : (fallbackSections?.$2 ?? start).clamp(start, 16);
    return Course(
      id: Course.makeId(
        name: e.name,
        weekday: weekday,
        startSection: start,
        endSection: end,
      ),
      name: e.name,
      teacher: e.teacher,
      room: e.room,
      weekday: weekday,
      startSection: start,
      endSection: end,
      weeks: e.weeks,
      sectionsProvisional: provisionalSections,
    );
  }

  static List<Course> _parseCell(
    String raw,
    int weekday,
    (int, int) fallbackSections,
  ) {
    return [
      for (final e in parseCellLines(raw))
        entryToCourse(e, weekday, fallbackSections: fallbackSections),
    ];
  }
}
