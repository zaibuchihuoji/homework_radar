/// 学习通（超星）作业/考试查询。
///
/// 链路（与网页端一致）：
/// 1. Cookie 校验: GET mooc1-api.chaoxing.com/mycourse/backclazzdata
/// 2. 课程列表:   GET mooc2-ans.chaoxing.com/visit/courses/list （HTML）
/// 3. 课程参数:   课程页隐藏域 courseid/clazzid/cpi/enc/openc（必要时走 mycourse/transfer）
/// 4. 作业列表:   GET mooc1.chaoxing.com/work/getAllWork （HTML）
/// 5. 考试列表:   GET mooc1.chaoxing.com/exam-ans/exam/test-list （HTML，社区端点；
///    页面行形状未真机校准，kDebugMode 落盘原始 HTML 辅助校准）
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../models/homework.dart';
import 'safe_http.dart';

class _CourseRef {
  String name;
  String link;
  _CourseRef(this.name, this.link);
}

class _WorkParams {
  String? courseId, clazzId, cpi, enc, openc;

  /// 课程页 `enc` 隐藏域（≠ [enc]：enc 抓的是 oldenc，作业列表用；
  /// 考试模块的 stuenc 参数要的是 enc 本尊——两值不同，2026-10-06 真机实证）。
  String? encPlain;

  /// 课程页 `t` 隐藏域（毫秒时间戳，考试模块必带）。
  String? t;

  /// 考试模块入口（课程页导航 li[dataname=ks] 的 data-url；课程页没给时
  /// 用 [_defaultExamUrl]——2026-10-06 真机实证 exam-ans/exam/test-list 404，
  /// 正确入口是 exam-ans/mooc2/exam/exam-list）。
  String? examUrl;
  static const String _defaultExamUrl =
      'https://mooc1.chaoxing.com/exam-ans/mooc2/exam/exam-list';
  String get examListUrl =>
      (examUrl?.isNotEmpty ?? false) ? examUrl! : _defaultExamUrl;

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

  final List<String> _failureDetails = [];

  /// 只包含课程名与固定阶段名称，不含 URL、凭据或原始响应内容。
  List<String> get failureDetails => List.unmodifiable(_failureDetails);

  void _courseFailed(String course, String stage) {
    failedCount++;
    final name = course.replaceAll(RegExp(r'\s+'), ' ').trim();
    final shortName = name.length > 48 ? '${name.substring(0, 48)}…' : name;
    _failureDetails.add('《$shortName》$stage');
  }

  // This service owns CX credentials. The shared HTTP allowlist also includes
  // other platforms and update servers, so it cannot authorize these headers.
  static Uri? _cxUri(String url) {
    final uri = SafeHttp.validate(url);
    if (uri == null || uri.scheme != 'https' || uri.userInfo.isNotEmpty) {
      return null;
    }
    final host = uri.host.toLowerCase();
    return host == 'chaoxing.com' || host.endsWith('.chaoxing.com')
        ? uri
        : null;
  }

  Future<http.Response?> _get(String url, {bool followRedirects = true}) async {
    var target = _cxUri(url);
    final visited = <Uri>{};
    var redirects = 0;
    final elapsed = Stopwatch()..start();
    const budget = Duration(seconds: 30);
    while (target != null && visited.add(target)) {
      final remaining = budget - elapsed.elapsed;
      if (remaining <= Duration.zero) return null;
      final response = await SafeHttp.get(
        target.toString(),
        headers: SafeHttp.authedHeaders(cookie),
        followRedirects: false,
      ).timeout(remaining, onTimeout: () => null);
      if (elapsed.elapsed >= budget) return null;
      if (response == null ||
          !followRedirects ||
          !const [301, 302, 303, 307, 308].contains(response.statusCode)) {
        return response;
      }
      final location = response.headers['location'];
      if (location == null || redirects++ >= 5) return null;
      try {
        target = _cxUri(target.resolve(location).toString());
      } on FormatException {
        return null;
      }
    }
    return null;
  }

