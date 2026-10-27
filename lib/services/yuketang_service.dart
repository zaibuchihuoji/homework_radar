/// 雨课堂（*.yuketang.cn / pro.yuketang.cn）作业同步服务。
///
/// 认证：纯 Cookie 会话——社区实现（yuketang-helper-auto 的作业流）实证
/// 「web 登录握手用 CSRF + 浏览器 Cookie 会话，复制 h5 的 Bearer/x-client
/// 头反而失败」，与现有 MethodChannel 取 Cookie 模式同构。
///
/// 端点（社区逆向实证，yuketang-helper 系）：
/// 1. 课程列表 `GET {origin}/v2/api/web/courses/list?identity=2`
///    → {list: [{classroom_id, role, ...}]}，官方前端 role=5 为正式学生，
///    role=6 为旁听，role=1 为教师；只同步正式选课；
/// 2. 学习日志 `GET /v2/api/web/logs/learn/{classroomId}?page=&offset=200&sort=0&actype=-1`
///    → {activities: [...]}。真机实证（2026-10-06）：考核为 type==5，
///    截止/成绩在条目顶层 deadline/score/status；社区文档形状 type==19
///    作业 / 20 考试（截止 content.score_d）保留为兜底。详见
///    parseLogActivities 注释；
/// 3. 练习进度 `GET /mooc-api/v1/lms/exercise/get_exercise_list/{leafTypeId}/`——
///    一期不拉（完成状态证据弱，恒 todo + 合并层保留旧状态，同 MOOC 口径）。
///
/// origin 多样性：普通学校走 {school}.yuketang.cn，长江雨课堂走
/// pro.yuketang.cn，主站 www.yuketang.cn——按候选 origin 顺序试，Cookie
/// 在 *.yuketang.cn 父域时一份会话到处通用（捕获时已多 origin 合并）。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../models/homework.dart';
import 'safe_http.dart';
import 'stable_hash.dart';

enum YktSessionState { ok, expired, unknown }

class YktCourse {
  final String name;
  final String classroomId;
  YktCourse(this.name, this.classroomId);
}

class YuketangService {
  String? cookie;

  YuketangService({this.cookie});

  /// 候选 API origin：主站 + 长江雨课堂（学校子域与父域 Cookie 通用）。
  static const List<String> origins = [
    'https://www.yuketang.cn',
    'https://pro.yuketang.cn',
  ];

  /// 学习日志分页：社区实证 offset=200、页码从 0 起；防御上限 20 页
  /// （4000 条活动，正常选课量远达不到）。
  static const int _logPageSize = 200;
  static const int _maxLogPages = 20;

  /// web 端特征头（社区实证）；university-id/uv-id 取自同名 Cookie，
  /// 缺省 '0'（主站个人版口径）。
  Map<String, String> get _headers {
    final c = cookie ?? '';
    String cookieField(String name) {
      final m = RegExp('(?:^|;\\s*)$name=([^;]+)').firstMatch(c);
      return m?.group(1) ?? '0';
    }

    return {
      'Cookie': SafeHttp.cookieHeader(cookie),
      'university-id': cookieField('university_id'),
      'uv-id': cookieField('uv_id'),
      'X-Client': 'web',
      'Xt-Agent': 'web',
    };
  }

  /// 请求层失败（课程列表不可达），同步层据此放弃清理旧条目。
  bool listFailed = false;

  /// 课程级失败次数（单课失败不当「没有作业」）。
  int failedCount = 0;
  final List<String> failedCourses = [];

  /// Positive non-student evidence only, after a complete scan/session check.
  /// Absence on one origin cannot prove removal on another institutional site.
  Set<String>? nonStudentClassroomScope;
  Set<String> _listedNonStudentClassrooms = {};

  /// 会话实际可用的 origin（课程列表首个成功者）；日志接口必须打同一
  /// origin——长江雨课堂用户的会话在主站不认，写死主站会让作业全挂。
  String? _activeOrigin;

  Future<http.Response?> _get(String url) =>
      SafeHttp.get(url, headers: _headers);

