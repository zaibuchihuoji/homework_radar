/// 同步编排：拉取各平台 → 归并 → 存库 → 重排通知 → 更新桌面小组件。
/// 设计为不依赖 UI，可在后台 isolate 里复用。
library;

import 'dart:convert';

import 'package:home_widget/home_widget.dart';

import '../models/homework.dart';
import 'chaoxing_service.dart';
import 'mooc_service.dart';
import 'notification_service.dart';
import 'safe_http.dart';
import 'storage.dart';
import 'xuetangx_service.dart';
import 'yuketang_service.dart';
import 'zhihuishu_service.dart';

/// 把一次平台抓取结果并回总表。
/// - 备注保留：平台解析出的条目 note 恒为空，直接覆盖会把用户写的备注
///   （「需交纸质版」等）冲掉，旧条目的备注要带回新条目；
/// - 状态保留（仅 MOOC/学堂在线/雨课堂）：这三家解析不出真实状态（恒
///   todo），它们的 todo 不是平台证据，不得把旧条目的已完成/已提交打回
///   待办；学习通/智慧树的状态是解析出的真实值，仍以平台为准；
/// - 空结果防御：本次没拉到数据（网络抖动、页面改版、部分课程失败）时
///   不清理平台侧旧条目——清理只应发生在「完整抓到且确认消失」之后，
///   否则一次失败请求就清光整个平台的作业与提醒。
///
/// 公开给测试（sync_merge_test.dart）钉住语义。
void mergePlatform(
  Map<String, HomeworkItem> merged,
  List<HomeworkItem> incoming,
  PlatformKind platform, {
  required bool complete,
}) {
  for (final it in incoming) {
    final old = merged[it.id];
    final oldNote = old?.note;
    final oldStatus = old?.status;
    final keepStatus = (platform == PlatformKind.mooc ||
            platform == PlatformKind.xuetangx ||
            platform == PlatformKind.yuketang) &&
        (oldStatus == HwStatus.done || oldStatus == HwStatus.submitted) &&
        it.status == HwStatus.todo;
    var item = it;
    if (keepStatus) item = item.copyWith(status: oldStatus);
    if (oldNote != null &&
        oldNote.isNotEmpty &&
        (it.note == null || it.note!.isEmpty)) {
      item = item.copyWith(note: oldNote);
    }
    merged[it.id] = item;
  }
  if (complete && incoming.isNotEmpty) {
    final seen = {for (final it in incoming) it.id};
    merged.removeWhere((k, v) => v.platform == platform && !seen.contains(k));
  }
}

class SyncResult {
  List<HomeworkItem> items = [];
  bool chaoxingValid = false;
  bool moocValid = false;
  bool zhihuishuValid = false;
  bool xuetangxValid = false;
  bool yuketangValid = false;
  bool chaoxingUnknown = false;
  bool moocUnknown = false;
  bool zhihuishuUnknown = false;
  bool xuetangxUnknown = false;
  bool yuketangUnknown = false;
  /// 网关签名校验拒收（密钥组/网关校验变化）：重登无效，账号卡不得把
  /// 用户标成「需重新登录」误导其反复重登，保持原状态即可
  bool zhihuishuSignatureRejected = false;
  String message = '';
}

