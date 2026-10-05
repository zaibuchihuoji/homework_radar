/// 学习通（超星）作业查询。
///
/// 链路（与网页端一致）：
/// 1. Cookie 校验: GET mooc1-api.chaoxing.com/mycourse/backclazzdata
/// 2. 课程列表:   GET mooc2-ans.chaoxing.com/visit/courses/list （HTML）
/// 3. 课程参数:   课程页隐藏域 courseid/clazzid/cpi/enc/openc（必要时走 mycourse/transfer）
/// 4. 作业列表:   GET mooc1.chaoxing.com/work/getAllWork （HTML）
library;

import 'package:html/parser.dart' as html_parser;

import '../models/homework.dart';
import 'safe_http.dart';

class _CourseRef {
  String name;
  String link;
  _CourseRef(this.name, this.link);
}

class _WorkParams {
  String? courseId, clazzId, cpi, enc, openc;

  /// 空串同样算缺失：隐藏域 value="" 时 `!= null` 会假象通过校验，
  /// 拼出必然失败的 getAllWork URL，最终汇入「误判完整抓取→清旧数据」。
  bool get complete =>
      (courseId?.isNotEmpty ?? false) &&
      (clazzId?.isNotEmpty ?? false) &&
      (enc?.isNotEmpty ?? false);
}

class ChaoxingService {
  String? cookie;

  ChaoxingService({this.cookie});

  final Map<String, _WorkParams> _paramsCache = {};

  /// 课程列表请求失败（区分「真没课」与「没拉到」，供同步层决定能否清理旧条目）。
  bool listFailed = false;

  /// 课程级请求失败次数（单门课失败不阻塞整体，但要上报）。
  int failedCount = 0;

  /// Cookie 是否有效。
  /// 返回 null = 网络层失败（请求没得到回答），调用方不得据此判定「登录失效」；
  /// true/false = 有明确结论。
  Future<bool?> checkLogin() async {
    if (cookie == null || cookie!.isEmpty) return false;
    final resp = await SafeHttp.get(
      'https://mooc1-api.chaoxing.com/mycourse/backclazzdata?view=json&rss=1',
      headers: SafeHttp.authedHeaders(cookie),
    );
    if (resp == null) return null; // 网络失败 ≠ 登录过期
    if (resp.statusCode != 200) return false;
    try {
      return resp.body.contains('"result":1');
    } catch (_) {
      return false;
    }
  }

  /// 并发拉取全部课程作业（2 路，单路间隔 0.7s——请求太密容易触发风控），
  /// onProgress 上报完成进度。
  Future<List<HomeworkItem>> allHomework({
    void Function(int done, int total)? onProgress,
  }) async {
    final courses = await _courses();
    final items = <HomeworkItem>[];
    final queue = List<_CourseRef>.of(courses);
    var done = 0;

    Future<void> worker() async {
      while (queue.isNotEmpty) {
        final c = queue.removeAt(0);
        try {
          final params = await _workParams(c);
          if (params == null || !params.complete) {
            // 参数不全（enc 解析不到等）：此前静默跳过不计失败，
            // 同步层据此误判「完整抓取」把该课旧作业清光。
            failedCount++;
          } else {
            final list = await _workList(c.name, params);
            if (list == null) {
              failedCount++; // 请求失败（网络/非200），不能当「没有作业」
            } else {
              items.addAll(list);
            }
          }
        } catch (_) {
          failedCount++;
        }
        done++;
        onProgress?.call(done, courses.length);
        await Future.delayed(const Duration(milliseconds: 700));
      }
    }

    await Future.wait([for (var i = 0; i < 2; i++) worker()]);
    return items;
  }

  Future<List<_CourseRef>> _courses() async {
    final url = 'https://mooc2-ans.chaoxing.com/visit/courses/list'
        '?v=${DateTime.now().millisecondsSinceEpoch}&rss=1&start=0&size=500'
        '&catalogId=0&searchname=';
    final resp = await SafeHttp.get(url, headers: SafeHttp.authedHeaders(cookie));
    if (resp == null || resp.statusCode != 200) {
      listFailed = true;
      return [];
    }
    final doc = html_parser.parse(resp.body);
    final out = <_CourseRef>[];
    for (final li in doc.querySelectorAll('li.course')) {
      // 结课课程带 not-open-tip，跳过
      if (li.querySelector('a.not-open-tip') != null) continue;
      final a = li.querySelector('a[href]');
      final nameEl = li.querySelector('.course-name');
      if (a == null || nameEl == null) continue;
      final href = a.attributes['href'];
      if (href == null) continue;
      final link = href.startsWith('http')
          ? href
          : 'https://mooc2-ans.chaoxing.com$href';
      out.add(_CourseRef(nameEl.text.trim(), link));
    }
    return out;
  }