  /// Cookie 是否有效（问一次课程列表）。结论见 [YktSessionState]。
  YktSessionState? lastSessionState;
  Future<YktSessionState> checkLogin() async {
    final state = await _checkLogin();
    lastSessionState = state;
    return state;
  }

  Future<YktSessionState> _checkLogin() async {
    if (cookie == null || cookie!.isEmpty) return YktSessionState.expired;
    var unknown = false;
    for (final origin in origins) {
      final resp = await _get('$origin/v2/api/web/courses/list?identity=2');
      if (resp == null || resp.statusCode >= 500) {
        unknown = true;
        continue;
      }
      if (resp.statusCode == 401 || resp.statusCode == 403) {
        continue;
      }
      if (resp.statusCode == 200 && courseListOk(resp.body)) {
        _activeOrigin = origin;
        return YktSessionState.ok;
      }
      // 陌生页面、限流和未校准的业务码不是过期证据；仍尝试另一站。
      unknown = true;
    }
    return unknown ? YktSessionState.unknown : YktSessionState.expired;
  }

  /// 课程列表响应判定（公开纯函数便于单测）：JSON Map 且 list 是数组。
  static bool courseListOk(String body) {
    dynamic json;
    try {
      json = jsonDecode(body);
    } catch (_) {
      return false;
    }
    if (json is! Map || !_envelopeOk(json)) return false;
    final data = json['data'] ?? json;
    return data is Map && data['list'] is List;
  }

  /// 我的课程。首页失败置 listFailed；主站失败自动换 pro origin（长江雨
  /// 课堂口径），成功者记入 _activeOrigin。调试构建把原始响应落盘供校准。
  Future<List<YktCourse>> courses() async {
    final ordered = [
      ?_activeOrigin,
      ...origins.where((o) => o != _activeOrigin),
    ];
    for (final origin in ordered) {
      final resp = await _get('$origin/v2/api/web/courses/list?identity=2');
      if (resp == null) continue;
      if (resp.statusCode != 200) continue;
      if (kDebugMode) {
        try {
          final dir = await getApplicationDocumentsDirectory();
          final host = Uri.parse(origin).host;
          File('${dir.path}/ykt_courses_$host.json')
              .writeAsStringSync(resp.body, flush: true);
        } catch (_) {}
      }
      final parsed = _parseCourseScan(resp.body);
      if (parsed != null) {
        _activeOrigin = origin;
        _listedNonStudentClassrooms = parsed.nonStudent;
        return parsed.courses;
      }
      // 形状陌生：换下一个 origin；两个都不行在循环外落 listFailed
    }
    listFailed = true;
    return [];
  }

  /// 课程列表解析（公开纯函数便于单测）：收学生课程，名字取
  /// course_name/name/title，缺省「课程 {cid}」。list 缺失/非数组返回
  /// null（形状陌生），空数组返回空列表（授权正常无课）。
  ///
  /// Official pc client (2026-10-26): STUDENT=5, TEACHER=1, AUDITOR=6;
  /// its course card explicitly badges role 6 as auditing. Unknown/missing roles
  /// are incomplete evidence, never a reason to import all classroom roles.
  static List<YktCourse>? parseCourseList(String body) =>
      _parseCourseScan(body)?.courses;

  static ({List<YktCourse> courses, Set<String> nonStudent})? _parseCourseScan(
    String body,
  ) {
    dynamic json;
    try {
      json = jsonDecode(body);
    } catch (_) {
      return null;
    }
    if (json is! Map || !_envelopeOk(json)) return null;
    final data = json['data'] ?? json;
    if (data is! Map || data['list'] is! List) return null;
    YktCourse? fromEntry(Map e) {
      final cid = e['classroom_id'];
      if (cid == null || '$cid'.trim().isEmpty) return null;
      String? name;
      for (final k in const ['course_name', 'name', 'title']) {
        final v = e[k];
        if (v is String && v.trim().isNotEmpty) {
          name = v.trim();
          break;
        }
      }
      return YktCourse(name ?? '课程 $cid', '$cid'.trim());
    }

    final out = <YktCourse>[];
    final excluded = <String>{};
    final seen = <String>{};
    // A malformed student row must not disappear from a supposedly complete
    // course list, even when another course parsed successfully.
    for (final e in data['list'] as List) {
      if (e is! Map || fromEntry(e) == null) return null;
      if (!const [1, '1', 5, '5', 6, '6'].contains(e['role'])) return null;
    }
    for (final e in data['list'] as List) {
      if (e is! Map) continue;
      final role = e['role'];
      final c = fromEntry(e);
      if (role != 5 && role != '5') {
        if (c != null) excluded.add(c.classroomId);
        continue;
      }
      if (c != null && seen.add(c.classroomId)) out.add(c);
    }
    // Multiple role rows can refer to one classroom. Positive formal student
    // evidence must not be overridden by an alternate teacher/auditor row.
    excluded.removeAll(seen);
    return (courses: out, nonStudent: excluded);
  }

