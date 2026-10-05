/// 智慧树（知到，zhihuishu.com）作业查询。
///
/// 与 mooc_service 同构：WebView 登录后捕获整串 Cookie（无需知道具体
/// Cookie 名）+ 网关接口。已验证的外部事实（来自社区逆向项目 zhihuishu-tool）：
/// - 登录是 CAS 流：passport.zhihuishu.com 登录成功后 service 跳转会在
///   *.zhihuishu.com 父域种下会话 Cookie；
/// - 课程列表网关存在：onlineservice-api.zhihuishu.com/gateway/t/v1/
///   student/course/share/queryShareCourseInfo，信封 {code: 0, message, data}，
///   code==0 即成功；
/// - 网关挂 AppInterfaceSignInterceptor：明文参数直接被拒（真机日志实证
///   code=400「aes加密参数异常」/checkSecretStr），参数必须 AES-CBC 加密
///   成 secretStr 提交，密钥组在客户端 JS 里（逆向项目已公开）。
/// 未验证：作业列表接口的具体路径与字段名——候选端点收敛在
/// [homeworkEndpoints]（待真机抓包校准），逐个尝试 + 宽松形状匹配，
/// 命中即锁定；全部失败返回 null 走 failedCount，绝不把失败当
/// 「有效空结果」清库（sync 层 complete 守卫依赖这一点）。
library;

import 'dart:convert';

import 'package:encrypt/encrypt.dart' as enc;
import 'package:http/http.dart' as http;

import '../models/homework.dart';
import 'safe_http.dart';
import 'stable_hash.dart';

class ZhsCourse {
  String name;
  String courseId;
  ZhsCourse(this.name, this.courseId);
}

/// 会话检查结论的细化：
/// - ok：网关信封成功；
/// - expired：带会话被明确拒绝（HTTP 401/403，或业务码不明时保守按过期）
///   ——重登可解；
/// - signatureRejected：网关签名校验拒收（响应含 aes 异常字样，真机日志
///   实证 code=400「aes加密参数异常」/checkSecretStr）——这是密钥组/网关
///   校验变化，重登无效，提示应指向「接口需更新」；
/// - unknown：网络层失败/网关 5xx，调用方不得据此判定「登录失效」。
enum ZhsSessionState { ok, expired, signatureRejected, unknown }

class ZhihuishuService {
  String? cookie;

  ZhihuishuService({this.cookie});

  /// 课程列表网关（社区已验证存在；分页参数名/请求体编码形态待真机抓包校准）。
  static const String _courseGateway = 'https://onlineservice-api.zhihuishu.com/'
      'gateway/t/v1/student/course/share/queryShareCourseInfo';

  /// 作业列表候选端点（**待真机抓包校准**）：share=共享课网关（社区给出过
  /// 网关风格的路径）；school=校内课网关变体（学分课作业通常在校内通道，
  /// 路径按 share 侧镜像，纯推测）。请求时按序尝试，宽松形状匹配命中
  /// （code==0/200 且 data 为数组 / data 内含数组）即锁定下标，本次会话内
  /// 后续课程直接复用；全部失败返回 null（failedCount++），绝不当作
  /// 「这门课没有作业」。
  static const List<String> homeworkEndpoints = [
    'https://onlineservice-api.zhihuishu.com/'
        'gateway/t/v1/student/work/share/queryShareCourseWorkList',
    'https://onlineservice-api.zhihuishu.com/'
        'gateway/t/v1/student/work/share/courseWorkList',
    'https://onlineservice-api.zhihuishu.com/'
        'gateway/t/v1/student/homework/share/courseWorkList',
    'https://onlineservice-api.zhihuishu.com/'
        'gateway/t/v1/student/work/school/querySchoolCourseWorkList',
    'https://onlineservice-api.zhihuishu.com/'
        'gateway/t/v1/student/work/school/courseWorkList',
    'https://onlineservice-api.zhihuishu.com/'
        'gateway/t/v1/student/homework/school/courseWorkList',
  ];

