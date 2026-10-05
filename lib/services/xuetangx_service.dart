/// 学堂在线（www.xuetangx.com）作业同步服务。
///
/// 认证：WebView 登录捕获 .xuetangx.com 域 Cookie，纯 Cookie 会话——
/// 社区逆向项目（XueTangxGetAnswer 等）实证无请求签名，特征头
/// `xtbz: xt` + `x-csrftoken: undefined` 即可。
///
/// 端点链（社区实证）：
/// 1. 课程章节树 `GET /api/v1/lms/learn/course/chapter?cid={教室id}&sign={课程sign}`
///    → data.course_chapter[].section_leaf_list[].leaf_list[]，leaf_type=6 为作业；
/// 2. 作业单元 `GET /mooc-api/v1/lms/learn/leaf_info/{cid}/{leafId}/`
///    → data.content_info.leaf_type_id（练习包 id，非作业叶子为 null）；
/// 3. 练习列表 `GET /api/v1/lms/exercise/get_exercise_list/{leafTypeId}/`。
///
/// 「我的课程」列表端点未在社区项目实证（各家爬虫均手工传课程 id）：
/// 走候选端点 + 宽松形状匹配 + 真机调试日志校准（与智慧树作业端点同一套
/// 防御）。截止时间字段同样未实证：宽松收集（deadline/end_time 等），
/// 无截止的条目跳过——作业雷达以截止提醒为核心。
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/homework.dart';
import 'safe_http.dart';
import 'stable_hash.dart';

/// 会话检查结论：
/// - ok：HTTP 200 且信封可解析；
/// - expired：带会话被明确拒绝（401/403，或业务码拒绝）——重登可解；
/// - unknown：网络层失败/网关 5xx，调用方不得据此判定「登录失效」。
enum XtSessionState { ok, expired, unknown }

class XtCourse {
  final String name;

  /// 教室 id（chapter 接口的 cid 参数，如 4231538）。
  final String cid;

  /// 课程 sign（如 HNU03031001055）。
  final String sign;
  XtCourse(this.name, this.cid, this.sign);
}

/// 章节树扫描结果：null = 结构陌生（信封不通/无 leaf 结构），调用方按
/// 失败计；homeworkLeaves 为空但结构可辨 = 权威「本课程无作业叶子」。
class XtChapterScan {
  final List<({String id, String name})> homeworkLeaves;
  XtChapterScan(this.homeworkLeaves);
}

class XuetangxService {
  String? cookie;

  XuetangxService({this.cookie});

  static const String _base = 'https://www.xuetangx.com';

  /// 「我的课程」端点（前端 JS 实证：src/api/mine/mine.js 的 user_courses，
  /// axios 默认 baseURL=/api/v1，即 GET /api/v1/lms/user/user-courses/）。
  /// 响应 {success, data.product_list}；未登录 HTTP 403 Django 风格。
  /// status: 1=在学 2=即将开始 3=已结束——一期拉在学+即将开始，已结束
  /// 的作业截止基本死线已过，不进雷达。
  static const String _userCoursesUrl =
      '$_base/api/v1/lms/user/user-courses/';
  static const List<int> courseStatuses = [1, 2];
  static const int _maxCoursePages = 5; // 每页 10 条（前端 count/10 口径）

  Map<String, String> get _headers => {
        'Cookie': SafeHttp.cookieHeader(cookie),
        'xtbz': 'xt',
        'x-client': 'web',
        'x-csrftoken': 'undefined',
        'referer': '$_base/',
      };

  /// 请求层失败（课程列表候选全失败/章节树不可达），同步层据此放弃清理。
  bool listFailed = false;

  /// 课程级失败次数（单课失败不当「没有作业」，同步层靠它判定能否清理）。
  int failedCount = 0;

  Future<http.Response?> _get(String url) =>
      SafeHttp.get(url, headers: _headers);