  /// 单门课程的作业/考试截止（学习日志活动流）。形状见
  /// [parseLogActivities]：type=5 顶层 deadline / type=19,20 content.score_d。
  /// 返回 null = 拉取失败（请求失败/形状陌生），与「解析到但没带截止」
  /// 区分——失败被当空的话该课旧条目会被整课清掉。
  Future<List<HomeworkItem>?> homeworkOf(YktCourse c) async {
    final out = <HomeworkItem>[];
    final seen = <String>{};
    for (var page = 0; page < _maxLogPages; page++) {
      final resp = await _get(
        '${_activeOrigin ?? origins.first}/v2/api/web/logs/learn/'
        '${Uri.encodeQueryComponent(c.classroomId)}'
        '?page=$page&offset=$_logPageSize&sort=0&actype=-1',
      );
      // 中途任何一页失败都整体返回 null：半截数据不能当权威结果，
      // 否则 complete 守卫会把没拉到的旧条目当「确认消失」清掉
      if (resp == null || resp.statusCode != 200) return null;
      if (kDebugMode) {
        try {
          final dir = await getApplicationDocumentsDirectory();
          File('${dir.path}/ykt_${c.classroomId}_p$page.json')
              .writeAsStringSync(resp.body, flush: true);
        } catch (_) {}
      }
      final parsed = parseLogActivities(
        resp.body,
        courseName: c.name,
        classroomId: c.classroomId,
      );
      if (parsed == null) return null; // 形状陌生 → 不可信结果
      var added = 0;
      for (final item in parsed) {
        if (seen.add(item.id)) {
          out.add(item);
          added++;
        }
      }
      // 短页/整页重复 = 日志拉完
      final envelope = jsonDecode(resp.body) as Map;
      final payload = envelope['data'] ?? envelope;
      final activityCount = (payload['activities'] as List).length;
      final hasMore = payload['has_more'];
      if (hasMore == false ||
          (hasMore == null && activityCount < _logPageSize)) {
        break;
      }
      if (hasMore != null && hasMore is! bool) return null;
      // Filtered-empty pages may still contain older homework on the next page.
      // Repeated nonempty homework pages cannot establish that the feed ended.
      if (parsed.isNotEmpty && added == 0) {
        failedCount++;
        return out;
      }
      if (page == _maxLogPages - 1) failedCount++;
    }
    return out;
  }

  /// 并发拉取全部课程作业（2 路，单路间隔 0.8s；与智慧树/学堂在线同款）。
  Future<List<HomeworkItem>> allHomework({
    void Function(int done, int total)? onProgress,
  }) async {
    nonStudentClassroomScope = null;
    _listedNonStudentClassrooms = {};
    if (await checkLogin() != YktSessionState.ok) {
      listFailed = true;
      return [];
    }
    final cs = await courses();
    final out = <HomeworkItem>[];
    final queue = List<YktCourse>.of(cs);
    var done = 0;

    Future<void> worker() async {
      while (queue.isNotEmpty) {
        final c = queue.removeAt(0);
        try {
          final list = await homeworkOf(c);
          if (list == null) {
            failedCourses.add('《${c.name}》作业获取未完成');
            failedCount++; // 失败不能当「没有作业」
          } else {
            out.addAll(list);
          }
        } catch (_) {
          failedCount++;
          failedCourses.add('《${c.name}》作业获取未完成');
        }
        done++;
        onProgress?.call(done, cs.length);
        await Future.delayed(const Duration(milliseconds: 800));
      }
    }

    await Future.wait([for (var i = 0; i < 2; i++) worker()]);
    final session = await checkLogin();
    if (session != YktSessionState.ok) listFailed = true;
    if (!listFailed && failedCount == 0 && session == YktSessionState.ok) {
      nonStudentClassroomScope = {..._listedNonStudentClassrooms};
    }
    return out;
  }

