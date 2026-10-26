// Mirrors the current official school-course panel: course.id is distinct from
// termPanel.id, schoolPanel.id and currentTermId. Dates are course dates, never
// individual homework deadlines.
Map<String, Object?> moocSchoolPanel(
  int id, {
  int mode = 20,
  int? termId,
  String? name,
  DateTime? start,
  DateTime? end,
}) {
  final now = DateTime.now();
  return {
    'id': id,
    'name': name ?? 'Course $id',
    'currentTermId': id + 9000,
    'mode': mode,
    'termPanel': {
      'id': termId ?? id + 1000,
      'mode': mode,
      'startTime': (start ?? now.subtract(const Duration(days: 7)))
          .millisecondsSinceEpoch,
      'endTime':
          (end ?? now.add(const Duration(days: 100))).millisecondsSinceEpoch,
    },
    'schoolPanel': {'id': id + 2000, 'name': 'University'},
  };
}