  /// Cookie 是否有效（问一次在学课程列表第 1 页）。结论见 [XtSessionState]。
  Future<XtSessionState> checkLogin() async {
    if (cookie == null || cookie!.isEmpty) return XtSessionState.expired;
    final resp = await _get('$_userCoursesUrl?status=1&page=1');
    if (resp == null) return XtSessionState.unknown; // 网络失败 ≠ 登录过期
    if (resp.statusCode == 401 || resp.statusCode == 403) {
      // 未登录实证：HTTP 403 + {"detail":"Authentication credentials..."}
      return XtSessionState.expired;
    }
    if (resp.statusCode != 200) return XtSessionState.unknown;
    // 信封可解析即视为会话有效（{success,data} 形态，无 code 字段也认）
    if (envelopeOk(resp.body)) return XtSessionState.ok;
    return XtSessionState.expired;
  }

  /// 信封判定（公开纯函数便于单测）：Map 且（code 为成功码，或直接带
  /// data 键）。学堂在线无统一网关信封，宽松处理，细节靠调试日志校准。
  static bool envelopeOk(String body) {
    dynamic json;
    try {
      json = jsonDecode(body);
    } catch (_) {
      return false;
    }
    if (json is! Map) return false;
    final code = json['code'];
    final codeOk = code is num ? code == 0 || code == 200 : code == '0' || code == '200';
    return codeOk || json.containsKey('data');
  }

  /// 我的课程（在学+即将开始，翻页拉全）。第一页失败置 listFailed；
  /// 后续页/状态组失败降级为「拿到多少算多少」——首页已证明会话和端点
  /// 可用，抖动不该让整个平台当次失效。
  Future<List<XtCourse>> courses() async {
    final found = <XtCourse>[];
    final seen = <String>{};
    var first = true;
    for (final status in courseStatuses) {
      for (var page = 1; page <= _maxCoursePages; page++) {
        final resp = await _get('$_userCoursesUrl?status=$status&page=$page');
        if (resp == null || resp.statusCode != 200) {
          if (first) listFailed = true;
          return found;
        }
        final parsed = parseCourseListJson(resp.body);
        if (parsed == null) {
          // 命中端点但形状陌生：可能页面结构变化，绝不能当「没有课程」
          if (first) listFailed = true;
          return found;
        }
        first = false;
        var added = 0;
        for (final c in parsed) {
          if (seen.add('${c.cid}#${c.sign}')) {
            found.add(c);
            added++;
          }
        }
        // 空页/短页/整页重复 = 这个状态组已拉完
        if (parsed.isEmpty || added == 0) break;
      }
    }
    return found;
  }

  /// 课程章节树里的作业叶子（leaf_type=6）。单课程作业清单的入口。
  /// 返回 null = 章节结构陌生（请求失败/信封不通/全树无 leaf_type 字段），
  /// 与「解析出 0 个作业叶子」（结构可辨、确实没有）严格区分。
  Future<List<HomeworkItem>?> homeworkOf(XtCourse c) async {
    final resp = await _get('$_base/api/v1/lms/learn/course/chapter'
        '?cid=${Uri.encodeQueryComponent(c.cid)}'
        '&sign=${Uri.encodeQueryComponent(c.sign)}');
    if (resp == null || resp.statusCode != 200) return null;
    final scan = parseChapterScan(resp.body);
    if (scan == null) return null;
    final out = <HomeworkItem>[];
    for (final leaf in scan.homeworkLeaves) {
      final item = await _homeworkOfLeaf(c, leaf);
      if (item != null) out.add(item);
      // 叶子间小间隔：单课作业叶子可能十来个，别贴脸连打
      await Future.delayed(const Duration(milliseconds: 300));
    }
    // 叶子存在却一条可用截止都没有：多半是截止字段名没对上（未抓包
    // 校准）。返回 null（不可信结果 → failedCount++）而不是权威空列表
    // ——空列表 + complete 守卫会把该课程旧条目整批清掉
    if (scan.homeworkLeaves.isNotEmpty && out.isEmpty) return null;
    return out;
  }

