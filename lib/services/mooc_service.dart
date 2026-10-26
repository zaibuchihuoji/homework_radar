/// 中国大学MOOC（icourse163.org）作业/测验查询。
///
/// 说明：该平台无公开文档接口，此处按社区已验证的通用方式实现：
/// - Cookie 会话：NTESSTUDYSESSINFO（WebView 登录后捕获）；
/// - csrfKey：登录后从页面源码提取，所有 rpc/dwr 调用以 ?csrfKey= 带上；
/// - 课程列表：learnerCourseRpcBean.getMyLearnedCoursePanelList.rpc
/// - 课程结构：courseBean.getMocTermDto.rpc（表单请求、JSON DTO）；
///   历史 DWR 文本仅保留不允许清理旧记录的兼容输出。
/// 接口返回格式如有变动，调试页可查看原始响应辅助修正。
library;

import 'dart:convert';

import '../models/homework.dart';
import 'safe_http.dart';
import 'stable_hash.dart';

class MoocCourse {
  String name;
  String courseId;
  String? termId;
  int? mode;
  DateTime? startAt;
  DateTime? endAt;
  MoocCourse(this.name, this.courseId, [this.termId]);
}

class MoocService {
  String? cookie;
  String? csrfKey;

  MoocService({this.cookie, this.csrfKey});

  /// 课程列表请求失败（供同步层决定能否清理旧条目）。
  bool listFailed = false;

  /// 会话失效（课程列表刷新重试后仍收到明确的 401/403）。同步层靠它触发
  /// 「登录已过期」通知（与学习通同款）和 needRelogin 状态。
  bool loginFailed = false;

  /// 课程级请求失败次数。
  int failedCount = 0;

  /// Only a complete, authenticated scan may narrow the active local scope.
  /// null means unknown, while an empty set is a confirmed empty school term.
  Set<String>? schoolTermScope;

  static final _csrfFromJson = RegExp(r'"csrfKey"\s*:\s*"(\w+)"');
  static final _csrfFromJs = RegExp(r'''csrfKey\s*[=:]\s*["']?(\w{10,})''');

  /// Cookie 是否有效（用课程 RPC 探测，csrfKey 本身不是登录证据）。
  /// 返回 null = 网络层失败（页面没拿到），调用方不得据此判定「登录失效」。
  Future<bool?> checkLogin() async {
    // 会话 Cookie 新旧双名：NTESSTUDYSESSINFO 已被平台下线，2026-10-06
    // 真机实证现行会话是 STUDY_SESS（webview_login_page 捕获同款判定）
    final hasSession =
        cookie != null &&
        (cookie!.contains('NTESSTUDYSESSINFO') ||
            cookie!.contains('STUDY_SESS'));
    if (!hasSession) return false;
    if (csrfKey == null || csrfKey!.isEmpty) {
      final refreshed = await refreshCsrfKey();
      if (refreshed == null) return null; // 网络失败 ≠ 登录过期
    }
    if (csrfKey == null || csrfKey!.isEmpty) return false;
    final response = await SafeHttp.postForm(
      'https://www.icourse163.org/web/j/'
      'learnerCourseRpcBean.getMyLearnedCoursePanelList.rpc?csrfKey=${Uri.encodeQueryComponent(csrfKey!)}',
      body: {'type': '30', 'courseType': '2', 'p': '1', 'psize': '1'},
      headers: _headers,
    );
    if (response == null || response.statusCode >= 500) return null;
    if (response.statusCode == 401 || response.statusCode == 403) return false;
    if (response.statusCode != 200) return null;
    try {
      final data = jsonDecode(response.body);
      if (data is! Map) return null;
      final code = data['code'];
      if (const [1, '1', 401, 403, '401', '403'].contains(code)) {
        return false;
      }
      if (code != null &&
          code != 0 &&
          code != 200 &&
          code != '0' &&
          code != '200') {
        return null;
      }
      return _walkCoursePage(data['result'] ?? data['data'], <MoocCourse>[])
          ? true
          : null;
    } catch (_) {
      return null;
    }
  }

