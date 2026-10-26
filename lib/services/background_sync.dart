import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import 'notification_service.dart';
import 'storage.dart';
import 'sync_policy.dart';
import 'sync_service.dart';
import 'timetable_widget.dart';
import 'widget_theme.dart';

/// Runs in the SAME Dart isolate as the UI, including cold Android jobs.
class BackgroundSync {
  BackgroundSync(this.state, {required this.onForeground});
  static const channel = MethodChannel('homework_radar/background_sync');
  static final scheduleError = ValueNotifier<String?>(null);
  final AppState state;
  final Future<void> Function() onForeground;
  Timer? _foregroundTimer;
  Timer? _retryTimer;
  bool _foreground = false;
  int _lifecycleVersion = 0;
  Future<bool>? _running;

  Future<void> init() async {
    state.onSyncScheduleChanged = configure;
    channel.setMethodCallHandler((call) async {
      if (call.method == 'foreground') {
        _lifecycleVersion++;
        await foreground(call.arguments == true);
        return true;
      }
      if (call.method == 'run') {
        return run(call.arguments as String? ?? 'periodic');
      }
      throw MissingPluginException();
    });
    final version = _lifecycleVersion;
    bool active;
    try {
      active = await channel.invokeMethod<bool>('ready') == true;
    } on MissingPluginException {
      // Other platforms keep the foreground policy; Android owns persistent jobs.
      active = true;
    }
    await configure();
    // A pause/resume event can arrive while ready/configure is awaiting native I/O.
    // Do not overwrite that newer event with the initial foreground snapshot.
    if (_lifecycleVersion == version) await foreground(active);
  }

  Future<void> foreground(bool active) async {
    final changed = active != _foreground;
    _foreground = active;
    _foregroundTimer?.cancel();
    _retryTimer?.cancel();
    if (!active) return;
    await onForeground();
    if (!_foreground) return;
    _foregroundTimer = Timer.periodic(const Duration(minutes: 15), (_) {
      unawaited(run('foreground'));
    });
    _armRetry();
    if (changed) unawaited(run('resume'));
  }

  void _armRetry() {
    _retryTimer?.cancel();
    if (!_foreground) return;
    final retry = _nextRetry();
    if (retry == null) return;
    final delay = retry.difference(DateTime.now());
    _retryTimer = Timer(delay.isNegative ? Duration.zero : delay, () {
      unawaited(run('retry'));
    });
  }

  DateTime? _nextRetry() {
    final accounts = Storage.syncAccounts();
    final times =
        Storage.syncStatuses().entries
            .where((e) => accounts.contains(e.key) && !e.value.paused)
            .map((e) => e.value.nextRetry)
            .nonNulls
            .toList()
          ..sort();
    return times.firstOrNull;
  }

  Future<void> configure() async {
    final config = Storage.syncConfig();
    try {
      await channel.invokeMethod<bool>('configure', {
        'enabled': config.enabled && Storage.syncAccounts().isNotEmpty,
        'minutes': config.minutes,
        'retryAt': _nextRetry()?.millisecondsSinceEpoch,
      });
      scheduleError.value = null;
    } on MissingPluginException {
      // No native background scheduler on iOS/desktop.
    } catch (_) {
      scheduleError.value = '后台任务安排失败；回到 App 后会重试，请保留手动刷新';
    }
    _armRetry();
  }

  Future<bool> run(String reason) => _running ??= _run(reason).whenComplete(() {
    _running = null;
  });

  Future<bool> _run(String reason) async {
    if (reason == 'reminders') {
      // Exact-alarm access / clock changes need offline rescheduling even when
      // platform sync is disabled and there are no logged-in accounts.
      try {
        await state.waitForSync();
        await Storage.waitForBusinessTransaction();
        await NotificationService.reschedule(
          state.homework,
          courses: state.courses,
        );
        return NotificationService.scheduleError.value == null;
      } catch (_) {
        return false;
      }
    }
    if (reason == 'periodic' || reason == 'retry') {
      if (!Storage.syncConfig().enabled && !_foreground) return true;
    }
    try {
      await state.waitForSync();
      await Storage.waitForBusinessTransaction();
      final now = DateTime.now();
      final statuses = Storage.syncStatuses();
      final age = Duration(
        minutes: reason == 'resume'
            ? 5
            : reason == 'foreground'
            ? 15
            : Storage.syncConfig().minutes,
      );
      final due = SyncPolicy.due(Storage.syncAccounts(), statuses, now, age);
      if (reason == 'retry') {
        due.removeWhere((p) => statuses[p]?.nextRetry == null);
      }
      if (due.isNotEmpty) await state.syncPlatforms(platforms: due);
      // Refresh rolling reminder windows and time-based widget content even
      // when no network request was needed. Homework export has the same filter.
      await Future.wait([
        TimetableWidget.push(state.courses),
        WidgetTheme.push(state.style, state.themeMode),
        if (due.isEmpty) SyncService.updateHomeWidget(state.homework),
        if (due.isEmpty)
          NotificationService.reschedule(
            state.homework,
            courses: state.courses,
          ),
      ]);
      await configure();
      return scheduleError.value == null &&
          NotificationService.scheduleError.value == null &&
          SyncService.widgetPublishError.value == null;
    } catch (_) {
      // Attempt metadata was persisted before fetching. Keep records and let
      // the OS retry a runtime/storage failure instead of reporting success.
      await configure();
      return false;
    }
  }

  void dispose() {
    _foregroundTimer?.cancel();
    _retryTimer?.cancel();
    state.onSyncScheduleChanged = null;
    channel.setMethodCallHandler(null);
  }
}
