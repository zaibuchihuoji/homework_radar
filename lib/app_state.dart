/// 全局应用状态。
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show ThemeMode;

import 'models/course.dart';
import 'models/homework.dart';
import 'services/notification_service.dart';
import 'services/storage.dart';
import 'services/sync_service.dart';
import 'services/timetable_widget.dart';
import 'ui/tokens.dart';

enum AccountState { notLoggedIn, ok, needRelogin }

class AppState extends ChangeNotifier {
  List<HomeworkItem> homework = [];
  List<Course> courses = [];
  AccountState chaoxingState = AccountState.notLoggedIn;
  AccountState moocState = AccountState.notLoggedIn;
  AccountState zhihuishuState = AccountState.notLoggedIn;
  AccountState xuetangxState = AccountState.notLoggedIn;
  AccountState yuketangState = AccountState.notLoggedIn;
  AccountState zfState = AccountState.notLoggedIn;
  bool syncing = false;
  DateTime? lastSync;
  String lastSyncMessage = '';
  /// 同步进度文本，如 "12/42"
  String syncProgress = '';

  /// 课表同步进度已并入抓取页流程，这里只留最近一次结果信息
  DateTime? lastTimetableSync;
  String timetableMessage = '';

  /// 外观模式：system / light / dark
  ThemeMode get themeMode => switch (Storage.themeMode()) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };

  Future<void> setThemeMode(ThemeMode mode) async {
    await Storage.saveThemeMode(mode.name);
    notifyListeners();
  }

  /// 界面样式（清夏/莫兰迪/像素/墨黑/暖纸/漫画），与深浅模式正交
  ThemeStyle get style => themeStyleFromName(Storage.uiStyle());

  Future<void> setStyle(ThemeStyle s) async {
    await Storage.saveUiStyle(s.name);
    notifyListeners();
  }

  bool get hasAnyAccount =>
      Storage.chaoxingCookie()?.isNotEmpty == true ||
      Storage.moocCookie()?.isNotEmpty == true ||
      Storage.zhihuishuCookie()?.isNotEmpty == true ||
      Storage.xuetangxCookie()?.isNotEmpty == true ||
      Storage.yuketangCookie()?.isNotEmpty == true ||
      Storage.zfCookie()?.isNotEmpty == true;

  /// 磁盘作业按 dismissedIds 过滤后的可见集——所有「读盘回填内存」的统一入口。
  /// 为什么必须过滤：隐藏名单只记 id、条目本体仍躺在 homework_json 里，
  /// 回填时直读 Storage.homework() 的话，已隐藏条目会在会话内复活，
  /// 还会经 updateHomeWidget 重新排上桌面小组件。
  List<HomeworkItem> _visibleHomework() {
    final dismissed = Storage.dismissedIds();
    return Storage.homework()
        .where((h) => !dismissed.contains(h.id))
        .toList();
  }

  Future<void> loadLocal() async {
    homework = _visibleHomework();
    courses = Storage.courses();
    chaoxingState =
        Storage.chaoxingCookie()?.isNotEmpty == true ? AccountState.ok : AccountState.notLoggedIn;
    moocState = Storage.moocCookie()?.isNotEmpty == true ? AccountState.ok : AccountState.notLoggedIn;
    zhihuishuState = Storage.zhihuishuCookie()?.isNotEmpty == true ? AccountState.ok : AccountState.notLoggedIn;
    xuetangxState = Storage.xuetangxCookie()?.isNotEmpty == true ? AccountState.ok : AccountState.notLoggedIn;
    yuketangState = Storage.yuketangCookie()?.isNotEmpty == true ? AccountState.ok : AccountState.notLoggedIn;
    zfState = Storage.zfCookie()?.isNotEmpty == true ? AccountState.ok : AccountState.notLoggedIn;
    notifyListeners();
  }

  bool _syncQueued = false;

  Future<String> syncAll() async {
    if (syncing) {
      // 同步进行中又来了同步请求（典型：刚登录成功触发）：置位排队，
      // 结束后补跑一次。直接吞掉的话新凭据本次不生效，还要手动再刷。
      _syncQueued = true;
      return '';
    }
    syncing = true;
    lastSyncMessage = '';
    syncProgress = '';
    notifyListeners();
    try {
      final result = await SyncService.run(onProgress: (done, total) {
        syncProgress = total > 0 ? '$done/$total' : '';
        notifyListeners();
      });
      homework = result.items;
      lastSync = DateTime.now();
      syncProgress = '';

      chaoxingState = Storage.chaoxingCookie()?.isNotEmpty == true
          ? (result.chaoxingValid
              ? AccountState.ok
              : (result.chaoxingUnknown
                  ? chaoxingState // 网络失败≠登录失效，保持原状态
                  : AccountState.needRelogin))
          : AccountState.notLoggedIn;
      moocState = Storage.moocCookie()?.isNotEmpty == true
          ? (result.moocValid
              ? AccountState.ok
              : (result.moocUnknown ? moocState : AccountState.needRelogin))
          : AccountState.notLoggedIn;
      zhihuishuState = Storage.zhihuishuCookie()?.isNotEmpty == true
          ? (result.zhihuishuValid
              ? AccountState.ok
              : (result.zhihuishuUnknown || result.zhihuishuSignatureRejected
                  // 签名被拒重登也过不了捕获校验：保持原状态，通知文案
                  // 已引导「可能需要更新 App」，别把用户标成需重登去反复碰壁
                  ? zhihuishuState
                  : AccountState.needRelogin))
          : AccountState.notLoggedIn;
      xuetangxState = Storage.xuetangxCookie()?.isNotEmpty == true
          ? (result.xuetangxValid
              ? AccountState.ok
              : (result.xuetangxUnknown ? xuetangxState : AccountState.needRelogin))
          : AccountState.notLoggedIn;
      yuketangState = Storage.yuketangCookie()?.isNotEmpty == true
          ? (result.yuketangValid
              ? AccountState.ok
              : (result.yuketangUnknown ? yuketangState : AccountState.needRelogin))
          : AccountState.notLoggedIn;

      lastSyncMessage = result.message;
    } finally {
      // 没有 finally 的老实现：收尾任何一步抛错都让 syncing 永久卡 true，
      // 所有同步入口（下拉刷新/按钮/回前台自动同步）静默失效直到杀进程
      syncing = false;
      notifyListeners();
    }
    if (_syncQueued) {
      _syncQueued = false;
      // 排队的那次是登录回调触发的，fire-and-forget 即可
      unawaited(syncAll());
    }
    return lastSyncMessage;
  }

  /// WebView 登录成功后回调
  Future<void> onChaoxingLogin(String cookie, String? uid) async {
    await Storage.saveChaoxing(cookie: cookie, uid: uid);
    await syncAll();
  }

  Future<void> onMoocLogin(String cookie, String csrf) async {
    await Storage.saveMooc(cookie: cookie, csrf: csrf);
    await syncAll();
  }

  Future<void> loginZhihuishu(String cookie) async {
    await Storage.saveZhihuishu(cookie: cookie);
    await syncAll();
  }

  Future<void> loginXuetangx(String cookie) async {
    await Storage.saveXuetangx(cookie: cookie);
    await syncAll();
  }

  Future<void> loginYuketang(String cookie) async {
    await Storage.saveYuketang(cookie: cookie);
    await syncAll();
  }

  Future<void> logoutChaoxing() async {
    await Storage.clearChaoxing();
    chaoxingState = AccountState.notLoggedIn;
    // 对齐 logoutZf 的退出范式：只清凭据的话，该平台的作业还挂在列表里，
    // 凭据没了也无法再同步维护，提醒与小组件里也一直清不掉
    final disk = Storage.homework()
      ..removeWhere((h) => h.platform == PlatformKind.chaoxing);
    await Storage.saveHomework(disk);
    // 隐藏名单里该平台的条目一并清掉：条目本体已删，残留的记录会让
    // 「设置 → 隐藏名单」恢复出一个永远不会再被同步清理的孤儿
    final hidden = Storage.hiddenItems()
      ..removeWhere((id, _) => id.startsWith('cx_'));
    await Storage.restoreHiddenItems(hidden);
    homework = _visibleHomework();
    await NotificationService.reschedule(homework, courses: courses);
    unawaited(SyncService.updateHomeWidget(homework));
    notifyListeners();
  }

  Future<void> logoutMooc() async {
    await Storage.clearMooc();
    moocState = AccountState.notLoggedIn;
    // 对齐 logoutZf 的退出范式，理由同 logoutChaoxing
    final disk = Storage.homework()
      ..removeWhere((h) => h.platform == PlatformKind.mooc);
    await Storage.saveHomework(disk);
    // 同 logoutChaoxing：隐藏名单里该平台的孤儿记录一并清掉
    final hidden = Storage.hiddenItems()
      ..removeWhere((id, _) => id.startsWith('mooc_'));
    await Storage.restoreHiddenItems(hidden);
    homework = _visibleHomework();
    await NotificationService.reschedule(homework, courses: courses);
    unawaited(SyncService.updateHomeWidget(homework));
    notifyListeners();
  }

  Future<void> logoutZhihuishu() async {
    await Storage.clearZhihuishu();
    zhihuishuState = AccountState.notLoggedIn;
    // 对齐 logoutZf 的退出范式，理由同 logoutChaoxing
    final disk = Storage.homework()
      ..removeWhere((h) => h.platform == PlatformKind.zhihuishu);
    await Storage.saveHomework(disk);
    // 同 logoutChaoxing：隐藏名单里该平台的孤儿记录一并清掉
    final hidden = Storage.hiddenItems()
      ..removeWhere((id, _) => id.startsWith('zhs_'));
    await Storage.restoreHiddenItems(hidden);
    homework = _visibleHomework();
    await NotificationService.reschedule(homework, courses: courses);
    unawaited(SyncService.updateHomeWidget(homework));
    notifyListeners();
  }

  Future<void> logoutXuetangx() async {
    await Storage.clearXuetangx();
    xuetangxState = AccountState.notLoggedIn;
    // 对齐 logoutZf 的退出范式，理由同 logoutChaoxing
    final disk = Storage.homework()
      ..removeWhere((h) => h.platform == PlatformKind.xuetangx);
    await Storage.saveHomework(disk);
    // 同 logoutChaoxing：隐藏名单里该平台的孤儿记录一并清掉
    final hidden = Storage.hiddenItems()
      ..removeWhere((id, _) => id.startsWith('xtx_'));
    await Storage.restoreHiddenItems(hidden);
    homework = _visibleHomework();
    await NotificationService.reschedule(homework, courses: courses);
    unawaited(SyncService.updateHomeWidget(homework));
    notifyListeners();
  }

  Future<void> logoutYuketang() async {
    await Storage.clearYuketang();
    yuketangState = AccountState.notLoggedIn;
    // 对齐 logoutZf 的退出范式，理由同 logoutChaoxing
    final disk = Storage.homework()
      ..removeWhere((h) => h.platform == PlatformKind.yuketang);
    await Storage.saveHomework(disk);
    // 同 logoutChaoxing：隐藏名单里该平台的孤儿记录一并清掉
    final hidden = Storage.hiddenItems()
      ..removeWhere((id, _) => id.startsWith('ykt_'));
    await Storage.restoreHiddenItems(hidden);
    homework = _visibleHomework();
    await NotificationService.reschedule(homework, courses: courses);
    unawaited(SyncService.updateHomeWidget(homework));
    notifyListeners();
  }

  // ---- 教务课表 ----

  /// 人工修正课程的匹配键（与 Course.editKey 同源：名字+星期+起始节次）。
  /// 不用 id——id 一旦编入周次，教务微调周次就会换 id，让修正失联。
  static String _editKey(Course c) => c.editKey;

  /// 学期文本相似判定：完全一致（忽略空白/大小写）或仅 OCR 级噪声
  /// （≤2 字符差异）视为同一学期。换学期的整表替换绝不能被一次误读
  /// 触发——「第二学期」误读成「第三学期」只有一字之差，误判会连手动
  /// 课程带人工修正整表清掉；判定宁偏「同」（少替换），真正的学年滚动
  /// 至少差 3 个字符，不会被吞。公开给测试（semester_text_test.dart）。
  static bool sameSemesterText(String a, String b) {
    String norm(String s) => s.replaceAll(RegExp(r'\s+'), '').toLowerCase();
    final x = norm(a);
    final y = norm(b);
    if (x == y) return true;
    if (x.isEmpty || y.isEmpty) return false;
    if ((x.length - y.length).abs() > 2) return false;
    return _editDistance(x, y) <= 2;
  }

  static int _editDistance(String a, String b) {
    var prev = List<int>.generate(b.length + 1, (i) => i);
    var cur = List<int>.filled(b.length + 1, 0);
    for (var i = 1; i <= a.length; i++) {
      cur[0] = i;
      for (var j = 1; j <= b.length; j++) {
        final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
        var best = prev[j] + 1;
        if (cur[j - 1] + 1 < best) best = cur[j - 1] + 1;
        if (prev[j - 1] + cost < best) best = prev[j - 1] + cost;
        cur[j] = best;
      }
      final t = prev;
      prev = cur;
      cur = t;
    }
    return prev[b.length];
  }

  /// 在列表中定位目标课程。不能按对象身份（identical）匹配：Storage.courses()
  /// 每次调用都从 JSON 重新反序列化，真实链路里拿到的是全新对象，永远失配，
  /// 会退化成按 id 连删——同 id 双胞胎（同名同槽不同周次，makeId 不含周次）
  /// 删一条变删两条（真机实测）。这里按「id+周次」字段身份匹配：双胞胎足以
  /// 区分；真重复（同 id 同周次）删哪条都等价。公开给测试。
  static int courseIndex(List<Course> list, Course target) {
    for (var i = 0; i < list.length; i++) {
      final c = list[i];
      if (c.id == target.id && _sameWeeks(c.weeks, target.weeks)) return i;
    }
    return -1;
  }

  static bool _sameWeeks(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!b.contains(a[i])) return false;
    }
    return true;
  }

  /// 合并策略：同一学期的重新抓取/导入中，用户人工修正过（edited）的课程
  /// 按匹配键优先保留；手动添加（manual_ 前缀）的课程始终追加保留。
  /// incoming 是完整课表（教务整表抓取）时以 incoming 为主干；
  /// [union] = 补课式部分导入（文本/截图/Excel 兜底）：未提及的旧课保留，
  /// 只覆盖本次导入提到的课——否则一次部分导入就把整张课表清掉。
  static List<Course> mergeEdited(
      List<Course> incoming, List<Course> existing,
      {bool union = false}) {
    final edited = {
      for (final c in existing)
        if (c.edited && !c.id.startsWith('manual_')) _editKey(c): c,
    };
    final manual = [
      for (final c in existing)
        if (c.id.startsWith('manual_')) c,
    ];
    final incomingKeys = {for (final c in incoming) _editKey(c)};
    if (!union && edited.isEmpty && manual.isEmpty) return incoming;

    // 决定每条修正由哪条 incoming 承载。匹配两轮：
    // 1) 按 incoming 的当前 key 直接查（现状行为）；
    // 2) 查不到再按修正课的 anchorKey 兜底——用户改名/挪课后重抓，incoming
    //    的 key 已对不上修正后的课，没有锚点修正会静默丢失，union 还会把
    //    旧槽位的原课 kept 成同槽双份。
    // 每条修正至多应用一次（Course 未重写 ==，Set 按对象身份判重）。
    final editedByAnchor = <String, Course>{
      for (final c in edited.values)
        if (c.anchorKey != null) c.anchorKey!: c,
    };
    final carrier = <int, Course>{}; // incoming 下标 → 承载的修正课
    final consumed = <Course>{};
    // 同 key 的 incoming 下标分组（保持出现顺序）
    final groups = <String, List<int>>{};
    for (var i = 0; i < incoming.length; i++) {
      groups.putIfAbsent(_editKey(incoming[i]), () => []).add(i);
    }
    void bind(Map<String, Course> source) {
      for (final g in groups.entries) {
        if (g.value.any(carrier.containsKey)) continue;
        final fix = source[g.key];
        if (fix == null || consumed.contains(fix)) continue;
        // 同 key 命中多条 incoming（同名同槽、endSection 不同的两节课）时，
        // 优先把修正应用到 endSection 与修正一致的那条，没有则取组内第一条；
        // 其余按普通 incoming 保留——旧行为把整组都替换成同一个修正对象，
        // 等价于把组里其余的课互相吞掉。
        final pick = g.value.firstWhere(
          (i) => incoming[i].endSection == fix.endSection,
          orElse: () => g.value.first,
        );
        carrier[pick] = fix;
        consumed.add(fix);
      }
    }

    bind(edited); // 先按当前 key 直接匹配（现状）
    bind(editedByAnchor); // 再按锚点兜底：改名/挪课后的重抓
    // 真正被某条 incoming 承载应用的修正锚点：union 的 kept 排除只看这些。
    // 若两条修正撞了同一锚点（editedByAnchor 是 map，后者覆盖前者），
    // 输掉的那条没被应用——它描述的旧课仍要 kept，否则静默丢课。
    final appliedAnchors = <String>{
      for (final f in consumed)
        if (f.anchorKey != null) f.anchorKey!,
    };
    final merged = [
      for (var i = 0; i < incoming.length; i++) carrier[i] ?? incoming[i],
    ];
    // union：保留 existing 中未被本次导入覆盖的课。去重与修正解析用
    // 「id#周次」复合键而非 editKey——单双周同槽是两条课（makeId 不含
    // 周次，本就同 id 同 key），按 editKey 折叠会把第二条静默挤掉，修正
    // 解析撞 key 还会把另一条顶替成编辑版的双份。
    // 锚点已被某条 incoming 的 key 占用**且修正已应用**的旧课不保留：
    // 那条 incoming 已按锚点承载了它的修正值，旧课再保留就是同槽双份幽灵。
    String keepKey(Course c) => '${c.id}#${c.weeks.join(",")}';
    final editedByKeepKey = <String, Course>{
      for (final c in edited.values) keepKey(c): c,
    };
    final keptKeys = <String>{};
    final kept = union
        ? [
            for (final c in existing)
              if (!c.id.startsWith('manual_') &&
                  !incomingKeys.contains(_editKey(c)) &&
                  (c.anchorKey == null ||
                      !incomingKeys.contains(c.anchorKey!) ||
                      !appliedAnchors.contains(c.anchorKey!)) &&
                  keptKeys.add(keepKey(c)))
                editedByKeepKey[keepKey(c)] ?? c,
          ]
        : const <Course>[];
    return [...merged, ...kept, ...manual];
  }

  /// 抓取/导入拿到课表后入库：保存 Cookie/学号/课程，校准周次，重排提醒。
  /// 文本/截图导入时 cookie 为 null（不覆盖已存教务登录态）。
  /// [fullImport] = 本次拿到的是一张**完整课表**（Excel/截图整表/教务抓取），
  /// 而非「贴几门课」的零散补录：同学期时不再 union 保留未提及的旧课，
  /// 手动课程与人工修正照常保留；默认 false 完全保持现状。
  Future<void> onTimetableCaptured({
    String? cookie,
    String xh = '',
    required List<Course> courses,
    required String rawPage,
    String semesterText = '',
    int? detectedWeek,
    String source = '教务',
    bool fullImport = false,
  }) async {
    if (cookie != null && cookie.isNotEmpty) {
      await Storage.saveZf(cookie: cookie, xh: xh);
      zfState = AccountState.ok;
    }
    if (courses.isEmpty) {
      timetableMessage = '教务已连上，但课表解析结果为空（可能未排课或格式陌生）';
    } else {
      // 同一学期重复导入时保留人工修正与手动课程；换学期/换学校则整体替换。
      // 「同一学期」用相似判定而非精确相等：OCR 把学期文本误读一两个字
      // （「第2学期」→「第3学期」）就触发整表替换的话，手动课程与人工
      // 修正会被无提示清掉。union 只由 fullImport 决定：零散补录
      // （fullImport=false）即使文本里带了学期行也照常 union——学期文本
      // 只参与换学期判定，不能因为贴的几门课里捎带了「2025-2026学年第X
      // 学期」就把没提到的旧课清掉。fullImport=true 是显式的整表语义：
      // 即使不带学期文本也按完整课表合并（不 union），未提及的旧课不再残留。
      final stored = Storage.timetableSemester();
      final sameSemester = stored.isEmpty ||
          semesterText.isEmpty ||
          sameSemesterText(semesterText, stored);
      final existing = Storage.courses();
      final merged = sameSemester
          ? mergeEdited(courses, existing, union: !fullImport)
          // 真正换学期的整表替换也保留手动课程：选修/体育这类教务里没有
          // 的课往往下学期还在（与退出教务不清手动课的口径一致）
          : [...courses, ...existing.where((c) => c.id.startsWith('manual_'))];
      await Storage.saveCourses(merged);
      this.courses = merged;
      timetableMessage = '课表已更新：${merged.length} 节课'
          '${source.isEmpty ? '' : ' · $source'}'
          '${semesterText.isEmpty ? '' : ' · $semesterText'}';
    }
    if (semesterText.isNotEmpty) {
      final storedSem = Storage.timetableSemester();
      final genuineChange =
          storedSem.isNotEmpty && !sameSemesterText(semesterText, storedSem);
      if (genuineChange && Storage.flag('semester_start_manual')) {
        // 换学期整体替换：上学期的手动校准标记一并作废，
        // 否则自动周次校准被永久跳过，新学期提醒排错周
        await Storage.setFlag('semester_start_manual', false);
      }
      // OCR 噪声级漂移（相似）不覆盖已存的干净学期文本；首次写入或真正
      // 换学期才落盘，避免把误读值固化成后续判定的基准
      if (genuineChange || storedSem.isEmpty) {
        await Storage.saveTimetableSemester(semesterText);
      }
    }
    if (rawPage.isNotEmpty) await Storage.saveZfRawPage(rawPage);
    // 用页面检测到的周次自动校准开学日期：
    // - 用户手动校准过（semester_start_manual）绝不覆盖；
    // - 自动校准的值允许被后续抓取重新校准——页面公告/校历里的「第N周」
    //   可能骗过首次检测，写错后周次/提醒/小组件全偏，重抓时以新页面自愈。
    final w = detectedWeek;
    if (w != null && w >= 1 && w <= 30) {
      final manualCalibrated = Storage.flag('semester_start_manual');
      if (Storage.semesterStart() == null || !manualCalibrated) {
        final now = DateTime.now();
        final monday =
            DateTime(now.year, now.month, now.day).subtract(Duration(days: now.weekday - 1));
        await Storage.saveSemesterStart(monday.subtract(Duration(days: (w - 1) * 7)));
        await Storage.setFlag('semester_start_manual', false);
      }
    }
    lastTimetableSync = DateTime.now();
    // 解析为空时本次没有动课表：提醒与小组件要按已有课表重排，
    // 不能把空列表传下去把上课提醒清光、把今日课表小组件清空。
    // 非空时也要用合并后的 this.courses 而不是原始入参——否则本次合并
    // 保留下来的手动/修正课程会被 cancelAll 从提醒与小组件里清掉。
    await NotificationService.reschedule(homework, courses: this.courses);
    await TimetableWidget.push(this.courses);
    notifyListeners();
  }

  // ---- 课表课程的手动增删改（超级课程表式）----

  /// 手动添加课程（选修课、体育课等教务里没有的）。
  Future<void> addManualCourse(Course c) async {
    final list = Storage.courses()..add(c);
    await Storage.saveCourses(list);
    courses = list;
    await NotificationService.reschedule(homework, courses: courses);
    await TimetableWidget.push(courses);
    notifyListeners();
  }

  /// 更新单条课程（课表页编辑入口；edited 标记让重抓时保留修正）。
  /// [original] 是编辑前的对象：同 id 双胞胎（不同周次）按「id+周次」
  /// 字段身份定位，找不到才退回按 id 首个命中。
  Future<void> updateCourse(Course original, Course updated) async {
    final list = Storage.courses();
    var i = courseIndex(list, original);
    if (i < 0) i = list.indexWhere((c) => c.id == updated.id);
    if (i < 0) return;
    list[i] = updated;
    await Storage.saveCourses(list);
    courses = list;
    await NotificationService.reschedule(homework, courses: courses);
    await TimetableWidget.push(courses);
    notifyListeners();
  }

  /// 删除单条课程。教务导入的课重新抓取同一学期时会回来（与超级课程表一致，
  /// 解析错误的课程应该用「编辑」修正——修正值会被保留）；手动添加的课删除后不再出现。
  /// 按「id+周次」字段身份删：同 id 双胞胎（不同周次）只删目标那条；
  /// 失配时退回按 id 兜底。
  Future<void> deleteCourse(Course target) async {
    final list = Storage.courses();
    final i = courseIndex(list, target);
    if (i >= 0) {
      list.removeAt(i);
    } else {
      list.removeWhere((c) => c.id == target.id);
    }
    await Storage.saveCourses(list);
    courses = list;
    await NotificationService.reschedule(homework, courses: courses);
    await TimetableWidget.push(courses);
    notifyListeners();
  }

  /// 备份导入后全量重载并重排提醒。
  Future<void> reloadLocal() async {
    await loadLocal();
    await NotificationService.reschedule(homework, courses: courses);
    await TimetableWidget.push(courses);
    // 作业小组件也要重推，否则换机/清数据恢复后作业组件一直显示旧机数据
    await SyncService.updateHomeWidget(homework);
  }

  /// 作息时间调整后重排上课提醒。
  Future<void> refreshClassReminders() async {
    await NotificationService.reschedule(homework, courses: courses);
    await TimetableWidget.push(courses);
    notifyListeners();
  }

  Future<void> logoutZf() async {
    await Storage.clearZf();
    // clearZf 会保留手动添加的课程，这里同步内存态
    courses = Storage.courses();
    zfState = AccountState.notLoggedIn;
    // 教务配置一并清掉：残留的话下一个用户点登录会被直接带进
    // 上一账号的学校教务页，没有重新选学校的机会
    await Storage.saveJwConfigRaw('');
    await NotificationService.reschedule(homework, courses: courses);
    await TimetableWidget.push(courses);
    notifyListeners();
  }

  /// 手动校准学期第一周的周一（自动检测不准时用）。
  /// 打上 manual 标记后，自动检测不再覆盖这个值。
  Future<void> setSemesterStart(DateTime monday) async {
    await Storage.saveSemesterStart(monday);
    await Storage.setFlag('semester_start_manual', true);
    await NotificationService.reschedule(homework, courses: courses);
    await TimetableWidget.push(courses);
    notifyListeners();
  }

  /// 修改上课提醒开关后重排。
  Future<void> updateClassReminder(bool enabled) async {
    await Storage.saveClassReminder(enabled);
    await NotificationService.reschedule(homework, courses: courses);
    notifyListeners();
  }

  /// 手动隐藏某条作业（老师撤回、不需要提交等场景）。
  Future<void> dismissHomework(HomeworkItem hw) async {
    // Dismissible 契约要求 onDismissed 当帧从树上移除：先改内存并通知，
    // 再做落盘与提醒重排——此前两次 prefs 平台通道写在移除之前，
    // 留了断言/回弹窗口
    homework = homework.where((h) => h.id != hw.id).toList();
    notifyListeners();
    await Storage.dismiss(hw.id, jsonEncode(hw.toJson()));
    await NotificationService.reschedule(homework, courses: courses);
    // 小组件与提醒共用一份列表：隐藏后不推小组件的话，
    // 已隐藏条目会一直留在桌面上
    unawaited(SyncService.updateHomeWidget(homework));
  }

  /// 恢复隐藏的作业（立即可见；下次同步因 id 已不再被隐藏而保留）。
  Future<void> restoreHomework(String id) async {
    final raw = Storage.hiddenItems()[id];
    await Storage.restoreDismissed(id);
    if (raw != null) {
      final item = HomeworkItem.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      if (!homework.any((h) => h.id == id)) {
        homework = [...homework, item]..sort((a, b) {
            final at = a.status == HwStatus.done ? 1 : 0;
            final bt = b.status == HwStatus.done ? 1 : 0;
            if (at != bt) return at - bt;
            final ad = a.dueAt, bd = b.dueAt;
            if (ad == null && bd == null) return 0;
            if (ad == null) return 1;
            if (bd == null) return -1;
            return ad.compareTo(bd);
          });
      }
      // 落库：restoreDismissed 只清隐藏名单、restore 只改内存，条目本体
      // 若已被上次同步从 homework_json 清掉（平台侧条目的常规路径），
      // 不写回的话重启/下次同步后条目消失——手动作业更是永久丢失。
      final disk = Storage.homework();
      if (!disk.any((h) => h.id == id)) {
        disk.add(item);
        await Storage.saveHomework(disk);
      }
    }
    await NotificationService.reschedule(homework, courses: courses);
    // 恢复同理要同步小组件，否则桌面还停留在「已隐藏」的旧列表
    unawaited(SyncService.updateHomeWidget(homework));
    notifyListeners();
  }

  /// 手动添加的自定义作业（同步不会删除）。
  Future<void> addManualHomework({
    required String course,
    required String title,
    DateTime? dueAt,
    String note = '',
  }) async {
    final hw = HomeworkItem(
      id: 'manual_${DateTime.now().millisecondsSinceEpoch}',
      platform: PlatformKind.manual,
      course: course,
      title: title,
      dueAt: dueAt,
      status: HwStatus.todo,
      note: note,
    );
    // 磁盘写全量（隐藏条目按存储模型继续躺在 homework_json，恢复时才有本体），
    // 内存回填走过滤后的可见集——见 _visibleHomework 的注释
    final disk = Storage.homework()..add(hw);
    await Storage.saveHomework(disk);
    homework = _visibleHomework();
    await NotificationService.reschedule(homework, courses: courses);
    unawaited(SyncService.updateHomeWidget(homework));
    notifyListeners();
  }

  Future<void> updateManualHomework(HomeworkItem hw) async {
    final disk = Storage.homework();
    final i = disk.indexWhere((h) => h.id == hw.id);
    if (i >= 0) disk[i] = hw;
    await Storage.saveHomework(disk);
    homework = _visibleHomework();
    await NotificationService.reschedule(homework, courses: courses);
    unawaited(SyncService.updateHomeWidget(homework));
    notifyListeners();
  }

  Future<void> deleteManualHomework(String id) async {
    final disk = Storage.homework()..removeWhere((h) => h.id == id);
    await Storage.saveHomework(disk);
    homework = _visibleHomework();
    await NotificationService.reschedule(homework, courses: courses);
    unawaited(SyncService.updateHomeWidget(homework));
    notifyListeners();
  }

  /// 更新作业备注（任意平台的条目都可以）。
  Future<void> updateNote(String id, String note) async {
    final disk = Storage.homework();
    final i = disk.indexWhere((h) => h.id == id);
    if (i < 0) return;
    disk[i] = disk[i].copyWith(note: note);
    await Storage.saveHomework(disk);
    homework = _visibleHomework();
    notifyListeners();
  }

  Future<void> updateReminders(ReminderSettings r) async {
    await Storage.saveReminders(r);
    await NotificationService.reschedule(homework, courses: courses);
    notifyListeners();
  }
}
