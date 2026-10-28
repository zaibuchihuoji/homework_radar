class StudyNoteReminder {
  const StudyNoteReminder(this.noteId, this.title, this.token, this.fire);
  final String noteId, title, token;
  final DateTime fire;
}

class StudyNoteReminderPlan {
  static List<StudyNoteReminder> build(
    List<Map<String, dynamic>> notes,
    DateTime now,
  ) {
    final result = <StudyNoteReminder>[];
    final limit = now.add(const Duration(days: 56));
    for (final note in notes) {
      if (note['deleted'] == true || note['reminder'] == null) continue;
      final reminder = note['reminder'];
      if (note['id'] is! String ||
          reminder is! Map ||
          reminder['at'] is! int ||
          reminder['token'] is! String ||
          !const ['none', 'daily', 'weekly'].contains(reminder['repeat'])) {
        throw const FormatException('笔记提醒数据损坏');
      }
      final start = DateTime.fromMillisecondsSinceEpoch(reminder['at'] as int);
      final repeat = reminder['repeat'] as String;
      final title =
          (note['title'] is String &&
              (note['title'] as String).trim().isNotEmpty)
          ? note['title'] as String
          : '未命名笔记';
      void add(DateTime fire) => result.add(
        StudyNoteReminder(
          note['id'] as String,
          title,
          reminder['token'] as String,
          fire,
        ),
      );
      if (repeat == 'none') {
        if (start.isAfter(now)) add(start);
        continue;
      }
      if (start.isAfter(limit)) {
        add(start);
        continue;
      }
      final step = repeat == 'daily' ? 1 : 7;
      final days = now.difference(start).inDays;
      var offset = days > 0 ? ((days ~/ step) - 1).clamp(0, days) * step : 0;
      for (;;) {
        final fire = DateTime(
          start.year,
          start.month,
          start.day + offset,
          start.hour,
          start.minute,
        );
        if (fire.isAfter(limit)) break;
        if (fire.isAfter(now)) add(fire);
        offset += step;
      }
    }
    result.sort((a, b) => a.fire.compareTo(b.fire));
    return result;
  }
}