  Future<_WorkParams?> _workParams(_CourseRef c) async {
    final cached = _paramsCache[c.link];
    if (cached != null && cached.complete) return cached;

    final p = _WorkParams();

    // 第一步：拿课程页（可能 302）
    String? html = await _getFinalHtml(c.link);
    if (html != null) _fillFromHiddenInputs(p, html);

    // 第二步：缺 enc 时走 mycourse/transfer 重定向拿全参数
    if (!p.complete && p.courseId != null && p.clazzId != null) {
      final refer = Uri.encodeComponent(
          'https://mooc1.chaoxing.com/mycourse/studentcourse?courseId=${p.courseId}&clazzid=${p.clazzId}&cpi=${p.cpi ?? ''}&ut=s');
      final transferUrl = 'https://mooc1.chaoxing.com/mycourse/transfer'
          '?moocId=${p.courseId}&ut=s&clazzid=${p.clazzId}&refer=$refer';
      final resp = await SafeHttp.get(
        transferUrl,
        headers: SafeHttp.authedHeaders(cookie),
        followRedirects: false,
      );
      // 只有真重定向才有 Location：200（JS 跳转页等）时读 location 是
      // 拿不到 enc 的，别把空参数当半成品继续走
      final loc = (resp != null &&
              resp.statusCode >= 300 &&
              resp.statusCode < 400)
          ? resp.headers['location']
          : null;
      if (loc != null) {
        // Location 可能是相对路径：此前直接被白名单拒掉，二跳拿不到页面，
        // enc 静默缺失 → 该课被当失败清理。先按请求 URL 解析成绝对地址。
        final base = Uri.tryParse(transferUrl);
        final abs = base?.resolve(loc).toString() ?? loc;
        final q = Uri.tryParse(abs)?.queryParameters ?? const {};
        p.courseId ??= q['courseId'];
        p.clazzId ??= q['clazzid'] ?? q['clazzId'];
        p.enc ??= q['enc'];
        p.cpi ??= q['cpi'];
        p.openc ??= q['openc'];
      }
    }

    if (p.complete) _paramsCache[c.link] = p;
    return p;
  }

  Future<String?> _getFinalHtml(String url) async {
    final resp = await SafeHttp.get(
      url,
      headers: SafeHttp.authedHeaders(cookie),
      followRedirects: false,
    );
    if (resp == null) return null;
    final loc = resp.headers['location'];
    if (resp.statusCode >= 300 && resp.statusCode < 400 && loc != null) {
      // 相对 Location 按请求 URL 解析成绝对地址，否则白名单直接拒掉
      final base = Uri.tryParse(url);
      final abs = base?.resolve(loc).toString() ?? loc;
      final resp2 = await SafeHttp.get(abs, headers: SafeHttp.authedHeaders(cookie));
      return resp2?.body;
    }
    return resp.body;
  }

  void _fillFromHiddenInputs(_WorkParams p, String html) {
    final doc = html_parser.parse(html);
    String? val(String id) =>
        doc.querySelector('#$id')?.attributes['value'];
    p.courseId ??= val('courseid') ?? val('courseId');
    p.clazzId ??= val('clazzid') ?? val('clazzId');
    p.cpi ??= val('cpi');
    p.enc ??= val('oldenc') ?? val('enc');
    p.openc ??= val('openc');
  }

