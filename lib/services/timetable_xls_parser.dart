/// Excel/表格文件课表导入解析：
///  - xlsx（含教务导出的 Excel）：按工作表网格重建 HTML 表，
///    复用通用课表格子解析器 parseTimetableGrid；
///  - 「假 xls」：不少教务导出的 .xls 其实是 HTML 表格，直接按 HTML 解析；
///  - SpreadsheetML（Excel 2003 XML，`<?xml ... progid="Excel.Sheet"?>`
///    开头的 .xls）：Row/Cell/Data 网格重建成 HTML 表解析；
///  - CSV/TSV：引号感知的全文状态机切网格（字段内可含分隔符与换行）。
/// 识别不出星期表头时抛 FormatException，由页面给出友好提示。
library;

import 'dart:convert';

import 'package:fast_gbk/fast_gbk.dart';
import 'package:spreadsheet_decoder/spreadsheet_decoder.dart';

import '../models/course.dart';
import 'timetable_parser.dart';

class TimetableXlsParser {
  TimetableXlsParser._();

  /// 入口：文件字节 → 课程列表。
  static List<Course> parse(List<int> bytes) {
    if (bytes.length >= 4 &&
        bytes[0] == 0xD0 &&
        bytes[1] == 0xCF &&
        bytes[2] == 0x11 &&
        bytes[3] == 0xE0) {
      // 老式二进制 xls（BIFF），纯 Dart 解析成本高：
      // 让用户在教务/Office 里另存为 xlsx，或用截图/文本导入兜底
      throw const FormatException(
          '这是老版 .xls 二进制格式：请在电脑上用 Excel/WPS 另存为 .xlsx 再导入，'
          '或改用「截图导入 / 粘贴文本导入」');
    }
    final head = asciiPrefix(bytes, 64).toLowerCase();
    // SpreadsheetML（Excel 2003 XML）探测：`<?xml` 声明必在文件最前面；
    // `progid="Excel.Sheet"`/`<Workbook` 前面常还有 encoding 声明与
    // mso-application 处理指令，会超出 64 字节，所以放宽到前 512 字节找。
    // 必须排在 HTML 分支之前：文件里的 <Table> 元素转小写后同样命中 <table。
    final xmlHead = asciiPrefix(bytes, 512).toLowerCase();
    if (head.contains('<?xml') &&
        (xmlHead.contains('progid="excel.sheet"') ||
            xmlHead.contains('<workbook'))) {
      return _fromSpreadsheetMl(_decodeText(bytes));
    }
    if (head.contains('<!doctype html') ||
        head.contains('<html') ||
        head.contains('<table')) {
      // 伪装成 .xls 的 HTML 表格（教务导出常见）
      return _fromHtmlTable(_decodeText(bytes));
    }
    if (bytes.length >= 2 && bytes[0] == 0x50 && bytes[1] == 0x4B) {
      // zip 头 → xlsx
      return _fromXlsx(bytes);
    }
    // 尝试按 CSV/TSV 文本解析
    final text = _decodeText(bytes);
    if (text.contains(',') || text.contains('\t')) {
      return _fromDelimited(text);
    }
    throw const FormatException('识别不了文件格式：请用 .xlsx 文件，'
        '或改用「截图导入 / 粘贴文本导入」');
  }

  /// 文本解码：UTF-8 优先；出现替换符说明是 GBK 系编码
  /// （教务导出的 HTML/CSV 极常见），按 GBK 重解，纯 ASCII 两种解码等价。
  static String _decodeText(List<int> bytes) {
    final utf8Text = utf8.decode(bytes, allowMalformed: true);
    if (!utf8Text.contains('�')) return utf8Text;
    try {
      // allowMalformed：GB18030 四字节字符（生僻字）GBK 解不出来，
      // 不放行会直接抛异常退回整篇乱码；放行只把解不出的字节换成 U+FFFD
      return gbk.decode(bytes, allowMalformed: true);
    } catch (_) {
      return utf8Text;
    }
  }

