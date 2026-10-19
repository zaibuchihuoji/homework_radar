import '../models/homework.dart';

/// Presentation-only cache. The caller supplies visible records; exporting never
/// changes source records, their semester, status, notes or account ownership.
Map<String, Object> homeworkWidgetSnapshot(
  List<HomeworkItem> items, {
  DateTime? now,
}) {
  final at = now ?? DateTime.now();
  final pending = items
      .where((h) => h.status != HwStatus.done && h.status != HwStatus.submitted)
      .toList();
  pending.sort((a, b) {
    final ad = a.dueAt, bd = b.dueAt;
    if (ad == null && bd == null) return a.id.compareTo(b.id);
    if (ad == null) return 1;
    if (bd == null) return -1;
    final order = ad.compareTo(bd);
    return order == 0 ? a.id.compareTo(b.id) : order;
  });
  String shortDue(HomeworkItem h) {
    final d = h.dueAt;
    if (d == null) return '未设截止';
    final minutes = d.difference(at).inMinutes;
    if (!d.isAfter(at)) return '已逾期';
    if (minutes < 60) return '不足1小时';
    if (minutes < 24 * 60) return '剩余${minutes ~/ 60}小时';
    return '剩余${minutes ~/ (24 * 60)}天';
  }

  final rows = [
    for (final h in pending)
      <String, Object>{
        'id': h.id,
        'title': h.title,
        'course': h.course,
        'status': h.statusKey,
        'count': shortDue(h),
        if (h.dueAt != null) 'd': h.dueAt!.millisecondsSinceEpoch,
        'due': h.dueAt == null ? '' : HomeworkItem.formatDueTime(h.dueAt!),
        'u': h.dueAt == null
            ? 2
            : !h.dueAt!.isAfter(at)
            ? 0
            : h.dueAt!.difference(at).inHours < 24
            ? 0
            : 2,
      },
  ];
  final stats = <String, Object>{
    'todo': pending.length,
    'overdue': pending
        .where((h) => h.dueAt != null && !h.dueAt!.isAfter(at))
        .length,
    'done': items.length - pending.length,
    'total': items.length,
  };
  return {
    'version': 2,
    'updatedAt': at.millisecondsSinceEpoch,
    'items': rows,
    'stats': stats,
  };
}
