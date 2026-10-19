/// Recognition results are transient. Only an explicit selection becomes an entry.
class HomeworkDraft {
  const HomeworkDraft({
    required this.course,
    required this.title,
    required this.sourceText,
    required this.warnings,
    this.dueAt,
    this.likelyHomework = true,
  });
  final String course, title, sourceText;
  final DateTime? dueAt;
  final List<String> warnings;
  final bool likelyHomework;
}

class ManualHomeworkEntry {
  const ManualHomeworkEntry({
    required this.course,
    required this.title,
    this.dueAt,
    this.note = '',
    this.duplicateApproved = false,
  });
  final String course, title, note;
  final DateTime? dueAt;
  final bool duplicateApproved;
}

class HomeworkImportResult {
  const HomeworkImportResult(this.count, {this.outputsDelayed = false});
  final int count;
  final bool outputsDelayed;
}

class HomeworkImportDuplicateException implements Exception {
  const HomeworkImportDuplicateException();
  @override
  String toString() => '保存前发现疑似重复作业，请核对后重新确认';
}