class SyncService {
  /// 拉取并归并。传入当前保存的凭据；凭据无效的平台标记为需重新登录。
  static Future<SyncResult> run({
    void Function(int done, int total)? onProgress,
  }) async {
    final result = SyncResult();
    final merged = <String, HomeworkItem>{};
    for (final old in Storage.homework()) {
      merged[old.id] = old;
    }
    String? loginExpiredNotice; // 收着，等 reschedule 之后才弹（见 run 尾部）
    String? moocExpiredNotice;
    String? zhsExpiredNotice;
    String? xtxExpiredNotice;
    String? yktExpiredNotice;

    final cx = ChaoxingService(cookie: Storage.chaoxingCookie());
    try {
      final cxOk = await cx.checkLogin();
      // 登录从有效变为失效时，发系统通知提醒重新登录（只提醒一次）。
      // 网络失败算「未知」：把网络抖动当登录过期会误发通知、误标失效，
      // 还会清掉 cx_ok 让真正的过期永远不再提醒。
      if (cxOk == null) {
        result.chaoxingUnknown = true;
      } else {
        if (Storage.chaoxingCookie()?.isNotEmpty == true &&
            !cxOk &&
            Storage.flag('cx_ok')) {
          loginExpiredNotice = '学习通登录已过期';
        }
        await Storage.setFlag('cx_ok', cxOk);
        if (cxOk) {
          result.chaoxingValid = true;
          final list = await cx.allHomework(onProgress: onProgress);
          mergePlatform(merged, list, PlatformKind.chaoxing,
              complete: !cx.listFailed && cx.failedCount == 0);
        }
      }
    } catch (e) {
      result.message += '学习通同步异常：$e\n';
    }

    final mooc = MoocService(
      cookie: Storage.moocCookie(),
      csrfKey: Storage.moocCsrf(),
    );
    try {
      final moocOk = await mooc.checkLogin();
      if (moocOk == null) {
        result.moocUnknown = true;
      } else if (moocOk) {
        final wasValid = Storage.flag('mooc_ok');
        final list = await mooc.allHomework(onProgress: onProgress);
        if (mooc.loginFailed) {
          // 与学习通同款：从有效变为失效发一次系统通知提醒重新登录。
          // checkLogin 凭缓存的 csrfKey 恒 true，没有这个信号的话 MOOC
          // 掉登录后静默停更、界面永远显示「已登录」
          if (Storage.moocCookie()?.isNotEmpty == true && wasValid) {
            moocExpiredNotice = 'MOOC登录已过期';
          }
          await Storage.setFlag('mooc_ok', false);
        } else {
          result.moocValid = true;
          await Storage.setFlag('mooc_ok', true);
          mergePlatform(merged, list, PlatformKind.mooc,
              complete: !mooc.listFailed && mooc.failedCount == 0);
        }
      }
    } catch (e) {
      result.message += 'MOOC同步异常：$e\n';
    }

    // 智慧树分支：与学习通同构——checkLogin 是真实网关探测，能直接给出
    // 三态结论（不像 MOOC 凭缓存 csrfKey 恒 true，需要靠 loginFailed 补信号）
    final zhs = ZhihuishuService(cookie: Storage.zhihuishuCookie());
    try {
      final zhsState = await zhs.checkLogin();
      // 网络失败算「未知」：把网络抖动当登录过期会误发通知、误标失效，
      // 还会清掉 zhs_ok 让真正的过期永远不再提醒（与学习通/MOOC 同款）
      if (zhsState == ZhsSessionState.unknown) {
        result.zhihuishuUnknown = true;
      } else {
        // 会话从有效变为失效时，发一次系统通知提醒（通知在 reschedule
        // 之后才弹，见 run 尾部）。签名被拒 ≠ 登录过期：密钥组/网关校验
        // 变化时重登无效，文案分开，免得用户反复重登（真会话过期的业务
        // 码语义待抓包核实后再细分）
        if (Storage.zhihuishuCookie()?.isNotEmpty == true &&
            zhsState != ZhsSessionState.ok &&
            Storage.flag('zhs_ok')) {
          zhsExpiredNotice = zhsState == ZhsSessionState.signatureRejected
              ? '智慧树接口校验被拒，可能需要更新 App'
              : '智慧树登录已过期';
        }
        if (zhsState == ZhsSessionState.signatureRejected) {
          result.zhihuishuSignatureRejected = true;
        }
        await Storage.setFlag('zhs_ok', zhsState == ZhsSessionState.ok);
        if (zhsState == ZhsSessionState.ok) {
          result.zhihuishuValid = true;
          final list = await zhs.allHomework(onProgress: onProgress);
          // complete 守卫语义不可动：课程/作业没拉全（候选端点全失败、
          // 网关抖动）绝不能把旧条目当「确认消失」清库
          mergePlatform(merged, list, PlatformKind.zhihuishu,
              complete: !zhs.listFailed && zhs.failedCount == 0);
        }
      }
    } catch (e) {
      result.message += '智慧树同步异常：$e\n';
    }

    // 学堂在线分支：与智慧树同构——checkLogin 三态（无签名概念，无
    // signatureRejected），Cookie 会话纯只读拉取
    final xt = XuetangxService(cookie: Storage.xuetangxCookie());
    try {
      final xtState = await xt.checkLogin();
      if (xtState == XtSessionState.unknown) {
        result.xuetangxUnknown = true;
      } else {
        if (Storage.xuetangxCookie()?.isNotEmpty == true &&
            xtState != XtSessionState.ok &&
            Storage.flag('xtx_ok')) {
          xtxExpiredNotice = '学堂在线登录已过期';
        }
        await Storage.setFlag('xtx_ok', xtState == XtSessionState.ok);
        if (xtState == XtSessionState.ok) {
          result.xuetangxValid = true;
          final list = await xt.allHomework(onProgress: onProgress);
          // complete 守卫语义不可动：课程列表候选端点未校准/章节树失败
          // （listFailed）或单课失败时，绝不能把旧条目当「确认消失」清库
          mergePlatform(merged, list, PlatformKind.xuetangx,
              complete: !xt.listFailed && xt.failedCount == 0);
        }
      }
    } catch (e) {
      result.message += '学堂在线同步异常：$e\n';
    }

    // 雨课堂分支：与学堂在线同构——纯 Cookie 会话、候选 origin 自适应
    final ykt = YuketangService(cookie: Storage.yuketangCookie());
    try {
      final yktState = await ykt.checkLogin();
      if (yktState == YktSessionState.unknown) {
        result.yuketangUnknown = true;
      } else {
        if (Storage.yuketangCookie()?.isNotEmpty == true &&
            yktState != YktSessionState.ok &&
            Storage.flag('ykt_ok')) {
          yktExpiredNotice = '雨课堂登录已过期';
        }
        await Storage.setFlag('ykt_ok', yktState == YktSessionState.ok);
        if (yktState == YktSessionState.ok) {
          result.yuketangValid = true;
          final list = await ykt.allHomework(onProgress: onProgress);
          // complete 守卫语义不可动：origin 全挂/单课失败时绝不能把旧
          // 条目当「确认消失」清库
          mergePlatform(merged, list, PlatformKind.yuketang,
              complete: !ykt.listFailed && ykt.failedCount == 0);
        }
      }
    } catch (e) {
      result.message += '雨课堂同步异常：$e\n';
    }

    // 落库前重读一遍磁盘：同步可达数十秒，期间用户的手动增删改与备注编辑
    // 已直接落库，不能被开始时的快照合并结果覆盖回滚（manual_ 条目仅存
    // 本地，被覆盖即永久丢失）。
    final fresh = {for (final h in Storage.homework()) h.id: h};

    // 手动隐藏过的条目不再入库（下次同步也不会回来）。快照放到重读磁盘
    // 之后取：dismissed 读得越晚，同步窗口内「恢复隐藏」被开始时的旧状态
    // 当成仍隐藏而丢弃的窗口越小。
    final dismissed = Storage.dismissedIds();
    merged.removeWhere((k, _) => dismissed.contains(k));

    for (final id in merged.keys.toList()) {
      final f = fresh[id];
      if (f == null) {
        // 同步期间被删除：手动条目尊重删除
        if (id.startsWith('manual_')) merged.remove(id);
        continue;
      }
      if (id.startsWith('manual_')) {
        merged[id] = f; // 手动条目整条以磁盘最新为准（同步期间的编辑）
      } else if (f.note != merged[id]!.note) {
        // 平台条目：平台解析出的 note 恒为空，磁盘值就是用户编辑值，无条件
        // 采纳——若只认「磁盘备注非空」，同步窗口内清空备注会被旧快照回退。
        // copyWith 的 note 传 null 表示「保持原值」，表达不了清空，直接重建
        final m = merged[id]!;
        merged[id] = HomeworkItem(
          id: m.id,
          platform: m.platform,
          course: m.course,
          title: m.title,
          dueAt: m.dueAt,
          status: m.status,
          url: m.url,
          score: m.score,
          note: f.note,
        );
      }
    }
    for (final f in fresh.values) {
      if (f.id.startsWith('manual_') &&
          !merged.containsKey(f.id) &&
          !dismissed.contains(f.id)) {
        merged[f.id] = f; // 同步期间新增的手动作业
      }
    }

    result.items = merged.values.toList()
      ..sort((a, b) {
        // 未完成优先，按截止时间升序；无截止时间的放后面
        final at = a.status == HwStatus.done ? 1 : 0;
        final bt = b.status == HwStatus.done ? 1 : 0;
        if (at != bt) return at - bt;
        final ad = a.dueAt, bd = b.dueAt;
        if (ad == null && bd == null) return 0;
        if (ad == null) return 1;
        if (bd == null) return -1;
        return ad.compareTo(bd);
      });

    await Storage.saveHomework(result.items);
    await Storage.saveDebugLog(SafeHttp.log);
    // 上课提醒要一并重排：reschedule 会先 cancelAll，漏掉 courses 就会把
    // 课前 15 分钟提醒清光（每次打开 App 都同步，等于提醒常灭）
    await NotificationService.reschedule(result.items, courses: Storage.courses());
    // 过期通知必须在 reschedule 之后弹：reschedule 先 cancelAll，先弹会被
    // 自己清掉，而且去重标志已置位、永远不会再补发
    if (loginExpiredNotice != null) {
      await NotificationService.showSimple(
          loginExpiredNotice, '作业没法同步了，点开作业通重新登录一下');
    }
    if (moocExpiredNotice != null) {
      await NotificationService.showSimple(
          moocExpiredNotice, 'MOOC作业没法同步了，点开作业通重新登录一下');
    }
    if (zhsExpiredNotice != null) {
      await NotificationService.showSimple(
          zhsExpiredNotice, '智慧树作业没法同步了，点开作业通重新登录一下');
    }
    if (xtxExpiredNotice != null) {
      await NotificationService.showSimple(
          xtxExpiredNotice, '学堂在线作业没法同步了，点开作业通重新登录一下');
    }
    if (yktExpiredNotice != null) {
      await NotificationService.showSimple(
          yktExpiredNotice, '雨课堂作业没法同步了，点开作业通重新登录一下');
    }
    await updateHomeWidget(result.items);
    return result;
  }

