/// 同步编排：拉取各平台 → 归并 → 存库 → 重排通知 → 更新桌面小组件。
/// UI 与 WorkManager 共用同一引擎、事务队列及账号代际。
library;

import 'dart:convert';

import 'package:home_widget/home_widget.dart';
import 'package:flutter/foundation.dart';

import '../models/homework.dart';
import 'chaoxing_service.dart';
import 'async_limiter.dart';
import 'mooc_service.dart';
import 'homework_widget_snapshot.dart';
import 'notification_service.dart';
import 'safe_http.dart';
import 'storage.dart';
import 'sync_policy.dart';
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
  final bySource = <String, List<HomeworkItem>>{};
  for (final item in merged.values) {
    if (item.sourceKey != null) {
      bySource.putIfAbsent(item.sourceKey!, () => []).add(item);
    }
  }
  final seenIds = <String>{};
  String? legacyZhsKey(String? key) {
    if (platform != PlatformKind.zhihuishu || key == null) return null;
    final parts = key.split('|');
    return parts.length == 5 && parts.first == 'zhs'
        ? 'zhs|${parts[1]}|${parts[3]}|${parts[4]}'
        : null;
  }

  final incomingLegacy = <String, int>{};
  for (final item in incoming) {
    final key = legacyZhsKey(item.sourceKey);
    if (key != null) incomingLegacy[key] = (incomingLegacy[key] ?? 0) + 1;
  }
  final ambiguous =
      bySource.values.any((items) => items.length > 1) ||
      incomingLegacy.values.any((count) => count > 1);
  for (final it in incoming) {
    var aliases = it.sourceKey == null ? null : bySource[it.sourceKey];
    final legacy = legacyZhsKey(it.sourceKey);
    if (aliases == null && legacy != null && incomingLegacy[legacy] == 1) {
      aliases = bySource[legacy];
    }
    final linked = aliases != null && aliases.length == 1
        ? aliases.single
        : null;
    final resolved = linked == null ? it : it.copyWith(id: linked.id);
    seenIds.add(resolved.id);
    final old = merged[resolved.id];
    final oldNote = old?.note;
    final oldStatus = old?.status;
    final keepStatus =
        (platform == PlatformKind.mooc ||
            platform == PlatformKind.xuetangx ||
            platform == PlatformKind.yuketang) &&
        (oldStatus == HwStatus.done || oldStatus == HwStatus.submitted) &&
        it.status == HwStatus.todo;
    var item = resolved;
    if (keepStatus) item = item.copyWith(status: oldStatus);
    if (oldNote != null &&
        oldNote.isNotEmpty &&
        (it.note == null || it.note!.isEmpty)) {
      item = item.copyWith(note: oldNote);
    }
    merged[resolved.id] = item;
  }
  if (complete && !ambiguous && incoming.isNotEmpty) {
    merged.removeWhere(
      (k, v) =>
          v.platform == platform &&
          !seenIds.contains(k) &&
          // 存量名字ID在首次补齐稳定身份前不能可靠关联，至少保住用户备注。
          !(v.sourceKey == null &&
              (v.note?.isNotEmpty == true ||
                  ((platform == PlatformKind.mooc ||
                          platform == PlatformKind.xuetangx ||
                          platform == PlatformKind.yuketang) &&
                      (v.status == HwStatus.done ||
                          v.status == HwStatus.submitted)))) &&
          // Older ZHS records lack enrollment/type evidence. Unmapped records
          // survive the identity upgrade instead of guessing which new row owns
          // their notes or treating them as confirmed deletions.
          !(platform == PlatformKind.zhihuishu &&
              incomingLegacy.isNotEmpty &&
              v.sourceKey?.startsWith('zhs|') == true &&
              v.sourceKey!.split('|').length == 4),
    );
  }
}

class SyncResult {
  final Set<PlatformKind> attempted = {};
  final Map<PlatformKind, SyncOutcome> outcomes = {};
  bool cancelled = false;
  bool partial = false;
  int generation = -1;
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
  static final widgetPublishError = ValueNotifier<String?>(null);