  Future<String?> refreshCsrfKey() async {
    // 2026-10-06 官方 web 包（core_*.js）实证：所有 .rpc 调用的 csrfKey
    // 就是 Cookie `NTESSTUDYSI` 的值（"?csrfKey="+cookies.NTESSTUDYSI），
    // home.htm 已改为纯 SPA 壳不再内嵌——直接从 Cookie 解析，零网络往返
    final fromCookie = RegExp(r'(?:^|;\s*)NTESSTUDYSI=([^;]+)')
        .firstMatch(cookie ?? '');
    if (fromCookie != null && fromCookie.group(1)!.trim().isNotEmpty) {
      csrfKey = fromCookie.group(1)!.trim();
      return csrfKey;
    }
    final resp = await SafeHttp.get(
      'https://www.icourse163.org/home.htm',
      headers: {'Cookie': SafeHttp.cookieHeader(cookie)},
    );
    if (resp == null || resp.statusCode != 200) return null;
    final m =
        _csrfFromJson.firstMatch(resp.body) ??
        _csrfFromJs.firstMatch(resp.body);
    final key = m?.group(1);
    if (key != null) csrfKey = key;
    return key;
  }

  Map<String, String> get _headers => {
    'Cookie': SafeHttp.cookieHeader(cookie),
    'Referer': 'https://www.icourse163.org/',
    'X-Requested-With': 'XMLHttpRequest',
    'edu-script-token': csrfKey ?? '',
  };

  /// Official school-course tab uses courseType=2 (public-course tab uses 1).
  /// Keep all pages before filtering: a full page of old courses is not EOF.
  Future<List<MoocCourse>> courses() async {
    if (csrfKey == null) await refreshCsrfKey();
    if (csrfKey == null) {
      listFailed = true;
      return [];
    }
    final found = <MoocCourse>[];
    for (var page = 1; page <= 20; page++) {
      var resp = await SafeHttp.postForm(
        'https://www.icourse163.org/web/j/'
        'learnerCourseRpcBean.getMyLearnedCoursePanelList.rpc?csrfKey=$csrfKey',
        body: {'type': '30', 'courseType': '2', 'p': '$page', 'psize': '32'},
        headers: _headers,
      );
      // 非 200 可能是 csrfKey 被服务端轮换：刷新一次重试，别把旧会话
      // 的失败当「登录失效」反复要求重新登录
      if ((resp == null || resp.statusCode != 200) && csrfKey != null) {
        final refreshed = await refreshCsrfKey();
        if (refreshed != null && refreshed.isNotEmpty) {
          resp = await SafeHttp.postForm(
            'https://www.icourse163.org/web/j/'
            'learnerCourseRpcBean.getMyLearnedCoursePanelList.rpc?csrfKey=$csrfKey',
            body: {
              'type': '30',
              'courseType': '2',
              'p': '$page',
              'psize': '32',
            },
            headers: _headers,
          );
        }
      }
      if (resp == null || resp.statusCode != 200) {
        // 限流、服务端故障和陌生响应都不是会话过期的证据。
        if (resp?.statusCode == 401 || resp?.statusCode == 403) {
          loginFailed = true;
        }
        listFailed = true;
        return found;
      }
      final pageCourses = <MoocCourse>[];
      try {
        final json = jsonDecode(resp.body);
        if (json is Map &&
            json['code'] != null &&
            !const [0, 200, '0', '200'].contains(json['code'])) {
          if (const [1, '1', 401, 403, '401', '403'].contains(json['code'])) {
            loginFailed = true;
          }
          listFailed = true;
          return found;
        }
        final payload = json is Map ? json['result'] ?? json['data'] : null;
        if (!_walkCoursePage(payload, pageCourses)) {
          listFailed = true;
          return found;
        }
      } catch (_) {
        listFailed = true;
        return found;
      }
      for (final course in pageCourses) {
        final eligible = _inSchoolSemester(course);
        if (eligible == null) listFailed = true;
        if (eligible == true) found.add(course);
      }
      if (pageCourses.length < 32) break; // 短页 = 最后一页
      if (page == 20) listFailed = true;
    }
    // 遍历较宽松，同一课程对象可能在不同嵌套层被收多次，按课去重
    final seen = <String>{};
    return [
      for (final c in found)
        if (seen.add('${c.courseId}|${c.termId}')) c,
    ];
  }