  /// 把最近截止的未完成作业写给桌面小组件（结构化 JSON，原生侧按紧急度着色）。
  static Future<void> updateHomeWidget(List<HomeworkItem> items) async {
    try {
      final now = DateTime.now();
      final todo = items
          .where((h) =>
              h.status != HwStatus.done &&
              h.status != HwStatus.submitted &&
              h.dueAt != null &&
              h.dueAt!.isAfter(now))
          .toList()
        ..sort((a, b) => a.dueAt!.compareTo(b.dueAt!));

      String shortCountdown(HomeworkItem hw) {
        final diff = hw.dueAt!.difference(now);
        // 48 小时内用倒计时（24 小时内带分秒），更远按天；口径与应用内一致
        if (diff.inMinutes < 60) return '${diff.inMinutes}分钟';
        if (diff.inHours < 24) {
          final h = diff.inHours;
          final m = diff.inMinutes % 60;
          final s = diff.inSeconds % 60;
          return '$h小时$m分$s秒';
        }
        if (diff.inHours < 48) return '${diff.inHours}小时';
        return '${diff.inDays}天';
      }

      // 0=一天内(红) 1=三天内(琥珀) 2=更远(主题绿) 3=已完成/已提交(灰)
      int urgency(HomeworkItem hw) {
        final diff = hw.dueAt!.difference(now);
        if (diff.inHours <= 24) return 0;
        if (diff.inDays <= 3) return 1;
        return 2;
      }

      // 大尺寸小组件最多显示 12 条：待办在前（有截止的按时间升序，无截止的随后），
      // 不足时已提交/完成的按截止时间倒序灰色补位
      final undated = items
          .where((h) =>
              h.status != HwStatus.done &&
              h.status != HwStatus.submitted &&
              h.dueAt == null &&
              h.inCurrentSemester)
          .toList();
      final finished = items
          .where((h) =>
              (h.status == HwStatus.done || h.status == HwStatus.submitted) &&
              h.inCurrentSemester)
          .toList()
        ..sort((a, b) =>
            (b.dueAt ?? DateTime(1970)).compareTo(a.dueAt ?? DateTime(1970)));
      final rows = [...todo.take(20), ...undated];
      final filler = finished.take(20 - rows.length.clamp(0, 20)).toList();

      String shortStatus(HomeworkItem hw) =>
          hw.status == HwStatus.done ? '完成' : '已交';

      final data = [
        for (final hw in todo.take(20))
          {
            'count': shortCountdown(hw),
            // 原生重绘时按 due 里程碑重算倒计时/颜色，否则截止后组件
            // 仍显示同步时刻的「未来」倒计时
            'd': hw.dueAt!.millisecondsSinceEpoch,
            'title': hw.title,
            'due': '${hw.dueAt!.month}/${hw.dueAt!.day} 截止',
            'u': urgency(hw),
          },
        for (final hw in undated)
          {
            'count': '未设',
            'title': hw.title,
            'due': '',
            'u': 2,
          },
        for (final hw in filler)
          {
            'count': shortStatus(hw),
            'title': hw.title,
            'due': hw.dueAt == null
                ? ''
                : '${hw.dueAt!.month}/${hw.dueAt!.day}',
            'u': 3,
          },
      ];
      await HomeWidget.saveWidgetData<String>('items_json', jsonEncode(data));

      // 学期统计：供小组件汇总文案与进度条使用
      final semester = items.where((h) => h.inCurrentSemester).toList();
      final doneCount = semester
          .where((h) => h.status == HwStatus.done || h.status == HwStatus.submitted)
          .length;
      final todoAll = semester
          .where((h) => h.status != HwStatus.done && h.status != HwStatus.submitted)
          .toList();
      final overdue = todoAll
          .where((h) => h.dueAt != null && h.dueAt!.isBefore(now))
          .length;

      // 紧急焦点横幅：今天 > 明天 > 最近一条
      final today0 = DateTime(now.year, now.month, now.day);
      final dueToday = todo
          .where((h) =>
              h.dueAt!.year == today0.year &&
              h.dueAt!.month == today0.month &&
              h.dueAt!.day == today0.day)
          .toList();
      final tomorrow = today0.add(const Duration(days: 1));
      final dueTomorrow = todo
          .where((h) =>
              h.dueAt!.year == tomorrow.year &&
              h.dueAt!.month == tomorrow.month &&
              h.dueAt!.day == tomorrow.day)
          .toList();
      String bannerText;
      int bannerU;
      int? bannerD; // 横幅焦点条目的截止里程碑（epoch ms），供原生按当前时间重算
      if (dueToday.isNotEmpty) {
        bannerText =
            '今天截止 ${dueToday.length} 件 · ${dueToday.first.title}';
        bannerU = 0;
        bannerD = dueToday.first.dueAt!.millisecondsSinceEpoch;
      } else if (dueTomorrow.isNotEmpty) {
        bannerText = '明天截止 · ${dueTomorrow.first.title}';
        bannerU = 1;
        bannerD = dueTomorrow.first.dueAt!.millisecondsSinceEpoch;
      } else if (todo.isNotEmpty) {
        bannerText =
            '最近 ${shortCountdown(todo.first)} · ${todo.first.title}';
        bannerU = 2;
        bannerD = todo.first.dueAt!.millisecondsSinceEpoch;
      } else {
        bannerText = '';
        bannerU = 2;
      }

      // 课程待办分布（取前 4 门，按数量降序）
      final byCourse = <String, int>{};
      for (final h in todoAll) {
        final c = h.course.trim();
        if (c.isEmpty) continue;
        byCourse[c] = (byCourse[c] ?? 0) + 1;
      }
      final courseEntries = byCourse.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));

      await HomeWidget.saveWidgetData<String>(
          'stats',
          jsonEncode({
            'todo': todoAll.length,
            'overdue': overdue,
            'done': doneCount,
            'total': semester.length,
            'banner': {
              'text': bannerText,
              'u': bannerU,
              // 截止里程碑：横幅文本是同步瞬间的快照，小组件 30 分钟重绘
              // 只回放文本的话，截止后仍显示「未来X小时」；原生按 d 重算
              // 相对文案，缺失时回退快照（旧数据向后兼容）
              'd': ?bannerD,
            },
            'courses': [
              for (final e in courseEntries.take(4))
                {
                  // 按 UTF-16 码元 substring 会劈开代理对（emoji 课名等）
                  'c': String.fromCharCode(e.key.trim().runes.first),
                  'n': e.value
                },
            ],
          }));

      final n = DateTime.now();
      await HomeWidget.saveWidgetData<String>(
          'updated',
          '更新 ${n.hour.toString().padLeft(2, '0')}:'
          '${n.minute.toString().padLeft(2, '0')}');
      await HomeWidget.updateWidget(
        androidName: 'HomeworkWidgetProvider',
      );
    } catch (_) {
      // 小组件更新失败不影响同步
    }
  }
}
