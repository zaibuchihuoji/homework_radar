import '../models/homework.dart';

/// A description of a committed local result, not a claim about unseen tasks.
class SyncSummary {
  const SyncSummary({
    required this.at,
    this.added = 0,
    this.changed = 0,
    this.retained = 0,
    this.removed = 0,
    this.archived = 0,
    this.failedRequests = 0,
    this.listIncomplete = false,
    this.details = const [],
  });
  final DateTime at;
  final int added, changed, retained, removed, archived, failedRequests;
  final bool listIncomplete;
  final List<String> details;

  factory SyncSummary.compare({
    required PlatformKind platform,
    required Iterable<HomeworkItem> before,
    required Iterable<HomeworkItem> after,
    required DateTime at,
    Set<String> hidden = const {},
    Set<String> archivedIds = const {},
    int failedRequests = 0,
    bool listIncomplete = false,
    List<String> details = const [],
  }) {
    final old = {
      for (final h in before)
        if (h.platform == platform && !hidden.contains(h.id)) h.id: h,
    };
    final current = {
      for (final h in after)
        if (h.platform == platform && !hidden.contains(h.id)) h.id: h,
    };
    var added = 0, changed = 0, retained = 0;
    for (final h in current.values) {
      final previous = old[h.id];
      if (previous == null) {
        added++;
      } else if (previous.title != h.title ||
          previous.course != h.course ||
          previous.dueAt != h.dueAt ||
          previous.status != h.status ||
          previous.score != h.score) {
        changed++;
      } else {
        retained++;
      }
    }
    return SyncSummary(
      at: at,
      added: added,
      changed: changed,
      retained: retained,
      removed: old.keys
          .where((id) => !current.containsKey(id) && !archivedIds.contains(id))
          .length,
      archived: archivedIds.length,
      failedRequests: failedRequests,
      listIncomplete: listIncomplete,
      details: List.unmodifiable(details.toSet()),
    );
  }

  Map<String, dynamic> toJson() => {
    'at': at.millisecondsSinceEpoch,
    'added': added,
    'changed': changed,
    'retained': retained,
    'removed': removed,
    'archived': archived,
    'failedRequests': failedRequests,
    'listIncomplete': listIncomplete,
    'details': details,
  };
  factory SyncSummary.fromJson(Map<String, dynamic> j) {
    int count(String name) =>
        j[name] is int && j[name] >= 0 ? j[name] as int : 0;
    return SyncSummary(
      at: DateTime.fromMillisecondsSinceEpoch(j['at'] as int),
      added: count('added'),
      changed: count('changed'),
      retained: count('retained'),
      removed: count('removed'),
      archived: count('archived'),
      failedRequests: count('failedRequests'),
      listIncomplete: j['listIncomplete'] == true,
      details: (j['details'] as List? ?? const []).whereType<String>().toList(),
    );
  }
}
