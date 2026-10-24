import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../app_state.dart';
import '../ui/sync_status_parts.dart';
import '../services/background_sync.dart';
import '../services/storage.dart';
import '../services/sync_policy.dart';
import '../services/sync_service.dart';
import '../ui/adaptive.dart';
import '../ui/activity_icon.dart';
import '../ui/settings_parts.dart';
import 'accounts_page.dart';

class BackgroundSyncSettingsPage extends StatelessWidget {
  const BackgroundSyncSettingsPage({super.key, required this.state});
  final AppState state;

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
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => AccountsPage(state: state),
              ),
            ),
            child: const Text('账号'),
          ),
        ],
        body: SettingsList(
          children: [
            if (state.syncing)
              SyncProgressNotice(busy: true, progress: state.syncProgress)
            else
              SettingsSection(
                children: [
                  SettingsRow(
                    icon: Icons.sync_rounded,
                    title: '作业同步',
                    subtitle: accounts.isEmpty
                        ? '登录平台后可自动获取作业'
                        : '已连接 ${accounts.length} 个作业平台',
                    trailing: IconButton.filledTonal(
                      tooltip: '立即同步',
                      onPressed: () => state.syncAll(),
                      icon: ActivityIcon(
                        Icons.refresh_rounded,
                        active: state.syncing,
                      ),
                    ),
                  ),
                ],
              ),
            if (accounts.isEmpty)
              const SettingsSection(
                children: [
                  SettingsRow(
                    icon: Icons.account_circle_outlined,
                    title: '尚未登录作业平台',
                    subtitle: '请在账号页登录；课表仍按本地数据显示和提醒',
                  ),
                ],
              ),
            for (final platform in accounts)
              SyncPlatformStatus(
                platform: platform,
                status: statuses[platform],
              ),
            if (!state.syncing && state.lastSyncMessage.isNotEmpty)
              SettingsSection(
                title: '本次同步说明',
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: SettingsNote(state.lastSyncMessage),
                  ),
                ],
              ),
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