  /// 课程列表每页条数（短页即停）。
  static const int _coursePageSize = 20;

  /// 单门课程作业列表单页条数（不做作业翻页：作业数远小于课程数；
  /// 真机校准若发现单课作业超此数再补）。
  static const int _workPageSize = 50;

  /// 课程列表最大翻页数（防御性上限，正常选课数远达不到）。
  static const int _maxCoursePages = 30;

  /// 请求层失败（课程网关不可达等，供同步层决定能否清理旧条目）。
  bool listFailed = false;

  /// 课程级请求失败次数（单课失败不当「没有作业」，同步层靠它判定能否清理）。
  int failedCount = 0;

  /// 命中的作业端点下标（会话内缓存：第一个命中的课程把下标存这里，
  /// 后续课程从它开始试，不再逐个试错）。null = 本会话尚未命中。
  int? hitEndpointIndex;

  /// secretStr 的 AES 密钥组与 IV：客户端 JS 内置（社区逆向项目
  /// zhihuishu-tool 公开），共三把候选，当前网关认哪把未知——请求时
  /// 按序试错，信封 code==0 即锁定下标（[_secretKeyIndex]）。
  static const List<String> _secretKeys = [
    '7q9oko0vqb3la20r',
    'azp53h0kft7qi78q',
    'w1k5ntxecb8wmbc2',
  ];
  static const String _secretIv = '1g3qqdh4jvbskb9x';

  /// 命中的 secretStr 密钥下标（会话内缓存，语义同 hitEndpointIndex）。
  int? _secretKeyIndex;

  Map<String, String> get _headers => {
        'Cookie': SafeHttp.cookieHeader(cookie),
        'Referer': 'https://onlineweb.zhihuishu.com/',
      };

  /// 网关请求体的编码形态未核实：先按 JSON 体试（前端 axios 的常见形态），
  /// 非 200 再退回表单编码；两形态都失败才把结果交给调用方按失败处理。
  /// 参数加密（secretStr）：AES-CBC + PKCS7，base64 输出。密钥/IV 来自
  /// 客户端 JS（社区逆向项目公开），共三把候选，网关认哪把未知——调用方
  /// 按序试错后锁定下标。
  static String encryptSecret(String plain, int keyIndex) {
    var i = keyIndex;
    if (i < 0) i = 0;
    if (i >= _secretKeys.length) i = _secretKeys.length - 1;
    final encrypter = enc.Encrypter(
        enc.AES(enc.Key.fromUtf8(_secretKeys[i]), mode: enc.AESMode.cbc));
    return encrypter.encrypt(plain, iv: enc.IV.fromUtf8(_secretIv)).base64;
  }

  /// 仅供测试：校验加密形态（CBC/PKCS7/base64）可被同密钥解回。
  static String decryptSecret(String cipherB64, int keyIndex) {
    var i = keyIndex;
    if (i < 0) i = 0;
    if (i >= _secretKeys.length) i = _secretKeys.length - 1;
    final encrypter = enc.Encrypter(
        enc.AES(enc.Key.fromUtf8(_secretKeys[i]), mode: enc.AESMode.cbc));
    return encrypter.decrypt64(cipherB64, iv: enc.IV.fromUtf8(_secretIv));
  }

