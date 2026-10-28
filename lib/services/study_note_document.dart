import 'dart:convert';

/// Validation for the editable document stored alongside legacy note fields.
/// Invalid or newer formats are rejected before they can replace a snapshot.
class StudyNoteDocument {
  StudyNoteDocument._();

  static final _digest = RegExp(r'^[0-9a-f]{64}$');
  static const textStyles = {
    'paragraph',
    'heading',
    'bullet',
    'numbered',
    'check',
  };
  static const markStyles = {'bold', 'italic', 'underline', 'highlight'};

  static Map<String, dynamic> _copyMap(Map value) =>
      Map<String, dynamic>.from(jsonDecode(jsonEncode(value)) as Map);

  /// Split without flattening or dropping marks and pen strokes.
  static (Map<String, dynamic>, Map<String, dynamic>) splitTextNode(
    Map<String, dynamic> node,
    int offset,
    String newId,
  ) {
    final text = node['text'];
    if (node['type'] != 'text' ||
        text is! String ||
        offset <= 0 ||
        offset >= text.length ||
        newId.isEmpty) {
      throw const FormatException('无法在此位置拆分文字');
    }
    final previous = text.codeUnitAt(offset - 1);
    final next = text.codeUnitAt(offset);
    if (previous >= 0xd800 &&
        previous <= 0xdbff &&
        next >= 0xdc00 &&
        next <= 0xdfff) {
      throw const FormatException('无法拆分字符');
    }
    final left = _copyMap(node), right = _copyMap(node);
    left['text'] = text.substring(0, offset);
    right['id'] = newId;
    right['text'] = text.substring(offset);
    final leftMarks = <dynamic>[], rightMarks = <dynamic>[];
    for (final raw in node['marks'] as List? ?? []) {
      final mark = _copyMap(raw as Map);
      final start = mark['start'] as int, end = mark['end'] as int;
      if (start < offset) leftMarks.add({...mark, 'end': end.clamp(0, offset)});
      if (end > offset) {
        rightMarks.add({
          ...mark,
          'start': (start - offset).clamp(0, text.length),
          'end': end - offset,
        });
      }
    }
    final leftInk = <dynamic>[], rightInk = <dynamic>[];
    for (final raw in node['annotations'] as List? ?? []) {
      final stroke = _copyMap(raw as Map);
      final anchor = stroke['anchor'];
      if (anchor is int && anchor >= offset) {
        stroke['anchor'] = anchor - offset;
        rightInk.add(stroke);
      } else {
        if (anchor == null) stroke['detached'] = true;
        leftInk.add(stroke);
      }
    }
    left['marks'] = leftMarks;
    right['marks'] = rightMarks;
    left['annotations'] = leftInk;
    right['annotations'] = rightInk;
    return (left, right);
  }

  /// Move text ranges and handwriting anchors through a single text edit.
  /// Strokes whose anchor was deleted remain stored and are marked for review.
  static void applyTextChange(Map<String, dynamic> node, String value) {
    final old = node['text'] as String;
    var prefix = 0;
    while (prefix < old.length &&
        prefix < value.length &&
        old.codeUnitAt(prefix) == value.codeUnitAt(prefix)) {
      prefix++;
    }
    bool high(int c) => c >= 0xd800 && c <= 0xdbff;
    bool low(int c) => c >= 0xdc00 && c <= 0xdfff;
    if (prefix > 0 &&
        prefix < old.length &&
        high(old.codeUnitAt(prefix - 1)) &&
        low(old.codeUnitAt(prefix))) {
      prefix--;
    }
    var oldEnd = old.length;
    var newEnd = value.length;
    while (oldEnd > prefix &&
        newEnd > prefix &&
        old.codeUnitAt(oldEnd - 1) == value.codeUnitAt(newEnd - 1)) {
      oldEnd--;
      newEnd--;
    }
    if (oldEnd > 0 &&
        oldEnd < old.length &&
        high(old.codeUnitAt(oldEnd - 1)) &&
        low(old.codeUnitAt(oldEnd))) {
      oldEnd++;
    }
    if (newEnd > 0 &&
        newEnd < value.length &&
        high(value.codeUnitAt(newEnd - 1)) &&
        low(value.codeUnitAt(newEnd))) {
      newEnd++;
    }
    final delta = newEnd - oldEnd;
    final marks = <dynamic>[];
    for (final raw in node['marks'] as List? ?? []) {
      final mark = _copyMap(raw as Map);
      var start = mark['start'] as int;
      var end = mark['end'] as int;
      if (end <= prefix) {
        // The range is before the edit.
      } else if (start >= oldEnd) {
        start += delta;
        end += delta;
      } else {
        start = start < prefix ? start : prefix;
        end = end >= oldEnd ? end + delta : newEnd;
      }
      start = start.clamp(0, value.length);
      end = end.clamp(0, value.length);
      if (start < end) marks.add({...mark, 'start': start, 'end': end});
    }
    final annotations = <dynamic>[];
    for (final raw in node['annotations'] as List? ?? []) {
      final stroke = _copyMap(raw as Map);
      final anchor = stroke['anchor'];
      if (anchor is int) {
        if (anchor >= oldEnd) {
          stroke['anchor'] = (anchor + delta).clamp(0, value.length);
        } else if (anchor >= prefix) {
          stroke['anchor'] = prefix.clamp(0, value.length);
          stroke['detached'] = true;
        }
      }
      annotations.add(stroke);
    }
    node['text'] = value;
    node['marks'] = marks;
    node['annotations'] = annotations;
  }