  /// 返回 null 表示「没拉到」（请求失败/非200），与「拉到了但没有作业」
  /// （空列表）区分——同步层靠它决定能否清理旧条目。
  Future<List<HomeworkItem>?> _workList(
      String courseName, _WorkParams p) async {
    final url = 'https://mooc1.chaoxing.com/work/getAllWork'
        '?classId=${Uri.encodeComponent(p.clazzId!)}'
        '&courseId=${Uri.encodeComponent(p.courseId!)}&isdisplaytable=2&mooc=1'
        '&ut=s&enc=${Uri.encodeComponent(p.enc!)}'
        '&cpi=${Uri.encodeComponent(p.cpi ?? '')}'
        '&openc=${Uri.encodeComponent(p.openc ?? '')}';
    final resp = await SafeHttp.get(url, headers: SafeHttp.authedHeaders(cookie));
    if (resp == null || resp.statusCode != 200) return null;
    final doc = html_parser.parse(resp.body);
    final items = <HomeworkItem>[];
    for (final li in doc.querySelectorAll('.ulDiv li')) {
      final a = li.querySelector('.titTxt a');
      if (a == null) continue;
      final title = (a.attributes['title'] ?? a.text).trim();
      if (title.isEmpty) continue;

      final spans = li.querySelectorAll('.pt5');
      DateTime? due;
      if (spans.length >= 2) {
        due = _parseDateTime(spans[1].text);
      }
      HwStatus status = HwStatus.unknown;
      // 真实结构：最后一个 .pt5 是「作业状态：<strong>待做/已完成/待批阅…</strong>」
      final strong = li.querySelector('.pt5:last-child strong') ??
          (spans.isNotEmpty ? spans.last.querySelector('strong') : null);
      final statusText = (strong?.text ?? '').trim();
      if (statusText.contains('待做') ||
          statusText.contains('未完成') ||
          statusText.contains('未开始')) {
        status = HwStatus.todo;
      } else if (statusText.contains('待批') || statusText.contains('已提交')) {
        status = HwStatus.submitted;
      } else if (statusText.contains('已完成') ||
          statusText.contains('已批') ||
          statusText.contains('已阅')) {
        status = HwStatus.done;
      }

      double? score;
      final scoreEl = li.querySelector('.titOper span.fl');
      if (scoreEl != null) {
        final m = RegExp(r'([\d.]+)\s*分').firstMatch(scoreEl.text);
        if (m != null) score = double.tryParse(m.group(1)!);
      }

      final href = a.attributes['href'];

      // 真实页面 href 是 javascript:void(0)，workId 在 data 属性里
      final workId = a.attributes['data'] ??
          RegExp(r'workId=(\d+)').firstMatch(href ?? '')?.group(1) ??
          RegExp(r'workRelationId=(\d+)').firstMatch(href ?? '')?.group(1);

      // 作业页直达链接需要运行时 JS 参数（直拼 doHomeWorkNew 会 403），
      // 改用课程作业列表页（已验证可带 Cookie 直接打开），少跳转官方 App。
      final workUrl =
          'https://mooc1.chaoxing.com/work/getAllWork'
          '?classId=${Uri.encodeComponent(p.clazzId!)}'
          '&courseId=${Uri.encodeComponent(p.courseId!)}&isdisplaytable=2'
          '&mooc=1&ut=s&enc=${Uri.encodeComponent(p.enc!)}'
          '&cpi=${Uri.encodeComponent(p.cpi ?? '')}'
          '&openc=${Uri.encodeComponent(p.openc ?? '')}';

      items.add(HomeworkItem(
        id: workId != null
            ? 'cx_${p.courseId}_${p.clazzId}_$workId'
            : 'cx_${p.courseId}_${p.clazzId}_${title.hashCode}',
        platform: PlatformKind.chaoxing,
        course: courseName,
        title: title,
        dueAt: due,
        status: status,
        url: workUrl,
        score: score,
      ));
    }
    return items;
  }

  static DateTime? _parseDateTime(String raw) {
    final m = RegExp(r'(\d{4})[-/.年](\d{1,2})[-/.月](\d{1,2})日?\s*(\d{1,2}):(\d{2})?')
        .firstMatch(raw);
    if (m == null) return null;
    try {
      return DateTime(
        int.parse(m.group(1)!),
        int.parse(m.group(2)!),
        int.parse(m.group(3)!),
        m.group(4) != null ? int.parse(m.group(4)!) : 23,
        m.group(5) != null ? int.parse(m.group(5)!) : 59,
      );
    } catch (_) {
      return null;
    }
  }
}
