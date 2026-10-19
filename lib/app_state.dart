/// 全局应用状态。
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show ThemeMode;

import 'models/course.dart';
import 'models/homework.dart';
import 'models/homework_draft.dart';
import 'services/homework_duplicates.dart';
import 'services/notification_service.dart';
import 'services/jw_config.dart';
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
    await Storage.waitForBusinessTransaction();
    await Storage.saveThemeMode(mode.name);
    notifyListeners();
  }

  /// 界面样式（清夏/莫兰迪/像素/墨黑/暖纸/漫画），与深浅模式正交
  ThemeStyle get style => themeStyleFromName(Storage.uiStyle());

  Future<void> setStyle(ThemeStyle s) async {
    await Storage.waitForBusinessTransaction();
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
    return Storage.homework().where((h) => !dismissed.contains(h.id)).toList();
  }

  /// Publish committed records without waiting for notification I/O. A slow or
  /// failed reminder queue must not leave deleted/hidden work on the desktop.
  Future<void> _refreshHomeworkOutputs() async {
    final visible = _visibleHomework();
    await Future.wait([
      SyncService.updateHomeWidget(visible),
      NotificationService.reschedule(visible, courses: courses),
    ]);
  }

  Future<void> loadLocal() async {
    homework = _visibleHomework();
    courses = Storage.courses();
    chaoxingState = Storage.chaoxingCookie()?.isNotEmpty == true
        ? AccountState.ok
        : AccountState.notLoggedIn;
    moocState = Storage.moocCookie()?.isNotEmpty == true
        ? AccountState.ok
        : AccountState.notLoggedIn;
    zhihuishuState = Storage.zhihuishuCookie()?.isNotEmpty == true
        ? AccountState.ok
        : AccountState.notLoggedIn;
    xuetangxState = Storage.xuetangxCookie()?.isNotEmpty == true
        ? AccountState.ok
        : AccountState.notLoggedIn;
    yuketangState = Storage.yuketangCookie()?.isNotEmpty == true
        ? AccountState.ok
        : AccountState.notLoggedIn;
    zfState = Storage.zfCookie()?.isNotEmpty == true
        ? AccountState.ok
        : AccountState.notLoggedIn;
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
      final result = await SyncService.run(
        onProgress: (done, total) {
          syncProgress = total > 0 ? '$done/$total' : '';
          notifyListeners();
        },
      );
      homework = _visibleHomework();
      if (result.cancelled || result.generation != Storage.syncEpoch) {
        if (hasAnyAccount) _syncQueued = true;
      } else {
        if (!result.partial) lastSync = DateTime.now();
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
                  : (result.zhihuishuUnknown ||
                            result.zhihuishuSignatureRejected
                        // 签名被拒重登也过不了捕获校验：保持原状态，通知文案
                        // 已引导「可能需要更新 App」，别把用户标成需重登去反复碰壁
                        ? zhihuishuState
                        : AccountState.needRelogin))
            : AccountState.notLoggedIn;
        xuetangxState = Storage.xuetangxCookie()?.isNotEmpty == true
            ? (result.xuetangxValid
                  ? AccountState.ok
                  : (result.xuetangxUnknown
                        ? xuetangxState
                        : AccountState.needRelogin))
            : AccountState.notLoggedIn;
        yuketangState = Storage.yuketangCookie()?.isNotEmpty == true
            ? (result.yuketangValid
                  ? AccountState.ok
                  : (result.yuketangUnknown
                        ? yuketangState
                        : AccountState.needRelogin))
            : AccountState.notLoggedIn;

        lastSyncMessage = result.message;
      }
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
  Future<void> _prepareAccountLogin(
    PlatformKind platform,
    String cookie, {
    String? uid,
  }) async {
    Storage.invalidateSync();
    final old = switch (platform) {
      PlatformKind.chaoxing => Storage.chaoxingCookie(),
      PlatformKind.mooc => Storage.moocCookie(),
      PlatformKind.zhihuishu => Storage.zhihuishuCookie(),
      PlatformKind.xuetangx => Storage.xuetangxCookie(),
      PlatformKind.yuketang => Storage.yuketangCookie(),
      PlatformKind.manual => null,
    };
    final sameUid =
        platform == PlatformKind.chaoxing &&
        uid != null &&
        uid.isNotEmpty &&
        uid == Storage.chaoxingUid();
    if (old != cookie && !sameUid) {
      await Storage.archivePlatform(platform);
    }
  }

  Future<void> _commitAccountLogin(
    PlatformKind platform,
    String cookie,
    Future<void> Function() save, {
    String? uid,
  }) async {
    await Storage.businessTransaction(() async {
      await _prepareAccountLogin(platform, cookie, uid: uid);
      await save();
    }, credentials: true);
    await loadLocal();
  }

  Future<void> onChaoxingLogin(
    String cookie,
    String? uid, {
    bool sync = true,
  }) async {
    await _commitAccountLogin(
      PlatformKind.chaoxing,
      cookie,
      () => Storage.saveChaoxing(cookie: cookie, uid: uid),
      uid: uid,
    );
    if (sync) await syncAll();
  }

  Future<void> onMoocLogin(
    String cookie,
    String csrf, {
    bool sync = true,
  }) async {
    await _commitAccountLogin(
      PlatformKind.mooc,
      cookie,
      () => Storage.saveMooc(cookie: cookie, csrf: csrf),
    );
    if (sync) await syncAll();
  }

  Future<void> loginZhihuishu(String cookie, {bool sync = true}) async {
    await _commitAccountLogin(
      PlatformKind.zhihuishu,
      cookie,
      () => Storage.saveZhihuishu(cookie: cookie),
    );
    if (sync) await syncAll();
  }

  Future<void> loginXuetangx(String cookie, {bool sync = true}) async {
    await _commitAccountLogin(
      PlatformKind.xuetangx,
      cookie,
      () => Storage.saveXuetangx(cookie: cookie),
    );
    if (sync) await syncAll();
  }

  Future<void> loginYuketang(String cookie, {bool sync = true}) async {
    await _commitAccountLogin(
      PlatformKind.yuketang,
      cookie,
      () => Storage.saveYuketang(cookie: cookie),
    );
    if (sync) await syncAll();
  }

  Future<void> _logoutPlatform(
    PlatformKind platform,
    Future<void> Function() clear,
  ) async {
    await Storage.businessTransaction(() async {
      await Storage.archivePlatform(platform);
      await clear();
    }, credentials: true);
    await loadLocal();
    await _refreshHomeworkOutputs();
  }

  Future<void> logoutChaoxing() =>
      _logoutPlatform(PlatformKind.chaoxing, Storage.clearChaoxing);
  Future<void> logoutMooc() =>
      _logoutPlatform(PlatformKind.mooc, Storage.clearMooc);
  Future<void> logoutZhihuishu() =>
      _logoutPlatform(PlatformKind.zhihuishu, Storage.clearZhihuishu);
  Future<void> logoutXuetangx() =>
      _logoutPlatform(PlatformKind.xuetangx, Storage.clearXuetangx);
  Future<void> logoutYuketang() =>
      _logoutPlatform(PlatformKind.yuketang, Storage.clearYuketang);
  // ---- 教务课表 ----

  /// 人工修正课程的匹配键（与 Course.editKey 同源：名字+星期+起始节次）。
  /// 不用 id——id 一旦编入周次，教务微调周次就会换 id，让修正失联。
  static String _editKey(Course c) => c.editKey;

  /// 只规范化明确的书写/OCR差异；学年与学期数字不同不能视为同一归属。
  static bool sameSemesterText(String a, String b) {
    String norm(String s) => s
        .replaceAll(RegExp(r'\s+'), '')
        .toLowerCase()
        .replaceAllMapped(RegExp(r'(?<=\d)o(?=\d)'), (_) => '0')
        .replaceAll('第一学期', '第1学期')
        .replaceAll('第二学期', '第2学期')
        .replaceAll('第三学期', '第3学期')
        .replaceAll('第四学期', '第4学期');
    final x = norm(a);
    final y = norm(b);
    if (x == y) return true;
    if (x.isEmpty || y.isEmpty) return false;
    final term = RegExp(r'第([1-4])学期');
    final tx = term.firstMatch(x)?.group(1), ty = term.firstMatch(y)?.group(1);
    if (tx != null && ty != null && tx != ty) return false;
    final years = RegExp(r'\d{4}[-–—]\d{4}');
    final ax = years.firstMatch(x)?.group(0),
        ay = years.firstMatch(y)?.group(0);
    if (ax != null && ay != null && ax != ay) return false;
    // 无法确认归属时不按相似度套用旧修正；默认导入是补充，不会清旧课。
    return false;
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
    List<Course> incoming,
    List<Course> existing, {
    bool union = false,
  }) {
    final edited = existing
        .where((c) => c.edited && !c.id.startsWith('manual_'))
        .toList();
    final manual = existing.where((c) => c.id.startsWith('manual_')).toList();
    if (!union && edited.isEmpty && manual.isEmpty) return incoming;
    final consumed = <Course>{};
    final merged = <Course>[];
    for (final next in incoming) {
      if (next.edited) {
        // 本次预览的明确输入优先于上一次的修正。
        merged.add(next);
        continue;
      }
      var candidates = edited
          .where(
            (old) =>
                !consumed.contains(old) &&
                (_editKey(old) == _editKey(next) ||
                    old.anchorKey == _editKey(next)),
          )
          .toList();
      final sameWeeks = candidates
          .where((c) => _sameWeeks(c.weeks, next.weeks))
          .toList();
      if (sameWeeks.isNotEmpty) candidates = sameWeeks;
      final sameEnd = candidates
          .where((c) => c.endSection == next.endSection)
          .toList();
      if (sameEnd.isNotEmpty) candidates = sameEnd;
      // 身份仍有歧义时不能把某条修正随意套在另一个单双周课程上。
      final fix = candidates.length == 1 ? candidates.single : null;
      merged.add(fix ?? next);
      if (fix != null) consumed.add(fix);
    }
    String keepKey(Course c) =>
        '${c.id}#${(c.weeks.toList()..sort()).join(",")}';
    final kept = <String, Course>{};
    if (union) {
      for (final old in existing) {
        if (old.id.startsWith('manual_') || consumed.contains(old)) continue;
        final oldGroup = existing
            .where((c) => _editKey(c) == _editKey(old))
            .length;
        final covered = incoming.any((n) {
          if (n.edited && n.id == old.id && _sameWeeks(n.weeks, old.weeks)) {
            return true;
          }
          if (_editKey(n) != _editKey(old) && n.anchorKey != _editKey(old)) {
            return false;
          }
          return _sameWeeks(n.weeks, old.weeks) || oldGroup == 1;
        });
        if (covered || merged.any((n) => keepKey(n) == keepKey(old))) continue;
        final key = keepKey(old);
        if (!kept.containsKey(key) || old.edited) kept[key] = old;
      }
    }
    return [...merged, ...kept.values, ...manual];
  }

  /// 抓取/导入拿到课表后入库：保存 Cookie/学号/课程，校准周次，重排提醒。
  /// 文本/截图导入时 cookie 为 null（不覆盖已存教务登录态）。
  /// [fullImport] = 本次拿到的是一张**完整课表**（Excel/截图整表/教务抓取），
  /// 而非「贴几门课」的零散补录：同学期时不再 union 保留未提及的旧课，
  /// 手动课程与人工修正照常保留；默认 false 完全保持现状。
  bool timetableRequiresReplacement({
    String xh = '',
    String semesterText = '',
  }) {
    final config = JwConfig.decode(Storage.jwConfigRaw() ?? '');
    final host = Uri.tryParse(config?.url ?? '')?.host.toLowerCase() ?? '';
    final previous = Storage.timetableSource();
    final oldXh = Storage.zfXh() ?? '';
    return (host.isNotEmpty &&
            previous.isNotEmpty &&
            (host != previous.split('#').first ||
                (xh.isNotEmpty &&
                    previous.contains('#') &&
                    '$host#$xh' != previous))) ||
        (xh.isNotEmpty && oldXh.isNotEmpty && xh != oldXh) ||
        (semesterText.isNotEmpty &&
            Storage.timetableSemester().isNotEmpty &&
            !sameSemesterText(semesterText, Storage.timetableSemester()));
  }

  List<Course> timetableReplacement(
    List<Course> selected, {
    String xh = '',
    String semesterText = '',
  }) {
    final existing = Storage.courses();
    return timetableRequiresReplacement(xh: xh, semesterText: semesterText)
        ? [...selected, ...existing.where((c) => c.id.startsWith('manual_'))]
        : mergeEdited(selected, existing, union: false);
  }

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
    var nextMessage = '';
    await Storage.businessTransaction(() async {
      final config = JwConfig.decode(Storage.jwConfigRaw() ?? '');
      final nextHost =
          Uri.tryParse(config?.url ?? '')?.host.toLowerCase() ?? '';
      final previousXh = Storage.zfXh() ?? '';
      final nextXh = xh.isNotEmpty ? xh : previousXh;
      final nextSource = nextHost.isEmpty ? '' : '$nextHost#$nextXh';
      final previousSource = Storage.timetableSource();
      final sourceChanged =
          (nextSource.isNotEmpty &&
              previousSource.isNotEmpty &&
              (nextHost != previousSource.split('#').first ||
                  (previousSource.contains('#') &&
                      nextSource != previousSource))) ||
          (xh.isNotEmpty && previousXh.isNotEmpty && xh != previousXh);
      final previousSemester = Storage.timetableSemester();
      final semesterChanged =
          semesterText.isNotEmpty &&
          previousSemester.isNotEmpty &&
          !sameSemesterText(semesterText, previousSemester);
      if (!fullImport &&
          Storage.courses().isNotEmpty &&
          (sourceChanged || semesterChanged)) {
        throw const FormatException('检测到学校或学期变化。为避免混入旧课，请确认整表替换；原课表尚未更改。');
      }
      if (courses.isEmpty && (sourceChanged || semesterChanged)) {
        throw const FormatException('学校或学期已变化，但未取得有效课程；原账号和课表尚未更改。');
      }
      if (cookie != null && cookie.isNotEmpty) {
        await Storage.saveZf(cookie: cookie, xh: xh);
      }
      if (courses.isEmpty) {
        nextMessage = '教务已连上，但课表解析结果为空（可能未排课或格式陌生）';
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
        final sameSemester =
            !sourceChanged &&
            (stored.isEmpty ||
                semesterText.isEmpty ||
                sameSemesterText(semesterText, stored));
        final existing = Storage.courses();
        if (fullImport) await Storage.archiveCourses();
        final merged = sameSemester
            ? mergeEdited(courses, existing, union: !fullImport)
            // 真正换学期的整表替换也保留手动课程：选修/体育这类教务里没有
            // 的课往往下学期还在（与退出教务不清手动课的口径一致）
            : [
                ...courses,
                ...existing.where((c) => c.id.startsWith('manual_')),
              ];
        await Storage.saveCourses(merged);
        nextMessage =
            '课表已更新：${merged.length} 节课'
            '${source.isEmpty ? '' : ' · $source'}'
            '${semesterText.isEmpty ? '' : ' · $semesterText'}';
      }
      if (semesterText.isNotEmpty) {
        final storedSem = Storage.timetableSemester();
        final genuineChange =
            storedSem.isNotEmpty && !sameSemesterText(semesterText, storedSem);
        if (genuineChange) {
          // 换学期整体替换：上学期的手动校准标记一并作废，
          // 否则自动周次校准被永久跳过，新学期提醒排错周
          await Storage.setFlag('semester_start_manual', false);
          await Storage.clearSemesterStart();
        }
        // OCR 噪声级漂移（相似）不覆盖已存的干净学期文本；首次写入或真正
        // 换学期才落盘，避免把误读值固化成后续判定的基准
        if (genuineChange || storedSem.isEmpty) {
          await Storage.saveTimetableSemester(semesterText);
        }
      }
      if (rawPage.isNotEmpty) await Storage.saveZfRawPage(rawPage);
      if (nextSource.isNotEmpty) await Storage.saveTimetableSource(nextSource);
      if (sourceChanged) {
        await Storage.setFlag('semester_start_manual', false);
        await Storage.clearSemesterStart();
      }
      // 用页面检测到的周次自动校准开学日期：
      // - 用户手动校准过（semester_start_manual）绝不覆盖；
      // - 自动校准的值允许被后续抓取重新校准——页面公告/校历里的「第N周」
      //   可能骗过首次检测，写错后周次/提醒/小组件全偏，重抓时以新页面自愈。
      final w = detectedWeek;
      if (w != null && w >= 1 && w <= 30) {
        final manualCalibrated = Storage.flag('semester_start_manual');
        if (Storage.semesterStart() == null || !manualCalibrated) {
          final now = DateTime.now();
          final monday = DateTime(
            now.year,
            now.month,
            now.day,
          ).subtract(Duration(days: now.weekday - 1));
          await Storage.saveSemesterStart(
            monday.subtract(Duration(days: (w - 1) * 7)),
          );
          await Storage.setFlag('semester_start_manual', false);
        }
      }
    }, credentials: cookie != null && cookie.isNotEmpty);
    this.courses = Storage.courses();
    zfState = Storage.zfCookie()?.isNotEmpty == true
        ? AccountState.ok
        : AccountState.notLoggedIn;
    timetableMessage = nextMessage;
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
    await Storage.waitForBusinessTransaction();
    final list = Storage.courses()..add(c);
    await Storage.saveCourses(list);
    courses = list;
    await NotificationService.reschedule(homework, courses: courses);
    await TimetableWidget.push(courses);
    notifyListeners();
  }

  /// 更新单条课程（课表页编辑入口；edited 标记让重抓时保留修正）。
  /// [original] 是编辑前的对象：同 id 双胞胎（不同周次）按「id+周次」
  /// 字段身份定位；过期编辑不能猜测目标并覆盖另一条课程。
  Future<void> updateCourse(Course original, Course updated) async {
    await Storage.waitForBusinessTransaction();
    final list = Storage.courses();
    final i = courseIndex(list, original);
    if (i < 0) throw StateError('课程已变化，请重新打开后编辑');
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
  /// 目标已变化时停止，避免删除其他周次的同名课程。
  Future<void> deleteCourse(Course target) async {
    await Storage.waitForBusinessTransaction();
    final list = Storage.courses();
    final i = courseIndex(list, target);
    if (i < 0) throw StateError('课程已变化，请重新打开后删除');
    list.removeAt(i);
    await Storage.saveCourses(list);
    courses = list;
    await NotificationService.reschedule(homework, courses: courses);
    await TimetableWidget.push(courses);
    notifyListeners();
  }

  /// 备份导入后全量重载并重排提醒。
  Future<void> reloadLocal() async {
    await Storage.waitForBusinessTransaction();
    await loadLocal();
    await Future.wait([
      _refreshHomeworkOutputs(),
      TimetableWidget.push(courses),
    ]);
  }

  /// 作息时间调整后重排上课提醒。
  Future<void> refreshClassReminders() async {
    await NotificationService.reschedule(homework, courses: courses);
    await TimetableWidget.push(courses);
    notifyListeners();
  }

  Future<void> logoutZf() async {
    await Storage.businessTransaction(() async {
      await Storage.archiveCourses();
      await Storage.clearZf();
      await Storage.saveJwConfigRaw('');
    }, credentials: true);
    // clearZf 会保留手动添加的课程，这里同步内存态
    courses = Storage.courses();
    zfState = AccountState.notLoggedIn;
    // 教务配置一并清掉：残留的话下一个用户点登录会被直接带进
    // 上一账号的学校教务页，没有重新选学校的机会
    await NotificationService.reschedule(homework, courses: courses);
    await TimetableWidget.push(courses);
    notifyListeners();
  }

  /// 手动校准学期第一周的周一（自动检测不准时用）。
  /// 打上 manual 标记后，自动检测不再覆盖这个值。
  Future<void> setSemesterStart(DateTime monday) async {
    await Storage.waitForBusinessTransaction();
    await Storage.saveSemesterStart(monday);
    await Storage.setFlag('semester_start_manual', true);
    await NotificationService.reschedule(homework, courses: courses);
    await TimetableWidget.push(courses);
    notifyListeners();
  }

  /// 修改上课提醒开关后重排。
  Future<void> updateClassReminder(bool enabled) async {
    await Storage.waitForBusinessTransaction();
    await Storage.saveClassReminder(enabled);
    await NotificationService.reschedule(homework, courses: courses);
    notifyListeners();
  }

  /// 手动隐藏某条作业（老师撤回、不需要提交等场景）。
  Future<void> dismissHomework(HomeworkItem hw) async {
    await Storage.waitForBusinessTransaction();
    // Dismissible 契约要求 onDismissed 当帧从树上移除：先改内存并通知，
    // 再做落盘与提醒重排——此前两次 prefs 平台通道写在移除之前，
    // 留了断言/回弹窗口
    homework = homework.where((h) => h.id != hw.id).toList();
    notifyListeners();
    await Storage.dismiss(hw.id, jsonEncode(hw.toJson()));
    await _refreshHomeworkOutputs();
  }

  /// 恢复隐藏的作业（立即可见；下次同步因 id 已不再被隐藏而保留）。
  Future<void> restoreHomework(String id) async {
    await Storage.waitForBusinessTransaction();
    final raw = Storage.hiddenItems()[id];
    if (raw != null) {
      final item = HomeworkItem.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
      final disk = Storage.homework();
      if (!disk.any((h) => h.id == id)) {
        disk.add(item);
        await Storage.saveHomework(disk);
      }
      await Storage.restoreDismissed(id);
      if (!homework.any((h) => h.id == id)) {
        homework = [...homework, item]
          ..sort((a, b) {
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
    }
    notifyListeners();
    await _refreshHomeworkOutputs();
  }

  /// 确认后的识别草稿只追加保存；输出刷新失败不会让用户重复添加。
  Future<HomeworkImportResult> addRecognizedHomework(
    List<ManualHomeworkEntry> selection,
  ) async {
    if (selection.isEmpty) return const HomeworkImportResult(0);
    final entries = List<ManualHomeworkEntry>.unmodifiable(selection);
    if (entries.any((entry) => entry.title.trim().isEmpty)) {
      throw ArgumentError('请填写勾选作业的标题');
    }
    final count = await Storage.appendManualHomeworkBatch((existing, ids) {
      var serial = DateTime.now().microsecondsSinceEpoch;
      final used = {...ids};
      final additions = <HomeworkItem>[];
      for (final entry in entries) {
        final duplicate = [...existing, ...additions].any(
          (old) => HomeworkDuplicates.matches(entry.course, entry.title, old),
        );
        if (duplicate && !entry.duplicateApproved) {
          throw const HomeworkImportDuplicateException();
        }
        while (used.contains('manual_$serial')) {
          serial++;
        }
        final id = 'manual_${serial++}';
        used.add(id);
        additions.add(
          HomeworkItem(
            id: id,
            platform: PlatformKind.manual,
            course: entry.course.trim(),
            title: entry.title.trim(),
            dueAt: entry.dueAt,
            note: entry.note.trim(),
            status: HwStatus.todo,
          ),
        );
      }
      return additions;
    });
    // The commit is final. Output refresh failures must never invite a retry
    // which would append the same confirmed batch a second time.
    homework = _visibleHomework();
    notifyListeners();
    var delayed = false;
    try {
      await _refreshHomeworkOutputs();
    } catch (_) {
      delayed = true;
    }
    return HomeworkImportResult(count, outputsDelayed: delayed);
  }

  /// 手动添加的自定义作业（同步不会删除）。
  Future<void> addManualHomework({
    required String course,
    required String title,
    DateTime? dueAt,
    String note = '',
  }) async {
    await Storage.waitForBusinessTransaction();
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
    notifyListeners();
    await _refreshHomeworkOutputs();
  }

  Future<void> updateManualHomework(HomeworkItem hw) async {
    await Storage.waitForBusinessTransaction();
    final disk = Storage.homework();
    final i = disk.indexWhere((h) => h.id == hw.id);
    if (i >= 0) disk[i] = hw;
    await Storage.saveHomework(disk);
    homework = _visibleHomework();
    notifyListeners();
    await _refreshHomeworkOutputs();
  }

  Future<void> deleteManualHomework(String id) async {
    await Storage.waitForBusinessTransaction();
    final disk = Storage.homework()..removeWhere((h) => h.id == id);
    await Storage.saveHomework(disk);
    homework = _visibleHomework();
    notifyListeners();
    await _refreshHomeworkOutputs();
  }

  /// 更新作业备注（任意平台的条目都可以）。
  Future<void> updateNote(String id, String note) async {
    await Storage.waitForBusinessTransaction();
    final disk = Storage.homework();
    final i = disk.indexWhere((h) => h.id == id);
    if (i < 0) return;
    disk[i] = disk[i].copyWith(note: note);
    await Storage.saveHomework(disk);
    homework = _visibleHomework();
    notifyListeners();
  }

  Future<void> setHomeworkStatus(String id, HwStatus status) async {
    await Storage.waitForBusinessTransaction();
    final disk = Storage.homework();
    final index = disk.indexWhere((h) => h.id == id);
    if (index < 0) return;
    disk[index] = disk[index].copyWith(status: status);
    await Storage.saveHomework(disk);
    homework = _visibleHomework();
    notifyListeners();
    await _refreshHomeworkOutputs();
  }

  Future<void> updateReminders(ReminderSettings r) async {
    await Storage.waitForBusinessTransaction();
    await Storage.saveReminders(r);
    await NotificationService.reschedule(homework, courses: courses);
    notifyListeners();
  }
}