  // The official course card reads its selected/enrolled term from termPanel,
  // not currentTermId (latest public offering), and badges modes 10/15/20 as
  // SPOC. Merely having schoolPanel is not school enrollment evidence.
  bool? _inSchoolSemester(MoocCourse course) {
    final mode = course.mode;
    if (mode == 0 || mode == 30) return false;
    if (!const [10, 15, 20].contains(mode)) return null;
    final start = course.startAt, end = course.endAt;
    if (course.termId == null ||
        start == null ||
        end == null ||
        !end.isAfter(start)) {
      return null;
    }
    final now = DateTime.now();
    final (semesterStart, semesterEnd) = switch (now.month) {
      >= 8 => (DateTime(now.year, 8), DateTime(now.year + 1, 2)),
      1 => (DateTime(now.year - 1, 8), DateTime(now.year, 2)),
      _ => (DateTime(now.year, 2), DateTime(now.year, 8)),
    };
    return start.isBefore(semesterEnd) && !end.isBefore(semesterStart);
  }

  static DateTime? _courseDate(dynamic value) {
    if (value is! num ||
        !value.isFinite ||
        value < 946684800000 ||
        value > 253402300799000) {
      return null;
    }
    return DateTime.fromMillisecondsSinceEpoch(value.toInt());
  }

  // Only a recognizable list can establish an empty course page. A success
  // code alone (or an error/message object) cannot authorize cleanup.
  bool _walkCoursePage(dynamic node, List<MoocCourse> out) {
    if (node is List) {
      for (final entry in node) {
        final parsed = <MoocCourse>[];
        _walkForCourses(entry, parsed);
        if (parsed.isEmpty) return false;
        out.addAll(parsed);
      }
      return true;
    }
    if (node is Map) {
      for (final key in const [
        'list',
        'courseList',
        'courses',
        'result',
        'data',
      ]) {
        if (node.containsKey(key)) return _walkCoursePage(node[key], out);
      }
      // Preserve existing nonempty wrapper variants without treating unknown
      // empty metadata arrays as a recognizable empty course response.
      var recognized = false;
      for (final value in node.values) {
        if (value is! Map && value is! List) continue;
        final parsed = <MoocCourse>[];
        if (_walkCoursePage(value, parsed) && parsed.isNotEmpty) {
          out.addAll(parsed);
          recognized = true;
        }
      }
      return recognized;
    }
    return false;
  }

  void _walkForCourses(dynamic node, List<MoocCourse> out) {
    if (node is List) {
      for (final e in node) {
        _walkForCourses(e, out);
      }
      return;
    }
    if (node is Map) {
      final keys = node.keys.cast<String>().toSet();
      final hasName = keys.contains('name') && node['name'] is String;
      final id = node['id'] ?? node['courseId'];
      if (hasName && id != null && RegExp(r'^\d+$').hasMatch('$id')) {
        final panel = node['termPanel'];
        final term = panel is Map ? panel['id'] : node['termId'];
        final validTerm =
            term != null && RegExp(r'^[1-9]\d*$').hasMatch('$term');
        final mode = panel is Map
            ? panel['mode'] ?? node['mode']
            : node['mode'];
        out.add(
          MoocCourse(node['name'] as String, '$id', validTerm ? '$term' : null)
            ..mode = int.tryParse('$mode')
            ..startAt = panel is Map ? _courseDate(panel['startTime']) : null
            ..endAt = panel is Map ? _courseDate(panel['endTime']) : null,
        );
      } else {
        for (final v in node.values) {
          _walkForCourses(v, out);
        }
        return;
      }
      // A course's schoolPanel, teachers and termPanel also contain name/id.
      // They are metadata, never extra enrolled courses.
    }
  }

  /// 单门课程的测验/作业/考试。
  /// 返回 null = 「没拉到」（termId 解析不到 / 双路请求失败），与「拉到了
  /// 但这门课没有作业」（空列表）区分——此前一律静默返空列表，同步层把
  /// 失败当「确认消失」，把该课已入库作业连同提醒整课清掉。
  Future<List<HomeworkItem>?> homeworkOf(MoocCourse c) async {
    final termId = c.termId;
    if (termId == null) return null;
    final raw = await _termDtoRaw(termId);
    if (raw == null) return null;
    try {
      final json = jsonDecode(raw);
      return _parseJsonTerm(json, c, termId);
    } on FormatException {
      // Old servers may still return DWR instead of the current JSON DTO.
    }
    // Legacy extraction lacks the complete structured assessment lists. Keep
    // its compatibility output, but never use it to authorize deletion.
    failedCount++;
    return _parseTermDto(raw, c.name, c.courseId, termId);
  }