  /// 网关公共请求：参数 JSON → AES 加密成 secretStr 提交。
  ///
  /// 真机日志证实：表单编码 + 密钥 0 是网关接受的形态（返回 code:200），
  /// 故表单优先；JSON 编码保留作后备。密钥按序试、信封成功即锁定
  /// （[_secretKeyIndex]）；401/403 是「带会话被明确拒绝」，换密钥/编码都
  /// 不会变好，直接返回。
  Future<http.Response?> _gatewayPost(
      String url, Map<String, String> params) async {
    http.Response? last;
    for (final useForm in const [true, false]) {
      for (final ki in endpointTryOrder(_secretKeyIndex)) {
        final plain = jsonEncode({
          ...params,
          // 逆向项目里网关请求普遍携带 UTC 时间戳，放进加密体防重放
          'date': DateTime.now().toUtc().toIso8601String(),
        });
        final secret = encryptSecret(plain, ki);
        final resp = useForm
            ? await SafeHttp.postForm(
                url, body: {'secretStr': secret}, headers: _headers)
            : await SafeHttp.postJson(
                url, body: jsonEncode({'secretStr': secret}), headers: _headers);
        if (resp == null) return null; // 网络失败，上层按 unknown 处理
        last = resp;
        if (resp.statusCode == 401 || resp.statusCode == 403) return resp;
        if (resp.statusCode == 200 && envelopeOk(resp.body)) {
          _secretKeyIndex = ki;
          return resp;
        }
      }
    }
    return last;
  }

  /// Cookie 是否有效（问一次课程网关第 1 页），结论见 [ZhsSessionState]。
  Future<ZhsSessionState> checkLogin() async {
    if (cookie == null || cookie!.isEmpty) return ZhsSessionState.expired;
    final resp =
        await _gatewayPost(_courseGateway, {'pageIndex': '1', 'pageSize': '1'});
    if (resp == null) return ZhsSessionState.unknown; // 网络失败 ≠ 登录过期
    if (resp.statusCode == 401 || resp.statusCode == 403) {
      return ZhsSessionState.expired;
    }
    if (resp.statusCode != 200) return ZhsSessionState.unknown; // 网关抖动 ≠ 登录失效
    if (envelopeOk(resp.body)) return ZhsSessionState.ok;
    // 真机日志实证：密钥/签名被拒时网关回 200 + code=400 +「aes加密参数
    // 异常」（拦截器 checkSecretStr）。据此与会话失效分开——这不是重新
    // 登录能解决的问题。其余业务码语义未抓包核实，保守沿用「过期」口径。
    return signatureRejectedBody(resp.body)
        ? ZhsSessionState.signatureRejected
        : ZhsSessionState.expired;
  }

  /// 响应体是否为网关签名校验拒收（公开纯函数便于单测）。匹配已知实证
  /// 字样：aes 加解密异常（大小写不敏感）与拦截器名 checkSecretStr。
  static bool signatureRejectedBody(String body) {
    final lower = body.toLowerCase();
    return (lower.contains('aes') && body.contains('异常')) ||
        lower.contains('checksecretstr');
  }

  /// 信封判定（公开纯函数便于单测）：code==0 视为成功。
  /// code 可能序列化成数字 0 或字符串 "0"（网关版本口径不一），都认。
  static bool envelopeOk(String body) {
    try {
      final json = jsonDecode(body);
      return json is Map && _codeOk(json['code']);
    } catch (_) {
      return false;
    }
  }

  /// 成功码：真机日志证实 onlineservice-api 网关的成功信封是
  /// `{code: 200, result: ...}`（不是逆向项目里其他网关的 code==0），
  /// 两种都认，兼容不同子网关。
  static bool _codeOk(dynamic code) =>
      code is num ? code == 0 || code == 200 : code == '0' || code == '200';

  /// 我学的课程（翻页拉全：短页即停；若网关忽略分页参数，靠「整页全是
  /// 已见 id」兜底停翻，避免白打几十页重复请求）。
  Future<List<ZhsCourse>> courses() async {
    final found = <ZhsCourse>[];
    final seen = <String>{};
    for (var page = 1; page <= _maxCoursePages; page++) {
      final resp = await _gatewayPost(
          _courseGateway, {'pageIndex': '$page', 'pageSize': '$_coursePageSize'});
      if (resp == null || resp.statusCode != 200) {
        // 拿不到响应 ≠ 没有课程：置 listFailed，同步层据此放弃清理旧条目
        listFailed = true;
        return found;
      }
      final pageCourses = parseCourseListJson(resp.body);
      if (pageCourses == null) {
        // 信封被拒（code!=0/形状陌生）：page 1 说明整体不可用置 listFailed；
        // page>1 被拒绝不能当「短页=最后一页」，否则 complete 误真、
        // 后续页课程的旧条目会被清掉
        listFailed = true;
        break;
      }
      found.addAll(pageCourses);
      final before = seen.length;
      for (final c in pageCourses) {
        seen.add(c.courseId);
      }
      if (pageCourses.length < _coursePageSize) break; // 短页 = 最后一页
      if (seen.length == before) break; // 整页重复 = 网关忽略分页
    }
    // 解析较宽松，同一课程对象可能在不同嵌套层被收多次，按课去重
    final used = <String>{};
    return [
      for (final c in found)
        if (used.add(c.courseId)) c,
    ];
  }

