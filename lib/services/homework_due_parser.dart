class HomeworkDueResult {
  const HomeworkDueResult(this.dueAt, this.warnings);
  final DateTime? dueAt;
  final List<String> warnings;
}

/// Resolve explicit deadlines only. The notice date is supplied by the user,
/// never inferred from screenshot timestamps or the device's current day.
class HomeworkDueParser {
  static final strongCue = RegExp(r'截止|截至|最迟|最晚|提交时间|上交时间|延期至|改到|调整到');
  static final dateHint = RegExp(
    r'\d{4}[-/年]|\d{1,2}月|今天|明天|后天|今晚|本周|这周|下周|星期|周[一二三四五六日天]',
  );
  static final _weakCue = RegExp(r'前|提交|上交|交作业|交$');

  static HomeworkDueResult parse(String text, {DateTime? referenceDate}) {
    final clauses = text.split(RegExp(r'[，,；;\n]'));
    var selected = clauses.where((c) => strongCue.hasMatch(c)).toList();
    if (selected.isEmpty) {
      selected = clauses
          .where((c) => dateHint.hasMatch(c) && _weakCue.hasMatch(c))
          .toList();
    }
    if (selected.isEmpty) return const HomeworkDueResult(null, ['未找到明确截止时间']);
    final value = selected.join('，');
    HomeworkDueResult unknown(String message) =>
        HomeworkDueResult(null, [message]);
    if (RegExp(r'暂定|待定|可能|大概|预计|左右|不确定|不是|取消|待通知|下下周|[?？]').hasMatch(value) ||
        RegExp(r'\b[ap]\.?m\.?\b', caseSensitive: false).hasMatch(value) ||
        RegExp(r'\d{1,2}[:：]\d{1,2}[:：]\d').hasMatch(value)) {
      return unknown('截止时间的表述需核对，请手动确认');
    }
    if (RegExp(r'UTC|GMT|时区', caseSensitive: false).hasMatch(value)) {
      return unknown('截止时间含时区信息，请手动核对');
    }
    final dates = <DateTime>[];
    String? error;
    void date(int? year, int month, int day) {
      if (year == null && referenceDate == null) {
        error = '缺少年份：请设置通知日期或手动选择截止时间';
        return;
      }
      final y = year ?? referenceDate!.year;
      if (y < 1 || month < 1 || month > 12 || day < 1 || day > 31) {
        error = '日期无效，请手动核对';
        return;
      }
      final d = DateTime(y, month, day);
      if (d.year != y || d.month != month || d.day != day) {
        error = '日期无效，请手动核对';
        return;
      }
      if (year == null &&
          d.isBefore(
            DateTime(
              referenceDate!.year,
              referenceDate.month,
              referenceDate.day,
            ),
          )) {
        error = '日期早于通知日期，年份需核对';
        return;
      }
      dates.add(d);
    }

    for (final m in RegExp(
      r'(?:(\d{4})\s*年\s*)?(\d{1,2})\s*月\s*(\d{1,2})\s*[日号]?',
    ).allMatches(value)) {
      date(int.tryParse(m[1] ?? ''), int.parse(m[2]!), int.parse(m[3]!));
    }
    for (final m in RegExp(
      r'(\d{4})[-/](\d{1,2})[-/](\d{1,2})',
    ).allMatches(value)) {
      date(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
    }
    for (final m in RegExp(
      r'(?<![\d/])(\d{1,2})/(\d{1,2})(?![/\d])',
    ).allMatches(value)) {
      date(null, int.parse(m[1]!), int.parse(m[2]!));
    }
    for (final m in RegExp(r'大后天|后天|明天|今天|今晚').allMatches(value)) {
      if (referenceDate == null) {
        error = '相对日期需要设置通知日期';
        continue;
      }
      final offset = switch (m[0]) {
        '大后天' => 3,
        '后天' => 2,
        '明天' => 1,
        _ => 0,
      };
      dates.add(
        DateTime(
          referenceDate.year,
          referenceDate.month,
          referenceDate.day + offset,
        ),
      );
    }
    final weekdays = RegExp(r'(本周|这周|下周|周|星期)([一二三四五六日天])')
        .allMatches(value)
        .toList();
    for (final m in weekdays) {
      final day = '一二三四五六日'.indexOf(m[2]!.replaceAll('天', '日')) + 1;
      if (m[1] == '周' || m[1] == '星期') {
        if (dates.isEmpty) {
          error = '只写了星期，需确认是哪一周';
        } else if (dates.any((d) => d.weekday != day)) {
          error = '日期与星期不一致，请核对';
        }
        continue;
      }
      if (referenceDate == null) {
        error = '相对日期需要设置通知日期';
        continue;
      }
      dates.add(
        DateTime(
          referenceDate.year,
          referenceDate.month,
          referenceDate.day -
              referenceDate.weekday +
              day +
              (m[1] == '下周' ? 7 : 0),
        ),
      );
    }
    if (error != null) return unknown(error!);
    final distinctDates = dates.map((d) => d.millisecondsSinceEpoch).toSet();
    if (distinctDates.length != 1) {
      return unknown(dates.isEmpty ? '未找到明确截止日期' : '出现多个日期，请手动确认截止时间');
    }

    final times = <(int, int)>[];
    final clock = RegExp(
      r'(?<!\d)(凌晨|早上|上午|中午|下午|晚上|今晚|晚)?\s*(\d{1,2}|[零〇一二三四五六七八九十两]{1,3})\s*([:：点时])\s*(半|\d{1,2}|[零〇一二三四五六七八九十两]{1,3})?\s*分?',
    );
    for (final m in clock.allMatches(value)) {
      var hour = _number(m[2]!);
      final minute = m[4] == '半' ? 30 : _number(m[4] ?? '0');
      final period = m[1];
      if (hour == null || minute == null || hour > 23 || minute > 59) {
        return unknown('时刻无效，请手动核对');
      }
      if (period == null &&
          m[3] != ':' &&
          m[3] != '：' &&
          hour >= 1 &&
          hour <= 12) {
        return unknown('上午或下午未明确，请确认截止时刻');
      }
      if (period == '下午') {
        if (hour < 12) hour += 12;
      }
      if (period == '晚上' || period == '晚' || period == '今晚') {
        if (hour < 6 || (hour >= 12 && hour < 18)) {
          return unknown('晚间时刻有歧义，请手动核对');
        }
        if (hour < 12) hour += 12;
      }
      if ((period == '上午' || period == '早上' || period == '凌晨') && hour >= 12) {
        return unknown('上午时刻有歧义，请手动核对');
      }
      if (period == '中午' && (hour < 11 || hour > 13)) {
        return unknown('中午时刻有歧义，请手动核对');
      }
      times.add((hour, minute));
    }
    if (times.toSet().length != 1) {
      return unknown(times.isEmpty ? '只有日期，未明确具体截止时刻' : '出现多个时刻，请手动确认');
    }
    final d = dates.first, t = times.first;
    return HomeworkDueResult(
      DateTime(d.year, d.month, d.day, t.$1, t.$2),
      const [],
    );
  }

  static int? _number(String text) {
    final digit = int.tryParse(text);
    if (digit != null) return digit;
    const map = {
      '零': 0,
      '〇': 0,
      '一': 1,
      '二': 2,
      '两': 2,
      '三': 3,
      '四': 4,
      '五': 5,
      '六': 6,
      '七': 7,
      '八': 8,
      '九': 9,
    };
    if (map.containsKey(text)) return map[text];
    if (text == '十') return 10;
    final parts = text.split('十');
    if (parts.length != 2) return null;
    final ten = parts.first.isEmpty ? 1 : map[parts.first];
    final one = parts.last.isEmpty ? 0 : map[parts.last];
    return ten == null || one == null ? null : ten * 10 + one;
  }
}