  // ---- 纯函数解析（公开便于单测）----

  /// 学习日志解析（公开便于单测）。
  ///
  /// 条目形状两套并存（2026-10-06 真机实证 + 社区文档）：
  /// - type=5 习题/考核（真机实证）：截止在条目顶层 `deadline`（毫秒），
  ///   status/score/total_score 也在顶层，content 为空；status==3 或带
  ///   score 视为已完成判分；
  /// - type=19 作业 / 20 考试（社区口径）：截止 content.score_d，无完成
  ///   证据恒 todo；
  /// - 其余（type=14 图文课件等教学内容）无截止概念，跳过。
  ///
  /// 返回 null 仅限「截止型条目（5/19/20）存在却一条都没解析出截止」——
  /// 字段口径可能再漂移，空列表会被合并层当权威整课清理，不能赌。
  /// 全是教学内容或 activities 为空 = 权威「本课无截止条目」，返回空列表。
  static List<HomeworkItem>? parseLogActivities(
    String body, {
    required String courseName,
    String classroomId = '',
  }) {
    dynamic json;
    try {
      json = jsonDecode(body);
    } catch (_) {
      return null;
    }
    if (json is! Map || !_envelopeOk(json)) return null;
    final data = json['data'] ?? json;
    if (data is! Map || data['activities'] is! List) return null;
    final out = <HomeworkItem>[];
    var sawDeadlineCapable = false;
    for (final raw in data['activities'] as List) {
      if (raw is! Map || raw['type'] == null) return null;
      final type = raw['type'];
      final isExamType = type == 5 || type == 20 || type == '5' || type == '20';
      final isWorkType = type == 19 || type == '19';
      if (!isExamType && !isWorkType) continue;
      sawDeadlineCapable = true;
      final content = raw['content'] is Map ? raw['content'] as Map : const {};
      final due = _dueOf(raw['deadline']) ?? _dueOf(content['score_d']);
      if (due == null) {
        return null; // Partial parse failure cannot authorize cleanup.
      }
      final id = raw['id'] ?? content['leaf_type_id'] ?? content['leaf_id'];
      if (id == null) return null;
      String? title;
      final t = raw['title'];
      if (t is String && t.trim().isNotEmpty) title = t.trim();
      final graded =
          raw['status'] == 3 || raw['status'] == '3' || raw['score'] is num;
      out.add(
        HomeworkItem(
          id: 'ykt_${stableHash(courseName)}_${type}_$id',
          platform: PlatformKind.yuketang,
          course: courseName,
          title: title ?? (isExamType ? '考试' : '作业'),
          dueAt: due,
          status: graded ? HwStatus.done : HwStatus.todo,
          sourceKey: classroomId.isEmpty ? null : 'ykt|$classroomId|$type|$id',
        ),
      );
    }
    if (sawDeadlineCapable && out.isEmpty) return null;
    return out;
  }

  // Captured production responses use errcode=0; bare envelopes are retained
  // for compatibility. An explicit error always wins over a list-shaped data.
  static bool _envelopeOk(Map json) =>
      !json.containsKey('errcode') ||
      json['errcode'] == 0 ||
      json['errcode'] == '0';

  /// score_d → 截止时间：数字（秒/毫秒，>0）或数字字符串；0/负数/解析
  /// 失败返回 null（雨课堂用 0 表示「未设置」，绝不能变 1970 假截止）。
  static DateTime? _dueOf(dynamic v) {
    if (v is! num && v is! String) return null;
    final n = v is num ? v : int.tryParse(v.trim());
    if (n == null) return null;
    final ms = n >= 100000000000 ? n.toInt() : n.toInt() * 1000;
    if (ms <= 0) return null;
    return DateTime.fromMillisecondsSinceEpoch(ms);
  }
}
