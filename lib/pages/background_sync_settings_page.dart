import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models/homework.dart';
import '../services/background_sync.dart';
import '../services/storage.dart';
import '../services/sync_policy.dart';
import '../services/sync_service.dart';
import '../ui/adaptive.dart';
import '../ui/ink_wash.dart';
import '../ui/style_background.dart';
import '../ui/theme_page_parts.dart';

class BackgroundSyncSettingsPage extends StatelessWidget {
  const BackgroundSyncSettingsPage({super.key, required this.state});
  final AppState state;

  static String time(DateTime? at) => at == null
      ? '尚无完整同步'
      : '${at.month}/${at.day} ${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';

  Future<void> _save(BuildContext context, SyncConfig config) async {
    try {
      await state.setSyncConfig(config);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('设置保存失败，请重试')));
      }
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([
      state,
      BackgroundSync.scheduleError,
      SyncService.widgetPublishError,
    ]),
    builder: (context, _) {
      final config = Storage.syncConfig();
      final accounts = Storage.syncAccounts();
      final statuses = Storage.syncStatuses();
      final ios = defaultTargetPlatform == TargetPlatform.iOS;
      final native =
          !kIsWeb && (ios || defaultTargetPlatform == TargetPlatform.android);
      return StyleBackground(
        child: Scaffold(
          backgroundColor: scaffoldBgOf(context),
          appBar: AppBar(title: appBarTitle(context, '后台同步')),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            children: [
              ThemePanel(
                label: '同步频率',
                icon: Icons.sync_rounded,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('后台自动同步'),
                      subtitle: Text(
                        ios
                            ? '由 iOS 安排刷新作业、小组件和提醒'
                            : native
                            ? '有网络时更新作业、小组件和提醒'
                            : '当前平台暂不支持后台任务',
                      ),
                      value: native && config.enabled,
                      onChanged: native
                          ? (v) => _save(
                              context,
                              SyncConfig(enabled: v, minutes: config.minutes),
                            )
                          : null,
                    ),
                    Text(ios ? '最早后台检查间隔' : '后台检查间隔'),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        for (final minutes in SyncConfig.intervals)
                          ChoiceChip(
                            label: Text(
                              minutes < 60
                                  ? '$minutes 分钟'
                                  : '${minutes ~/ 60} 小时',
                            ),
                            selected: config.minutes == minutes,
                            onSelected: native
                                ? (_) => _save(
                                    context,
                                    SyncConfig(
                                      enabled: config.enabled,
                                      minutes: minutes,
                                    ),
                                  )
                                : null,
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Text('打开 App 时也会检查更新。'),
                    const SizedBox(height: 6),
                    const Text('同步失败后会自动重试，旧记录会保留。'),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              ThemePanel(
                label: '各平台状态',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (accounts.isEmpty) const Text('尚未登录作业平台；课表按本地数据显示和提醒。'),
                    for (final platform in accounts) ...[
                      Text(
                        platform.label,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text('上次完整同步：${time(statuses[platform]?.lastSuccess)}'),
                      if (statuses[platform]?.lastAttempt != null)
                        Text('最近尝试：${time(statuses[platform]!.lastAttempt)}'),
                      Text(switch (statuses[platform]?.outcome) {
                        SyncOutcome.success => '已同步',
                        SyncOutcome.retry =>
                          '未完整同步，保留旧记录；重试时间 ${time(statuses[platform]?.nextRetry)}',
                        SyncOutcome.loginExpired => '登录已过期，请到账号页重新登录',
                        SyncOutcome.signatureRejected =>
                          '接口校验被拒，请检查 App 更新后手动同步',
                        null => '等待首次同步',
                      }),
                      const SizedBox(height: 14),
                    ],
                    OutlinedButton.icon(
                      onPressed: state.syncing ? null : () => state.syncAll(),
                      icon: const Icon(Icons.refresh_rounded),
                      label: Text(state.syncing ? '正在同步…' : '立即同步'),
                    ),
                  ],
                ),
              ),
              if (BackgroundSync.scheduleError.value != null) ...[
                const SizedBox(height: 12),
                Text(BackgroundSync.scheduleError.value!),
              ],
              if (SyncService.widgetPublishError.value != null) ...[
                const SizedBox(height: 12),
                Text(SyncService.widgetPublishError.value!),
              ],
              const SizedBox(height: 12),
              Text(
                ios
                    ? 'iOS 会根据使用频率、电量和网络决定刷新时间，不能保证按所选间隔准点执行。请开启系统后台 App 刷新；手动划掉 App 后，需重新打开才能恢复后台任务。'
                    : '系统省电可能延迟同步，可在手机设置中允许作业通后台运行。',
              ),
            ],
          ),
        ),
      );
    },
  );
}