  /// Opening a legacy note only constructs a view; it does not write or
  /// replace the original snapshot. The document is saved after an edit.
  static Map<String, dynamic> fromNote(Map<String, dynamic> note) {
    final existing = note['document'];
    if (existing != null) {
      referencedAttachments(existing);
      return _copyMap(existing as Map);
    }
    final nodes = <Map<String, dynamic>>[
      {
        'id': 'legacy-text',
        'type': 'text',
        'text': note['body'] as String? ?? '',
        'style': 'paragraph',
        'marks': <dynamic>[],
        'annotations': <dynamic>[],
      },
    ];
    final blocks = note['blocks'] as List? ?? [];
    for (var i = 0; i < blocks.length; i++) {
      final block = _copyMap(blocks[i] as Map);
      nodes.add({
        ...block,
        'id': 'legacy-$i',
        'type': block['type'] == 'drawing' ? 'canvas' : block['type'],
      });
    }
    final result = <String, dynamic>{'version': 1, 'nodes': nodes};
    referencedAttachments(result);
    return result;
  }

  /// Keep legacy search and note previews useful for structured documents.
  static String plainText(Map<String, dynamic> document) {
    referencedAttachments(document);
    final text = <String>[];
    for (final node in document['nodes'] as List) {
      if (node['type'] == 'text') {
        final value = node['text'] as String;
        if (value.isNotEmpty ||
            (document['version'] == 2 && node['keepEmpty'] == true)) {
          text.add(value);
        }
      } else if (node['type'] == 'canvas') {
        for (final item in node['items'] as List? ?? []) {
          if (item['type'] == 'text' && (item['text'] as String).isNotEmpty) {
            text.add(item['text'] as String);
          }
        }
      }
    }
    return text.join('\n');
  }

  /// Retain the previous representation for older note previews and history.
  static List<Map<String, dynamic>> legacyBlocks(
    Map<String, dynamic> document,
  ) {
    referencedAttachments(document);
    final result = <Map<String, dynamic>>[];
    for (final raw in document['nodes'] as List) {
      if (raw['type'] != 'image' && raw['type'] != 'canvas') continue;
      final block = _copyMap(raw as Map)..remove('id');
      block['type'] = block['type'] == 'canvas' ? 'drawing' : 'image';
      result.add(block);
    }
    return result;
  }

  static bool _unit(dynamic value) =>
      value is num && value.isFinite && value >= 0 && value <= 1;

