/// 设置首页与分类详情；数据操作沿用原有服务。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:home_widget/home_widget.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../app_state.dart';
import '../ui/theme_forms.dart';
import '../ui/settings_parts.dart';
import '../ui/focus_parts.dart';
import '../models/homework.dart';
import '../services/backup_service.dart';
import '../services/notification_service.dart';
import '../services/safe_http.dart';
import '../services/storage.dart';
import '../services/app_update_controller.dart';
import 'update_dialog.dart';
import '../ui/adaptive.dart';
import '../ui/ink_wash.dart';
import '../ui/tokens.dart';
import '../ui/dashed_line.dart';
import 'section_times_page.dart';
import 'notification_settings_page.dart';
import 'background_sync_settings_page.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, required this.state});

  final AppState state;
  static Future<PackageInfo>? _packageInfo;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([state, NotificationService.permission]),
    builder: (context, _) {
      final reminders = Storage.reminders();
      final permission = NotificationService.notificationsEnabled;
      final last = state.lastSync;
      final sync = last == null
          ? '尚未同步'
          : '最近 ${last.hour.toString().padLeft(2, '0')}:${last.minute.toString().padLeft(2, '0')} 同步';
      if (paletteOf(context).sunny) {
        return _focusRoot(
          context,
          sync,
          permission,
          reminders.enabledHours.length,
        );
      }
      return SettingsScaffold(
        title: '设置',
        root: true,
        body: SettingsList(
          children: [
            SettingsSection(
              title: '个性化',
              children: [
                SettingsRow(
                  icon: Icons.palette_outlined,
                  title: '外观与小组件',
                  subtitle: '主题、显示模式与桌面组件',
                  value: state.style.label,
                  navigation: true,
                  onTap: () =>
                      _openDetail(context, '外观与小组件', _appearanceSettings),
                ),
              ],
            ),
            SettingsSection(
              title: '日常使用',
              children: [
                SettingsRow(
                  icon: Icons.notifications_none_rounded,
                  title: '提醒与课表',
                  subtitle: permission == false
                      ? '通知权限未开启'
                      : '截止提醒 ${reminders.enabledHours.length} 项 · 上课提醒${Storage.classReminder() ? '已开启' : '已关闭'}',
                  navigation: true,
                  onTap: () => _openDetail(context, '提醒与课表', _reminderSettings),
                ),
                const SettingsDivider(),
                SettingsRow(
                  icon: Icons.sync_rounded,
                  title: '同步与后台',
                  subtitle: sync,
                  navigation: true,
                  onTap: () => _openDetail(context, '同步与后台', _syncSettings),
                ),
              ],
            ),
            SettingsSection(
              title: '管理与支持',
              children: [
                SettingsRow(
                  icon: Icons.folder_open_rounded,
                  title: '数据管理',
                  subtitle: '备份、恢复与隐藏作业',
                  navigation: true,
                  onTap: () => _openDetail(context, '数据管理', _dataSettings),
                ),
                const SettingsDivider(),
                SettingsRow(
                  icon: Icons.info_outline_rounded,
                  title: '关于与帮助',
                  subtitle: '应用更新与问题反馈',
                  navigation: true,
                  onTap: () => _openDetail(context, '关于与帮助', _aboutSettings),
                ),
              ],
            ),
          ],
        ),
      );
    },
  );

  Widget _focusRoot(
    BuildContext context,
    String sync,
    bool? permission,
    int reminders,
  ) => SettingsScaffold(
    title: '设置',
    root: true,
    body: SettingsList(
      children: [
        InkWell(
          onTap: () => _openDetail(context, '外观与小组件', _appearanceSettings),
          borderRadius: BorderRadius.circular(12),
          child: FocusSummary(
            eyebrow: '当前外观',
            title: state.style.label,
            trailing: Icon(
              Icons.palette_outlined,
              size: 30,
              color: paletteOf(context).onAccent,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '外观与小组件',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: paletteOf(context).onAccent,
                    ),
                  ),
                ),
                Icon(
                  Icons.arrow_forward_rounded,
                  size: 20,
                  color: paletteOf(context).onAccent,
                ),
              ],
            ),
          ),
        ),
        const FocusSectionTitle('学习偏好'),
        SettingsRow(
          icon: Icons.notifications_none_rounded,
          title: '提醒与课表',
          subtitle: permission == false
              ? '通知权限未开启'
              : '截止提醒 $reminders 项 · 上课提醒${Storage.classReminder() ? '已开启' : '已关闭'}',
          navigation: true,
          onTap: () => _openDetail(context, '提醒与课表', _reminderSettings),
        ),
        const SettingsDivider(indent: 0),
        SettingsRow(
          icon: Icons.sync_outlined,
          title: '同步与后台',
          subtitle: sync,
          navigation: true,
          onTap: () => _openDetail(context, '同步与后台', _syncSettings),
        ),
        const FocusSectionTitle('数据与支持'),
        SettingsRow(
          icon: Icons.folder_open_outlined,
          title: '数据管理',
          subtitle: '备份、恢复与隐藏作业',
          navigation: true,
          onTap: () => _openDetail(context, '数据管理', _dataSettings),
        ),
        const SettingsDivider(indent: 0),
        SettingsRow(
          icon: Icons.info_outline_rounded,
          title: '关于与帮助',
          subtitle: '应用更新与问题反馈',
          navigation: true,
          onTap: () => _openDetail(context, '关于与帮助', _aboutSettings),
        ),
      ],
    ),
  );

  Widget _focusDetailIntro(BuildContext context, String title) {
    final (eyebrow, headline, detail) = switch (title) {
      '外观与小组件' => ('当前主题', state.style.label, '显示模式、主题与桌面小组件在这里统一设置。'),
      '提醒与课表' => (
        '作业截止提醒',
        '${Storage.reminders().enabledHours.length} 个提醒时点',
        '按你的习惯安排截止与上课提醒。',
      ),
      '同步与后台' => (
        '作业同步',
        state.syncing
            ? '正在同步…'
            : state.lastSync == null
            ? '尚未同步'
            : '最近 ${state.lastSync!.hour.toString().padLeft(2, '0')}:${state.lastSync!.minute.toString().padLeft(2, '0')}',
        '后台检查、同步记录与平台状态。',
      ),
      '数据管理' => (
        '当前数据',
        '${state.homework.length} 项作业 · ${state.courses.length} 门课',
        '导出备份、恢复数据或管理隐藏记录。',
      ),
      _ => ('作业通', '关于与帮助', ''),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: FocusSummary(
        eyebrow: eyebrow,
        title: headline,
        detail: detail.isEmpty ? null : detail,
      ),
    );
  }

  void _openDetail(
    BuildContext context,
    String title,
    List<Widget> Function(BuildContext) content,
  ) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ListenableBuilder(
          listenable: Listenable.merge([
            state,
            NotificationService.permission,
            NotificationService.scheduleError,
            AppUpdateController.instance,
          ]),
          builder: (context, _) => SettingsScaffold(
            title: title,
            body: SettingsList(
              children: [
                if (paletteOf(context).sunny && title != '关于与帮助')
                  _focusDetailIntro(context, title),
                ...content(context),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _appearanceSettings(BuildContext context) {
    final locked =
        state.style != ThemeStyle.clean && state.style != ThemeStyle.green;
    return [
      SettingsSection(
        title: '界面',
        children: [
          _stylePicker(context, state),
          _divider(context),
          SettingsRow(
            icon: Icons.contrast_rounded,
            title: '主题模式',
            subtitle: locked ? '此主题仅支持浅色' : null,
            value: locked
                ? null
                : switch (state.themeMode) {
                    ThemeMode.light => '浅色',
                    ThemeMode.dark => '深色',
                    _ => '跟随系统',
                  },
            onTap: locked ? null : () => _pickThemeMode(context, state),
            navigation: !locked,
            trailing: locked
                ? Icon(
                    Icons.lock_outline_rounded,
                    size: 18,
                    color: textFaint(context),
                  )
                : null,
          ),
        ],
      ),
      SettingsSection(
        title: '桌面',
        children: [
          SettingsRow(
            icon: Icons.widgets_outlined,
            title: '桌面小组件',
            subtitle: '添加方式、透明背景与壁纸',
            navigation: true,
            onTap: () => _showWidgetGuide(context),
          ),
        ],
      ),
    ];
  }

  List<Widget> _reminderSettings(BuildContext context) {
    final r = Storage.reminders();
    return [
      if (NotificationService.notificationsEnabled == false)
        SettingsSection(
          children: [
            SettingsRow(
              icon: Icons.notifications_off_outlined,
              title: '通知权限被拒绝',
              subtitle: '开启通知权限后，才能收到作业和上课提醒',
              navigation: true,
              onTap: () => NotificationService.rerequestPermission(),
            ),
          ],
        ),
      if (NotificationService.scheduleError.value != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: SettingsNote(
            NotificationService.scheduleError.value!,
            warning: true,
          ),
        ),
      SettingsSection(
        title: '作业截止提醒',
        footer: '${r.enabledHours.length}/3 项已开启',
        children: [
          _switchTile(
            context,
            icon: Icons.notifications_active_outlined,
            title: '截止前 24 小时',
            value: r.before24h,
            onChanged: (v) => state.updateReminders(r..before24h = v),
          ),
          SettingsDivider(indent: paletteOf(context).clean ? 16 : 62),
          _switchTile(
            context,
            icon: Icons.schedule_rounded,
            title: '截止前 6 小时',
            value: r.before6h,
            onChanged: (v) => state.updateReminders(r..before6h = v),
          ),
          SettingsDivider(indent: paletteOf(context).clean ? 16 : 62),
          _switchTile(
            context,
            icon: Icons.alarm_rounded,
            title: '截止前 1 小时',
            value: r.before1h,
            onChanged: (v) => state.updateReminders(r..before1h = v),
          ),
        ],
      ),
      SettingsSection(
        title: '课表',
        children: [
          _switchTile(
            context,
            icon: Icons.school_outlined,
            title: '上课前 15 分钟提醒',
            subtitle: Storage.classReminder() && Storage.semesterStart() == null
                ? '请先在课表页设置开学日期'
                : null,
            value: Storage.classReminder(),
            onChanged: state.updateClassReminder,
          ),
          SettingsDivider(indent: paletteOf(context).clean ? 16 : 62),
          SettingsRow(
            icon: Icons.access_time_rounded,
            title: '作息时间',
            subtitle: '按学校作息调整每节课时间',
            navigation: true,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => SectionTimesPage(state: state),
              ),
            ),
          ),
        ],
      ),
      if (defaultTargetPlatform == TargetPlatform.android)
        SettingsSection(
          title: '系统通知',
          children: [
            SettingsRow(
              icon: Icons.tune_rounded,
              title: '通知横幅与声音',
              navigation: true,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => NotificationSettingsPage(
                    homeworkId: state.homework
                        .where((h) => h.status != HwStatus.done)
                        .firstOrNull
                        ?.id,
                  ),
                ),
              ),
            ),
          ],
        ),
    ];
  }

  List<Widget> _syncSettings(BuildContext context) {
    final last = state.lastSync;
    final syncText = last == null
        ? '还没有同步过'
        : '${last.month}月${last.day}日 ${last.hour.toString().padLeft(2, '0')}:${last.minute.toString().padLeft(2, '0')}';
    return [
      SettingsSection(
        title: '同步方式',
        children: [
          SettingsRow(
            icon: Icons.sync_rounded,
            title: '后台同步',
            subtitle: Storage.syncConfig().enabled
                ? '每 ${Storage.syncConfig().minutes} 分钟检查'
                : '后台定时已关闭',
            navigation: true,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => BackgroundSyncSettingsPage(state: state),
              ),
            ),
          ),
        ],
      ),
      SettingsSection(
        title: '同步状态',
        children: [
          SettingsRow(
            icon: Icons.history_rounded,
            title: '上次同步',
            subtitle: syncText,
            onLongPress: () => Navigator.of(
              context,
            ).push(MaterialPageRoute<void>(builder: (_) => const DebugPage())),
          ),
          _divider(context),
          SettingsRow(
            icon: Icons.refresh_rounded,
            title: '立即同步全部作业',
            onTap: state.syncing ? null : () => state.syncAll(),
            trailing: state.syncing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : null,
          ),
        ],
      ),
    ];
  }

  List<Widget> _dataSettings(BuildContext context) => [
    SettingsSection(
      title: '备份与恢复',
      footer: '备份包含作业、课表、作息和隐藏记录，不包含账号登录信息。',
      children: [
        SettingsRow(
          icon: Icons.file_upload_outlined,
          title: '导出数据',
          subtitle: '将当前数据保存为备份文件',
          navigation: true,
          onTap: () => _exportBackup(context),
        ),
        _divider(context),
        SettingsRow(
          icon: Icons.file_download_outlined,
          title: '导入数据',
          subtitle: '从备份文件恢复',
          navigation: true,
          onTap: () => _importBackup(context, state),
        ),
      ],
    ),
    SettingsSection(
      title: '记录管理',
      children: [
        SettingsRow(
          icon: Icons.visibility_off_outlined,
          title: '已隐藏的作业',
          subtitle: '查看与恢复左滑隐藏的作业',
          navigation: true,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => HiddenPage(state: state)),
          ),
        ),
        _divider(context),
        SettingsRow(
          icon: Icons.inventory_2_outlined,
          title: '历史账号数据',
          subtitle: '只读查看或导出换号前的记录',
          navigation: true,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const AccountArchivesPage(),
            ),
          ),
        ),
      ],
    ),
  ];

  List<Widget> _aboutSettings(BuildContext context) => [
    Padding(
      padding: const EdgeInsets.fromLTRB(4, 24, 4, 28),
      child: Row(
        children: [
          Image.asset('assets/icon/icon_rounded.png', width: 54, height: 54),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '作业通',
                  style: serifTitle(
                    context,
                    TextStyle(
                      fontSize: 23,
                      fontWeight: FontWeight.w600,
                      color: textPrimary(context),
                    ),
                  ),
                ),
                FutureBuilder<PackageInfo>(
                  future: _packageInfo ??= PackageInfo.fromPlatform(),
                  builder: (context, snapshot) => snapshot.hasData
                      ? Padding(
                          padding: const EdgeInsets.only(top: 5),
                          child: SettingsNote('版本 ${snapshot.data!.version}'),
                        )
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
    SettingsSection(
      title: '应用',
      children: [
        SettingsRow(
          icon: Icons.system_update_outlined,
          title: '检查更新',
          subtitle: AppUpdateController.instance.status.label,
          navigation: true,
          onTap: () => checkForAppUpdate(context),
        ),
      ],
    ),
    SettingsSection(
      title: '支持',
      children: [
        for (final email in _feedbackEmails)
          SettingsRow(
            icon: Icons.mail_outline_rounded,
            title: '联系开发者',
            subtitle: email,
            trailing: Icon(
              Icons.copy_rounded,
              size: 18,
              color: textFaint(context),
            ),
            onTap: () => _copyFeedbackEmail(context, email),
          ),
      ],
    ),
    const Padding(
      padding: EdgeInsets.symmetric(horizontal: 4),
      child: SettingsNote('仅同步你已登录账号的作业数据。'),
    ),
  ];

  /// 关于与帮助中的反馈地址，点击复制。
  static const List<String> _feedbackEmails = ['yaohuizheng22@gmail.com'];

  void _copyFeedbackEmail(BuildContext context, String email) {
    Clipboard.setData(ClipboardData(text: email));
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('已复制 $email')));
  }

  Future<void> _exportBackup(BuildContext context) async {
    try {
      final bytes = Uint8List.fromList(utf8.encode(BackupService.encode()));
      final now = DateTime.now();
      final name =
          'homework_radar_'
          '${now.year}${now.month.toString().padLeft(2, '0')}'
          '${now.day.toString().padLeft(2, '0')}.json';
      final path = await FilePicker.saveFile(
        fileName: name,
        bytes: bytes,
        mimeType: 'application/json',
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(path == null ? '已取消导出' : '已导出到 $path')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('导出失败：$e')));
    }
  }

  Future<void> _importBackup(BuildContext context, AppState state) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => SettingsAlertDialog(
        title: const Text('导入备份'),
        content: const Text(
          '将覆盖当前课表、作业与相关设置，'
          '账号登录不受影响。继续？',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('导入'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      final path = files.isEmpty ? null : files.single.path;
      if (path == null || !context.mounted) return;
      final msg = await BackupService.importJson(File(path).readAsStringSync());
      await state.reloadLocal();
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } on FormatException catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('导入失败：$e')));
    }
  }

  void _pickThemeMode(BuildContext context, AppState state) {
    final options = [
      (ThemeMode.system, '跟随系统', Icons.brightness_auto_outlined),
      (ThemeMode.light, '浅色', Icons.light_mode_outlined),
      (ThemeMode.dark, '深色', Icons.dark_mode_outlined),
    ];
    showDialog<void>(
      context: context,
      builder: (dialogContext) => SettingsAlertDialog(
        title: const Text('主题模式'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (mode, label, icon) in options)
              SettingsRow(
                icon: icon,
                title: label,
                trailing: state.themeMode == mode
                    ? Icon(
                        Icons.check_rounded,
                        color: accentColor(dialogContext),
                        size: 20,
                      )
                    : null,
                onTap: () {
                  state.setThemeMode(mode);
                  Navigator.of(dialogContext).pop();
                },
              ),
          ],
        ),
      ),
    );
  }

  /// 两列主题预览；选择后立即保存并关闭弹层。
  Widget _stylePicker(BuildContext context, AppState state) {
    return _tile(
      context,
      icon: Icons.palette_outlined,
      title: '界面风格',
      subtitle: state.style.label,
      trailing: Icon(
        Icons.chevron_right_rounded,
        color: textSecondary(context),
      ),
      onTap: () => _showStylePicker(context, state),
    );
  }

  void _showStylePicker(BuildContext context, AppState state) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => ThemeModalSurface(
        child: FractionallySizedBox(
          heightFactor: 0.85,
          child: ListenableBuilder(
            listenable: state,
            builder: (_, _) => ListView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '界面风格',
                        style: serifTitle(
                          context,
                          TextStyle(
                            fontSize: 21,
                            fontWeight: FontWeight.w600,
                            color: textPrimary(context),
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: '关闭',
                      onPressed: () => Navigator.of(sheetContext).pop(),
                      icon: const Icon(Icons.close_rounded, size: 21),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  '选择后立即生效',
                  style: TextStyle(
                    fontSize: 13,
                    color: textSecondary(sheetContext),
                  ),
                ),
                const SizedBox(height: 20),
                LayoutBuilder(
                  builder: (context, constraints) => Wrap(
                    spacing: 14,
                    runSpacing: 20,
                    children: [
                      for (final style in [
                        ThemeStyle.clean,
                        ThemeStyle.green,
                        ...ThemeStyle.values.where(
                          (s) => s != ThemeStyle.clean && s != ThemeStyle.green,
                        ),
                      ])
                        _styleThumb(
                          context,
                          state,
                          style,
                          style == state.style,
                          width: (constraints.maxWidth - 14) / 2,
                          previewHeight: 96,
                          onSelected: () {
                            if (sheetContext.mounted) {
                              Navigator.of(sheetContext).pop();
                            }
                          },
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _styleThumb(
    BuildContext context,
    AppState state,
    ThemeStyle style,
    bool selected, {
    double width = 92,
    double previewHeight = 64,
    VoidCallback? onSelected,
  }) {
    final bright = (style == ThemeStyle.clean || style == ThemeStyle.green)
        ? Theme.of(context).brightness
        : Brightness.light;
    final pal = stylePalette(style, bright);
    return Semantics(
      button: true,
      selected: selected,
      child: GestureDetector(
        onTap: () async {
          await state.setStyle(style);
          onSelected?.call();
        },
        child: SizedBox(
          width: width,
          child: Column(
            children: [
              Container(
                height: previewHeight,
                decoration: BoxDecoration(
                  color: pal.bg,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: selected
                        ? pal.accent
                        : isDark(context)
                        ? Tokens.cardBorderDark
                        : const Color(0xFFE3E5E9),
                    width: selected ? 2 : 1,
                  ),
                ),
                padding: const EdgeInsets.all(9),
                child: _thumbBody(style, pal, bright == Brightness.dark),
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    style.label,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      color: selected
                          ? accentColor(context)
                          : textSecondary(context),
                    ),
                  ),
                  if (selected) ...[
                    const SizedBox(width: 3),
                    Icon(
                      Icons.check_circle_rounded,
                      size: 13,
                      color: accentColor(context),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 缩略图画的是每套主题的结构签名，不是同一模板换色：
  /// 清夏=灰底白卡圆点（基准）；莫兰迪=奶白软卡豆沙点；像素=直角描边硬投影；墨黑=淡墨洗卡
  /// （笔锋圆角）+ 墨滴 + 飞白横笔 + 朱砂小印；暖纸=缝线虚线框印刷卡；
  /// 漫画=剪影描边贴纸 + 硬投影、微斜。
  Widget _thumbBody(ThemeStyle style, StylePalette pal, bool dark) {
    Widget bar({double alpha = 0.55}) => Expanded(
      child: Container(
        height: 3,
        decoration: BoxDecoration(
          color: pal.ink2.withValues(alpha: alpha),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );

    return switch (style) {
      // ---- 墨黑：墨洗卡（笔锋圆角）上浮墨滴、飞白与一枚斜钤朱砂小印 ----
      ThemeStyle.amoled => Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: pal.cardWash ?? [pal.card, pal.card],
                ),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(11),
                  topRight: Radius.circular(4),
                  bottomRight: Radius.circular(11),
                  bottomLeft: Radius.circular(4),
                ),
              ),
            ),
          ),
          Positioned(
            top: 7,
            left: 7,
            right: 14,
            child: Row(
              children: [
                Container(
                  width: 11,
                  height: 11,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        (dark ? Colors.white : Colors.black).withValues(
                          alpha: 0.28,
                        ),
                        (dark ? Colors.white : Colors.black).withValues(
                          alpha: 0.04,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                bar(alpha: 0.5),
              ],
            ),
          ),
          Positioned(
            top: 3,
            right: 3,
            child: Transform.rotate(
              angle: -0.06,
              child: Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  color: pal.accent,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 7,
            left: 7,
            right: 7,
            child: Row(
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: pal.accent,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 5),
                Expanded(
                  child: BrushLine(
                    color: pal.ink2.withValues(alpha: 0.6),
                    thickness: 2,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      // ---- 暖纸：白纸印刷卡 + 缝线虚线内框 + 方角章形块 ----
      ThemeStyle.paper => Container(
        padding: const EdgeInsets.all(5),
        decoration: BoxDecoration(
          color: pal.card,
          borderRadius: BorderRadius.circular(pal.radius / 2),
          border: Border.all(color: pal.cardBorder),
        ),
        foregroundDecoration: StitchDecoration(
          radius: pal.radius / 2 + 5,
          color: pal.cardBorder,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: pal.accentFill.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(2),
                    border: Border.all(
                      color: pal.ink2.withValues(alpha: 0.5),
                      width: 0.8,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                bar(),
              ],
            ),
            const Spacer(),
            Row(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: pal.accentFill.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(3),
                    border: Border.all(
                      color: pal.ink.withValues(alpha: 0.55),
                      width: 1,
                    ),
                  ),
                ),
                const SizedBox(width: 5),
                bar(alpha: 0.3),
              ],
            ),
          ],
        ),
      ),
      // ---- 漫画：微斜白贴纸卡（剪影描边+硬投影）+ 一枚斜贴小贴纸 ----
      ThemeStyle.comic => Column(
        children: [
          Transform.rotate(
            angle: -0.03,
            child: Container(
              height: 22,
              padding: const EdgeInsets.symmetric(horizontal: 5),
              decoration: BoxDecoration(
                color: pal.card,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: pal.cardBorder, width: 1.6),
                boxShadow: [
                  BoxShadow(
                    color: pal.cardBorder,
                    blurRadius: 0,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: pal.accentFill.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  const SizedBox(width: 4),
                  bar(alpha: 0.45),
                ],
              ),
            ),
          ),
          const Spacer(),
          Row(
            children: [
              Transform.rotate(
                angle: 0.04,
                child: Container(
                  width: 13,
                  height: 13,
                  decoration: BoxDecoration(
                    color: pal.accentFill.withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: pal.cardBorder, width: 1.3),
                  ),
                ),
              ),
              const SizedBox(width: 5),
              bar(alpha: 0.3),
            ],
          ),
        ],
      ),
      // ---- 莫兰迪：燕麦底上的奶白软卡 + 豆沙圆点 ----
      ThemeStyle.morandi => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 22,
            padding: const EdgeInsets.symmetric(horizontal: 5),
            decoration: BoxDecoration(
              color: pal.card,
              borderRadius: BorderRadius.circular(8),
              boxShadow: pal.shadow.isEmpty ? null : [pal.shadow.first],
            ),
            child: Row(
              children: [
                Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    color: pal.accentFill.withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(width: 4),
                bar(alpha: 0.5),
              ],
            ),
          ),
          const Spacer(),
          Row(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: pal.accentFill.withValues(alpha: 0.8),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 5),
              bar(alpha: 0.3),
            ],
          ),
        ],
      ),
      // ---- 像素：直角卡 + 近黑描边 + 对角硬投影 + HUD 方块 ----
      ThemeStyle.pixel => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 22,
            padding: const EdgeInsets.symmetric(horizontal: 5),
            decoration: BoxDecoration(
              color: pal.card,
              borderRadius: BorderRadius.circular(2),
              border: Border.all(color: pal.cardBorder, width: 1.6),
              boxShadow: [
                BoxShadow(
                  color: pal.cardBorder,
                  blurRadius: 0,
                  offset: const Offset(2, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    color: pal.accent,
                    borderRadius: BorderRadius.circular(1),
                  ),
                ),
                const SizedBox(width: 4),
                bar(alpha: 0.5),
              ],
            ),
          ),
          const Spacer(),
          Row(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: pal.accent,
                  borderRadius: BorderRadius.circular(1),
                  border: Border.all(color: pal.cardBorder, width: 1.2),
                ),
              ),
              const SizedBox(width: 5),
              bar(alpha: 0.3),
            ],
          ),
        ],
      ),
      // ---- 清夏：基准形态——白卡圆角 + 品牌圆点 ----
      ThemeStyle.clean || ThemeStyle.green => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 22,
            padding: const EdgeInsets.symmetric(horizontal: 5),
            decoration: BoxDecoration(
              color: pal.card,
              borderRadius: BorderRadius.circular(pal.radius / 2),
              boxShadow: pal.shadow.isEmpty ? null : [pal.shadow.first],
            ),
            child: Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: pal.accentFill.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(width: 4),
                bar(),
              ],
            ),
          ),
          const Spacer(),
          Row(
            children: [
              Container(
                width: 13,
                height: 13,
                decoration: BoxDecoration(
                  color: pal.accentFill,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 5),
              bar(alpha: 0.3),
            ],
          ),
        ],
      ),
      // ---- 小票：锯齿撕纸白条 + 宽窄条码 + 一枚细框红章 ----
      ThemeStyle.receipt => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipPath(
            clipper: _ThumbTearClipper(),
            child: Container(
              height: 32,
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
              decoration: BoxDecoration(
                color: pal.card,
                border: Border.all(
                  color: pal.cardBorder.withValues(alpha: 0.6),
                  width: 0.8,
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        for (var i = 0; i < 12; i++)
                          Container(
                            width: i % 3 == 0 ? 2.2 : 1.1,
                            margin: const EdgeInsets.symmetric(horizontal: 0.9),
                            color: pal.ink.withValues(alpha: 0.65),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(
                      border: Border.all(color: pal.accent, width: 1.3),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Spacer(),
          bar(alpha: 0.22),
        ],
      ),
      // ---- 杂志：顶部粗规则线 + 巨大日期数字 + 瑞士红方块，纯平 ----
      ThemeStyle.editorial => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 2,
            width: double.infinity,
            color: pal.ink.withValues(alpha: 0.85),
          ),
          const SizedBox(height: 5),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '05',
                style: TextStyle(
                  fontSize: 25,
                  height: 1,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -1,
                  color: pal.ink,
                ),
              ),
              const Spacer(),
              Container(
                width: 8,
                height: 8,
                margin: const EdgeInsets.only(bottom: 2),
                color: pal.accent,
              ),
            ],
          ),
          const Spacer(),
          Container(
            height: 1,
            width: double.infinity,
            color: pal.ink2.withValues(alpha: 0.35),
          ),
        ],
      ),
      // ---- 终端：1px 单线窗格 + 提示符与光标块 ----
      ThemeStyle.terminal => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(5),
        decoration: BoxDecoration(
          color: pal.card,
          borderRadius: BorderRadius.circular(2),
          border: Border.all(color: pal.cardBorder, width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  '>',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    fontFamily: 'monospace',
                    color: pal.accent,
                  ),
                ),
                const SizedBox(width: 3),
                bar(alpha: 0.5),
              ],
            ),
            const Spacer(),
            Row(
              children: [
                Container(width: 5, height: 9, color: pal.accent),
                const SizedBox(width: 4),
                bar(alpha: 0.3),
              ],
            ),
          ],
        ),
      ),
      // ---- 手账：便签白卡 + 斜贴的半透明胶带 ----
      ThemeStyle.journal => Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            height: 27,
            padding: const EdgeInsets.symmetric(horizontal: 5),
            decoration: BoxDecoration(
              color: pal.card,
              borderRadius: BorderRadius.circular(3),
              border: Border.all(
                color: pal.cardBorder.withValues(alpha: 0.8),
                width: 0.8,
              ),
              boxShadow: pal.shadow.isEmpty ? null : [pal.shadow.first],
            ),
            child: Row(children: [bar(alpha: 0.45)]),
          ),
          Positioned(
            top: -4,
            left: 14,
            child: Transform.rotate(
              angle: -0.09,
              child: Container(
                width: 30,
                height: 9,
                color: const Color(0xFFA8C0D8).withValues(alpha: 0.85),
              ),
            ),
          ),
        ],
      ),
    };
  }

  Widget _divider(BuildContext context) => const SettingsDivider();

  Widget _switchTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    String? subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) => SettingsSwitchRow(
    icon: paletteOf(context).clean ? null : icon,
    title: title,
    subtitle: subtitle,
    value: value,
    onChanged: onChanged,
  );

  Widget _tile(
    BuildContext context, {
    required IconData icon,
    required String title,
    String? subtitle,
    Widget? trailing,
    VoidCallback? onTap,
    VoidCallback? onLongPress,
  }) => SettingsRow(
    icon: icon,
    title: title,
    subtitle: subtitle,
    trailing: trailing,
    onTap: onTap,
    onLongPress: onLongPress,
  );

  /// 小组件没有应用内的开关，添加入口在系统桌面；
  /// 安卓也不开放"直接跳到微件选择器"的 API，只能给步骤引导。
  /// 弹窗里带个性化设置：背景 白卡 / 透明，改完立即刷新桌面小组件。
  Future<void> _showWidgetGuide(BuildContext context) async {
    final steps = const [
      ('回到手机桌面，长按空白处', Icons.touch_app_rounded),
      ('弹出菜单里点「微件」（部分手机叫「小组件」）', Icons.apps_rounded),
      ('找到「作业通」，选择「最近作业」或「今日课表」拖到桌面', Icons.drive_file_move_rounded),
    ];
    var transparent =
        await HomeWidget.getWidgetData<bool>('widget_transparent') ?? false;
    var glassBgPath = await HomeWidget.getWidgetData<String>('glass_bg_path');
    if (!context.mounted) return;
    showDialog<void>(
      context: context,
      builder: (dialogContext) => SettingsAlertDialog(
        title: const Text('添加桌面小组件'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 480),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < steps.length; i++) ...[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 22,
                        height: 22,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: accentColor(dialogContext)
                              .withValues(alpha: 0.2),
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          '${i + 1}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: accentColor(dialogContext),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            steps[i].$1,
                            style: TextStyle(
                              fontSize: 13.5,
                              height: 1.45,
                              color: textPrimary(dialogContext),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (i != steps.length - 1) const SizedBox(height: 12),
                ],
                const SizedBox(height: 16),
                Text(
                  '外观跟随 App 主题，也可以选择透明背景。',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: textSecondary(dialogContext),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  '小组件背景',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: textPrimary(dialogContext),
                  ),
                ),
                const SizedBox(height: 8),
                StatefulBuilder(
                  builder: (context, setDialogState) => Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SegmentedButton<bool>(
                        segments: const [
                          ButtonSegment(
                            value: false,
                            icon: Icon(Icons.crop_square_rounded, size: 17),
                            label: Text('跟随主题'),
                          ),
                          ButtonSegment(
                            value: true,
                            icon: Icon(Icons.blur_on_rounded, size: 17),
                            label: Text('透明'),
                          ),
                        ],
                        selected: {transparent},
                        onSelectionChanged: (sel) async {
                          final v = sel.first;
                          transparent = v;
                          setDialogState(() {});
                          await HomeWidget.saveWidgetData<bool>(
                            'widget_transparent',
                            v,
                          );
                          // 两个小组件都立即重绘
                          await HomeWidget.updateWidget(
                            androidName: 'HomeworkWidgetProvider',
                          );
                          await HomeWidget.updateWidget(
                            androidName: 'TimetableWidgetProvider',
                          );
                        },
                      ),
                      const SizedBox(height: 10),
                      // 液态玻璃的素材：未选图 = 半透玻璃面板（壁纸真实透出）；选图 = 真实折射
                      Row(
                        children: [
                          Icon(
                            Icons.wallpaper_rounded,
                            size: 15,
                            color: textSecondary(dialogContext),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              (glassBgPath ?? '').isEmpty
                                  ? '玻璃底图：半透玻璃（壁纸透出）'
                                  : '玻璃底图：已选图',
                              style: TextStyle(
                                fontSize: 12.5,
                                color: textSecondary(dialogContext),
                              ),
                            ),
                          ),
                          TextButton.icon(
                            onPressed: () async {
                              final picked = await ImagePicker().pickImage(
                                source: ImageSource.gallery,
                                maxWidth: 1600,
                                imageQuality: 88,
                              );
                              if (picked == null) return;
                              final dir =
                                  await getApplicationSupportDirectory();
                              final dest = File(
                                '${dir.path}${Platform.pathSeparator}widget_glass_bg.jpg',
                              );
                              await dest.parent.create(recursive: true);
                              await File(picked.path).copy(dest.path);
                              await HomeWidget.saveWidgetData<String>(
                                'glass_bg_path',
                                dest.path,
                              );
                              await HomeWidget.updateWidget(
                                androidName: 'HomeworkWidgetProvider',
                              );
                              await HomeWidget.updateWidget(
                                androidName: 'TimetableWidgetProvider',
                              );
                              setDialogState(() => glassBgPath = dest.path);
                            },
                            icon: const Icon(
                              Icons.add_photo_alternate_rounded,
                              size: 16,
                            ),
                            label: const Text(
                              '选图',
                              style: TextStyle(fontSize: 12.5),
                            ),
                          ),
                          if ((glassBgPath ?? '').isNotEmpty)
                            TextButton.icon(
                              onPressed: () async {
                                final f = File(glassBgPath!);
                                if (await f.exists()) await f.delete();
                                await HomeWidget.saveWidgetData<String>(
                                  'glass_bg_path',
                                  '',
                                );
                                await HomeWidget.updateWidget(
                                  androidName: 'HomeworkWidgetProvider',
                                );
                                await HomeWidget.updateWidget(
                                  androidName: 'TimetableWidgetProvider',
                                );
                                setDialogState(() => glassBgPath = '');
                              },
                              icon: const Icon(Icons.undo_rounded, size: 16),
                              label: const Text(
                                '清除',
                                style: TextStyle(fontSize: 12.5),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.info_outline_rounded,
                      size: 15,
                      color: textSecondary(dialogContext),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '长按小组件可调整大小，列表可以上下滑动。'
                        '更换壁纸后，可重新选择玻璃底图。',
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.45,
                          color: textSecondary(dialogContext),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }
}

class AccountArchivesPage extends StatelessWidget {
  const AccountArchivesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final archives = Storage.accountArchives().reversed.toList();
    return SettingsScaffold(
      title: '历史账号数据',
      body: archives.isEmpty
          ? const Center(child: SettingsNote('暂无历史归档'))
          : SettingsList(
              children: [
                SettingsSection(
                  title: '只读归档',
                  footer: '查看与导出不会修改当前账号。',
                  children: [
                    for (var i = 0; i < archives.length; i++) ...[
                      if (i > 0) const SettingsDivider(),
                      SettingsRow(
                        icon: Icons.inventory_2_outlined,
                        title: '${archives[i]['platform']}',
                        subtitle:
                            '${archives[i]['createdAt']}\n'
                            '${(archives[i]['homework'] as List? ?? const []).length} 条作业 · '
                            '${(archives[i]['hiddenItems'] as Map? ?? const {}).length} 条隐藏作业 · '
                            '${(archives[i]['courses'] as List? ?? const []).length} 门课程',
                        navigation: true,
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) =>
                                _AccountArchiveDetail(archive: archives[i]),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
    );
  }
}

class _AccountArchiveDetail extends StatelessWidget {
  const _AccountArchiveDetail({required this.archive});
  final Map<String, dynamic> archive;

  Future<void> _export(BuildContext context) async {
    try {
      final id = (archive['id'] ?? 'history').toString().replaceAll(
        RegExp(r'[^a-zA-Z0-9_-]'),
        '_',
      );
      final path = await FilePicker.saveFile(
        fileName: 'account_archive_$id.json',
        bytes: Uint8List.fromList(utf8.encode(jsonEncode(archive))),
        mimeType: 'application/json',
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(path == null ? '已取消导出' : '已导出历史归档')),
        );
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('导出失败，请重试')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final visible = (archive['homework'] as List? ?? const []).whereType<Map>();
    final hidden = (archive['hiddenItems'] as Map? ?? const {}).values;
    final tasks = <Map>[...visible];
    for (final value in hidden) {
      try {
        final decoded = value is String ? jsonDecode(value) : value;
        if (decoded is Map) tasks.add({...decoded, '_hidden': true});
      } catch (_) {
        /* 原始归档仍可完整导出，坏条目不阻塞其余内容。 */
      }
    }
    final courses = (archive['courses'] as List? ?? const []).whereType<Map>();
    return SettingsScaffold(
      title: '归档详情（只读）',
      actions: [
        IconButton(
          tooltip: '导出归档',
          icon: const Icon(Icons.file_upload_outlined),
          onPressed: () => _export(context),
        ),
      ],
      body: SettingsList(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(4, 8, 4, 12),
            child: SettingsNote('此处保留换号或替换前的数据。查看与导出不会修改当前账号。'),
          ),
          if (tasks.isNotEmpty)
            SettingsSection(
              title: '作业',
              children: [
                for (var i = 0; i < tasks.length; i++) ...[
                  if (i > 0) const SettingsDivider(),
                  SettingsRow(
                    title: '${tasks[i]['title'] ?? '未命名作业'}',
                    subtitle:
                        '${tasks[i]['course'] ?? ''}${tasks[i]['_hidden'] == true ? ' · 已隐藏' : ''}'
                        '${tasks[i]['note'] == null ? '' : '\n${tasks[i]['note']}'}',
                  ),
                ],
              ],
            ),
          if (courses.isNotEmpty)
            SettingsSection(
              title: '课程',
              children: [
                for (final course in courses)
                  SettingsRow(
                    title: '${course['name'] ?? '未命名课程'}',
                    subtitle:
                        '周${course['weekday']} · 第${course['startSection']}-${course['endSection']}节'
                        ' · ${course['room'] ?? ''}\n周次：${course['weeks'] ?? ''}',
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class HiddenPage extends StatelessWidget {
  const HiddenPage({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return SettingsScaffold(
      title: '已隐藏的作业',
      body: ListenableBuilder(
        listenable: state,
        builder: (context, _) {
          final hidden = Storage.hiddenItems();
          if (hidden.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.visibility_off_outlined,
                    size: 48,
                    color: textFaint(context),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '没有隐藏的作业',
                    style: TextStyle(
                      color: textSecondary(context),
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '在作业列表左滑卡片即可隐藏',
                    style: TextStyle(color: textFaint(context), fontSize: 12),
                  ),
                ],
              ),
            );
          }
          final items = hidden.entries
              .map((e) {
                try {
                  return MapEntry(
                    e.key,
                    HomeworkItem.fromJson(
                      jsonDecode(e.value) as Map<String, dynamic>,
                    ),
                  );
                } catch (_) {
                  return null;
                }
              })
              .whereType<MapEntry<String, HomeworkItem>>()
              .toList();
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              final entry = items[i];
              final hw = entry.value;
              return SettingsSection(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${hw.platform.label} · ${hw.course}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: textSecondary(context),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                hw.title,
                                style: TextStyle(
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w600,
                                  color: textPrimary(context),
                                ),
                              ),
                            ],
                          ),
                        ),
                        TextButton(
                          onPressed: () async {
                            await state.restoreHomework(entry.key);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  behavior: SnackBarBehavior.floating,
                                  content: Text('已恢复「${hw.title}」'),
                                ),
                              );
                            }
                          },
                          child: const Text('恢复'),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class DebugPage extends StatelessWidget {
  const DebugPage({super.key});

  @override
  Widget build(BuildContext context) {
    final entries = SafeHttp.log.isEmpty ? Storage.debugLog() : SafeHttp.log;
    return Scaffold(
      appBar: AppBar(
        title: const Text('接口调试日志'),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy_rounded),
            onPressed: () {
              final buf = StringBuffer();
              for (final e in entries) {
                // 复制导出与落盘共用同一份脱敏（Storage.redactLogEntry）：
                // 内存日志保留原文是记录在案的排查取舍，但剪贴板会离开
                // App 沙箱（用户随手贴到群聊/issue），不能带凭据出去
                final r = Storage.redactLogEntry(e);
                buf.writeln('--- ${r.time} ${r.method} ${r.status ?? '-'}');
                buf.writeln(r.url);
                buf.writeln(r.bodySnippet);
              }
              Clipboard.setData(ClipboardData(text: buf.toString()));
              ScaffoldMessenger.of(context)
                  .showSnackBar(const SnackBar(content: Text('已复制全部日志')));
            },
          ),
        ],
      ),
      body: entries.isEmpty
          ? const Center(child: Text('暂无请求记录，先去同步一次'))
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: entries.length,
              separatorBuilder: (_, _) => const Divider(),
              itemBuilder: (context, i) {
                final e = entries[i];
                return ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    '${e.method} ${e.status ?? 'ERR'} ${e.url}',
                    style: const TextStyle(fontSize: 12),
                  ),
                  subtitle: Text(
                    e.bodySnippet,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                  ),
                );
              },
            ),
    );
  }
}

/// 缩略图小票的撕纸裁剪：底边锯齿（齿尖朝下）
class _ThumbTearClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final p = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width, size.height - 3);
    var x = size.width;
    while (x - 7 >= 0) {
      p.lineTo(x - 3.5, size.height);
      x -= 7;
      p.lineTo(x, size.height - 3);
    }
    p.lineTo(0, size.height - 3);
    p.close();
    return p;
  }

  @override
  bool shouldReclip(_ThumbTearClipper old) => false;
}