  static String asciiPrefix(List<int> bytes, int n) {
    final out = StringBuffer();
    for (var i = 0; i < bytes.length && i < n; i++) {
      final b = bytes[i];
      out.writeCharCode(b >= 32 && b < 127 ? b : 32);
    }
    return out.toString();
  }

  /// xlsx → 每个工作表网格转 HTML 表 → 通用解析，取课程数最多的表。
  /// 用 spreadsheet_decoder 而非 excel 包：后者对 openpyxl/WPS 等
  /// 非自身生成的文件有空指针崩溃。
  static List<Course> _fromXlsx(List<int> bytes) {
    final SpreadsheetDecoder decoder;
    try {
      decoder = SpreadsheetDecoder.decodeBytes(bytes);
    } catch (_) {
      // openpyxl/WPS 导出的文件常见公式格无缓存值等形态，这里抛的
      // 各种类型异常统一转友好提示（外层只对 FormatException 给专门文案）
      throw const FormatException('Excel 打不开（文件损坏或含不支持的内容）：'
          '请在 Excel/WPS 里重新另存为 .xlsx 再导入，'
          '或改用「截图导入 / 粘贴文本导入」');
    }
    var best = const <Course>[];
    for (final name in decoder.tables.keys) {
      final sheet = decoder.tables[name]!;
      if (sheet.maxRows == 0 || sheet.maxCols == 0) continue;
      final html = StringBuffer('<table>');
      for (var r = 0; r < sheet.maxRows; r++) {
        html.write('<tr>');
        for (var c = 0; c < sheet.maxCols; c++) {
          final v = sheet.rows[r][c]?.toString() ?? '';
          html.write('<td>${_escape(v).replaceAll('\n', '<br>')}</td>');
        }
        html.write('</tr>');
      }
      html.write('</table>');
      try {
        final courses = TimetableParser.parseTimetableGrid(html.toString());
        if (courses.length > best.length) best = courses;
      } catch (_) {}
    }
    if (best.isEmpty) {
      throw const FormatException('Excel 里没认出课表：需要含「星期一~星期日」'
          '表头的二维表（先在教务里切到「二维表」视图再导出）');
    }
    return best;
  }

  static List<Course> _fromHtmlTable(String text) {
    final courses = TimetableParser.parseTimetableGrid(text);
    if (courses.isEmpty) {
      throw const FormatException('HTML 表格里没认出课表（缺「星期一~星期日」表头）：'
          '或改用「截图导入 / 粘贴文本导入」');
    }
    return courses;
  }

  /// SpreadsheetML（Excel 2003 XML）→ 通用课表格子解析。
  /// 只关心 Row/Cell/Data 骨架，重建成 <table><tr><td> 复用 parseTimetableGrid。
  static List<Course> _fromSpreadsheetMl(String xml) {
    final courses =
        TimetableParser.parseTimetableGrid(_spreadsheetMlToHtml(xml));
    if (courses.isEmpty) {
      throw const FormatException('Excel 2003 XML 里没认出课表'
          '（缺「星期一~星期日」表头）：或改用「截图导入 / 粘贴文本导入」');
    }
    return courses;
  }