  /// Cookie 是否有效。
  /// 返回 null = 网络层失败（请求没得到回答），调用方不得据此判定「登录失效」；
  /// true/false = 有明确结论。
  Future<bool?> checkLogin() async {
    if (cookie == null || cookie!.isEmpty) return false;
    final resp = await _get(
      'https://mooc1-api.chaoxing.com/mycourse/backclazzdata?view=json&rss=1',
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
            _courseFailed(c.name, '课程信息不完整');
          } else {
            final list = await _workList(c.name, params);
            if (list == null) {
              _courseFailed(c.name, '作业列表获取或解析失败');
            } else {
              items.addAll(list);
            }
            // 考试列表与作业列表同课双拉：单路限速内多隔一拍再打，
            // 请求太密容易触发风控
            await Future.delayed(const Duration(milliseconds: 400));
            final exams = await _examList(c.name, params);
            if (exams == null) {
              _courseFailed(c.name, '考试列表获取或解析失败');
            } else {
              items.addAll(exams);
            }
          }
        } catch (_) {
          _courseFailed(c.name, '读取课程时出现异常');
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
    final url =
        'https://mooc2-ans.chaoxing.com/visit/courses/list'
        '?v=${DateTime.now().millisecondsSinceEpoch}&rss=1&start=0&size=500'
        '&catalogId=0&searchname=';
    final resp = await _get(url);
    if (resp == null || resp.statusCode != 200) {
      listFailed = true;
      _failureDetails.add('课程列表获取失败');
      return [];
    }
    final doc = html_parser.parse(resp.body);
    final out = <_CourseRef>[];
    final entries = doc.querySelectorAll('li.course');
    if (entries.length >= 500) {
      listFailed = true;
      _failureDetails.add('课程列表可能未读取完整');
    }
    for (final li in entries) {
      // 结课课程带 not-open-tip，跳过
      if (li.querySelector('a.not-open-tip') != null) continue;
      final a = li.querySelector('a[href]');
      final nameEl = li.querySelector('.course-name');
      if (a == null || nameEl == null) continue;
      final href = a.attributes['href'];
      if (href == null) continue;
      try {
        final link = Uri.parse(url).resolve(href).toString();
        out.add(_CourseRef(nameEl.text.trim(), link));
      } on FormatException {
        listFailed = true;
        _failureDetails.add('课程链接无法解析');
      }
    }
    return out;
  }

