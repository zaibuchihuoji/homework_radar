import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Uncompressed, length-delimited backup with content checksums.
/// No archive paths are extracted, and declared sizes are checked first.
class StudyNoteBundle {
  StudyNoteBundle({
    required this.businessJson,
    required this.notes,
    required this.attachments,
    this.history = const [],
    this.historyIncluded = true,
  });
  final String businessJson;
  final List<Map<String, dynamic>> notes;
  final Map<String, Uint8List> attachments;
  final List<List<Map<String, dynamic>>> history;
  final bool historyIncluded;

  static const _magic = 'HWRNBK01';
  static const _maxHeader = 64 * 1024 * 1024;
  static const _maxBundle = 256 * 1024 * 1024;
  static final _digestPattern = RegExp(r'^[0-9a-f]{64}$');

  static Set<String> referencedAttachments(List<Map<String, dynamic>> notes) {
    final ids = <String>{};
    final refs = <String>{};
    for (final note in notes) {
      final id = note['id'];
      if (id is! String || id.isEmpty || !ids.add(id)) {
        throw const FormatException('备份中的笔记编号无效或重复');
      }
      for (final key in [
        'title',
        'body',
        'course',
        'chapter',
        'courseTeacher',
        'courseAnchor',
        'updatedAt',
      ]) {
        if (note[key] != null && note[key] is! String) {
          throw const FormatException('笔记文字字段损坏');
        }
      }
      for (final key in ['favorite', 'deleted']) {
        if (note[key] != null && note[key] is! bool) {
          throw const FormatException('笔记状态损坏');
        }
      }
      final cards = note['cards'];
      if (cards != null && cards is! List) {
        throw const FormatException('自测卡片损坏');
      }
      for (final card in cards as List? ?? []) {
        if (card is! Map ||
            card['question'] is! String ||
            card['answer'] is! String ||
            (card['hard'] != null && card['hard'] is! bool)) {
          throw const FormatException('自测卡片损坏');
        }
      }
      final reminder = note['reminder'];
      if (reminder != null) {
        if (reminder is! Map ||
            reminder['at'] is! int ||
            reminder['token'] is! String ||
            (reminder['token'] as String).isEmpty ||
            !const ['none', 'daily', 'weekly'].contains(reminder['repeat'])) {
          throw const FormatException('笔记提醒损坏');
        }
        try {
          DateTime.fromMillisecondsSinceEpoch(reminder['at'] as int);
        } catch (_) {
          throw const FormatException('笔记提醒时间损坏');
        }
      }
      final blocks = note['blocks'];
      if (blocks != null && blocks is! List) {
        throw const FormatException('备份中的笔记内容损坏');
      }
      for (final block in blocks as List? ?? []) {
        if (block is! Map || block['type'] is! String) {
          throw const FormatException('备份中的笔记内容损坏');
        }
        if (!const ['image', 'drawing'].contains(block['type'])) {
          throw const FormatException('备份包含不支持的笔记内容');
        }
        final strokes = block['strokes'];
        if (strokes != null && strokes is! List) {
          throw const FormatException('笔迹数据损坏');
        }
        for (final stroke in strokes as List? ?? []) {
          if (stroke is! Map ||
              stroke['color'] is! int ||
              stroke['points'] is! List) {
            throw const FormatException('笔迹数据损坏');
          }
          for (final point in stroke['points'] as List) {
            if (point is! List ||
                point.length != 2 ||
                point[0] is! num ||
                point[1] is! num ||
                !(point[0] as num).isFinite ||
                !(point[1] as num).isFinite ||
                (point[0] as num) < 0 ||
                (point[0] as num) > 1 ||
                (point[1] as num) < 0 ||
                (point[1] as num) > 1) {
              throw const FormatException('笔迹坐标损坏');
            }
          }
        }
        if (block['type'] == 'image') {
          final attachment = block['attachmentId'];
          if (attachment is! String || !_digestPattern.hasMatch(attachment)) {
            throw const FormatException('备份中的图片引用损坏');
          }
          refs.add(attachment);
        }
      }
    }
    return refs;
  }

