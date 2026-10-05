/// 中国大学MOOC（icourse163.org）作业/测验查询。
///
/// 说明：该平台无公开文档接口，此处按社区已验证的通用方式实现：
/// - Cookie 会话：NTESSTUDYSESSINFO（WebView 登录后捕获）；
/// - csrfKey：登录后从页面源码提取，所有 rpc/dwr 调用以 ?csrfKey= 带上；
/// - 课程列表：learnerCourseRpcBean.getMyLearnedCoursePanelList.rpc
/// - 课程结构：CourseBean.getMocTermDto（DWR 文本），从中抽取测验/作业/考试。
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
  MoocCourse(this.name, this.courseId, [this.termId]);
}

class MoocService {
  String? cookie;
  String? csrfKey;

  MoocService({this.cookie, this.csrfKey});

  /// 课程列表请求失败（供同步层决定能否清理旧条目）。
  bool listFailed = false;

  /// 会话失效（csrfKey 刷新重试后仍被拒绝）。checkLogin 凭缓存的
  /// csrfKey 恒返回 true，掉登录后没有别的信号——同步层靠它触发
  /// 「登录已过期」通知（与学习通同款）和 needRelogin 状态。
  bool loginFailed = false;

  /// 课程级请求失败次数。
  int failedCount = 0;

  static final _csrfFromJson = RegExp(r'"csrfKey"\s*:\s*"(\w+)"');
  static final _csrfFromJs =
      RegExp(r'''csrfKey\s*[=:]\s*["']?(\w{10,})''');

  /// Cookie 是否有效（能取到 csrfKey 即认为有效）。
  /// 返回 null = 网络层失败（页面没拿到），调用方不得据此判定「登录失效」。
  Future<bool?> checkLogin() async {
    if (cookie == null || !cookie!.contains('NTESSTUDYSESSINFO')) return false;
    if (csrfKey == null || csrfKey!.isEmpty) {
      final refreshed = await refreshCsrfKey();
      if (refreshed == null) return null; // 网络失败 ≠ 登录过期
    }
    return csrfKey != null && csrfKey!.isNotEmpty;
  }

  Future<String?> refreshCsrfKey() async {
    final resp = await SafeHttp.get(
      'https://www.icourse163.org/home.htm',
      headers: {'Cookie': SafeHttp.cookieHeader(cookie)},
    );
    if (resp == null || resp.statusCode != 200) return null;
    final m = _csrfFromJson.firstMatch(resp.body) ?? _csrfFromJs.firstMatch(resp.body);
    final key = m?.group(1);
    if (key != null) csrfKey = key;
    return key;
  }

  Map<String, String> get _headers => {
        'Cookie': SafeHttp.cookieHeader(cookie),
        'Referer': 'https://www.icourse163.org/',
        'X-Requested-With': 'XMLHttpRequest',
      };