  /// 课程列表解析（公开纯函数便于单测）：信封 code==0 后在 data 里宽松
  /// 收集「有 courseName/name/title + courseId」的课程对象——网关返回的
  /// 嵌套结构（data.list / data.records / 分页包装）未经真机核实，走遍历
  /// 兜底。必须有 courseId 才认：纯 {name, id} 的对象（教师/章节等）会
  /// 被误收成「课程」，后续按它查作业只会白耗失败数。
  /// 返回 null = 信封被拒（code!=0）或形状陌生。翻页据此置 listFailed：
  /// 绝不能把拒绝当「短页=最后一页」，否则多页课表在第 2 页被拒时
  /// complete 误真，后续页课程的旧条目会被整批清掉。
  static List<ZhsCourse>? parseCourseListJson(String body) {
    dynamic json;
    try {
      json = jsonDecode(body);
    } catch (_) {
      return null;
    }
    if (json is! Map || !_codeOk(json['code'])) return null;
    // 成功负载在 result（真机实证：result.totalCount + result.courseOpenDtos），
    // 兼容 data；都没有视为「授权正常但没有列表」→ 空列表而非失败
    final payload = json['data'] ?? json['result'];
    if (payload == null) return const <ZhsCourse>[];
    final out = <ZhsCourse>[];
    _walkForCourses(payload, out);
    return out;
  }

  static void _walkForCourses(dynamic node, List<ZhsCourse> out) {
    if (node is List) {
      for (final e in node) {
        _walkForCourses(e, out);
      }
      return;
    }
    if (node is Map) {
      final name = node['courseName'] ?? node['name'] ?? node['title'];
      // courseOpenDtos 命名说明智慧树课程 id 叫 courseOpenId（recruitId 是
      // 开课批次，同名多批次会撞，不收）
      final id = node['courseId'] ?? node['courseOpenId'];
      if (name is String &&
          name.trim().isNotEmpty &&
          id != null &&
          '$id'.trim().isNotEmpty) {
        out.add(ZhsCourse(name.trim(), '$id'.trim()));
        return;
      }
      for (final v in node.values) {
        _walkForCourses(v, out);
      }
    }
  }

  /// 候选端点尝试顺序（公开纯函数便于单测）：已锁定下标优先，其余按原序；
  /// 越界/未锁定按原始顺序。
  static List<int> endpointTryOrder(int? hitIndex) {
    final order = [for (var i = 0; i < homeworkEndpoints.length; i++) i];
    if (hitIndex != null && hitIndex >= 0 && hitIndex < order.length) {
      order.remove(hitIndex);
      order.insert(0, hitIndex);
    }
    return order;
  }

  /// 单门课程的作业列表。返回 null = 「没拉到」（候选端点全部失败），
  /// 与「拉到了但这门课没有作业」（空列表）区分——失败被当空的话，
  /// 同步层会把该课已入库作业连同提醒整课清掉（见 mooc_service 同名注释）。
  Future<List<HomeworkItem>?> homeworkOf(ZhsCourse c) async {
    for (final i in endpointTryOrder(hitEndpointIndex)) {
      final resp = await _gatewayPost(homeworkEndpoints[i], {
        // 参数名双保险：课程 id 实际取自 courseOpenDtos（字段名
        // courseOpenId），作业端点认哪个参数名未抓包核实——两个名都带上，
        // 网关各取所需（整个参数包要 AES 加密成 secretStr，多余键无副作用）
        'courseId': c.courseId,
        'courseOpenId': c.courseId,
        'pageIndex': '1',
        'pageSize': '$_workPageSize',
      });
      if (resp == null || resp.statusCode != 200) continue; // 请求层失败：换候选
      final items = parseWorkListJson(resp.body, courseName: c.name);
      if (items != null) {
        // 命中即锁定：本次会话内后续课程不再逐个试错
        hitEndpointIndex = i;
        return items;
      }
    }
    return null;
  }