  static void _strokes(dynamic value, {int? textLength}) {
    if (value == null) return;
    if (value is! List) throw const FormatException('笔迹数据损坏');
    for (final stroke in value) {
      if (stroke is! Map ||
          stroke['color'] is! int ||
          stroke['points'] is! List) {
        throw const FormatException('笔迹数据损坏');
      }
      final width = stroke['width'];
      if (width != null &&
          (width is! num || !width.isFinite || width <= 0 || width > 64)) {
        throw const FormatException('笔迹粗细无效');
      }
      final anchor = stroke['anchor'];
      if (anchor != null &&
          (anchor is! int ||
              textLength == null ||
              anchor < 0 ||
              anchor > textLength)) {
        throw const FormatException('笔迹位置无效');
      }
      if (stroke['detached'] != null && stroke['detached'] is! bool) {
        throw const FormatException('笔迹状态无效');
      }
      final hasGeometry = [
        'anchorX',
        'anchorY',
        'basisWidth',
        'basisHeight',
      ].any(stroke.containsKey);
      if (hasGeometry &&
          (anchor is! int ||
              !_unit(stroke['anchorX']) ||
              !_unit(stroke['anchorY']) ||
              stroke['basisWidth'] is! num ||
              stroke['basisHeight'] is! num ||
              !(stroke['basisWidth'] as num).isFinite ||
              !(stroke['basisHeight'] as num).isFinite ||
              (stroke['basisWidth'] as num) <= 0 ||
              (stroke['basisHeight'] as num) <= 0)) {
        throw const FormatException('笔迹定位数据无效');
      }
      for (final point in stroke['points'] as List) {
        if (point is! List ||
            point.length != 2 ||
            !_unit(point[0]) ||
            !_unit(point[1])) {
          throw const FormatException('笔迹坐标损坏');
        }
      }
    }
  }

  static String _attachment(dynamic value) {
    if (value is! String || !_digest.hasMatch(value)) {
      throw const FormatException('笔记图片引用损坏');
    }
    return value;
  }

  /// Returns all original image files referenced by a document, including
  /// images placed inside a free canvas.
  static Set<String> referencedAttachments(dynamic value) {
    if (value is! Map ||
        (value['version'] != 1 && value['version'] != 2) ||
        value['nodes'] is! List) {
      throw const FormatException('笔记文档格式损坏或版本不受支持');
    }
    final references = <String>{};
    final ids = <String>{};
    for (final node in value['nodes'] as List) {
      if (node is! Map ||
          node['id'] is! String ||
          (node['id'] as String).isEmpty ||
          !ids.add(node['id'] as String)) {
        throw const FormatException('笔记内容编号无效');
      }
      switch (node['type']) {
        case 'text':
          final text = node['text'];
          if (text is! String || !textStyles.contains(node['style'])) {
            throw const FormatException('笔记文字内容损坏');
          }
          if (node.containsKey('keepEmpty') &&
              (value['version'] != 2 || node['keepEmpty'] is! bool)) {
            throw const FormatException('笔记空行标记损坏');
          }
          if (node['checked'] != null && node['checked'] is! bool) {
            throw const FormatException('待办状态损坏');
          }
          final marks = node['marks'];
          if (marks != null && marks is! List) {
            throw const FormatException('笔记文字样式损坏');
          }
          for (final mark in marks as List? ?? []) {
            if (mark is! Map ||
                mark['start'] is! int ||
                mark['end'] is! int ||
                (mark['start'] as int) < 0 ||
                (mark['end'] as int) > text.length ||
                (mark['start'] as int) >= (mark['end'] as int) ||
                !markStyles.contains(mark['type'])) {
              throw const FormatException('笔记文字样式损坏');
            }
          }
          _strokes(node['annotations'], textLength: text.length);
        case 'image':
          references.add(_attachment(node['attachmentId']));
          _strokes(node['strokes']);
        case 'canvas':
          _strokes(node['strokes']);
          final items = node['items'];
          if (items != null && items is! List) {
            throw const FormatException('画布内容损坏');
          }
          final itemIds = <String>{};
          for (final item in items as List? ?? []) {
            if (item is! Map ||
                item['id'] is! String ||
                (item['id'] as String).isEmpty ||
                !itemIds.add(item['id'] as String) ||
                !_unit(item['x']) ||
                !_unit(item['y']) ||
                !_unit(item['width']) ||
                !_unit(item['height']) ||
                item['width'] == 0 ||
                item['height'] == 0) {
              throw const FormatException('画布内容位置损坏');
            }
            if (item['type'] == 'image') {
              references.add(_attachment(item['attachmentId']));
            } else if (item['type'] == 'text') {
              if (item['text'] is! String) {
                throw const FormatException('画布文字损坏');
              }
            } else {
              throw const FormatException('画布包含不支持的内容');
            }
          }
        default:
          throw const FormatException('笔记包含不支持的内容');
      }
    }
    return references;
  }
}
