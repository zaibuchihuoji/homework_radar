import '../models/homework.dart';

enum SyncOutcome { success, retry, loginExpired, signatureRejected }

class SyncConfig {
  const SyncConfig({this.enabled = true, this.minutes = 30});
  static const intervals = [15, 30, 60, 120];
  final bool enabled;
  final int minutes;
  factory SyncConfig.fromJson(Map<String, dynamic> j) => SyncConfig(
    enabled: j['enabled'] != false,
    minutes: intervals.contains(j['minutes']) ? j['minutes'] as int : 30,
  );
  Map<String, dynamic> toJson() => {'enabled': enabled, 'minutes': minutes};
}

/// Only scheduling metadata, never credentials or copies of homework.
class PlatformSyncStatus {
  const PlatformSyncStatus({
    this.lastAttempt,
    this.lastSuccess,
    this.outcome,
    this.failures = 0,
    this.nextRetry,
  });
  final DateTime? lastAttempt;
  final DateTime? lastSuccess;
  final SyncOutcome? outcome;
  final int failures;
  final DateTime? nextRetry;
  bool get paused =>
      outcome == SyncOutcome.loginExpired ||
      outcome == SyncOutcome.signatureRejected;

  PlatformSyncStatus finish(SyncOutcome result, DateTime at) {
    final count = result == SyncOutcome.retry ? failures + 1 : 0;
    final delay = count <= 1
        ? 5
        : count == 2
        ? 15
        : 30;
    return PlatformSyncStatus(
      lastAttempt: at,
      lastSuccess: result == SyncOutcome.success ? at : lastSuccess,
      outcome: result,
      failures: count,
      nextRetry: result == SyncOutcome.retry
          ? at.add(Duration(minutes: delay))
          : null,
    );
  }

  factory PlatformSyncStatus.fromJson(Map<String, dynamic> j) {
    DateTime? date(String key) => j[key] is int
        ? DateTime.fromMillisecondsSinceEpoch(j[key] as int)
        : null;
    return PlatformSyncStatus(
      lastAttempt: date('attempt'),
      lastSuccess: date('success'),
      outcome: SyncOutcome.values
          .where((v) => v.name == j['outcome'])
          .firstOrNull,
      failures: j['failures'] is int && (j['failures'] as int) > 0
          ? j['failures'] as int
          : 0,
      nextRetry: date('retry'),
    );
  }
  Map<String, dynamic> toJson() => {
    'attempt': lastAttempt?.millisecondsSinceEpoch,
    'success': lastSuccess?.millisecondsSinceEpoch,
    'outcome': outcome?.name,
    'failures': failures,
    'retry': nextRetry?.millisecondsSinceEpoch,
  };
}

abstract final class SyncPolicy {
  static Set<PlatformKind> due(
    Set<PlatformKind> accounts,
    Map<PlatformKind, PlatformSyncStatus> statuses,
    DateTime now,
    Duration age,
  ) => accounts.where((p) {
    final s = statuses[p];
    if (s == null) return true;
    if (s.paused) return false;
    if (s.nextRetry != null) return !now.isBefore(s.nextRetry!);
    return s.lastSuccess == null || !now.isBefore(s.lastSuccess!.add(age));
  }).toSet();
}
