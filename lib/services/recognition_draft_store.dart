import 'dart:convert';

import '../models/homework_draft.dart';
import 'storage.dart';

/// User input only. Never a saved homework item or an account session.
class RecognitionReviewRow {
  RecognitionReviewRow({
    required this.source,
    required this.course,
    required this.title,
    required this.dueAt,
    required this.selected,
  });
  final HomeworkDraft source;
  String course, title;
  DateTime? dueAt;
  bool selected;

  Map<String, dynamic> toJson() => {
    'course': course,
    'title': title,
    'dueAt': dueAt?.millisecondsSinceEpoch,
    'selected': selected,
    'source': {
      'course': source.course,
      'title': source.title,
      'text': source.sourceText,
      'dueAt': source.dueAt?.millisecondsSinceEpoch,
      'warnings': source.warnings,
      'likely': source.likelyHomework,
    },
  };

  factory RecognitionReviewRow.fromJson(Map<String, dynamic> value) {
    final source = Map<String, dynamic>.from(value['source'] as Map);
    DateTime? date(dynamic ms) =>
        ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms as int);
    return RecognitionReviewRow(
      source: HomeworkDraft(
        course: source['course'] as String,
        title: source['title'] as String,
        sourceText: source['text'] as String,
        dueAt: date(source['dueAt']),
        warnings: (source['warnings'] as List).cast<String>(),
        likelyHomework: source['likely'] as bool,
      ),
      course: value['course'] as String,
      title: value['title'] as String,
      dueAt: date(value['dueAt']),
      selected: value['selected'] as bool,
    );
  }
}

class RecognitionSession {
  String text = '';
  DateTime? noticeDate;
  String? imagePath;
  bool imageMode = false;
  List<RecognitionReviewRow>? rows;

  void updateSource(String value, DateTime? date) {
    if (text != value || noticeDate != date) rows = null;
    text = value;
    noticeDate = date;
  }

  Map<String, dynamic> toJson() => {
    'version': 1,
    'text': text,
    'noticeDate': noticeDate?.millisecondsSinceEpoch,
    'imagePath': imagePath,
    'imageMode': imageMode,
    if (rows != null) 'rows': [for (final row in rows!) row.toJson()],
  };

  factory RecognitionSession.fromJson(Map<String, dynamic> value) {
    if (value['version'] != 1 ||
        value['text'] is! String ||
        (value['text'] as String).length > 20000 ||
        (value['rows'] != null && value['rows'] is! List)) {
      throw const FormatException('草稿格式无法读取');
    }
    return RecognitionSession()
      ..text = value['text'] as String
      ..noticeDate = value['noticeDate'] == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(value['noticeDate'] as int)
      ..imagePath = value['imagePath'] as String?
      ..imageMode = value['imageMode'] == true
      ..rows = (value['rows'] as List?)
          ?.map(
            (row) => RecognitionReviewRow.fromJson(
              Map<String, dynamic>.from(row as Map),
            ),
          )
          .toList();
  }
  RecognitionSession();
}

abstract final class RecognitionDraftStore {
  static RecognitionSession? read() {
    final raw = Storage.recognitionDraft();
    if (raw == null) return null;
    return RecognitionSession.fromJson(
      Map<String, dynamic>.from(jsonDecode(raw) as Map),
    );
  }

  static Future<void> save(RecognitionSession value) {
    final raw = jsonEncode(value.toJson());
    return _write(raw);
  }

  static Future<void> clear() => _write(null);
  static Future<void> _write(String? value) {
    // SharedPreferences updates its in-memory value synchronously and sends
    // writes in call order. Do not delay a newer snapshot behind a route's
    // unrelated asynchronous work (or retain its lifecycle in a global queue).
    return Storage.saveRecognitionDraft(value);
  }
}
