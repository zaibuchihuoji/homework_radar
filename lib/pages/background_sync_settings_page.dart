import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models/homework.dart';
import '../services/background_sync.dart';
import '../services/storage.dart';
import '../services/sync_policy.dart';
import '../services/sync_service.dart';
import '../ui/adaptive.dart';
import '../ui/settings_parts.dart';

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
      final android = defaultTargetPlatform == TargetPlatform.android;
      return SettingsScaffold(
        title: '后台同步',
        body: SettingsList(
          children: [
            SettingsSection(
              title: '自动同步',
              footer: '打开 App 时也会检查更新。同步失败后会自动重试，旧记录会保留。',
              children: [
                SettingsSwitchRow(
                  title: '后台自动同步',
                  subtitle: android ? '有网络时更新作业、小组件和提醒' : '后台定时同步目前支持 Android',
                  value: android && config.enabled,
                  onChanged: android
                      ? (v) => _save(
                          context,
                          SyncConfig(enabled: v, minutes: config.minutes),
                        )
                      : null,
                ),
                const SettingsDivider(),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        '后台检查间隔',
                        style: TextStyle(
                          fontSize: 13,
                          color: textSecondary(context),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final minutes in SyncConfig.intervals)
                            ChoiceChip(
                              label: Text(
                                minutes < 60
                                    ? '$minutes 分钟'
                                    : '${minutes ~/ 60} 小时',
                              ),
                              selected: config.minutes == minutes,
                              onSelected: android
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
                    ],
                  ),
                ),
              ],
            ),
            SettingsSection(
              title: '各平台状态',
              children: [
                if (accounts.isEmpty)
                  const SettingsRow(
                    icon: Icons.account_circle_outlined,
                    title: '尚未登录作业平台',
                    subtitle: '课表仍按本地数据显示和提醒',
                  ),
                for (final platform in accounts) ...[
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          platform.label,
                          style: TextStyle(
                            fontSize: 15.5,
                            fontWeight: FontWeight.w500,
                            color: textPrimary(context),
                          ),
                        ),
                        const SizedBox(height: 8),
                        SettingsNote(
                          '上次完整同步：${time(statuses[platform]?.lastSuccess)}',
                        ),
                        if (statuses[platform]?.lastAttempt != null)
                          SettingsNote(
                            '最近尝试：${time(statuses[platform]!.lastAttempt)}',
                          ),
                        const SizedBox(height: 6),
                        SettingsNote(switch (statuses[platform]?.outcome) {
                          SyncOutcome.success => '已同步',
                          SyncOutcome.retry =>
                            '未完整同步，保留旧记录；重试时间 ${time(statuses[platform]?.nextRetry)}',
                          SyncOutcome.loginExpired => '登录已过期，请到账号页重新登录',
                          SyncOutcome.signatureRejected =>
                            '接口校验被拒，请检查 App 更新后手动同步',
                          null => '等待首次同步',
                        }),
                      ],
                    ),
                  ),
                  const SettingsDivider(),
                ],
                SettingsRow(
                  icon: Icons.refresh_rounded,
                  title: state.syncing ? '正在同步…' : '立即同步',
                  onTap: state.syncing ? null : () => state.syncAll(),
                ),
              ],
            ),
            if (BackgroundSync.scheduleError.value != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: SettingsNote(
                  BackgroundSync.scheduleError.value!,
                  warning: true,
                ),
              ),
            if (SyncService.widgetPublishError.value != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: SettingsNote(
                  SyncService.widgetPublishError.value!,
                  warning: true,
                ),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: SettingsNote('系统省电可能延迟同步，可在手机设置中允许作业通后台运行。'),
            ),
          ],
        ),
      );
    },
  );
}