  Future<HomeworkItem?> _homeworkOfLeaf(
      XtCourse c, ({String id, String name}) leaf) async {
    DateTime? due;
    var title = leaf.name;
    final li = await _get('$_base/mooc-api/v1/lms/learn/leaf_info/'
        '${Uri.encodeQueryComponent(c.cid)}/${Uri.encodeQueryComponent(leaf.id)}/'
        '?sign=${Uri.encodeQueryComponent(c.sign)}&term=latest&uv_id=0');
    String? leafTypeId;
    if (li != null && li.statusCode == 200) {
      final data = _dataOf(li.body);
      leafTypeId = _pickString(data?['content_info'], const ['leaf_type_id']);
      due ??= firstDue(data);
    }
    if (due == null && leafTypeId != null && leafTypeId != 'null') {
      final ex = await _get('$_base/api/v1/lms/exercise/get_exercise_list/'
          '${Uri.encodeQueryComponent(leafTypeId)}/');
      if (ex != null && ex.statusCode == 200) {
        final data = _dataOf(ex.body);
        final exName = _pickString(data, const ['name', 'title']);
        if (title.isEmpty && exName != null) title = exName;
        due = firstDue(data);
      }
    }
    if (due == null) return null; // 无截止无法排提醒，跳过（雷达核心原则）
    return HomeworkItem(
      id: 'xtx_${stableHash(c.name)}_${leaf.id}',
      platform: PlatformKind.xuetangx,
      course: c.name,
      title: title.isEmpty ? '作业 ${leaf.id}' : title,
      dueAt: due,
      // 练习链路没有可信的完成状态证据（user.answer 存在与否是猜测），
      // 恒 todo；合并层对 xuetangx 与 mooc 同款保留旧状态，不打回
      status: HwStatus.todo,
    );
  }