  // Contract verified against three live public course responses on 2026-10-18.
  // Assessments belong to semantic lists; contentType is also used on ordinary
  // documents and lessons, and is not a reliable global assessment discriminator.
  List<HomeworkItem>? _parseJsonTerm(
    dynamic json,
    MoocCourse course,
    String termId,
  ) {
    if (json is! Map || !const [0, '0'].contains(json['code'])) return null;
    final term = json['result'];
    if (term is! Map ||
        '${term['id']}' != termId ||
        '${term['courseId']}' != course.courseId ||
        term['chapters'] is! List ||
        term['exams'] is! List) {
      return null;
    }
    final items = <HomeworkItem>[];
    final seen = <String>{};
    var invalid = false;
    void add(dynamic value, String kind) {
      if (value is! Map) {
        invalid = true;
        return;
      }
      final id = value['id'];
      final deadline = value['deadline'];
      if (id == null ||
          !RegExp(r'^[1-9]\d*$').hasMatch('$id') ||
          !value.containsKey('deadline')) {
        invalid = true;
        return;
      }
      DateTime? due;
      if (deadline != null && deadline != 0) {
        if (deadline is! num || deadline < 946684800000) {
          invalid = true;
          return;
        }
        due = DateTime.fromMillisecondsSinceEpoch(deadline.toInt());
      }
      final source = 'mooc|${course.courseId}|$termId|$kind|$id';
      if (!seen.add(source)) return;
      final label = kind == '4'
          ? '作业'
          : kind == '2'
          ? '单元测验'
          : '考试';
      final name = value['name'];
      items.add(
        HomeworkItem(
          id: 'mooc_${stableHash(course.name)}_$label$id',
          platform: PlatformKind.mooc,
          course: course.name,
          title: name is String && name.trim().isNotEmpty
              ? name.trim()
              : '$label $id',
          dueAt: due,
          status: HwStatus.todo,
          sourceKey: source,
        ),
      );
    }

    void assessmentList(Map chapter, String key, String kind) {
      final list = chapter[key] ?? const [];
      if (!chapter.containsKey(key) || list is! List) {
        invalid = true;
        return;
      }
      for (final wrapper in list) {
        if (wrapper is! Map) {
          invalid = true;
          continue;
        }
        add(wrapper['test'], kind);
      }
    }

    for (final chapter in term['chapters'] as List) {
      if (chapter is! Map) {
        invalid = true;
        continue;
      }
      assessmentList(chapter, 'homeworks', '4');
      assessmentList(chapter, 'quizs', '2');
      if (chapter['exam'] != null) add(chapter['exam'], 'exam');
      final lessons = chapter['lessons'] ?? const [];
      if (!chapter.containsKey('lessons') || lessons is! List) {
        invalid = true;
        continue;
      }
      for (final lesson in lessons) {
        if (lesson is! Map) {
          invalid = true;
          continue;
        }
        if (lesson['test'] != null) {
          final test = lesson['test'];
          if (test is! Map || !const [2, 3].contains(test['type'])) {
            invalid = true;
          } else {
            add(test, test['type'] == 3 ? '4' : '2');
          }
        }
        if (lesson['exam'] != null) add(lesson['exam'], 'exam');
      }
    }
    for (final exam in term['exams'] as List) {
      add(exam, 'exam');
    }
    return invalid ? null : items;
  }

