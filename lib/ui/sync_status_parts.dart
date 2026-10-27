import 'package:flutter/material.dart';

import '../models/homework.dart';
import '../services/sync_policy.dart';
import 'account_platform_icon.dart';
import 'adaptive.dart';
import 'activity_icon.dart';
import 'settings_parts.dart';

String syncTime(DateTime? at) {
  if (at == null) return '尚无记录';
  final now = DateTime.now();
  final year = at.year == now.year ? '' : '${at.year}/';
  return '$year${at.month}/${at.day} ${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';
}

class SyncProgressNotice extends StatelessWidget {
  const SyncProgressNotice({
    super.key,
    this.progress = '',
    this.message = '',
    this.busy = false,
    this.onDetails,
  });
  final String progress, message;
  final bool busy;
  final VoidCallback? onDetails;
  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: SettingsSection(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ActivityIcon(
                busy ? Icons.sync_rounded : Icons.info_outline_rounded,
                active: busy,
                size: 20,
                color: textSecondary(context),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      busy ? '正在更新作业' : '同步需要关注',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: textPrimary(context),
                      ),
                    ),
                    const SizedBox(height: 5),
                    SettingsNote(
                      busy
                          ? (progress.isEmpty ? '正在检查已登录的平台' : '课程进度 $progress')
                          : message,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (busy)
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 14),
            child: LinearProgressIndicator(minHeight: 2),
          ),
        if (!busy && onDetails != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
            child: Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: onDetails,
                icon: const Icon(Icons.arrow_forward_rounded, size: 16),
                label: const Text('查看同步状态'),
              ),
            ),
          ),
      ],
    ),
  );
}

class SyncPlatformStatus extends StatelessWidget {
  const SyncPlatformStatus({super.key, required this.platform, this.status});
  final PlatformKind platform;
  final PlatformSyncStatus? status;
  @override
  Widget build(BuildContext context) {
    final outcome = status?.outcome;
    final label = switch (outcome) {
      SyncOutcome.success => '完整同步',
      SyncOutcome.retry => '等待重试',
      SyncOutcome.loginExpired => '需重新登录',
      SyncOutcome.signatureRejected => '校验未通过',
      null => '等待首次同步',
    };
    final note = switch (outcome) {
      SyncOutcome.success => '最近一次已完整获取此平台的作业。',
      SyncOutcome.retry => '本次未完整获取，旧记录已保留。',
      SyncOutcome.loginExpired => '自动同步已暂停，请到账号页重新登录。',
      SyncOutcome.signatureRejected => '自动同步已暂停，请检查 App 更新后手动同步。',
      null => '登录后尚无完整同步记录。',
    };
    final icon = switch (outcome) {
      SyncOutcome.success => Icons.check_circle_outline_rounded,
      SyncOutcome.retry => Icons.schedule_rounded,
      SyncOutcome.loginExpired => Icons.person_outline_rounded,
      SyncOutcome.signatureRejected => Icons.error_outline_rounded,
      null => Icons.more_horiz_rounded,
    };
    final index = switch (platform) {
      PlatformKind.chaoxing => 1,
      PlatformKind.mooc => 2,
      PlatformKind.zhihuishu => 3,
      PlatformKind.xuetangx => 4,
      PlatformKind.yuketang => 5,
      PlatformKind.manual => 6,
    };
    return SettingsSection(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  AccountPlatformIcon(index: index, size: 36),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      platform.label,
                      style: serifTitle(
                        context,
                        monoText(
                          context,
                          TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: textPrimary(context),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 7,
                children: [
                  Icon(icon, size: 17, color: textPrimary(context)),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: textPrimary(context),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 7),
              SettingsNote(note),
              if (status?.summary case final summary?) ...[
                const SizedBox(height: 10),
                Text(
                  '新增 ${summary.added} 项 · 更新 ${summary.changed} 项',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: textPrimary(context),
                  ),
                ),
                const SizedBox(height: 4),
                SettingsNote(
                  '保留原记录 ${summary.retained} 项'
                  '${summary.archived > 0 ? ' · 已归档 ${summary.archived} 项' : ''}'
                  '${summary.removed > 0 ? ' · 移出列表 ${summary.removed} 项' : ''}',
                ),
                SettingsNote('结果保存于 ${syncTime(summary.at)}'),
                if (summary.listIncomplete)
                  const SettingsNote('课程列表或登录状态未完整核实，本次结果不代表全部作业。'),
                if (summary.failedRequests > 0)
                  SettingsNote(
                    '记录到 ${summary.failedRequests} 处获取异常，未确认的旧作业继续保留。',
                  ),
                if (summary.details.isNotEmpty)
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: Text('查看未完成项目（${summary.details.length}）'),
                    children: [
                      for (final detail in summary.details)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: SettingsNote(detail),
                          ),
                        ),
                    ],
                  ),
              ],
              if (outcome == SyncOutcome.retry &&
                  status?.nextRetry != null) ...[
                const SizedBox(height: 6),
                SettingsNote('计划重试 ${syncTime(status!.nextRetry)} · 以系统调度为准'),
              ],
            ],
          ),
        ),
        const SettingsDivider(indent: 16),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SettingsNote(
                '上次完整同步：${status?.lastSuccess == null ? '尚无完整同步' : syncTime(status!.lastSuccess)}',
              ),
              if (status?.lastAttempt != null) ...[
                const SizedBox(height: 4),
                SettingsNote('最近尝试：${syncTime(status!.lastAttempt)}'),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
