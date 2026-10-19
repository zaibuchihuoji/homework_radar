import '../models/homework_draft.dart';
import 'homework_due_parser.dart';

/// Split only explicit list/course boundaries; uncertain prose remains visible.
class HomeworkRecognition {
  static final _number = RegExp(
    r'^\s*(?:\d{1,3}|[一二三四五六七八九十]+)(?:\.(?!\d)|[、)）])\s*',
  );
  static final _work = RegExp(
    r'作业|习题|练习|报告|实验|作文|论文|阅读|预习|复习|背诵|翻译|完成|整理|第.+题|做.+题|写',
  );
  static List<HomeworkDraft> parse(
    String text, {
    Iterable<String> knownCourses = const [],
    DateTime? referenceDate,
  }) {
    final input = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n').trim();
    if (input.isEmpty) return [];
    if (input.length > 20000) {
      throw const FormatException('文字过长，请分几次识别（每次不超过 20000 字）');
    }
    final known =
        knownCourses.map((c) => c.trim()).where((c) => c.isNotEmpty).toList()
          ..sort((a, b) => b.length.compareTo(a.length));
    final groups = <({String course, List<String> lines})>[];
    var scopedCourse = '';
    List<String> lines = [];
    var course = '';
    void flush() {
      if (lines.isNotEmpty) groups.add((course: course, lines: List.of(lines)));
      lines = [];
      course = scopedCourse;
    }

    final expanded = input.replaceAllMapped(
      RegExp(r'\s+(?=\d{1,2}[.、)）]\s*[^\d\s])'),
      (_) => '\n',
    );
    for (var line in expanded.split(RegExp(r'\n|[；;]'))) {
      line = line.trim();
      if (line.isEmpty) {
        flush();
        continue;
      }
      final numbered = _number.hasMatch(line);
      final plain = line.replaceFirst(_number, '').trim();
      final labeled = RegExp(r'^(?:课程|科目)\s*[:：]\s*(.+)$').firstMatch(plain);
      if (labeled != null && !RegExp(r'[，,]').hasMatch(labeled[1]!)) {
        flush();
        scopedCourse = labeled[1]!.trim();
        course = scopedCourse;
        continue;
      }
      final prefix = RegExp(r'^(?:【([^】]+)】|\[([^\]]+)\])\s*')
          .firstMatch(plain);
      var foundCourse = '', body = plain;
      if (prefix != null) {
        foundCourse = (prefix[1] ?? prefix[2]!).trim();
        body = plain
            .substring(prefix.end)
            .replaceFirst(RegExp(r'^\s*[:：]'), '')
            .trim();
      } else {
        for (final name in known) {
          if (plain == name ||
              plain.startsWith('$name ') ||
              plain.startsWith('$name：') ||
              plain.startsWith('$name:')) {
            foundCourse = name;
            body = plain
                .substring(name.length)
                .replaceFirst(RegExp(r'^\s*[:：]'), '')
                .trim();
            break;
          }
        }
      }
      if (foundCourse.isNotEmpty && body.isEmpty) {
        flush();
        scopedCourse = foundCourse;
        course = scopedCourse;
        continue;
      }
      if (numbered || foundCourse.isNotEmpty) flush();
      if (lines.isEmpty) {
        course = foundCourse.isNotEmpty ? foundCourse : scopedCourse;
      }
      // Leave ordinary lines together: OCR often wraps one task across lines.
      lines.add(body);
    }
    flush();
    if (groups.length > 50) {
      throw const FormatException('本次超过 50 项，请分几次识别；尚未保存任何作业');
    }
    if (groups.isEmpty) {
      // A course-like heading alone is not silently discarded as an empty import.
      groups.add((course: '', lines: [input]));
    }
    return groups.map((group) {
      final content = group.lines.join('\n').trim();
      final due = HomeworkDueParser.parse(
        content,
        referenceDate: referenceDate,
      );
      final parts = content
          .split(RegExp(r'[，,\n]'))
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
      final titleParts = parts.where((part) {
        if (parts.length == 1) return true;
        if (HomeworkDueParser.strongCue.hasMatch(part)) return false;
        if (HomeworkDueParser.dateHint.hasMatch(part) &&
            RegExp(r'(?:前(?:提交|交|上交)?|交|提交)$').hasMatch(part) &&
            !RegExp(r'报告|作业|作文|练习|习题|论文|实验').hasMatch(part)) {
          return false;
        }
        return true;
      }).toList();
      final title = titleParts.isEmpty ? content : titleParts.join('，');
      final headingOnly = RegExp(
        r'^(?:(?:今日|今天|本周|课程|课后)?作业(?:通知|安排|清单|汇总|要求)?|通知)[:：]?$',
      ).hasMatch(content.replaceAll(RegExp(r'\s+'), ''));
      final likely = _work.hasMatch(content) && !headingOnly;
      return HomeworkDraft(
        course: group.course,
        title: title,
        sourceText:
            '${group.course.isEmpty ? '' : '【${group.course}】\n'}$content',
        dueAt: due.dueAt,
        likelyHomework: likely,
        warnings: [
          if (group.course.isEmpty) '所属课程待确认',
          ...due.warnings,
          if (!likely) '未检测到明确作业描述，请核对后再勾选',
        ],
      );
    }).toList();
  }
}
