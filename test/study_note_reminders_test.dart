import 'package:flutter_test/flutter_test.dart';
import 'package:homework_radar/services/study_note_reminders.dart';

void main() {
  test('manual weekly reminder uses selected time and skips deleted notes', () {
    final now = DateTime(2026, 10, 28, 10);
    final notes = <Map<String, dynamic>>[
      {
        'id': 'n',
        'title': '线代',
        'reminder': {
          'at': DateTime(2026, 10, 26, 9).millisecondsSinceEpoch,
          'repeat': 'weekly',
          'token': 'v1',
        },
      },
      {
        'id': 'trash',
        'deleted': true,
        'reminder': {
          'at': now.add(const Duration(hours: 1)).millisecondsSinceEpoch,
          'repeat': 'none',
          'token': 'v2',
        },
      },
    ];
    final result = StudyNoteReminderPlan.build(notes, now);
    expect(result.first.noteId, 'n');
    expect(result.first.fire, DateTime(2026, 11, 2, 9));
    expect(result.map((entry) => entry.noteId).toSet(), {'n'});
  });
}
