/// 设置：提醒开关、同步信息、调试入口。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:home_widget/home_widget.dart';
import 'package:image_picker/image_picker.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_state.dart';
import '../ui/theme_forms.dart';
import '../models/homework.dart';
import '../services/backup_service.dart';
import '../services/notification_service.dart';
import '../services/safe_http.dart';
import '../services/storage.dart';
import '../services/update_service.dart';
import '../ui/adaptive.dart';
import '../ui/ink_wash.dart';
import '../ui/dashed_line.dart';
import '../ui/style_background.dart';
import '../ui/tokens.dart';
import '../ui/theme_page_parts.dart';
import 'section_times_page.dart';
import 'notification_settings_page.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return StyleBackground(
      // 玻璃样式下透明化 Scaffold，露出渐变磨砂底衬
      child: Scaffold(
        backgroundColor: scaffoldBgOf(context),
        appBar: AppBar(title: appBarTitle(context, '设置')),
        body: ListenableBuilder(
          listenable: state,
          builder: (context, _) {
            final r = Storage.reminders();
            final lastSync = state.lastSync;
            final syncText = lastSync == null
                ? '还没有同步过'
                : '最后同步于 ${lastSync.month}月${lastSync.day}日 '
                      '${lastSync.hour}:${lastSync.minute.toString().padLeft(2, '0')}';
            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              children: [
                if (!paletteOf(context).clean)
                  ThemePageHeader(
                    compact: true,
                    title: '偏好设置',
                    kicker: 'PREFERENCES',
                    summary:
                        '提醒 ${r.enabledHours.length}/3 已开启 · 上课提醒${Storage.classReminder() ? '开' : '关'}',
                    icon: Icons.tune_rounded,
                  ),
                _groupLabel(context, '外观'),
                _groupCard(context, [
                  _stylePicker(context, state),
                  _divider(context),
                  // 深色锁：只有清夏打磨过深色观感，其余主题锁死浅色
                  //（buildTheme 里同步钳制，跟随系统的深色也不会生效）
                  () {
                    final locked =
                        state.style != ThemeStyle.clean &&
                        state.style != ThemeStyle.green;
                    return _tile(
                      context,
                      icon: Icons.contrast_rounded,
                      title: '主题模式',
                      subtitle: locked
                          ? '切换深色模式会影响观感，故无法开启深色模式'
                          : switch (state.themeMode) {
                              ThemeMode.light => '浅色',
                              ThemeMode.dark => '深色',
                              _ => '跟随系统',
                            },
                      onTap: locked
                          ? null
                          : () => _pickThemeMode(context, state),
                      trailing: locked
                          ? Icon(
                              Icons.lock_outline_rounded,
                              size: 20,
                              color: textFaint(context),
                            )
                          : const Icon(
                              Icons.chevron_right_rounded,
                              color: Color(0xFF9CA3AF),
                            ),
                    );
                  }(),
                ]),
                _groupLabel(context, '截止提醒'),
                ListenableBuilder(
                  listenable: Listenable.merge([
                    NotificationService.permission,
                    NotificationService.scheduleError,
                  ]),
                  builder: (context, _) => _groupCard(context, [
                    if (NotificationService.scheduleError.value != null)
                      _tile(
                        context,
                        icon: Icons.warning_amber_rounded,
                        title: NotificationService.scheduleError.value!,
                      ),
                    if (NotificationService.notificationsEnabled == false)
                      _tile(
                        context,
                        icon: Icons.notifications_off_rounded,
                        title: '通知权限被拒绝',
                        subtitle: '全部截止/上课提醒都不会弹出，点这里重新授权',
                        onTap: () async {
                          await NotificationService.rerequestPermission();
                        },
                      ),
                    if (defaultTargetPlatform == TargetPlatform.android) ...[
                      _tile(
                        context,
                        icon: Icons.notifications_outlined,
                        title: '通知横幅与声音',
                        subtitle: '检查顶部弹出、声音和两类提醒的系统设置',
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => NotificationSettingsPage(
                              homeworkId: state.homework
                                  .where((h) => h.status != HwStatus.done)
                                  .firstOrNull
                                  ?.id,
                            ),
                          ),
                        ),
                        trailing: const Icon(Icons.chevron_right_rounded),
                      ),
                      _divider(context),
                    ],
                    _switchTile(
                      context,
                      icon: Icons.notifications_active_rounded,
                      title: '截止前 24 小时',
                      value: r.before24h,
                      onChanged: (v) => state.updateReminders(r..before24h = v),
                    ),
                    _divider(context),
                    _switchTile(
                      context,
                      icon: Icons.schedule_rounded,
                      title: '截止前 6 小时',
                      value: r.before6h,
                      onChanged: (v) => state.updateReminders(r..before6h = v),
                    ),
                    _divider(context),
                    _switchTile(
                      context,
                      icon: Icons.alarm_rounded,
                      title: '截止前 1 小时',
                      value: r.before1h,
                      onChanged: (v) => state.updateReminders(r..before1h = v),
                    ),
                  ]),
                ),
                _groupLabel(context, '课表'),
                _groupCard(context, [
                  _switchTile(
                    context,
                    icon: Icons.alarm_on_rounded,
                    title: '上课前 15 分钟提醒',
                    subtitle:
                        Storage.classReminder() &&
                            Storage.semesterStart() == null
                        ? '还没设置开学日期，上课提醒暂不生效——'
                              '到「课表」页右上角菜单设置开学日期即可'
                        : null,
                    value: Storage.classReminder(),
                    onChanged: (v) => state.updateClassReminder(v),
                  ),
                  _divider(context),
                  _tile(
                    context,
                    icon: Icons.access_time_rounded,
                    title: '作息时间',
                    subtitle: '按学校作息调整每节课时间，提醒与课表随之生效',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => SectionTimesPage(state: state),
                      ),
                    ),
                    trailing: const Icon(
                      Icons.chevron_right_rounded,
                      color: Color(0xFF9CA3AF),
                    ),
                  ),
                ]),
                _groupLabel(context, '备份'),
                _groupCard(context, [
                  _tile(
                    context,
                    icon: Icons.file_upload_outlined,
                    title: '导出数据',
                    subtitle: '课表、作业、作息与隐藏作业 → JSON 文件（不含账号）',
                    onTap: () => _exportBackup(context),
                    trailing: const Icon(
                      Icons.chevron_right_rounded,
                      color: Color(0xFF9CA3AF),
                    ),
                  ),
                  _divider(context),
                  _tile(
                    context,
                    icon: Icons.file_download_outlined,
                    title: '导入数据',
                    subtitle: '从备份文件恢复，会覆盖当前课表与相关设置',
                    onTap: () => _importBackup(context, state),
                    trailing: const Icon(
                      Icons.chevron_right_rounded,
                      color: Color(0xFF9CA3AF),
                    ),
                  ),
                  _divider(context),
                  _tile(
                    context,
                    icon: Icons.inventory_2_outlined,
                    title: '历史账号数据',
                    subtitle: '只读查看或导出换号前的数据，不会合入当前账号',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const AccountArchivesPage(),
                      ),
                    ),
                  ),
                ]),
                _groupLabel(context, '同步'),
                _groupCard(context, [
                  _tile(
                    context,
                    icon: Icons.update_rounded,
                    title: '上次同步',
                    subtitle: syncText,
                    // 长按查看原始接口日志（隐藏入口，不给普通用户看见）
                    onLongPress: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const DebugPage()),
                    ),
                  ),
                  _divider(context),
                  _tile(
                    context,
                    icon: Icons.sync_rounded,
                    title: '立即同步全部作业',
                    onTap: state.syncing ? null : () => state.syncAll(),
                    trailing: state.syncing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : null,
                  ),
                ]),
                _groupLabel(context, '其他'),
                _groupCard(context, [
                  _tile(
                    context,
                    icon: Icons.visibility_off_outlined,
                    title: '已隐藏的作业',
                    subtitle: '左滑隐藏的作业可在这里恢复',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => HiddenPage(state: state),
                      ),
                    ),
                    trailing: const Icon(
                      Icons.chevron_right_rounded,
                      color: Color(0xFF9CA3AF),
                    ),
                  ),
                  _divider(context),
                  _tile(
                    context,
                    icon: Icons.widgets_rounded,
                    title: '桌面小组件',
                    subtitle: '把最近截止的作业放到手机桌面',
                    onTap: () => _showWidgetGuide(context),
                    trailing: const Icon(
                      Icons.chevron_right_rounded,
                      color: Color(0xFF9CA3AF),
                    ),
                  ),
                  _divider(context),
                  _tile(
                    context,
                    icon: Icons.notifications_none_rounded,
                    title: '发送测试通知',
                    onTap: () async {
                      // 带上第一条作业的 id，顺便验证通知深链
                      final first = state.homework
                          .where((h) => h.status != HwStatus.done)
                          .toList();
                      try {
                        await NotificationService.showSimple(
                          '作业通',
                          '这是一条测试通知 ✓',
                          payload: first.isEmpty ? null : first.first.id,
                        );
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: const Text('已提交测试通知；顶部未弹出时请检查横幅设置'),
                            action:
                                defaultTargetPlatform == TargetPlatform.android
                                ? SnackBarAction(
                                    label: '横幅设置',
                                    onPressed: () => Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            NotificationSettingsPage(
                                              homeworkId: first.firstOrNull?.id,
                                            ),
                                      ),
                                    ),
                                  )
                                : null,
                          ),
                        );
                      } catch (_) {
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('测试通知发送失败，请检查系统通知设置')),
                        );
                      }
                    },
                  ),
                ]),
                _groupLabel(context, '关于'),
                _groupCard(context, [
                  _tile(
                    context,
                    icon: Icons.system_update_rounded,
                    title: '检查更新',
                    // 无自有后端：新版本经 GitHub Releases 发布（update_service）
                    subtitle: '新版本经 GitHub 发布，失败多为网络不通，稍后再试',
                    onTap: () => _checkForUpdates(context),
                    trailing: const Icon(
                      Icons.chevron_right_rounded,
                      color: Color(0xFF9CA3AF),
                    ),
                  ),
                ]),
                const SizedBox(height: 16),
                _groupLabel(context, '反馈问题'),
                _groupCard(context, [
                  for (final email in _feedbackEmails)
                    _tile(
                      context,
                      icon: Icons.mail_outline_rounded,
                      title: email,
                      subtitle: '点击复制',
                      onTap: () => _copyFeedbackEmail(context, email),
                      trailing: const Icon(
                        Icons.copy_rounded,
                        color: Color(0xFF9CA3AF),
                      ),
                    ),
                ]),
                const SizedBox(height: 16),
                Text(
                  '作业通仅读取你自己账号的作业数据，请控制同步频率（应用内置了请求间隔）。',
                  style: TextStyle(
                    fontSize: 12,
                    color: textSecondary(context),
                    height: 1.7,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// 反馈邮箱：设置页直接展示，点击复制。
  static const List<String> _feedbackEmails = ['yaohuizheng22@gmail.com'];

  void _copyFeedbackEmail(BuildContext context, String email) {
    Clipboard.setData(ClipboardData(text: email));
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('已复制 $email')));
  }

  /// 应用内检查更新：查 GitHub 最新 Release，与本地版本比较；
  /// 失败（被墙/断网/仓库未建）只提示不抛错——更新检查绝不能打扰主流程。
  Future<void> _checkForUpdates(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      const SnackBar(content: Text('正在检查更新…'), duration: Duration(seconds: 1)),
    );
    final info = await fetchLatestRelease();
    if (info == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('检查失败：GitHub 访问不通，请稍后再试')),
      );
      return;
    }
    final pkg = await PackageInfo.fromPlatform();
    if (info.isNewerThan(pkg.version)) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('发现新版本 v${info.version}（当前 v${pkg.version}）'),
          duration: const Duration(seconds: 8),
          action: SnackBarAction(
            label: '下载',
            onPressed: () => launchUrl(
              Uri.parse(info.apkUrl.isNotEmpty ? info.apkUrl : info.releaseUrl),
              mode: LaunchMode.externalApplication,
            ),
          ),
        ),
      );
    } else {
      messenger.showSnackBar(SnackBar(content: Text('已是最新版本 v${pkg.version}')));
    }
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
      builder: (context) => ThemedAlertDialog(
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
      (ThemeMode.system, '跟随系统', Icons.brightness_auto_rounded),
      (ThemeMode.light, '浅色', Icons.light_mode_rounded),
      (ThemeMode.dark, '深色', Icons.dark_mode_rounded),
    ];
    showDialog<void>(
      context: context,
      builder: (dialogContext) => ThemedDialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(20, 12, 20, 8),
                    child: ThemeEditorHeading(
                      title: '主题模式',
                      kicker: 'DISPLAY MODE',
                      icon: Icons.contrast_rounded,
                    ),
                  ),
                  for (final (mode, label, icon) in options)
                    ListTile(
                      leading: Icon(icon, color: accentColor(dialogContext)),
                      title: Text(
                        label,
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                          color: textPrimary(dialogContext),
                        ),
                      ),
                      trailing: state.themeMode == mode
                          ? Icon(
                              Icons.check_rounded,
                              color: accentColor(dialogContext),
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
          ),
        ),
      ),
    );
  }

  /// 样式选择：一排迷你预览卡，点按即切（全局立即生效，无需确认）。
  /// 横向可滚——五个缩略图塞不进一屏宽度。
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
                const ThemeEditorHeading(
                  title: '界面风格',
                  kicker: 'APPEARANCE',
                  icon: Icons.palette_outlined,
                ),
                const SizedBox(height: 6),
                Text(
                  '选择适合你的学习氛围',
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

  Widget _groupLabel(BuildContext context, String t) {
    if (!paletteOf(context).clean) {
      const groups = ['外观', '截止提醒', '课表', '备份', '同步', '其他', '关于', '反馈问题'];
      return ThemeSectionHeading(title: t, index: groups.indexOf(t) + 1);
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
      // 水墨：组头一枚淡墨顿点，与首页分段头同一语言
      child: Row(
        children: [
          if (isInkStyle(context)) ...[
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: textSecondary(context).withValues(alpha: 0.8),
              ),
            ),
            const SizedBox(width: 7),
          ],
          Text(
            t,
            style: serifTitle(
              context,
              TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: textSecondary(context),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _groupCard(BuildContext context, List<Widget> children) {
    if (!paletteOf(context).clean) {
      return ThemePanel(
        padding: EdgeInsets.zero,
        seed: 'settings',
        child: Material(
          type: MaterialType.transparency,
          child: Column(children: children),
        ),
      );
    }
    return Container(
      decoration:
          inkWashFill(context, cardRadius(context) + 2) ??
          (isPixelStyle(context)
              ? BoxDecoration(color: cardColor(context))
              : isReceiptStyle(context)
              ? receiptTear(context)
              : isEditorialStyle(context)
              ? BoxDecoration(color: cardColor(context))
              : BoxDecoration(
                  color: cardColor(context),
                  borderRadius: BorderRadius.circular(cardRadius(context) + 2),
                  border: cardBorderOf(context),
                )),
      foregroundDecoration: isPixelStyle(context)
          ? pixelFrame(context, cardRadius(context) + 2)
          : paperInnerRing(context, cardRadius(context) + 2) ??
                morandiCream(context, cardRadius(context) + 2) ??
                editorialRules(context),
      clipBehavior: Clip.antiAlias,
      child: Material(
        type: MaterialType.transparency,
        child: Column(children: children),
      ),
    );
  }

  Widget _divider(BuildContext context) {
    // 水墨：分隔线是一笔飞白（淡墨笔触，干笔留白）。
    if (isInkStyle(context)) {
      return Padding(
        padding: const EdgeInsets.only(left: 54, right: 16),
        child: BrushLine(color: textSecondary(context).withValues(alpha: 0.30)),
      );
    }
    return isPaperStyle(context) ||
            isReceiptStyle(context) ||
            isJournalStyle(context) ||
            isTerminalStyle(context)
        ? Padding(
            padding: const EdgeInsets.only(left: 54, right: 16),
            child: DashedLine(color: dividerColor(context)),
          )
        : Divider(
            height: 1,
            indent: 54,
            endIndent: 16,
            color: dividerColor(context),
          );
  }

  Widget _switchTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    String? subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    if (!paletteOf(context).clean) {
      return ListTile(
        onTap: () => onChanged(!value),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        minLeadingWidth: 34,
        horizontalTitleGap: 12,
        leading: ThemePreferenceIcon(icon: icon),
        title: Text(
          title,
          style: monoText(
            context,
            TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: textPrimary(context),
            ),
          ),
        ),
        subtitle: subtitle == null
            ? null
            : Text(
                subtitle,
                style: TextStyle(
                  fontSize: 12,
                  color: textSecondary(context),
                  height: 1.5,
                ),
              ),
        trailing: Semantics(
          label: title,
          toggled: value,
          onTap: () => onChanged(!value),
          child: ExcludeSemantics(
            child: SizedBox(
              width: isTerminalStyle(context) ? 72 : 56,
              child: ThemePreferenceToggle(value: value, onChanged: onChanged),
            ),
          ),
        ),
      );
    }
    return SwitchListTile(
      value: value,
      onChanged: onChanged,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      secondary: _icon(context, icon),
      title: Text(
        title,
        style: TextStyle(
          fontSize: 14.5,
          fontWeight: FontWeight.w600,
          color: textPrimary(context),
        ),
      ),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle,
              style: TextStyle(fontSize: 12, color: textSecondary(context)),
            ),
    );
  }

  Widget _tile(
    BuildContext context, {
    required IconData icon,
    required String title,
    String? subtitle,
    Widget? trailing,
    VoidCallback? onTap,
    VoidCallback? onLongPress,
  }) {
    return ListTile(
      onTap: onTap,
      onLongPress: onLongPress,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      minLeadingWidth: paletteOf(context).clean ? null : 34,
      horizontalTitleGap: paletteOf(context).clean ? null : 12,
      leading: paletteOf(context).clean
          ? _icon(context, icon)
          : ThemePreferenceIcon(icon: icon),
      title: Text(
        title,
        style: TextStyle(
          fontSize: 14.5,
          fontWeight: FontWeight.w600,
          color: textPrimary(context),
        ),
      ),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle,
              style: TextStyle(fontSize: 12, color: textSecondary(context)),
            ),
      trailing: trailing,
    );
  }

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
      builder: (dialogContext) => ThemedAlertDialog(
        backgroundColor: cardColor(dialogContext),
        title: const Text(
          '添加桌面小组件',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
        ),
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
                  '外观跟随 App 主题；透明模式保留主题装饰，文字按明暗配色，辅以轻微提边。',
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
                        '小组件可长按拖动边角缩放，作业最小 2×1，课表最小 2×2；列表可上下滑动。'
                        '透明背景透出真实壁纸，文字适度加重并带轻微提边，保持通透；'
                        '从相册选图后玻璃会带模糊与边缘折射，更换壁纸后可重新选图。',
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

  Widget _icon(BuildContext context, IconData icon) => Icon(
    icon,
    size: 22,
    // 水墨：列表图标用灰墨，朱砂只留给开关/选中态
    color: isInkStyle(context) ? textSecondary(context) : accentColor(context),
  );
}

class AccountArchivesPage extends StatelessWidget {
  const AccountArchivesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final archives = Storage.accountArchives().reversed.toList();
    return Scaffold(
      appBar: AppBar(title: const Text('历史账号数据')),
      body: archives.isEmpty
          ? const Center(child: Text('暂无历史归档'))
          : ListView.builder(
              itemCount: archives.length,
              itemBuilder: (context, i) {
                final archive = archives[i];
                final homework = archive['homework'] as List? ?? const [];
                final hidden = archive['hiddenItems'] as Map? ?? const {};
                final courses = archive['courses'] as List? ?? const [];
                return ListTile(
                  title: Text(
                    '${archive['platform']} · ${archive['createdAt']}',
                  ),
                  subtitle: Text(
                    '${homework.length} 条作业，${hidden.length} 条隐藏作业，${courses.length} 门课程',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => _AccountArchiveDetail(archive: archive),
                    ),
                  ),
                );
              },
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('归档详情（只读）'),
        actions: [
          IconButton(
            tooltip: '导出归档',
            icon: const Icon(Icons.file_upload_outlined),
            onPressed: () => _export(context),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('此处保留换号或替换前的数据。查看与导出不会修改当前账号。'),
          const SizedBox(height: 12),
          for (final task in tasks)
            ListTile(
              title: Text('${task['title'] ?? '未命名作业'}'),
              subtitle: Text(
                '${task['course'] ?? ''}${task['_hidden'] == true ? ' · 已隐藏' : ''}'
                '${task['note'] == null ? '' : '\n${task['note']}'}',
              ),
            ),
          for (final course in courses)
            ListTile(
              title: Text('${course['name'] ?? '未命名课程'}'),
              subtitle: Text(
                '周${course['weekday']} · 第${course['startSection']}-${course['endSection']}节'
                ' · ${course['room'] ?? ''}\n周次：${course['weeks'] ?? ''}',
              ),
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
    return Scaffold(
      appBar: AppBar(title: const Text('已隐藏的作业')),
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
              return Container(
                padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
                decoration: BoxDecoration(
                  color: cardColor(context),
                  borderRadius: BorderRadius.circular(18),
                ),
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
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
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
