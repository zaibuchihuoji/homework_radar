import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/app_update_controller.dart';
import '../services/update_service.dart';
import '../ui/theme_forms.dart';

bool _updateDialogOpen = false;
bool _checking = false;

Future<void> checkForAppUpdate(BuildContext context) async {
  if (_checking || _updateDialogOpen) return;
  _checking = true;
  final controller = AppUpdateController.instance;
  final messenger = ScaffoldMessenger.of(context);
  try {
    await controller.refresh();
    if (!context.mounted) return;
    if (controller.status.phase != 'idle') {
      await showAppUpdateDialog(context);
      return;
    }
    messenger.showSnackBar(
      const SnackBar(content: Text('正在检查更新…'), duration: Duration(seconds: 1)),
    );
    final info = await fetchLatestRelease(
      supportedAbis: await controller.supportedAbis(),
    );
    final pkg = await PackageInfo.fromPlatform();
    if (!context.mounted) return;
    if (info == null) {
      messenger.showSnackBar(const SnackBar(content: Text('暂时无法检查更新，请稍后再试')));
    } else if (!info.isNewerThan(pkg.version)) {
      messenger.showSnackBar(SnackBar(content: Text('已是最新版本 v${pkg.version}')));
    } else if (!controller.supported) {
      await launchUrl(
        Uri.parse(info.releaseUrl),
        mode: LaunchMode.externalApplication,
      );
    } else {
      await showAppUpdateDialog(context, info: info);
    }
  } catch (_) {
    messenger.showSnackBar(const SnackBar(content: Text('无法读取更新信息，请稍后再试')));
  } finally {
    _checking = false;
  }
}

Future<void> showAppUpdateDialog(
  BuildContext context, {
  UpdateInfo? info,
}) async {
  if (_updateDialogOpen || !context.mounted) return;
  _updateDialogOpen = true;
  try {
    await showDialog<void>(
      context: context,
      builder: (_) => _UpdateDialog(info: info),
    );
  } finally {
    _updateDialogOpen = false;
  }
}

class _UpdateDialog extends StatefulWidget {
  const _UpdateDialog({this.info});
  final UpdateInfo? info;
  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  final controller = AppUpdateController.instance;
  bool busy = false;
  String? error;
  Future<void> run(Future<void> Function() action) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await action();
    } on PlatformException catch (e) {
      if (mounted) setState(() => error = e.message ?? '操作失败，请重试');
    } catch (_) {
      if (mounted) setState(() => error = '操作失败，请稍后重试');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  String size(int bytes) => '${(bytes / 1048576).toStringAsFixed(1)} MB';

  Future<void> recheck() async {
    // Validate new metadata before discarding the failed task.
    final info = await fetchLatestRelease(
      supportedAbis: await controller.supportedAbis(),
    );
    if (info == null || info.apkUrl.isEmpty) {
      throw PlatformException(code: 'update', message: '暂未找到适合此设备的安装包，请稍后再试');
    }
    await controller.start(info);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final status = controller.status;
      final offer = status.phase == 'idle';
      final info = widget.info;
      final version = offer ? info?.version ?? '' : status.version;
      return ThemedDialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  status.phase == 'ready'
                      ? '更新已准备好'
                      : offer
                      ? '发现新版本'
                      : '应用更新',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  '作业通 v$version',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 16),
                if (offer) ...[
                  if (info != null && info.apkSize > 0)
                    Text('${size(info.apkSize)} · GitHub'),
                  if (info != null && info.notes.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 200),
                      child: SingleChildScrollView(child: Text(info.notes)),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Text(
                    info?.apkUrl.isNotEmpty == true
                        ? '下载后可直接安装，也可以放到后台继续下载。'
                        : '此版本暂未提供适合当前设备的安装包。',
                  ),
                ] else if (status.active) ...[
                  Text(status.label),
                  const SizedBox(height: 12),
                  LinearProgressIndicator(value: status.progress),
                  const SizedBox(height: 10),
                  Text(
                    '${size(status.bytes)}${status.total > 0 ? ' / ${size(status.total)}' : ''}',
                  ),
                  const SizedBox(height: 8),
                  Text(
                    status.phase == 'paused'
                        ? status.error
                        : '收起后继续下载，可在通知栏或设置中查看。',
                  ),
                ] else if (status.phase == 'ready')
                  Text('${size(status.total)} · 安装包已校验\n安装后保留当前数据。')
                else
                  Text(status.error.isEmpty ? '下载未完成，请重试。' : status.error),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                const SizedBox(height: 20),
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (status.active ||
                        status.phase == 'failed' ||
                        status.phase == 'ready')
                      TextButton(
                        onPressed: busy
                            ? null
                            : () => run(() async {
                                await controller.cancel();
                                if (context.mounted) Navigator.pop(context);
                              }),
                        child: Text(status.phase == 'ready' ? '删除安装包' : '取消下载'),
                      ),
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(status.active ? '后台下载' : '稍后'),
                    ),
                    if (offer && info?.apkUrl.isNotEmpty == true)
                      FilledButton(
                        onPressed: busy
                            ? null
                            : () => run(() => controller.start(info!)),
                        child: Text(busy ? '正在准备…' : '下载更新'),
                      ),
                    if (status.phase == 'failed')
                      FilledButton(
                        onPressed: busy
                            ? null
                            : () => run(
                                status.retryable ? controller.retry : recheck,
                              ),
                        child: Text(
                          busy
                              ? '正在准备…'
                              : status.retryable
                              ? '重试下载'
                              : '重新检查',
                        ),
                      ),
                    if (status.phase == 'ready')
                      FilledButton(
                        onPressed: busy ? null : () => run(controller.install),
                        child: Text(busy ? '正在校验…' : '立即安装'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