  /// 并发拉取全部课程作业（2 路，单路间隔 0.8s，避免触发风控；与
  /// 智慧树/MOOC 同款）。
  Future<List<HomeworkItem>> allHomework({
    void Function(int done, int total)? onProgress,
  }) async {
    if (await checkLogin() != XtSessionState.ok) return [];
    final cs = await courses();
    final out = <HomeworkItem>[];
    final queue = List<XtCourse>.of(cs);
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

  // ---- 纯函数解析（公开便于单测）----

  /// 从响应体取业务负载：信封 {code,data} 取 data，裸 {data} 同样取；
  /// 都没有返回原 Map（宽松，校准期看日志再收紧）。
  static dynamic _dataOf(String body) {
    dynamic json;
    try {
      json = jsonDecode(body);
    } catch (_) {
      return null;
    }
    if (json is Map && json['data'] != null) return json['data'];
    return json;
  }

  static String? _pickString(dynamic node, List<String> keys) {
    if (node is! Map) return null;
    for (final k in keys) {
      final v = node[k];
      if (v != null && '$v'.trim().isNotEmpty) return '$v'.trim();
    }
    return null;
  }

  /// 章节树扫描：course_chapter[].section_leaf_list[].leaf_list[] 里收
  /// leaf_type==6 的叶子。全树找不到任何带 leaf_type 的叶子 = 结构陌生
  /// 返回 null（章节 API 改版/信封不同）；有类型字段但无 6 = 权威无作业。
  static XtChapterScan? parseChapterScan(String body) {
    dynamic json;
    try {
      json = jsonDecode(body);
    } catch (_) {
      return null;
    }
    if (json is! Map) return null;
    final payload = json['data'] ?? json;
    final leaves = <({String id, String name})>[];
    var sawTypedLeaf = false;
    void walkLeafLists(dynamic node) {
      if (node is List) {
        for (final e in node) {
          walkLeafLists(e);
        }
        return;
      }
      if (node is! Map) return;
      final list = node['leaf_list'];
      if (list is List) {
        for (final e in list) {
          if (e is! Map) continue;
          final type = e['leaf_type'];
          if (type == null) continue;
          sawTypedLeaf = true;
          if (type == 6 || type == '6') {
            final id = e['id'];
            if (id == null) continue;
            final name = e['name'];
            leaves.add((
              id: '$id',
              name: name is String ? name.trim() : '',
            ));
          }
        }
      }
      for (final v in node.values) {
        walkLeafLists(v);
      }
    }

    walkLeafLists(payload);
    if (!sawTypedLeaf) return null;
    return XtChapterScan(leaves);
  }

  /// 课程列表解析：在负载里递归收「有 cid 形状 + sign 形状」的对象为
  /// 课程（name 缺省用「课程 {cid}」）。product_list 条目的字段名口径
  /// 未抓包核实，cid/sign 两族键名都放宽（id/products_sign 等）；
  /// 负载里连一个数组都没有 = 形状陌生返回 null；有数组但没课程对象
  /// = 权威空列表（授权正常无课）。
  static List<XtCourse>? parseCourseListJson(String body) {
    dynamic json;
    try {
      json = jsonDecode(body);
    } catch (_) {
      return null;
    }
    var payload = json;
    if (payload is Map) payload = payload['data'] ?? payload['result'] ?? payload;
    var sawArray = false;
    final found = <XtCourse>[];
    final seen = <String>{};

    void walk(dynamic node) {
      if (node is List) {
        sawArray = true;
        for (final e in node) {
          walk(e);
        }
        return;
      }
      if (node is! Map) return;
      final cid = _pickString(node, const [
        'classroomid',
        'classroomId',
        'classroom_id',
        'cid',
        'id',
      ]);
      final sign = _pickString(node, const [
        'sign',
        'course_sign',
        'products_sign',
        'product_sign',
        'classroom_sign',
        'coursesign',
      ]);
      if (cid != null && sign != null) {
        if (seen.add('$cid#$sign')) {
          final name = _pickString(
              node, const ['name', 'course_name', 'title', 'product_name']);
          found.add(XtCourse(
              (name == null || name.isEmpty) ? '课程 $cid' : name, cid, sign));
        }
        return;
      }
      for (final v in node.values) {
        walk(v);
      }
    }

    walk(payload);
    if (!sawArray) return null;
    return found;
  }

  /// 截止时间宽松收集：DFS 找第一个键名像截止、值能解析成时间的字段。
  /// 键名口径：*deadline* / end_time / *submit_end* / hw_end*，排除 start
  /// （提交开始不是截止）。真机实证：章节叶子的截止字段是
  /// `score_deadline`（毫秒 epoch），`end_time: 0` 表示未设置。
  /// 值支持 epoch（秒/毫秒）、ISO8601、「yyyy-MM-dd HH:mm[:ss]」。
  static DateTime? firstDue(dynamic node) {
    if (node is Map) {
      for (final e in node.entries) {
        final k = '${e.key}'.toLowerCase();
        final looksDue = k.contains('deadline') ||
            k == 'endtime' ||
            k == 'end_time' ||
            k.contains('submit_end') ||
            k.contains('hw_end') ||
            (k.contains('end') && k.contains('time'));
        if (looksDue && !k.contains('start')) {
          final d = _parseTime(e.value);
          if (d != null) return d;
        }
      }
      for (final v in node.values) {
        final d = firstDue(v);
        if (d != null) return d;
      }
    } else if (node is List) {
      for (final e in node) {
        final d = firstDue(e);
        if (d != null) return d;
      }
    }
    return null;
  }

  static DateTime? _parseTime(dynamic v) {
    if (v is num) return _fromEpoch(v);
    if (v is! String) return null;
    final s = v.trim();
    if (s.isEmpty) return null;
    // 纯数字字符串当时间戳
    final n = int.tryParse(s);
    if (n != null) return _fromEpoch(n);
    final iso = DateTime.tryParse(s);
    if (iso != null) return iso;
    // yyyy-MM-dd HH:mm(:ss)
    final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})[ T](\d{2}):(\d{2})(?::(\d{2}))?$')
        .firstMatch(s);
    if (m != null) {
      return DateTime(int.parse(m.group(1)!), int.parse(m.group(2)!),
          int.parse(m.group(3)!), int.parse(m.group(4)!), int.parse(m.group(5)!),
          m.group(6) != null ? int.parse(m.group(6)!) : 0);
    }
    return null;
  }

  /// epoch 秒/毫秒 → 时间；0/负数/明显脏的小数值视为「未设置」返回 null
  /// （真机实证 end_time 常为 0，不能解析成 1970 年的假截止）。
  static DateTime? _fromEpoch(num v) {
    final ms = v >= 100000000000 ? v.toInt() : v.toInt() * 1000;
    if (ms <= 0) return null;
    return DateTime.fromMillisecondsSinceEpoch(ms);
  }
}