  Future<_WorkParams?> _workParams(_CourseRef c) async {
    final cached = _paramsCache[c.link];
    if (cached != null && cached.complete) return cached;

    final p = _WorkParams();

    // 第一步：拿课程页（可能 302）
    String? html = await _getFinalHtml(c.link);
    if (html != null) {
      if (kDebugMode) {
        try {
          final dir = await getApplicationDocumentsDirectory();
          File('${dir.path}/cx_course_page.html')
              .writeAsStringSync(html, flush: true);
        } catch (_) {}
      }
      _fillFromHiddenInputs(p, html);
    }

    // 第二步：缺 enc 时走 mycourse/transfer 重定向拿全参数
    if (!p.complete && p.courseId != null && p.clazzId != null) {
      final refer = Uri.encodeComponent(
        'https://mooc1.chaoxing.com/mycourse/studentcourse?courseId=${p.courseId}&clazzid=${p.clazzId}&cpi=${p.cpi ?? ''}&ut=s',
      );
      final transferUrl =
          'https://mooc1.chaoxing.com/mycourse/transfer'
          '?moocId=${p.courseId}&ut=s&clazzid=${p.clazzId}&refer=$refer';
      final resp = await _get(transferUrl, followRedirects: false);
      // 只有真重定向才有 Location：200（JS 跳转页等）时读 location 是
      // 拿不到 enc 的，别把空参数当半成品继续走
      final loc =
          (resp != null && resp.statusCode >= 300 && resp.statusCode < 400)
          ? resp.headers['location']
          : null;
      if (loc != null) {
        // Location 可能是相对路径：此前直接被白名单拒掉，二跳拿不到页面，
        // enc 静默缺失 → 该课被当失败清理。先按请求 URL 解析成绝对地址。
        final base = Uri.tryParse(transferUrl);
        final abs = base?.resolve(loc).toString() ?? loc;
        final q = _cxUri(abs)?.queryParameters ?? const {};
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
    final resp = await _get(url);
    if (resp == null || resp.statusCode != 200) return null;
    return resp.body;
  }

  void _fillFromHiddenInputs(_WorkParams p, String html) {
    final doc = html_parser.parse(html);
    String? val(String id) => doc.querySelector('#$id')?.attributes['value'];
    p.courseId ??= val('courseid') ?? val('courseId');
    p.clazzId ??= val('clazzid') ?? val('clazzId');
    p.cpi ??= val('cpi');
    p.enc ??= val('oldenc') ?? val('enc');
    p.encPlain ??= val('enc');
    p.t ??= val('t');
    p.openc ??= val('openc');
    // 考试模块入口：导航里 dataname=ks 的 data-url（真机实证存在）
    for (final li in doc.querySelectorAll('li[dataname]')) {
      if (li.attributes['dataname'] == 'ks') {
        final u = li.querySelector('a[data-url]')?.attributes['data-url'];
        if (u != null && u.isNotEmpty) {
          p.examUrl = u;
          break;
        }
      }
    }
  }

  /// 返回 null 表示「没拉到」（请求失败/非200），与「拉到了但没有作业」
  /// （空列表）区分——同步层靠它决定能否清理旧条目。
  Future<List<HomeworkItem>?> _workList(
    String courseName,
    _WorkParams p,
  ) async {
    final url =
        'https://mooc1.chaoxing.com/work/getAllWork'
        '?classId=${Uri.encodeComponent(p.clazzId!)}'
        '&courseId=${Uri.encodeComponent(p.courseId!)}&isdisplaytable=2&mooc=1'
        '&ut=s&enc=${Uri.encodeComponent(p.enc!)}'
        '&cpi=${Uri.encodeComponent(p.cpi ?? '')}'
        '&openc=${Uri.encodeComponent(p.openc ?? '')}';
    final resp = await _get(url);
    if (resp == null || resp.statusCode != 200) return null;
    final doc = html_parser.parse(resp.body);
    if (doc.querySelector('.ulDiv') == null) return null;
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
      final strong =
          li.querySelector('.pt5:last-child strong') ??
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
      final workId =
          a.attributes['data'] ??
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

      items.add(
        HomeworkItem(
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
          sourceKey: workId == null
              ? null
              : 'cx|${p.courseId}|${p.clazzId}|work|$workId',
        ),
      );
    }
    return items;
  }

  /// 考试列表（考试模块 data-url + 课程参数；入口 URL 见 [_WorkParams.examUrl]）。
  /// 返回 null = 没拉到（请求失败/非200），与「这门课没有考试」（空列表）
  /// 区分——同步层靠它决定能否清理旧条目。kDebugMode 落盘原始 HTML。
  Future<List<HomeworkItem>?> _examList(
    String courseName,
    _WorkParams p,
  ) async {
    final base = p.examListUrl;
    final sep = base.contains('?') ? '&' : '?';
    // 参数 = course-stu.js 官方配方（else 分支）：courseid/clazzid 全小写 +
    // cpi + ut=s + t + stuenc(=enc 隐藏域)。真机实证：test-list 端点 404、
    // 驼峰 clazzId 报「无效的班级」、缺 t/stuenc 报「参数传递不正确」。
    final url =
        '$base$sep'
        'courseid=${Uri.encodeComponent(p.courseId!)}'
        '&clazzid=${Uri.encodeComponent(p.clazzId!)}'
        '&cpi=${Uri.encodeComponent(p.cpi ?? '')}&ut=s'
        '&t=${Uri.encodeComponent(p.t ?? '')}'
        '&stuenc=${Uri.encodeComponent(p.encPlain ?? '')}';
    final resp = await _get(url);
    if (resp == null || resp.statusCode != 200) return null;
    if (kDebugMode) {
      try {
        final dir = await getApplicationDocumentsDirectory();
        File('${dir.path}/cx_exam_${p.clazzId}.html')
            .writeAsStringSync(resp.body, flush: true);
      } catch (_) {}
    }
    final doc = html_parser.parse(resp.body);
    if (doc.querySelector('.bottomList, table') == null) {
      // 真实空考试页不渲染 bottomList，而是正常列表布局中的 null-data。
      // 只接受已核对的页面标题、容器层次和明确空状态；普通错误页、
      // 登录页及脚本里的“暂无考试”仍按失败处理，不能据此清理旧记录。
      final empty = doc.querySelector('.task-list .has-content .null-data');
      if (doc.querySelector('title')?.text.trim() == '考试列表' &&
          empty?.text.trim() == '暂无考试') {
        return [];
      }
      return null;
    }
    return parseExamListHtml(
      resp.body,
      courseName: courseName,
      courseId: p.courseId!,
      clazzId: p.clazzId!,
    );
  }

  /// 考试列表解析（公开纯函数便于单测）。真机实证：条目容器是
  /// `.bottomList ul li`（data 属性挂操作 URL），**不是表格行**；但账号里
  /// 尚无带条目的真实样本，故 li/tr 双扫、字段宽松抓：元素文本含日期时间
  /// 才算考试行，截止取行内最晚时间；标题优先 a[title]/h3/首个非时间文本；
  /// 状态含「已结束/已批阅/已完成」→ done；examId 从 examId=(\d+) 抓。
  static List<HomeworkItem> parseExamListHtml(
    String html, {
    required String courseName,
    required String courseId,
    required String clazzId,
  }) {
    final doc = html_parser.parse(html);
    final items = <HomeworkItem>[];
    final seen = <String>{};
    final rows = [...doc.querySelectorAll('li'), ...doc.querySelectorAll('tr')];
    for (final el in rows) {
      final text = el.text.trim();
      final times = _allDateTimes(text);
      if (times.isEmpty) continue;
      String title = '';
      for (final a in el.querySelectorAll('a')) {
        final t = (a.attributes['title'] ?? a.text).trim();
        if (t.isNotEmpty && !t.contains(RegExp(r'\d{4}-\d{2}-\d{2}'))) {
          title = t;
          break;
        }
      }
      if (title.isEmpty) {
        for (final h3 in el.querySelectorAll('h3')) {
          final t = h3.text.trim();
          if (t.isNotEmpty && !t.contains(RegExp(r'\d{4}-\d{2}-\d{2}'))) {
            title = t;
            break;
          }
        }
      }
      if (title.isEmpty) {
        final tds = el.querySelectorAll('td');
        if (tds.isNotEmpty) title = tds.first.text.trim();
      }
      if (title.isEmpty) continue;
      var due = times.first;
      for (final t in times) {
        if (t.isAfter(due)) due = t;
      }
      final done =
          text.contains('已结束') || text.contains('已批阅') || text.contains('已完成');
      // li 形状 examId 在元素自身 data 属性里（innerHtml 不含自身属性），
      // tr 形状在子节点里
      final ownData = el.attributes['data'] ?? '';
      final eid =
          RegExp(r'examId=(\d+)').firstMatch(ownData)?.group(1) ??
          RegExp(r'examId=(\d+)').firstMatch(el.innerHtml)?.group(1);
      final id = eid != null
          ? 'cxe_${courseId}_${clazzId}_$eid'
          : 'cxe_${courseId}_${clazzId}_${title.hashCode}';
      if (!seen.add(id)) continue;
      items.add(
        HomeworkItem(
          id: id,
          platform: PlatformKind.chaoxing,
          course: courseName,
          title: title,
          dueAt: due,
          status: done ? HwStatus.done : HwStatus.todo,
          sourceKey: eid == null ? null : 'cx|$courseId|$clazzId|exam|$eid',
        ),
      );
    }
    return items;
  }

  /// 行文本里的全部日期时间（含「开始/截止」前缀的中文日期形态）。
  static List<DateTime> _allDateTimes(String text) {
    final out = <DateTime>[];
    final re = RegExp(
      r'(\d{4})[-/.年](\d{1,2})[-/.月](\d{1,2})日?\s+(\d{1,2}):(\d{2})',
    );
    for (final m in re.allMatches(text)) {
      final d = _parseDateTime(m.group(0)!);
      if (d != null) out.add(d);
    }
    return out;
  }

  static DateTime? _parseDateTime(String raw) {
    final m = RegExp(
      r'(\d{4})[-/.年](\d{1,2})[-/.月](\d{1,2})日?\s*(\d{1,2}):(\d{2})?',
    ).firstMatch(raw);
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