  Future<String?> _termDtoRaw(String termId) async {
    // The current official /j/ request helper submits a form. isDraft is a
    // number: a live boolean "false" is rejected with code -1005, JSON content
    // types are rejected before parameter parsing.
    final respRpc = await SafeHttp.postForm(
      'https://www.icourse163.org/web/j/courseBean.getMocTermDto.rpc'
      '?csrfKey=$csrfKey',
      body: {'termId': termId, 'isDraft': '0', 'excludeUnrelease': 'false'},
      headers: _headers,
    );
    if (respRpc != null && respRpc.statusCode == 200) {
      try {
        final json = jsonDecode(respRpc.body);
        final result = json is Map ? json['result'] : null;
        if (result is Map &&
            (result.containsKey('chapters') || result.containsKey('exams'))) {
          return respRpc.body; // Full validation happens before any merge.
        }
      } on FormatException {
        /* Legacy DWR handled below. */
      }
    }
    if (respRpc != null &&
        respRpc.statusCode == 200 &&
        _isDwrTerm(respRpc.body)) {
      return respRpc.body;
    }
    final ts = DateTime.now().millisecondsSinceEpoch;
    // 现行 web 包 _$requestByDWR 实证（core_*.js）：DWR 体是 text/plain
    // 换行分隔的原始行（E(n.m) 以 \n join），Content-Type 必须是
    // text/plain——发 urlencoded 会被 DWR 行解析器按错行炸成通用 Error
    final dwrLines = [
      'callCount=1',
      'nextReverseAjaxIndex=0',
      'c0-scriptName=CourseBean',
      'c0-methodName=getMocTermDto',
      'c0-id=0',
      'c0-param0=number:$termId',
      'c0-param1=boolean:false',
      'c0-param2=boolean:false',
      'batchId=$ts',
      'httpSessionId=${csrfKey ?? ''}',
      'scriptSessionId=$ts/D9C8C4F0D5A9B5E2C1D0',
    ];
    final resp1 = await SafeHttp.postJson(
      'https://www.icourse163.org/dwr/call/plaincall/CourseBean.getMocTermDto.dwr'
      '?csrfKey=$csrfKey',
      body: dwrLines.join('\n'),
      headers: {..._headers, 'Content-Type': 'text/plain'},
    );
    if (resp1 != null && resp1.statusCode == 200 && _isDwrTerm(resp1.body)) {
      return resp1.body;
    }
    return null;
  }

  // The parser below handles DWR assignments, not JSON. Recognizing a method
  // name inside arbitrary JSON must not silently turn real work into [].
  static bool _isDwrTerm(String body) {
    if (body.trimLeft().startsWith('<')) return false;
    try {
      jsonDecode(body);
      return false;
    } catch (_) {
      return !body.contains('_remoteHandleException') &&
          (RegExp(r'\bcontentType=\d+;').hasMatch(body) ||
              RegExp(r'\bexamId=\d+;').hasMatch(body));
    }
  }

