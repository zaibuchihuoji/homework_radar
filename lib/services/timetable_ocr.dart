/// 课表截图 OCR 结果 → 课程：
/// 元素级原子块（一行可能跨两列）→ 全局行重组（被拆碎的「星期」「一」
/// 与同行跨列文字先归行）→ 表头锚点定列（缺列按天序补齐/外推）→
/// 表尺（大节序号列）定行带 → 逐列重组行、行带聚成格 → 复用通用单元格解析。
/// 纯逻辑，不依赖 ML Kit；单测可直接喂坐标块。
library;

import '../models/course.dart';
import 'timetable_parser.dart';

/// OCR 识别出的一个文本块（归一化到同一坐标系，单位像素即可）。
class OcrBlock {
  const OcrBlock({
    required this.text,
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  final String text;
  final double left;
  final double top;
  final double width;
  final double height;

  double get cx => left + width / 2;
  double get cy => top + height / 2;
}

/// 重组后的一行：同一视觉行的原子按 x 排序拼接。
class _RLine {
  final atoms = <OcrBlock>[];
  String text = '';
  double left = 0, right = 0, top = 0, height = 0, cx = 0, cy = 0;

  _RLine(OcrBlock first) {
    add(first);
    // 不在此处 normalize 的话新行几何字段全为 0，后续原子永远并不进任何行
    //（dy > 0.6*0 恒真被跳过）——「同行归并」整个机制成为死代码，
    // 真实截图的拆碎表头/同行跨列文字各自成行产出垃圾条目
    normalize();
  }

  void add(OcrBlock b) {
    atoms.add(b);
    _dirty = true;
  }

  bool _dirty = true;

  void normalize() {
    if (!_dirty) return;
    final sorted = [...atoms]..sort((a, b) => a.left.compareTo(b.left));
    text = sorted.map((a) => a.text).join();
    left = sorted.first.left;
    right = sorted.last.left + sorted.last.width;
    top = atoms.map((a) => a.top).reduce((a, b) => a < b ? a : b);
    height = atoms.map((a) => a.height).reduce((a, b) => a + b) / atoms.length;
    cx = (left + right) / 2;
    cy = top + height / 2;
    _dirty = false;
  }
}

class TimetableOcrParser {
  TimetableOcrParser._();

  static final _dayText =
      RegExp(r'^[（(]?\s*星期\s*([一二三四五六日天])\s*[)）]?$');
  static final _rulerText = RegExp(r'^[一二三四五六七八九十\d]{1,2}$');
  static const _cnDigits = {
    '一': 1, '二': 2, '三': 3, '四': 4, '五': 5,
    '六': 6, '七': 7, '八': 8, '九': 9, '十': 10,
  };

  static int _dayNum(String cn) {
    const map = {'一': 1, '二': 2, '三': 3, '四': 4, '五': 5, '六': 6, '日': 7, '天': 7};
    return map[cn] ?? 0;
  }

  static double _median(List<double> v) {
    if (v.isEmpty) return 0;
    final s = [...v]..sort();
    return s[s.length ~/ 2];
  }

  /// 相邻表头锚点距 → 稳健列距：先剔除离群差再取上中位。
  /// 为什么不直接取上中位：漏识别 2 个分散表头时会出现两个 2×pitch
  /// 差值，上中位恰被 2× 俘获 → pitch 翻倍，列窗（±0.45×pitch）与
  /// 表尺列阈值全部翻倍、相邻列互相串列。剔除门槛用下中位而非上中位：
  /// [p, p, 2p, 2p] 的上中位本身就是 2p，那两个 2p 永远剔不掉。
  static double _robustPitch(List<double> diffs) {
    if (diffs.isEmpty) return 0;
    final s = [...diffs]..sort();
    final med = s[(s.length - 1) ~/ 2]; // 下中位
    final kept = [for (final d in s) if (d <= med * 1.5) d];
    return kept[kept.length ~/ 2]; // 上中位（kept 至少含 med 自身，非空）
  }

  /// 同一视觉行的原子按 y 邻近归并、按 x 拼接成行。
  /// 同行归并条件：y 邻近 且 与行尾的水平间距小于字高 1.2 倍——
  /// 相邻格子同一行的文字 y 相同但 x 间距大，不能并成一行（列串扰）。
  static List<_RLine> _reassembleLines(List<OcrBlock> atoms) {
    final sorted = [...atoms]..sort((a, b) {
        final t = a.top.compareTo(b.top);
        return t != 0 ? t : a.left.compareTo(b.left);
      });
    final lines = <_RLine>[];
    for (final b in sorted) {
      _RLine? best;
      var bd = double.infinity;
      for (final ln in lines) {
        final dy = (b.cy - ln.cy).abs();
        if (dy > ln.height * 0.6) continue;
        final lineRight = ln.right;
        if (b.left < lineRight - 2) continue; // 已被更左原子覆盖
        final gap = b.left - lineRight;
        if (gap > ln.height * 1.2) continue; // 间距过大 → 是别的格子
        if (dy < bd) {
          bd = dy;
          best = ln;
        }
      }
      if (best == null) {
        lines.add(_RLine(b));
      } else {
        best.add(b);
        best.normalize();
      }
    }
    for (final l in lines) {
      l.normalize();
    }
    return lines..sort((a, b) => a.top.compareTo(b.top));
  }

  /// 行中心 → 表尺行带号（1..8）；离任何表尺行都太远（>0.55×间距）
  /// 返回 null。带归属带滞后：到最近带没有比到上一带的一半更近时，
  /// 仍归上一带。为什么：格子文字自行顶往下排，格底最后一行常越过
  /// 两带中点、几何上离下一带更近，但它是上一格的尾巴——按最近带
  /// 归属会把单带格记成「跨两带」，节次凭空多算一节。
  static int? _bandOf(_RLine ln, List<(double, int)> ruler, double spacing) {
    var k = -1;
    var bd = double.infinity;
    for (var i = 0; i < ruler.length; i++) {
      final d = (ruler[i].$1 - ln.cy).abs();
      if (d < bd) {
        bd = d;
        k = i;
      }
    }
    if (k < 0 || bd > spacing * 0.55) return null;
    var n = ruler[k].$2;
    if (k > 0) {
      final dPrev = (ruler[k - 1].$1 - ln.cy).abs();
      if (bd >= dPrev * 0.5) n = ruler[k - 1].$2;
    }
    return n;
  }

  static List<Course> parse(List<OcrBlock> atoms) {
    if (atoms.isEmpty) return const [];
    final lines = _reassembleLines(atoms);

    // ---- 表头锚点 ----
    final headerDays = <double, int>{};
    var headerTop = double.infinity;
    var headerBottom = 0.0;
    for (final ln in lines) {
      final m = _dayText.firstMatch(ln.text);
      if (m == null) continue;
      final d = _dayNum(m.group(1)!);
      if (d >= 1 && !headerDays.containsValue(d)) {
        headerDays[ln.cx] = d;
        if (ln.top < headerTop) headerTop = ln.top;
        final bottom = ln.top + ln.height;
        if (bottom > headerBottom) headerBottom = bottom;
      }
    }
    if (headerDays.length < 4) {
      return _parseNoGrid(lines);
    }
    final xs = headerDays.keys.toList()..sort();
    final diffs = <double>[];
    for (var i = 1; i < xs.length; i++) {
      diffs.add(xs[i] - xs[i - 1]);
    }
    final pitch = _robustPitch(diffs);

    // 缺列补齐：「星期一」最易被识别拆碎漏检——左侧外推一天；
    // 中间的按天序线性插值
    final byDay = <int, double>{for (final e in headerDays.entries) e.value: e.key};
    var minDay = 9;
    var maxDay = 0;
    byDay.forEach((d, _) {
      if (d < minDay) minDay = d;
      if (d > maxDay) maxDay = d;
    });
    if (!byDay.containsKey(1) && byDay.containsKey(2)) {
      byDay[1] = byDay[2]! - pitch;
    }
    for (var d = 2; d < maxDay; d++) {
      if (byDay.containsKey(d)) continue;
      int? lo;
      int? hi;
      for (var k = d - 1; k >= 1; k--) {
        if (byDay[k] != null) {
          lo = k;
          break;
        }
      }
      for (var k = d + 1; k <= 7; k++) {
        if (byDay[k] != null) {
          hi = k;
          break;
        }
      }
      if (lo != null && hi != null) {
        byDay[d] =
            byDay[lo]! + (byDay[hi]! - byDay[lo]!) * (d - lo) / (hi - lo);
      }
    }
    final anchors = byDay.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
    final firstX = anchors.first.value;
    final leftEdge = firstX - pitch * 0.75;

    // ---- 表尺（大节序号列）----
    final ruler = <(double, int)>[];
    for (final ln in lines) {
      if (ln.cx >= firstX - pitch * 0.35) continue;
      if (ln.cx < leftEdge) continue;
      if (ln.top < headerTop - 10 || ln.top < headerBottom - 2) continue;
      final t = ln.text.trim();
      if (!_rulerText.hasMatch(t)) continue;
      final n = int.tryParse(t) ?? _cnDigits[t];
      if (n != null && n >= 1 && n <= 8) {
        ruler.add((ln.cy, n));
      }
    }
    ruler.sort((a, b) => a.$1.compareTo(b.$1));
    final rulerSpacing = _median([
      for (var i = 1; i < ruler.length; i++) ruler[i].$1 - ruler[i - 1].$1,
    ]);

    // ---- 逐列：行重组 → 行带聚格 ----
    final out = <Course>[];
    for (final a in anchors) {
      final day = a.key;
      final ax = a.value;
      final colAtoms = atoms
          .where((b) =>
              b.cx >= ax - pitch * 0.45 &&
              b.cx <= ax + pitch * 0.45 &&
              b.top >= headerBottom - 2)
          .toList();
      if (colAtoms.isEmpty) continue;
      final colLines = _reassembleLines(colAtoms)
        ..sort((x, y) => x.top.compareTo(y.top));

      // 组元素 =（行, 行带号）：行带号随行留存，节次按组内最小/最大
      // 带号推导（连堂跨带）；无表尺分支带号恒 0
      final groups = <List<(_RLine, int)>>[];
      var dropped = false;
      if (ruler.length >= 2) {
        // 表尺行带：靠哪行大节就是哪个大节
        var cur = <(_RLine, int)>[];
        var curLo = 0, curHi = 0;
        void flush() {
          if (cur.isEmpty) return;
          groups.add(cur);
          cur = <(_RLine, int)>[];
          curLo = curHi = 0;
        }

        for (final ln in colLines) {
          final band = _bandOf(ln, ruler, rulerSpacing);
          if (band == null) {
            // 表尺覆盖不到的行组：表格下方注释/杂线，整组丢弃
            flush();
            dropped = true;
            continue;
          }
          if (cur.isNotEmpty && (band < curLo || band > curHi)) {
            // 带号变化 = 同列下一个格子开始了，要切组。此前只有
            // 「匹配不到任何带」才切组，而相邻带的覆盖范围必然重叠
            //（2×0.55 > 1），格与格之间又只有不产生文本行的空白，
            // 同列两格必然并成一组共用节次。但 rowspan 连堂的文字
            // 会连续排过两带中点、带号中途切换——格内行距小、格与格
            // 隔着空白行距大，所以只有换带且与上一行拉开明显间距
            // （>0.35 行带）才切组，否则连堂会被拦腰截断成两条课
            if (ln.top - cur.last.$1.top > rulerSpacing * 0.35) {
              flush();
            }
          }
          cur.add((ln, band));
          if (curLo == 0 || band < curLo) curLo = band;
          if (band > curHi) curHi = band;
        }
        flush();
      } else {
        // 无表尺：按行距突变聚格
        final th = _median([for (final l in colLines) l.height]) * 1.9;
        var cur = <(_RLine, int)>[(colLines.first, 0)];
        for (var i = 1; i < colLines.length; i++) {
          if (colLines[i].top - colLines[i - 1].top > th) {
            groups.add(cur);
            cur = <(_RLine, int)>[];
          }
          cur.add((colLines[i], 0));
        }
        if (cur.isNotEmpty) groups.add(cur);
      }

      for (var gi = 0; gi < groups.length; gi++) {
        final g = groups[gi];
        // OCR 漏读小字周次行的格子如果整格零产出，整门课就无声消失——
        // 截图导入保留无周次条目，交给预览页人工补
        final entries = TimetableParser.parseCellLines(
            g.map((e) => e.$1.text).join('\n'),
            keepWeekless: true);
        // 组内行带的最小/最大号 → 首带起始 ~ 末带结束（带1+带2 →
        // 1-4 节）。此前按组中心找单一最近带、写单带 2 节区间，
        // rowspan 连堂（真实占 4 节）的节次被塌缩掉一半
        var minBand = 0, maxBand = 0;
        for (final e in g) {
          if (e.$2 <= 0) continue;
          if (minBand == 0 || e.$2 < minBand) minBand = e.$2;
          if (e.$2 > maxBand) maxBand = e.$2;
        }
        for (final en in entries) {
          if (en.start <= 0 && minBand > 0) {
            en
              ..start = minBand * 2 - 1
              ..end = maxBand * 2;
          }
          if (en.start <= 0 && !dropped) {
            // 无表尺兜底：把「该列第几组」当「第几大节」。某天大节
            // 空堂会让序号整体错位一格——不做复杂补偿（预览页可人工
            // 改节次），只把节次钳回 1..16：9 个以上组时 gi*2+1 会
            // 算出 17-18 越过节次流出解析器
            final s = (gi * 2 + 1).clamp(1, 16);
            en
              ..start = s
              ..end = (gi * 2 + 2).clamp(s, 16);
          }
          final c = TimetableParser.entryToCourse(en, day);
          out.add(c);
        }
      }
    }
    return out;
  }

  /// 认不出表头时的兜底：全部按未定列（weekday 0），行距突变聚格。
  static List<Course> _parseNoGrid(List<_RLine> lines) {
    if (lines.isEmpty) return const [];
    final sorted = [...lines]..sort((a, b) => a.top.compareTo(b.top));
    final th = _median([for (final l in sorted) l.height]) * 1.9;
    final out = <Course>[];
    var cur = <_RLine>[sorted.first];
    void flush() {
      // 与主路径（keepWeekless: true）对齐：表头退化截图里「课名/教室」
      // 类无周次条目此前被整条过滤、课程无声消失；预览页本就不默认
      // 勾选无周次条目，交人工补即可
      final entries = TimetableParser.parseCellLines(
          cur.map((l) => l.text).join('\n'),
          keepWeekless: true);
      for (final e in entries) {
        if (e.start <= 0) {
          e
            ..start = 1
            ..end = 2;
        }
        out.add(TimetableParser.entryToCourse(e, 0));
      }
    }

    for (var i = 1; i < sorted.length; i++) {
      if (sorted[i].top - sorted[i - 1].top > th) {
        flush();
        cur = <_RLine>[];
      }
      cur.add(sorted[i]);
    }
    flush();
    return out;
  }
}