  /// 我学的课程（翻页拉全：此前固定第 1 页 32 条，选课多的用户第 33 门起
  /// 永远拉不到，还会被同步层当「完整抓取」清掉旧条目）。
  Future<List<MoocCourse>> courses() async {
    if (csrfKey == null) await refreshCsrfKey();
    if (csrfKey == null) return [];
    final found = <MoocCourse>[];
    for (var page = 1; page <= 20; page++) {
      var resp = await SafeHttp.postForm(
        'https://www.icourse163.org/web/j/'
        'learnerCourseRpcBean.getMyLearnedCoursePanelList.rpc?csrfKey=$csrfKey',
        body: {'type': '30', 'p': '$page', 'psize': '32'},
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
            body: {'type': '30', 'p': '$page', 'psize': '32'},
            headers: _headers,
          );
        }
      }
      if (resp == null || resp.statusCode != 200) {
        // 网络拿不到响应（null）≠ 会话被拒：只有重试后仍收到明确拒绝
        // （非 200，典型是掉登录后 rpc 返回错误页）才算登录失效
        if (resp != null) loginFailed = true;
        listFailed = true;
        return found;
      }
      final pageCourses = <MoocCourse>[];
      try {
        final json = jsonDecode(resp.body);
        _walkForCourses(json, pageCourses);
      } catch (_) {
        listFailed = true;
        return found;
      }
      found.addAll(pageCourses);
      if (pageCourses.length < 32) break; // 短页 = 最后一页
    }
    // 遍历较宽松，同一课程对象可能在不同嵌套层被收多次，按课去重
    final seen = <String>{};
    return [
      for (final c in found)
        if (seen.add('${c.courseId}|${c.termId}')) c,
    ];
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
      final id = node['courseId'] ?? node['id'];
      if (hasName && id != null && RegExp(r'^\d+$').hasMatch('$id')) {
        final term = node['termId'];
        out.add(MoocCourse(node['name'] as String, '$id',
            term == null ? null : '$term'));
      } else {
        for (final v in node.values) {
          _walkForCourses(v, out);
        }
        return;
      }
      // 同层继续找嵌套的课程对象（结构未知，尽量宽松）
      for (final v in node.values) {
        _walkForCourses(v, out);
      }
    }
  }

  /// 单门课程的测验/作业/考试。
  /// 返回 null = 「没拉到」（termId 解析不到 / 双路请求失败），与「拉到了
  /// 但这门课没有作业」（空列表）区分——此前一律静默返空列表，同步层把
  /// 失败当「确认消失」，把该课已入库作业连同提醒整课清掉。
  Future<List<HomeworkItem>?> homeworkOf(MoocCourse c) async {
    final termId = c.termId ?? await _resolveTermId(c.courseId);
    if (termId == null) return null;
    final raw = await _termDtoRaw(termId);
    if (raw == null) return null;
    return _parseTermDto(raw, c.name);
  }

  Future<String?> _resolveTermId(String courseId) async {
    // 优先从课程页 initial state 里找 termId
    final resp = await SafeHttp.get(
      'https://www.icourse163.org/course/-${Uri.encodeComponent(courseId)}',
      headers: _headers,
      followRedirects: true,
    );
    if (resp != null && resp.statusCode == 200) {
      final m = RegExp(r'termId["\s:=]+(\d{6,})').firstMatch(resp.body);
      if (m != null) return m.group(1);
    }
    return null;
  }

  Future<String?> _termDtoRaw(String termId) async {
    final ts = DateTime.now().millisecondsSinceEpoch;
    final dwrBody = <String, String>{
      'callCount': '1',
      'scriptSessionId': '${ts}190',
      'httpSessionId': csrfKey ?? '',
      'batchId': '$ts',
      'c0-param0': 'number:$termId',
      'c0-param1': 'number:0',
      'c0-param2': 'number:1',
    };
    // 先走 dwr 经典路径，失败再试 web/j rpc 路径
    final resp1 = await SafeHttp.postForm(
      'https://www.icourse163.org/dwr/call/plaincall/CourseBean.getMocTermDto.dwr'
      '?csrfKey=$csrfKey',
      body: dwrBody,
      headers: _headers,
    );
    if (resp1 != null && resp1.body.contains('contentType=')) return resp1.body;
    final resp2 = await SafeHttp.postForm(
      'https://www.icourse163.org/web/j/CourseBean.getMocTermDto.rpc?csrfKey=$csrfKey',
      body: dwrBody,
      headers: _headers,
    );
    if (resp2 != null && resp2.body.contains('contentType=')) return resp2.body;
    return null;
  }

  /// 从 MocTermDto 的 DWR 文本中抽取 单元测验(2)/作业(4)/考试(examId)。
  List<HomeworkItem> _parseTermDto(String raw, String courseName) {
    final items = <HomeworkItem>[];
    final seen = <String>{};

    void addEntry({required String kind, required String id, String? name, int? endMs, String? url}) {
      final key = '$kind-$id';
      if (seen.contains(key) || id.isEmpty) return;
      seen.add(key);
      items.add(HomeworkItem(
        id: 'mooc_${courseName.hashCode}_$kind$id',
        platform: PlatformKind.mooc,
        course: courseName,
        title: (name == null || name.isEmpty) ? '$kind $id' : name,
        dueAt: endMs == null ? null : DateTime.fromMillisecondsSinceEpoch(endMs),
        status: HwStatus.todo,
        url: url,
      ));
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
        final segEnd =
            markerPos.firstWhere((p) => p > i, orElse: () => raw.length);
        final win = raw.substring(i, segEnd);
        // DWR 文本形如 `s12.contentType=2; s12.contentId=...`：标记带 sN.
        // 前缀时用 sN 锚定本对象的 contentId（sN 在整包内唯一），段内也
        // 不怕串号；文本形态漂移（无前缀）才退化为段内 firstMatch
        final sn = RegExp(r's(\d+)\.$')
            .firstMatch(raw.substring((i - 24).clamp(0, i), i))
            ?.group(1);
        final cid = (sn == null
                ? null
                : RegExp('$sn\\.contentId=(\\d+)').firstMatch(win)?.group(1)) ??
            RegExp(r'contentId=(\d+)').firstMatch(win)?.group(1) ??
            RegExp(r'[^a-zA-Z]id=(\d+)').firstMatch(win)?.group(1) ??
            // 段内完全无 id：兜底从「文本偏移」改为稳定哈希——偏移随服务端
            // 字段顺序抖动会让 id 全换（旧条目失联、提醒重排、隐藏复活），
            // 哈希只吃段前 80 字符则不受影响
            '${stableHash(kind + win.substring(0, win.length.clamp(0, 80)))}';
        final name = RegExp(r'name="([^"]*)"').firstMatch(win)?.group(1);
        final endMs = _firstEnd(win);
        addEntry(kind: kind, id: cid, name: name, endMs: endMs);
      }
    }

    // 期末考试：examId=xxx
    var from = 0;
    while (true) {
      final m = RegExp(r'examId=(\d+);').firstMatch(raw.substring(from));
      if (m == null) break;
      final i = from + m.start;
      from = i + m.end;
      final win = raw.substring(
          (i - 300).clamp(0, raw.length), (i + 800).clamp(0, raw.length));
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
    if (await checkLogin() != true) return [];
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
        await Future.delayed(const Duration(milliseconds: 800));
      }
    }

    await Future.wait([for (var i = 0; i < 2; i++) worker()]);
    return out;
  }
}