  /// SpreadsheetML 网格 → `<table><tr><td>` HTML。
  /// 要点：SpreadsheetML 空单元格不输出 `<Cell>`，靠 `<Cell ss:Index="n">`
  /// 声明本格从第 n 列开始——缺的列必须补空 <td>，否则后面整行列错位；
  /// Data 内容保持原样（XML 里的 &amp; 等实体交给 HTML 解码，与原语义一致）。
  static String _spreadsheetMlToHtml(String xml) {
    final rowRe = RegExp(r'<Row\b[^>]*>(.*?)</Row>', dotAll: true);
    final cellRe = RegExp(r'<Cell\b([^>]*?)(?:/>|>(.*?)</Cell>)', dotAll: true);
    final dataRe = RegExp(r'<Data\b[^>]*>(.*?)</Data>', dotAll: true);
    final indexRe = RegExp(r'ss:Index\s*=\s*"(\d+)"');
    // 先收集每行再统一输出：行尾缺格（无「节次」列的短行）必须补空 <td>
    // 对齐最长行——parseTimetableGrid 对「列数明显少于表头」的行按垃圾整行
    // 跳过，短行课程会静默丢失
    final grid = <List<String>>[];
    var maxCols = 0;
    for (final rm in rowRe.allMatches(xml)) {
      final cells = <String>[];
      var col = 0;
      for (final cm in cellRe.allMatches(rm.group(1)!)) {
        final attrs = cm.group(1)!;
        // 无 ss:Index 的格按顺序紧排；有则跳到声明列
        final target =
            int.tryParse(indexRe.firstMatch(attrs)?.group(1) ?? '') ?? col + 1;
        while (cells.length < target - 1) {
          cells.add('');
        }
        final body = cm.group(2);
        final data =
            body == null ? '' : (dataRe.firstMatch(body)?.group(1) ?? '');
        if (cells.length < target) {
          cells.add(data);
        } else {
          cells[target - 1] = data;
        }
        col = target;
      }
      if (cells.length > maxCols) maxCols = cells.length;
      grid.add(cells);
    }
    final html = StringBuffer('<table>');
    for (final cells in grid) {
      html.write('<tr>');
      for (var i = 0; i < maxCols; i++) {
        html.write('<td>${i < cells.length ? cells[i] : ''}</td>');
      }
      html.write('</tr>');
    }
    html.write('</table>');
    return html.toString();
  }

  static List<Course> _fromDelimited(String text) {
    // 带引号的 CSV/TSV 字段里可能含换行（多行单元格，Excel「文本(制表符
    // 分隔)」导出的标准行为），必须全文状态机切分，逐行 split 会把
    // 多行字段拦腰切断
    final rows = text.contains('\t')
        ? _splitCsv(text, '\t')
        : _splitCsv(text, ',');
    final html = StringBuffer('<table>');
    for (final cells in rows) {
      html.write('<tr>');
      for (final cell in cells) {
        html.write('<td>${_escape(cell.trim()).replaceAll('\n', '<br>')}</td>');
      }
      html.write('</tr>');
    }
    html.write('</table>');
    final courses = TimetableParser.parseTimetableGrid(html.toString());
    if (courses.isEmpty) {
      throw const FormatException('表格里没认出课表（缺「星期一~星期日」表头）：'
          '或改用「截图导入 / 粘贴文本导入」');
    }
    return courses;
  }

  /// 引号感知的全文切分：字段内可含分隔符与换行（双引号转义 ""）。
  /// [sep] 指定字段分隔符（',' 或 '\t'），CSV/TSV 共用同一状态机。
  static List<List<String>> _splitCsv(String text, String sep) {
    final rows = <List<String>>[];
    var row = <String>[];
    final buf = StringBuffer();
    var inQuotes = false;
    for (var i = 0; i < text.length; i++) {
      final c = text[i];
      if (inQuotes) {
        if (c == '"') {
          if (i + 1 < text.length && text[i + 1] == '"') {
            buf.write('"');
            i++;
          } else {
            inQuotes = false;
          }
        } else {
          buf.write(c);
        }
      } else if (c == '"') {
        inQuotes = true;
      } else if (c == sep) {
        row.add(buf.toString());
        buf.clear();
      } else if (c == '\n') {
        row.add(buf.toString().replaceAll('\r', ''));
        buf.clear();
        if (row.any((x) => x.trim().isNotEmpty)) rows.add(row);
        row = <String>[];
      } else if (c == '\r') {
        continue;
      } else {
        buf.write(c);
      }
    }
    row.add(buf.toString());
    if (row.any((x) => x.trim().isNotEmpty)) rows.add(row);
    return rows;
  }

  static String _escape(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');
}
