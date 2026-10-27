import 'package:flutter_test/flutter_test.dart';
import 'package:homework_radar/models/homework.dart';
import 'package:homework_radar/services/sync_policy.dart';
import 'package:homework_radar/services/sync_service.dart';
import 'package:homework_radar/services/sync_summary.dart';

void main() {
  final at = DateTime(2026, 10, 26, 22);
  HomeworkItem item(
    String id, {
    String title = '作业',
    String? url,
    PlatformKind p = PlatformKind.mooc,
    String? source,
  }) => HomeworkItem(
    id: id,
    platform: p,
    course: '课程',
    title: title,
    note: '用户备注',
    url: url,
    sourceKey: source,
  );

  test('summary distinguishes changed, retained, removed, archived and hidden work', () {
    final result = SyncSummary.compare(
      platform: PlatformKind.mooc,
      at: at,
      before: [
        item('updated'),
        item('same', url: 'old'),
        item('removed'),
        item('archived'),
        item('hidden'),
        item('manual', p: PlatformKind.manual),
      ],
      after: [
        item('updated', title: '新标题'),
        item('same', url: 'new'),
        item('added'),
        item('manual', p: PlatformKind.manual),
      ],
      hidden: {'hidden'},
      archivedIds: {'archived'},
    );
    expect(result.added, 1);
    expect(result.changed, 1);
    expect(result.retained, 1);
    expect(result.removed, 1);
    expect(result.archived, 1);
  });

  test('source-linked IDs are counted as changes, while cross-platform collisions remain additions', () {
    final before = [
      item('stable', source: 'mooc|1|2|4|8'),
      item('conflict', p: PlatformKind.manual),
    ];
    final merged = {for (final h in before) h.id: h};
    mergePlatform(
      merged,
      [
        item('different', source: 'mooc|1|2|4|8', title: '更新标题'),
        item('conflict', source: 'mooc|1|2|4|9'),
      ],
      PlatformKind.mooc,
      complete: false,
    );
    final summary = SyncSummary.compare(
      platform: PlatformKind.mooc,
      before: before,
      after: merged.values,
      at: at,
    );
    expect(summary.added, 1);
    expect(summary.changed, 1);
    expect(summary.removed, 0);
    expect(merged['conflict']!.platform, PlatformKind.manual);
  });

  test(
    'malformed optional summary cannot erase persisted expiry or retry state',
    () {
      final status = PlatformSyncStatus.fromJson({
        'outcome': 'loginExpired',
        'attempt': at.millisecondsSinceEpoch,
        'summary': {'at': 'broken'},
      });
      expect(status.paused, isTrue);
      expect(status.lastAttempt, at);
      expect(status.summary, isNull);
      final saved = const PlatformSyncStatus().finish(
        SyncOutcome.retry,
        at,
        summary: SyncSummary(at: at, retained: 3, details: ['《数学》作业获取未完成']),
      );
      final read = PlatformSyncStatus.fromJson(saved.toJson());
      expect(read.summary!.retained, 3);
      expect(read.summary!.details, ['《数学》作业获取未完成']);
      expect(read.nextRetry, at.add(const Duration(minutes: 5)));
    },
  );
}