  /// 拉取并归并。传入当前保存的凭据；凭据无效的平台标记为需重新登录。
  static Future<SyncResult> run({
    void Function(int done, int total)? onProgress,
    Set<PlatformKind>? platforms,
    void Function()? onCommitted,
  }) async {
    await Storage.waitForBusinessTransaction();
    final result = SyncResult();
    final epoch = Storage.syncEpoch;
    result.generation = epoch;
    final selected = (platforms ?? Storage.syncAccounts()).intersection(
      Storage.syncAccounts(),
    );
    result.attempted.addAll(selected);
    final attemptedAt = DateTime.now();
    final statuses = Storage.syncStatuses();
    final previousStatuses = {...statuses};
    // Reserve a retry before network I/O: process death cannot leave a platform
    // permanently marked as running or falsely advance its successful time.
    for (final p in selected) {
      statuses[p] = (statuses[p] ?? const PlatformSyncStatus()).finish(
        SyncOutcome.retry,
        attemptedAt,
      );
    }
    if (selected.isNotEmpty) await Storage.saveSyncStatuses(statuses);
    if (epoch != Storage.syncEpoch) {
      result.cancelled = true;
      return result;
    }

    SyncResult cancelled() {
      result.cancelled = true;
      result.items = Storage.homework()
          .where((h) => !Storage.dismissedIds().contains(h.id))
          .toList();
      return result;
    }

    List<HomeworkItem> visible() => Storage.homework()
        .where((h) => !Storage.dismissedIds().contains(h.id))
        .toList();
    final merged = <String, HomeworkItem>{};
    for (final old in Storage.homework()) {
      merged[old.id] = old;
    }
    for (final raw in Storage.hiddenItems().values) {
      try {
        final item = HomeworkItem.fromJson(
          jsonDecode(raw) as Map<String, dynamic>,
        );
        merged.putIfAbsent(item.id, () => item);
      } catch (_) {
        /* 保留损坏副本，不阻断其他同步。 */
      }
    }
    String? loginExpiredNotice; // 收着，等 reschedule 之后才弹（见 run 尾部）
    String? moocExpiredNotice;
    String? zhsExpiredNotice;
    String? xtxExpiredNotice;
    String? yktExpiredNotice;

    final cx = ChaoxingService(cookie: Storage.chaoxingCookie());
    final mooc = MoocService(
      cookie: Storage.moocCookie(),
      csrfKey: Storage.moocCsrf(),
    );
    final zhs = ZhihuishuService(cookie: Storage.zhihuishuCookie());
    final xt = XuetangxService(cookie: Storage.xuetangxCookie());
    final ykt = YuketangService(cookie: Storage.yuketangCookie());
    final counts = <PlatformKind, (int, int)>{};
    void progress(PlatformKind p, int done, int total) {
      if (epoch != Storage.syncEpoch) return;
      counts[p] = (done, total);
      onProgress?.call(
        counts.values.fold(0, (a, b) => a + b.$1),
        counts.values.fold(0, (a, b) => a + b.$2),
      );
    }

    Future<void> pullCx() async {
      if (selected.contains(PlatformKind.chaoxing)) {
        try {
          final cxOk = await cx.checkLogin();
          if (epoch != Storage.syncEpoch) return;
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
              final list = await cx.allHomework(
                onProgress: (done, total) =>
                    progress(PlatformKind.chaoxing, done, total),
              );
              if (epoch != Storage.syncEpoch) return;
              mergePlatform(
                merged,
                list,
                PlatformKind.chaoxing,
                complete: !cx.listFailed && cx.failedCount == 0,
              );
            }
          }
        } catch (e) {
          result.chaoxingUnknown = true;
          result.message += '学习通同步异常：$e\n';
        }
      }
    }

    Future<void> pullMooc() async {
      if (selected.contains(PlatformKind.mooc)) {
        try {
          final moocOk = await mooc.checkLogin();
          if (epoch != Storage.syncEpoch) return;
          if (moocOk == null) {
            result.moocUnknown = true;
          } else if (moocOk) {
            final wasValid = Storage.flag('mooc_ok');
            final list = await mooc.allHomework(
              onProgress: (done, total) =>
                  progress(PlatformKind.mooc, done, total),
            );
            if (epoch != Storage.syncEpoch) return;
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
              mergePlatform(
                merged,
                list,
                PlatformKind.mooc,
                complete: !mooc.listFailed && mooc.failedCount == 0,
              );
            }
          }
        } catch (e) {
          result.moocUnknown = true;
          result.message += 'MOOC同步异常：$e\n';
        }
      }

      // 智慧树分支：与学习通同构——checkLogin 是真实网关探测，能直接给出
      // 三态结论（不像 MOOC 凭缓存 csrfKey 恒 true，需要靠 loginFailed 补信号）
    }

    Future<void> pullZhs() async {
      if (selected.contains(PlatformKind.zhihuishu)) {
        try {
          final zhsState = await zhs.checkLogin();
          if (epoch != Storage.syncEpoch) return;
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
              final list = await zhs.allHomework(
                onProgress: (done, total) =>
                    progress(PlatformKind.zhihuishu, done, total),
              );
              if (epoch != Storage.syncEpoch) return;
              // complete 守卫语义不可动：课程/作业没拉全（候选端点全失败、
              // 网关抖动）绝不能把旧条目当「确认消失」清库
              mergePlatform(
                merged,
                list,
                PlatformKind.zhihuishu,
                complete: !zhs.listFailed && zhs.failedCount == 0,
              );
            }
          }
        } catch (e) {
          result.zhihuishuUnknown = true;
          result.message += '智慧树同步异常：$e\n';
        }
      }

      // 学堂在线分支：与智慧树同构——checkLogin 三态（无签名概念，无
      // signatureRejected），Cookie 会话纯只读拉取
    }

    Future<void> pullXt() async {
      if (selected.contains(PlatformKind.xuetangx)) {
        try {
          final xtState = await xt.checkLogin();
          if (epoch != Storage.syncEpoch) return;
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
              final list = await xt.allHomework(
                onProgress: (done, total) =>
                    progress(PlatformKind.xuetangx, done, total),
              );
              if (epoch != Storage.syncEpoch) return;
              // complete 守卫语义不可动：课程列表候选端点未校准/章节树失败
              // （listFailed）或单课失败时，绝不能把旧条目当「确认消失」清库
              mergePlatform(
                merged,
                list,
                PlatformKind.xuetangx,
                complete: !xt.listFailed && xt.failedCount == 0,
              );
            }
          }
        } catch (e) {
          result.xuetangxUnknown = true;
          result.message += '学堂在线同步异常：$e\n';
        }
      }

      // 雨课堂分支：与学堂在线同构——纯 Cookie 会话、候选 origin 自适应
    }

    Future<void> pullYkt() async {
      if (selected.contains(PlatformKind.yuketang)) {
        try {
          final yktState = await ykt.checkLogin();
          if (epoch != Storage.syncEpoch) return;
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
              final list = await ykt.allHomework(
                onProgress: (done, total) =>
                    progress(PlatformKind.yuketang, done, total),
              );
              if (epoch != Storage.syncEpoch) return;
              // complete 守卫语义不可动：origin 全挂/单课失败时绝不能把旧
              // 条目当「确认消失」清库
              mergePlatform(
                merged,
                list,
                PlatformKind.yuketang,
                complete: !ykt.listFailed && ykt.failedCount == 0,
              );
            }
          }
        } catch (e) {
          result.yuketangUnknown = true;
          result.message += '雨课堂同步异常：$e\n';
        }
      }
    }

    final platformsInFlight = AsyncLimiter(2);
    await Future.wait([
      platformsInFlight.run(() async {
        if (epoch == Storage.syncEpoch) await pullCx();
      }),
      platformsInFlight.run(() async {
        if (epoch == Storage.syncEpoch) await pullMooc();
      }),
      platformsInFlight.run(() async {
        if (epoch == Storage.syncEpoch) await pullZhs();
      }),
      platformsInFlight.run(() async {
        if (epoch == Storage.syncEpoch) await pullXt();
      }),
      platformsInFlight.run(() async {
        if (epoch == Storage.syncEpoch) await pullYkt();
      }),
    ]);
    if (epoch != Storage.syncEpoch) return cancelled();

    // 落库前重读一遍磁盘：同步可达数十秒，期间用户的手动增删改与备注编辑
    // 已直接落库，不能被开始时的快照合并结果覆盖回滚（manual_ 条目仅存
    // 本地，被覆盖即永久丢失）。
    if (epoch != Storage.syncEpoch) return cancelled();
    final cxDetails = cx.failureDetails;
    if (cxDetails.isNotEmpty) {
      final remaining = cxDetails.length > 3 ? '；等共 ${cxDetails.length} 处' : '';
      result.message +=
          '学习通未完整同步：${cxDetails.take(3).join('；')}$remaining。已保留旧记录。\n';
    }
    final warnings = <String>[
      if (cxDetails.isEmpty &&
          (result.chaoxingUnknown || cx.listFailed || cx.failedCount > 0))
        '学习通',
      if (result.moocUnknown || mooc.listFailed || mooc.failedCount > 0) 'MOOC',
      if (result.zhihuishuUnknown || zhs.listFailed || zhs.failedCount > 0)
        '智慧树',
      if (result.xuetangxUnknown || xt.listFailed || xt.failedCount > 0) '学堂在线',
      if (result.yuketangUnknown || ykt.listFailed || ykt.failedCount > 0)
        '雨课堂',
    ];
    result.partial = warnings.isNotEmpty || result.message.isNotEmpty;
    if (warnings.isNotEmpty) {
      result.message += '${warnings.join('、')}未完整同步，已保留旧记录，请稍后重试。\n';
    }
    final health = <PlatformKind, (bool, bool, bool)>{
      PlatformKind.chaoxing: (
        result.chaoxingValid,
        result.chaoxingUnknown,
        cx.listFailed || cx.failedCount > 0,
      ),
      PlatformKind.mooc: (
        result.moocValid,
        result.moocUnknown,
        mooc.listFailed || mooc.failedCount > 0,
      ),
      PlatformKind.zhihuishu: (
        result.zhihuishuValid,
        result.zhihuishuUnknown,
        zhs.listFailed || zhs.failedCount > 0,
      ),
      PlatformKind.xuetangx: (
        result.xuetangxValid,
        result.xuetangxUnknown,
        xt.listFailed || xt.failedCount > 0,
      ),
      PlatformKind.yuketang: (
        result.yuketangValid,
        result.yuketangUnknown,
        ykt.listFailed || ykt.failedCount > 0,
      ),
    };
    for (final p in selected) {
      final (valid, unknown, incomplete) = health[p]!;
      result.outcomes[p] =
          p == PlatformKind.zhihuishu && result.zhihuishuSignatureRejected
          ? SyncOutcome.signatureRejected
          : p == PlatformKind.zhihuishu &&
                zhs.lastSessionState == ZhsSessionState.signatureRejected
          ? SyncOutcome.signatureRejected
          : (p == PlatformKind.mooc && mooc.loginFailed) ||
                (p == PlatformKind.zhihuishu &&
                    zhs.lastSessionState == ZhsSessionState.expired) ||
                (p == PlatformKind.xuetangx &&
                    xt.lastSessionState == XtSessionState.expired) ||
                (p == PlatformKind.yuketang &&
                    ykt.lastSessionState == YktSessionState.expired)
          ? SyncOutcome.loginExpired
          : unknown || incomplete
          ? SyncOutcome.retry
          : valid
          ? SyncOutcome.success
          : SyncOutcome.loginExpired;
    }
    if (result.outcomes[PlatformKind.zhihuishu] == SyncOutcome.loginExpired ||
        result.outcomes[PlatformKind.zhihuishu] ==
            SyncOutcome.signatureRejected) {
      result.zhihuishuValid = false;
      result.zhihuishuSignatureRejected =
          result.outcomes[PlatformKind.zhihuishu] ==
          SyncOutcome.signatureRejected;
      if (Storage.flag('zhs_ok')) {
        zhsExpiredNotice = result.zhihuishuSignatureRejected
            ? '智慧树接口校验被拒，可能需要更新 App'
            : '智慧树登录已过期';
      }
      await Storage.setFlag('zhs_ok', false);
      if (epoch != Storage.syncEpoch) return cancelled();
    }
    if (result.outcomes[PlatformKind.xuetangx] == SyncOutcome.loginExpired) {
      result.xuetangxValid = false;
      if (Storage.flag('xtx_ok')) xtxExpiredNotice = '学堂在线登录已过期';
      await Storage.setFlag('xtx_ok', false);
      if (epoch != Storage.syncEpoch) return cancelled();
    }
    if (result.outcomes[PlatformKind.yuketang] == SyncOutcome.loginExpired) {
      result.yuketangValid = false;
      if (Storage.flag('ykt_ok')) yktExpiredNotice = '雨课堂登录已过期';
      await Storage.setFlag('ykt_ok', false);
      if (epoch != Storage.syncEpoch) return cancelled();
    }
    if (epoch != Storage.syncEpoch) return cancelled();
    final fresh = {for (final h in Storage.homework()) h.id: h};

    // 手动隐藏过的条目不再入库（下次同步也不会回来）。快照放到重读磁盘
    // 之后取：dismissed 读得越晚，同步窗口内「恢复隐藏」被开始时的旧状态
    // 当成仍隐藏而丢弃的窗口越小。
    final hidden = Storage.hiddenItems();
    for (final id in hidden.keys) {
      final item = merged[id];
      if (item != null && item.sourceKey != null) {
        await Storage.updateHiddenBody(id, item);
        if (epoch != Storage.syncEpoch) return cancelled();
      }
    }
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
          sourceKey: m.sourceKey,
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

    if (epoch != Storage.syncEpoch) return cancelled();
    await Storage.saveHomework(result.items, fromSync: true);
    if (epoch != Storage.syncEpoch) return cancelled();
    onCommitted?.call();
    final completedAt = DateTime.now();
    for (final p in selected) {
      final outcome = result.outcomes[p]!;
      statuses[p] = (previousStatuses[p] ?? const PlatformSyncStatus()).finish(
        outcome,
        completedAt,
      );
    }
    await Storage.saveSyncStatuses(statuses);
    if (epoch != Storage.syncEpoch) return cancelled();
    await Storage.saveDebugLog(SafeHttp.log);
    // 上课提醒要一并重排：reschedule 会先 cancelAll，漏掉 courses 就会把
    // 课前 15 分钟提醒清光（每次打开 App 都同步，等于提醒常灭）
    await Future.wait([
      updateHomeWidget(visible()),
      NotificationService.reschedule(visible(), courses: Storage.courses()),
    ]);
    if (epoch != Storage.syncEpoch) return cancelled();
    // 过期通知必须在 reschedule 之后弹：reschedule 先 cancelAll，先弹会被
    // 自己清掉，而且去重标志已置位、永远不会再补发
    if (loginExpiredNotice case final notice?) {
      await NotificationService.showSimple(notice, '作业没法同步了，点开作业通重新登录一下');
    }
    if (moocExpiredNotice case final notice?) {
      await NotificationService.showSimple(notice, 'MOOC作业没法同步了，点开作业通重新登录一下');
    }
    if (zhsExpiredNotice case final notice?) {
      await NotificationService.showSimple(notice, '智慧树作业没法同步了，点开作业通重新登录一下');
    }
    if (xtxExpiredNotice case final notice?) {
      await NotificationService.showSimple(notice, '学堂在线作业没法同步了，点开作业通重新登录一下');
    }
    if (yktExpiredNotice case final notice?) {
      await NotificationService.showSimple(notice, '雨课堂作业没法同步了，点开作业通重新登录一下');
    }
    if (epoch != Storage.syncEpoch) result.cancelled = true;
    return result;
  }

  /// Export current-semester visible unfinished items, including overdue /
  /// undated records, using the same semester rule as the app list.
  /// The versioned cache is committed as one value; old cache keys remain readable.
  static Future<void> _widgetExports = Future<void>.value();

  static Future<void> updateHomeWidget(List<HomeworkItem> items) {
    final snapshot = homeworkWidgetSnapshot(items);
    // Edits, logout and synchronization may export concurrently. Preserve call
    // order so an older cache write cannot overtake the latest visible account.
    final write = _widgetExports.then((_) => _publishWidgetSnapshot(snapshot));
    _widgetExports = write;
    return write;
  }

  static Future<void> _publishWidgetSnapshot(
    Map<String, Object> snapshot,
  ) async {
    // Current Android providers read this single authoritative value. Publish
    // and repaint it before optional compatibility keys, whose failures must
    // never keep a hidden/deleted row visible in the current widget.
    var committed = false;
    for (var attempt = 0; attempt < 2 && !committed; attempt++) {
      try {
        committed =
            await HomeWidget.saveWidgetData<String>(
              'homework_snapshot',
              jsonEncode(snapshot),
            ) !=
            false;
      } catch (_) {
        // Retry a transient native channel/commit failure once, in call order.
      }
    }
    if (!committed) {
      widgetPublishError.value = '小组件缓存更新失败，会自动重试';
      return;
    }
    try {
      await HomeWidget.updateWidget(androidName: 'HomeworkWidgetProvider');
      widgetPublishError.value = null;
    } catch (_) {
      widgetPublishError.value = '小组件重绘失败，缓存已保存，会自动重试';
      // Retain the latest committed cache for the next host/app refresh.
    }
    try {
      await HomeWidget.saveWidgetData<String>(
        'items_json',
        jsonEncode(snapshot['items']),
      );
      await HomeWidget.saveWidgetData<String>(
        'stats',
        jsonEncode(snapshot['stats']),
      );
      final at = DateTime.fromMillisecondsSinceEpoch(
        snapshot['updatedAt'] as int,
      );
      await HomeWidget.saveWidgetData<String>(
        'updated',
        '更新 ${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}',
      );
    } catch (_) {
      // Compatibility data never changes business records or gates repainting.
    }
  }
}