  Uint8List encode() {
    if (!historyIncluded && history.isNotEmpty) {
      throw const FormatException('笔记历史备份标记不一致');
    }
    final refs = referencedAttachments(notes);
    for (final version in history) {
      refs.addAll(referencedAttachments(version));
    }
    if (refs.length != attachments.length ||
        !refs.containsAll(attachments.keys)) {
      throw const FormatException('笔记图片缺失或存在未知附件');
    }
    final names = attachments.keys.toList()..sort();
    var total = 0;
    for (final name in names) {
      final bytes = attachments[name]!;
      if (bytes.length > 64 * 1024 * 1024 ||
          sha256.convert(bytes).toString() != name) {
        throw const FormatException('笔记图片校验失败');
      }
      total += bytes.length;
      if (total > _maxBundle) throw const FormatException('备份过大');
    }
    final header = utf8.encode(
      jsonEncode({
        'version': 2,
        'business': businessJson,
        'notes': notes,
        'history': history,
        'historyIncluded': historyIncluded,
        'assets': [
          for (final name in names)
            {'id': name, 'size': attachments[name]!.length},
        ],
      }),
    );
    if (header.length > _maxHeader || header.length + total + 44 > _maxBundle) {
      throw const FormatException('备份过大');
    }
    final length = ByteData(4)..setUint32(0, header.length);
    final result = BytesBuilder(copy: false)
      ..add(ascii.encode(_magic))
      ..add(length.buffer.asUint8List())
      ..add(sha256.convert(header).bytes)
      ..add(header);
    for (final name in names) {
      result.add(attachments[name]!);
    }
    return result.takeBytes();
  }

  static StudyNoteBundle decode(Uint8List bytes) {
    if (bytes.length < 44 ||
        bytes.length > _maxBundle ||
        !const ListEquality().equals(
          bytes.sublist(0, 8),
          ascii.encode(_magic),
        )) {
      throw const FormatException('备份格式无效或文件过大');
    }
    final headerLength = ByteData.sublistView(bytes, 8, 12).getUint32(0);
    if (headerLength > _maxHeader || headerLength > bytes.length - 44) {
      throw const FormatException('备份清单长度无效');
    }
    final header = Uint8List.sublistView(bytes, 44, 44 + headerLength);
    if (!const ListEquality().equals(
      bytes.sublist(12, 44),
      sha256.convert(header).bytes,
    )) {
      throw const FormatException('备份清单校验失败');
    }
    try {
      final data = jsonDecode(utf8.decode(header));
      if (data is! Map ||
          (data['version'] != 1 && data['version'] != 2) ||
          data['business'] is! String ||
          data['notes'] is! List ||
          data['assets'] is! List) {
        throw const FormatException('备份清单格式无效或版本不受支持');
      }
      final notes = (data['notes'] as List)
          .map((n) => Map<String, dynamic>.from(n as Map))
          .toList();
      final refs = referencedAttachments(notes);
      if (data['version'] == 2 && data['history'] is! List) {
        throw const FormatException('笔记历史清单损坏');
      }
      if (data['version'] == 2 && data['historyIncluded'] is! bool) {
        throw const FormatException('笔记历史备份标记损坏');
      }
      final history = <List<Map<String, dynamic>>>[];
      for (final rawVersion in (data['history'] as List? ?? [])) {
        if (rawVersion is! List) throw const FormatException('笔记历史清单损坏');
        final version = rawVersion
            .map((n) => Map<String, dynamic>.from(n as Map))
            .toList();
        refs.addAll(referencedAttachments(version));
        history.add(version);
      }
      if (data['version'] == 2 &&
          data['historyIncluded'] == false &&
          history.isNotEmpty) {
        throw const FormatException('笔记历史备份标记不一致');
      }
      final attachments = <String, Uint8List>{};
      var offset = 44 + headerLength;
      for (final item in data['assets'] as List) {
        if (item is! Map || item['id'] is! String || item['size'] is! int) {
          throw const FormatException('备份附件清单无效');
        }
        final id = item['id'] as String;
        final size = item['size'] as int;
        if (!_digestPattern.hasMatch(id) ||
            size < 0 ||
            size > 64 * 1024 * 1024 ||
            size > bytes.length - offset ||
            attachments.containsKey(id) ||
            !refs.contains(id)) {
          throw const FormatException('备份附件清单无效');
        }
        final value = Uint8List.fromList(
          Uint8List.sublistView(bytes, offset, offset + size),
        );
        if (sha256.convert(value).toString() != id) {
          throw const FormatException('备份附件校验失败');
        }
        attachments[id] = value;
        offset += size;
      }
      if (offset != bytes.length || attachments.length != refs.length) {
        throw const FormatException('备份附件缺失或含有多余数据');
      }
      return StudyNoteBundle(
        businessJson: data['business'] as String,
        notes: notes,
        attachments: attachments,
        history: history,
        historyIncluded: data['version'] == 2
            ? data['historyIncluded'] as bool
            : false,
      );
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('备份格式损坏');
    }
  }
}

class ListEquality {
  const ListEquality();
  bool equals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