  /// 从 MocTermDto 的 DWR 文本中抽取 单元测验(2)/作业(4)/考试(examId)。
  List<HomeworkItem> _parseTermDto(
    String raw,
    String courseName,
    String courseId,
    String termId,
  ) {
    final items = <HomeworkItem>[];
    final seen = <String>{};

    void addEntry({
      required String kind,
      required String id,
      String? name,
      int? endMs,
      String? url,
      String? sourceKind,
      bool realId = true,
    }) {
      final key = '$kind-$id';
      if (seen.contains(key) || id.isEmpty) return;
      seen.add(key);
      items.add(
        HomeworkItem(
          id: 'mooc_${courseName.hashCode}_$kind$id',
          platform: PlatformKind.mooc,
          course: courseName,
          title: (name == null || name.isEmpty) ? '$kind $id' : name,
          dueAt: endMs == null
              ? null
              : DateTime.fromMillisecondsSinceEpoch(endMs),
          status: HwStatus.todo,
          url: url,
          sourceKey: !realId
              ? null
              : 'mooc|$courseId|$termId|${sourceKind ?? 'exam'}|$id',
        ),
      );
    }

    // 单元测验 / 作业：contentType=2 / contentType=4。
    // 段切分：先收集全部对象标记的位置，窗口取「本标记 → 下一标记」——
    // 此前的 ±800 字符双向窗口会罩住相邻对象，firstMatch 抓到邻居的
    // contentId，两条同型测验同 id，第二条被 seen 去重静默吞掉
    // （整条测验连同截止提醒一起消失）。
    final markerPos = <int>[];
    for (final ct in const ['2', '4']) {
      final m = 'contentType=$ct;';
      for (var p = raw.indexOf(m); p >= 0; p = raw.indexOf(m, p + m.length)) {
        markerPos.add(p);
      }
    }
    markerPos.sort();

    for (final ct in const ['2', '4']) {
      final kind = ct == '2' ? '单元测验' : '作业';
      final marker = 'contentType=$ct;';
      var from = 0;
      while (true) {
        final i = raw.indexOf(marker, from);
        if (i < 0) break;
        from = i + marker.length;
        // 段终点 = 下一个（任意型）对象标记位置：一个段恰好罩住一个对象
        final segEnd = markerPos.firstWhere(
          (p) => p > i,
          orElse: () => raw.length,
        );
        final win = raw.substring(i, segEnd);
        // DWR 文本形如 `s12.contentType=2; s12.contentId=...`：标记带 sN.
        // 前缀时用 sN 锚定本对象的 contentId（sN 在整包内唯一），段内也
        // 不怕串号；文本形态漂移（无前缀）才退化为段内 firstMatch
        final sn = RegExp(r's(\d+)\.$')
            .firstMatch(raw.substring((i - 24).clamp(0, i), i))
            ?.group(1);
        final sourceId =
            (sn == null
                ? null
                : RegExp('$sn\\.contentId=(\\d+)').firstMatch(win)?.group(1)) ??
            RegExp(r'contentId=(\d+)').firstMatch(win)?.group(1) ??
            RegExp(r'[^a-zA-Z]id=(\d+)').firstMatch(win)?.group(1);
        final cid =
            sourceId ??
            // 段内完全无 id：兜底从「文本偏移」改为稳定哈希——偏移随服务端
            // 字段顺序抖动会让 id 全换（旧条目失联、提醒重排、隐藏复活），
            // 哈希只吃段前 80 字符则不受影响
            '${stableHash(kind + win.substring(0, win.length.clamp(0, 80)))}';
        final name = RegExp(r'name="([^"]*)"').firstMatch(win)?.group(1);
        final endMs = _firstEnd(win);
        addEntry(
          kind: kind,
          id: cid,
          name: name,
          endMs: endMs,
          sourceKind: ct,
          realId: sourceId != null,
        );
      }
    }

    // 期末考试：examId=xxx
    var from = 0;
    while (true) {
      final m = RegExp(r'examId=(\d+);').firstMatch(raw.substring(from));
      if (m == null) break;
      final i = from + m.start;
      from += m.end;
      final win = raw.substring(
        (i - 300).clamp(0, raw.length),
        (i + 800).clamp(0, raw.length),
      );
      final name = RegExp(r'name="([^"]*)"').firstMatch(win)?.group(1);
      final endMs = _firstEnd(win);
      addEntry(kind: '考试', id: m.group(1)!, name: name, endMs: endMs);
    }

    return items;
  }

  static int? _firstEnd(String win) {
    for (final field in const ['endTime', 'submitEndTime', 'deadline']) {
      final m = RegExp('$field=(\\d{12,})').firstMatch(win);
      if (m != null) {
        final v = int.tryParse(m.group(1)!);
        if (v != null) return v;
      }
    }
    return null;
  }

  /// 并发拉取全部课程测验（2 路，单路间隔 0.8s，避免触发风控）。
  Future<List<HomeworkItem>> allHomework({
    void Function(int done, int total)? onProgress,
  }) async {
    schoolTermScope = null;
    final initialSession = await checkLogin();
    if (initialSession != true) {
      listFailed = true;
      if (initialSession == false) loginFailed = true;
      return [];
    }
    final cs = await courses();
    final out = <HomeworkItem>[];
    final queue = List<MoocCourse>.of(cs);
    var done = 0;

    Future<void> worker() async {
      while (queue.isNotEmpty) {
        final c = queue.removeAt(0);
        try {
          final list = await homeworkOf(c);
          if (list == null) {
            failedCount++; // 失败不能当「没有作业」，同步层靠它判定能否清理
          } else {
            out.addAll(list);
          }
        } catch (_) {
          failedCount++;
        }
        done++;
        onProgress?.call(done, cs.length);
        if (queue.isNotEmpty) {
          await Future.delayed(const Duration(milliseconds: 800));
        }
      }
    }

    await Future.wait([for (var i = 0; i < 2; i++) worker()]);
    // Public term metadata can still be returned after a login expires. A
    // successful metadata read alone must not authorize account-data cleanup.
    final session = await checkLogin();
    if (session != true) listFailed = true;
    if (session == false) loginFailed = true;
    if (!listFailed && failedCount == 0 && session == true) {
      schoolTermScope = {for (final c in cs) '${c.courseId}|${c.termId}'};
    }
    return out;
  }
}
