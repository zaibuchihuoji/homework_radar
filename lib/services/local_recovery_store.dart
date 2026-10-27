import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/homework.dart';
import 'storage.dart';

class DeletedHomework {
  const DeletedHomework(this.item, this.deletedAt, {this.originalBody});
  final HomeworkItem item;
  final DateTime deletedAt;
  final Map<String, dynamic>? originalBody;
  Map<String, dynamic> toJson() => {
    'item': originalBody ?? item.toJson(),
    'deletedAt': deletedAt.millisecondsSinceEpoch,
  };
  factory DeletedHomework.fromJson(String id, Map<String, dynamic> raw) {
    final item = HomeworkItem.fromJson(
      Map<String, dynamic>.from(raw['item'] as Map),
    );
    if (item.id != id || item.platform != PlatformKind.manual) {
      throw const FormatException('回收站条目的身份无法核实');
    }
    return DeletedHomework(
      item,
      DateTime.fromMillisecondsSinceEpoch(raw['deletedAt'] as int),
      originalBody: Map<String, dynamic>.from(raw['item'] as Map),
    );
  }
}

class LocalRecoveryPoint {
  const LocalRecoveryPoint({
    required this.id,
    required this.createdAt,
    required this.reason,
    required this.homeworkCount,
    required this.courseCount,
    required this.payload,
  });
  final String id, reason, payload;
  final DateTime createdAt;
  final int homeworkCount, courseCount;

  String readBackup() => utf8.decode(gzip.decode(base64Decode(payload)));
  Map<String, dynamic> toJson() => {
    'id': id,
    'createdAt': createdAt.millisecondsSinceEpoch,
    'reason': reason,
    'homeworkCount': homeworkCount,
    'courseCount': courseCount,
    'payload': payload,
  };
  factory LocalRecoveryPoint.fromJson(Map<String, dynamic> raw) =>
      LocalRecoveryPoint(
        id: raw['id'] as String,
        createdAt: DateTime.fromMillisecondsSinceEpoch(raw['createdAt'] as int),
        reason: raw['reason'] as String,
        homeworkCount: raw['homeworkCount'] as int,
        courseCount: raw['courseCount'] as int,
        payload: raw['payload'] as String,
      );
}

abstract final class LocalRecoveryStore {
  static final error = ValueNotifier<String?>(null);
  static const _maxPoints = 7;
  static const _maxChars = 8 * 1024 * 1024;

  static List<DeletedHomework> deleted() {
    final raw = jsonDecode(Storage.manualHomeworkTrashRaw()) as Map;
    return [
      for (final entry in raw.entries)
        DeletedHomework.fromJson(
          entry.key as String,
          Map<String, dynamic>.from(entry.value as Map),
        ),
    ]..sort((a, b) => b.deletedAt.compareTo(a.deletedAt));
  }

  static Future<void> saveDeleted(Iterable<DeletedHomework> items) =>
      Storage.saveManualHomeworkTrash({
        for (final entry in items) entry.item.id: entry.toJson(),
      });

  static List<LocalRecoveryPoint> points() => [
    for (final raw in Storage.localRecoveryPoints())
      LocalRecoveryPoint.fromJson(
        Map<String, dynamic>.from(jsonDecode(raw) as Map),
      ),
  ];

  /// Caller captures inside its business transaction or before any writes.
  /// Only self-generated, credential-free backup JSON is accepted here.
  static Future<void> capture(
    String backup, {
    required String reason,
    bool daily = false,
    DateTime? now,
  }) async {
    final value = jsonDecode(backup) as Map;
    if (value['app'] != 'homework_radar') {
      throw const FormatException('备份格式无法核实');
    }
    final homework = (value['homework'] as List? ?? const []).length;
    final courses = (value['courses'] as List? ?? const []).length;
    if (homework == 0 &&
        courses == 0 &&
        (value['hiddenItems'] as Map? ?? const {}).isEmpty &&
        (value['accountArchives'] as List? ?? const []).isEmpty &&
        (value['manualTrash'] as Map? ?? const {}).isEmpty) {
      return;
    }
    final at = now ?? DateTime.now();
    final existing = points();
    if (daily &&
        existing.any(
          (p) =>
              p.createdAt.year == at.year &&
              p.createdAt.month == at.month &&
              p.createdAt.day == at.day,
        )) {
      return;
    }
    final next = LocalRecoveryPoint(
      id: at.microsecondsSinceEpoch.toString(),
      createdAt: at,
      reason: reason,
      homeworkCount: homework,
      courseCount: courses,
      payload: base64Encode(gzip.encode(utf8.encode(backup))),
    );
    final encoded = [
      jsonEncode(next.toJson()),
      ...existing.map((p) => jsonEncode(p.toJson())),
    ].take(_maxPoints).toList();
    if (encoded.first.length > _maxChars) throw StateError('数据过大，请先导出外部备份');
    while (encoded.fold<int>(0, (n, p) => n + p.length) > _maxChars) {
      encoded.removeLast();
    }
    await Storage.saveLocalRecoveryPoints(encoded);
    error.value = null;
  }
}
