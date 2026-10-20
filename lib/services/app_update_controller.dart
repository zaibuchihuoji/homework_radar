import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'update_service.dart';

class UpdateDownloadStatus {
  const UpdateDownloadStatus(this.data);
  final Map<String, dynamic> data;
  String get phase => data['phase'] as String? ?? 'idle';
  String get version => data['version'] as String? ?? '';
  String get error => data['error'] as String? ?? '';
  String get source => data['source'] as String? ?? 'GitHub';
  bool get switchedSource => data['switchedSource'] == true;
  bool get retryable => data['retryable'] != false;
  int get bytes => (data['bytes'] as num?)?.toInt() ?? 0;
  int get total => (data['total'] as num?)?.toInt() ?? 0;
  double? get progress => total > 0 ? (bytes / total).clamp(0.0, 1.0) : null;
  bool get active => const ['queued', 'downloading', 'paused'].contains(phase);
  String get label => switch (phase) {
    'queued' => '等待下载',
    'downloading' =>
      progress == null ? '正在下载' : '正在下载 ${(progress! * 100).floor()}%',
    'paused' => '下载已暂停，等待恢复',
    'ready' => '下载完成，点击安装',
    'failed' => '下载未完成，点击查看',
    _ => '查看是否有新版本',
  };
}

/// Only observes a native download; dismissing routes never cancels it.
class AppUpdateController extends ChangeNotifier with WidgetsBindingObserver {
  static final instance = AppUpdateController();
  static const _channel = MethodChannel('homework_radar/updater');
  UpdateDownloadStatus status = const UpdateDownloadStatus({'phase': 'idle'});
  VoidCallback? onOpen;
  Timer? _timer;
  bool _started = false, _foreground = true, _refreshing = false;
  bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<void> initialize() async {
    if (_started || !supported) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'open') {
        final open = await _channel.invokeMethod<bool>('consumeOpen') ?? false;
        await refresh();
        if (open) onOpen?.call();
      } else if (call.method == 'refresh') {
        await refresh();
      }
    });
    await refresh();
    try {
      if (await _channel.invokeMethod<bool>('consumeOpen') == true) {
        onOpen?.call();
      }
    } on PlatformException {
      /* A failed UI request cannot affect the native task. */
    } on MissingPluginException {
      /* Desktop/widget-test fallback. */
    }
  }

  Future<List<String>> supportedAbis() async => supported
      ? (await _channel.invokeListMethod<String>('device') ?? [])
      : [];

  Future<void> refresh() async {
    if (!supported || _refreshing) return;
    _refreshing = true;
    try {
      final value = await _channel.invokeMapMethod<String, dynamic>('status');
      if (value != null) {
        status = UpdateDownloadStatus(value);
        notifyListeners();
      }
    } on PlatformException {
      /* Keep last observed progress on transient query failure. */
    } on MissingPluginException {
      /* Not installed on non-Android hosts. */
    } finally {
      _refreshing = false;
      _schedule();
    }
  }

  Future<void> _operation(String method, [Map<String, dynamic>? args]) async {
    final value = await _channel.invokeMapMethod<String, dynamic>(method, args);
    if (value != null) {
      status = UpdateDownloadStatus(value);
      notifyListeners();
    }
    _schedule();
  }

  Future<void> start(UpdateInfo info) => _operation('start', {
    'version': info.version,
    'url': info.apkUrl,
    'size': info.apkSize,
    'sha256': info.apkSha256,
    'fallbackUrl': info.fallbackApkUrl,
  });
  Future<void> retry() => _operation('retry');
  Future<void> cancel() => _operation('cancel');
  Future<void> install() async {
    await _channel.invokeMethod<String>('install');
    await refresh();
  }

  void _schedule() {
    _timer?.cancel();
    if (_foreground && status.active) {
      _timer = Timer(const Duration(seconds: 1), refresh);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) {
      unawaited(refresh());
    } else {
      _timer?.cancel();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    if (_started) WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