  /// 作业列表解析（公开纯函数便于单测）。宽松形状匹配：
  /// - 信封 code==0；data 直接是数组，或 data 是 Map 时取其值里第一个
  ///   全对象数组（data.list / data.records / data.rows 等分页命名统统能接）；
  /// - 条目字段：标题 title/workName/name、截止 endTime/submitEndTime/
  ///   deadline/limitTime（yyyy-MM-dd HH:mm 与 ISO 都认，兼容毫秒时间戳）、
  ///   标识 workId/homeworkId/id、完成状态（布尔/字符串可识别才算；
  ///   数值型 status 的语义各端点不一，未抓包核实前不猜——误标已交会把
  ///   作业从雷达里藏掉，宁可全按未完成展示）；
  /// - 无截止时间的条目跳过：作业雷达以截止提醒为核心，无截止无法排提醒，
  ///   也让错误端点的垃圾响应更难凑成「有效列表」。
  /// 返回 null = 响应不是作业列表（code!=0 / 非 JSON / 无数组形状），
  /// 候选端点链据此换下一个；空列表 = 有效响应、无可展示条目。
  static List<HomeworkItem>? parseWorkListJson(
    String body, {
    required String courseName,
  }) {
    dynamic json;
    try {
      json = jsonDecode(body);
    } catch (_) {
      return null;
    }
    if (json is! Map || !_codeOk(json['code'])) return null;
    // 成功负载在 result（同课程网关），兼容 data
    final entries = _extractEntries(json['data'] ?? json['result']);
    if (entries == null) return null;
    final out = <HomeworkItem>[];
    final seen = <String>{};
    for (final e in entries) {
      final due = _firstDue(e);
      if (due == null) continue; // 无截止时间的条目跳过（理由见上）
      final title = _firstString(
          e, const ['title', 'workName', 'name', 'homeworkName', 'workTitle']);
      final wid = _firstString(e, const ['workId', 'homeworkId', 'id']) ??
          // 无显式 id：标题+截止的稳定哈希兜底（id 稳定性口径见 stable_hash）
          '${stableHash('$title|${due.millisecondsSinceEpoch}')}';
      if (!seen.add(wid)) continue; // 同课同 id 去重：重复条目会重复排提醒
      out.add(HomeworkItem(
        id: 'zhs_${stableHash(courseName)}_$wid',
        platform: PlatformKind.zhihuishu,
        course: courseName,
        title: (title == null || title.isEmpty) ? '作业 $wid' : title,
        dueAt: due,
        status: _statusOf(e),
      ));
    }
    // 条目存在却一条可用截止都没有：多半是字段名没对上（候选端点与字段
    // 尚未抓包校准）。返回 null（不可信结果 → failedCount++）而不是权威
    // 空列表——空列表 + complete 守卫会把该课程旧条目整批清掉
    if (entries.isNotEmpty && out.isEmpty) return null;
    return out;
  }

  /// 从 data 里取条目数组：data 本身是数组，或 data 是 Map 时其值里
  /// 第一个「全对象数组」。数组元素混入非对象 → 形状陌生，返回 null。
  static List<Map<String, dynamic>>? _extractEntries(dynamic data) {
    if (data is List) return _asMaps(data);
    if (data is Map) {
      for (final v in data.values) {
        if (v is List) {
          final maps = _asMaps(v);
          if (maps != null) return maps;
        }
      }
    }
    return null;
  }

