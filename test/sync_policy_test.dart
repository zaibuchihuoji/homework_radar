import 'package:flutter_test/flutter_test.dart';
import 'package:homework_radar/models/homework.dart';
import 'package:homework_radar/services/sync_policy.dart';

void main() {
  final now = DateTime(2026, 10, 20, 12);
  const cx = PlatformKind.chaoxing;
  const mooc = PlatformKind.mooc;
  test('old or invalid configuration defaults to enabled 30 minutes', () {
    expect(SyncConfig.fromJson({}).minutes, 30);
    expect(SyncConfig.fromJson({'minutes': 1}).minutes, 30);
    expect(SyncConfig.fromJson({}).enabled, isTrue);
    expect(
      SyncConfig.fromJson({'enabled': false, 'minutes': 60}).enabled,
      isFalse,
    );
  });
  test(
    'partial failure retries independently with persisted capped backoff',
    () {
      var failed = const PlatformSyncStatus();
      final success = failed.finish(SyncOutcome.success, now);
      for (final minutes in [5, 15, 30, 30]) {
        failed = failed.finish(SyncOutcome.retry, now);
        expect(failed.nextRetry, now.add(Duration(minutes: minutes)));
        failed = PlatformSyncStatus.fromJson(failed.toJson());
      }
      final statuses = {cx: success, mooc: failed};
      expect(
        SyncPolicy.due({cx, mooc}, statuses, now, const Duration(minutes: 5)),
        isEmpty,
      );
      expect(
        SyncPolicy.due(
          {cx, mooc},
          statuses,
          now.add(const Duration(minutes: 30)),
          const Duration(hours: 2),
        ),
        {mooc},
      );
      expect(failed.finish(SyncOutcome.success, now).failures, 0);
      expect(failed.finish(SyncOutcome.success, now).nextRetry, isNull);
    },
  );
  test('expiry and signature rejection pause automatic sync until reset', () {
    for (final outcome in [
      SyncOutcome.loginExpired,
      SyncOutcome.signatureRejected,
    ]) {
      final status = const PlatformSyncStatus().finish(outcome, now);
      expect(
        SyncPolicy.due(
          {cx},
          {cx: status},
          now.add(const Duration(days: 2)),
          const Duration(minutes: 5),
        ),
        isEmpty,
      );
      expect(status.nextRetry, isNull);
    }
    expect(SyncPolicy.due({cx}, {}, now, const Duration(minutes: 5)), {cx});
  });
  test('successful data timestamp does not advance on failure', () {
    final good = const PlatformSyncStatus().finish(SyncOutcome.success, now);
    final bad = good.finish(
      SyncOutcome.retry,
      now.add(const Duration(minutes: 30)),
    );
    expect(bad.lastSuccess, now);
    expect(bad.lastAttempt, now.add(const Duration(minutes: 30)));
  });
}