  static List<Map<String, dynamic>>? _asMaps(List raw) {
    if (raw.isEmpty) return const []; // 空数组是合法的「这门课没有作业」
    final out = <Map<String, dynamic>>[];
    for (final e in raw) {
      if (e is! Map) return null;
      out.add(Map<String, dynamic>.from(e));
    }
    return out;
  }

  static DateTime? _firstDue(Map<String, dynamic> e) {
    for (final k in const ['endTime', 'submitEndTime', 'deadline', 'limitTime']) {
      if (!e.containsKey(k)) continue;
      final d = _parseTime(e[k]);
      if (d != null) return d;
    }
    return null;
  }

  static DateTime? _parseTime(dynamic v) {
    if (v is num) {
      // 毫秒时间戳（网关常见口径）；10 位按秒换算
      final ms = v >= 100000000000 ? v.toInt() : v.toInt() * 1000;
      // 秒级小数值可能是「时长」语义（如 limitTime=5400 秒），落进 1970：
      // 课表截止不可能早于 2000 年，早于即视为不是时刻
      if (ms < 946684800000) return null;
      return DateTime.fromMillisecondsSinceEpoch(ms);
    }
    if (v is! String) return null;
    final s = v.trim();
    if (s.isEmpty) return null;
    // ISO 8601（含带时区偏移的）交给 SDK 解析，Z 结尾归一到本地时区；
    // SDK 吃不下时再按「yyyy-MM-dd HH:mm」手工解（兜底主格式，
    // 不赌 SDK 对无秒时刻的语法容忍度）
    final iso = DateTime.tryParse(s);
    if (iso != null) return iso.toLocal();
    final m = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})[ T](\d{1,2}):(\d{1,2})')
        .firstMatch(s);
    if (m != null) {
      return DateTime(
        int.parse(m.group(1)!),
        int.parse(m.group(2)!),
        int.parse(m.group(3)!),
        int.parse(m.group(4)!),
        int.parse(m.group(5)!),
      );
    }
    return null;
  }

  static String? _firstString(Map<String, dynamic> e, List<String> keys) {
    for (final k in keys) {
      final v = e[k];
      if (v == null) continue;
      final s = '$v'.trim();
      if (s.isNotEmpty) return s;
    }
    return null;
  }

  /// 完成状态：布尔/字符串可识别才映射，默认 todo（口径见 parseWorkListJson）。
  static HwStatus _statusOf(Map<String, dynamic> e) {
    for (final k in const ['submitted', 'isSubmit']) {
      if (_truthy(e[k])) return HwStatus.submitted;
    }
    for (final k in const ['finished', 'isFinished', 'completed', 'isCompleted']) {
      if (_truthy(e[k])) return HwStatus.done;
    }
    final s = _firstString(e, const ['status', 'workStatus', 'submitStatus']);
    if (s != null) {
      final lower = s.toLowerCase();
      // 方向性保护：unsubmitted / not_submitted 含 submit 子串，先判负向，
      // 否则会把「未提交」误标成已提交、把作业从雷达里藏掉
      if (lower.contains('unsubmit') ||
          lower.startsWith('not') ||
          lower.contains('未提交')) {
        return HwStatus.todo;
      }
      if (lower.contains('submit')) return HwStatus.submitted;
      if (lower.contains('done') ||
          lower.contains('finish') ||
          lower.contains('complete')) {
        return HwStatus.done;
      }
    }
    return HwStatus.todo;
  }

  static bool _truthy(dynamic v) => v == true || v == 1 || v == '1' || v == 'true';

  /// 并发拉取全部课程作业（2 路，单路间隔 0.8s，避免触发风控；与 mooc 同款）。
  Future<List<HomeworkItem>> allHomework({
    void Function(int done, int total)? onProgress,
  }) async {
    if (await checkLogin() != ZhsSessionState.ok) return [];
    final cs = await courses();
    final out = <HomeworkItem>[];
    final queue = List<ZhsCourse>.of(cs);
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
