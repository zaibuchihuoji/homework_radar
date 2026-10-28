import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../services/study_note_document.dart';
import '../services/study_note_store.dart';
import '../ui/study_note_ink.dart';
import '../ui/study_note_text_controller.dart';
import '../ui/tokens.dart';
import 'study_note_canvas.dart';

class _DocumentSnapshot {
  const _DocumentSnapshot(this.json, this.activeId, this.selection);
  final String json;
  final String? activeId;
  final TextSelection? selection;
}

/// Editable content of one note. The parent owns durable snapshot writes.
class StudyNoteDocumentEditor extends StatefulWidget {
  const StudyNoteDocumentEditor({
    super.key,
    required this.document,
    required this.store,
    required this.onChanged,
    required this.save,
    required this.onError,
    required this.onCreateCard,
    this.header,
    this.footer,
    this.showDetails = false,
  });

  final Map<String, dynamic> document;
  final StudyNoteStore store;
  final ValueChanged<Map<String, dynamic>> onChanged;
  final Future<bool> Function() save;
  final ValueChanged<String> onError;
  final Future<void> Function(String text) onCreateCard;
  final Widget? header;
  final Widget? footer;
  final bool showDetails;

  @override
  State<StudyNoteDocumentEditor> createState() =>
      _StudyNoteDocumentEditorState();
}

class _StudyNoteDocumentEditorState extends State<StudyNoteDocumentEditor> {
  late Map<String, dynamic> _document;
  final _controllers = <String, StudyNoteTextController>{};
  final _focusNodes = <String, FocusNode>{};
  final _attachments = <String, Future<Uint8List>>{};
  String? _activeId;
  int _nextId = 0;
  bool _inking = false;
  bool _organizing = false;
  bool _eraser = false;
  String? _typingStyleId;
  int? _typingCursor;
  final _typingMarks = <String>{};
  Color _inkColor = const Color(0xff244d7a);
  double _inkWidth = 3;
  final _inkUndo =
      <({String id, String key, List<dynamic> before, List<dynamic> after})>[];
  final _inkRedo =
      <({String id, String key, List<dynamic> before, List<dynamic> after})>[];
  final _undo = <_DocumentSnapshot>[];
  final _redo = <_DocumentSnapshot>[];

  List<Map<String, dynamic>> get _nodes =>
      (_document['nodes'] as List).cast<Map<String, dynamic>>();

  int _numberAt(int index) {
    var number = 1;
    for (var i = index - 1; i >= 0 && _nodes[i]['style'] == 'numbered'; i--) {
      number++;
    }
    return number;
  }

  Map<String, dynamic> _copy(Map value) =>
      Map<String, dynamic>.from(jsonDecode(jsonEncode(value)) as Map);

  @override
  void initState() {
    super.initState();
    _document = _copy(widget.document);
    for (final node in _nodes) {
      if (node['type'] == 'text') {
        _controllers[node['id'] as String] = StudyNoteTextController(
          text: node['text'] as String,
          marks: node['marks'] as List? ?? [],
        );
        _activeId ??= node['id'] as String;
      }
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    for (final focus in _focusNodes.values) {
      focus.dispose();
    }
    super.dispose();
  }

  void _focusText(String id) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !widget.showDetails) _focusNodes[id]?.requestFocus();
    });
  }

  Widget _tool(IconData icon, String label, {bool active = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 9),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 21,
          color: active ? paletteOf(context).accent : paletteOf(context).ink2,
        ),
        const SizedBox(height: 3),
        Text(
          label,
          style: TextStyle(fontSize: 11, color: paletteOf(context).ink2),
        ),
      ],
    ),
  );

  PopupMenuItem<String> _markItem(String type, String label) {
    final controller = _controllers[_activeId];
    final selection = controller?.selection;
    final node = _nodes
        .where((n) => n['id'] == _activeId && n['type'] == 'text')
        .firstOrNull;
    var active = false;
    if (controller != null &&
        selection != null &&
        selection.isValid &&
        node != null) {
      if (selection.isCollapsed &&
          _typingStyleId == _activeId &&
          _typingCursor == selection.extentOffset) {
        active = _typingMarks.contains(type);
      } else {
        final start = selection.start, end = selection.end;
        active = (node['marks'] as List? ?? []).any(
          (mark) =>
              mark is Map &&
              mark['type'] == type &&
              (selection.isCollapsed
                  ? mark['start'] < start && mark['end'] >= start
                  : mark['start'] <= start && mark['end'] >= end),
        );
      }
    }
    return PopupMenuItem(
      value: type,
      child: Row(
        children: [
          Expanded(child: Text(label)),
          if (active) const Icon(Icons.check, size: 18),
        ],
      ),
    );
  }

  void _publish() => widget.onChanged(_copy(_document));

  _DocumentSnapshot _snapshot() => _DocumentSnapshot(
    jsonEncode(_document),
    _activeId,
    _controllers[_activeId]?.selection,
  );

  void _recordBeforeEdit() {
    final snapshot = _snapshot();
    // Large drawings are still saved and remain recoverable from note history.
    // Avoid keeping dozens of large document copies in mobile memory.
    if (snapshot.json.length > 2 * 1024 * 1024) {
      _undo.clear();
      _redo.clear();
      return;
    }
    _undo.add(snapshot);
    if (_undo.length > 30) _undo.removeAt(0);
    _redo.clear();
  }

  void _restoreDocument({required bool undo}) {
    final source = undo ? _undo : _redo;
    final destination = undo ? _redo : _undo;
    if (source.isEmpty) return;
    destination.add(_snapshot());
    final snapshot = source.removeLast();
    final restored = Map<String, dynamic>.from(
      jsonDecode(snapshot.json) as Map,
    );
    final restoredNodes = (restored['nodes'] as List)
        .cast<Map<String, dynamic>>();
    final textIds = restoredNodes
        .where((n) => n['type'] == 'text')
        .map((n) => n['id'] as String)
        .toSet();
    final removed = <StudyNoteTextController>[];
    final removedFocus = <FocusNode>[];
    for (final id in _controllers.keys.toList()) {
      if (!textIds.contains(id)) {
        removed.add(_controllers.remove(id)!);
        final focus = _focusNodes.remove(id);
        if (focus != null) removedFocus.add(focus);
      }
    }
    setState(() {
      _document = restored;
      _activeId = textIds.contains(snapshot.activeId)
          ? snapshot.activeId
          : textIds.firstOrNull;
      for (final node in restoredNodes.where((n) => n['type'] == 'text')) {
        final id = node['id'] as String;
        final text = node['text'] as String;
        final controller = _controllers.putIfAbsent(
          id,
          () => StudyNoteTextController(),
        );
        final previousSelection = id == _activeId
            ? snapshot.selection
            : controller.selection;
        final selection = previousSelection != null && previousSelection.isValid
            ? TextSelection(
                baseOffset: previousSelection.baseOffset.clamp(0, text.length),
                extentOffset: previousSelection.extentOffset.clamp(
                  0,
                  text.length,
                ),
              )
            : TextSelection.collapsed(offset: text.length);
        controller.value = TextEditingValue(text: text, selection: selection);
        controller.setMarks(node['marks'] as List? ?? []);
      }
      _inkUndo.clear();
      _inkRedo.clear();
      _typingStyleId = null;
      _typingCursor = null;
      _typingMarks.clear();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final controller in removed) {
        controller.dispose();
      }
      for (final focus in removedFocus) {
        focus.dispose();
      }
    });
    _publish();
  }

  List<dynamic> _copyList(List<dynamic> value) =>
      jsonDecode(jsonEncode(value)) as List;

  List<dynamic> _mergeMarks(List<dynamic> marks) {
    String attributes(Map<String, dynamic> mark) => jsonEncode(
      Map<String, dynamic>.from(mark)
        ..remove('start')
        ..remove('end'),
    );
    final result = <Map<String, dynamic>>[];
    for (final type in StudyNoteDocument.markStyles) {
      final ranges =
          marks
              .where((m) => m is Map && m['type'] == type)
              .map((m) => _copy(m as Map))
              .toList()
            ..sort((a, b) => (a['start'] as int).compareTo(b['start'] as int));
      for (final mark in ranges) {
        if (result.isNotEmpty &&
            result.last['type'] == type &&
            attributes(result.last) == attributes(mark) &&
            (mark['start'] as int) <= (result.last['end'] as int)) {
          if ((mark['end'] as int) > (result.last['end'] as int)) {
            result.last['end'] = mark['end'];
          }
        } else {
          result.add(mark);
        }
      }
    }
    return result;
  }

  void _changeInk(String id, String key, List<dynamic> value) {
    final index = _nodes.indexWhere((node) => node['id'] == id);
    if (index < 0) return;
    final before = _copyList(_nodes[index][key] as List? ?? []);
    final after = _copyList(value);
    if (jsonEncode(before) == jsonEncode(after)) return;
    _recordBeforeEdit();
    _inkUndo.add((id: id, key: key, before: before, after: after));
    if (_inkUndo.length > 50) _inkUndo.removeAt(0);
    _inkRedo.clear();
    setState(() => _nodes[index][key] = after);
    _publish();
  }

  void _restoreInk({required bool undo}) {
    final source = undo ? _inkUndo : _inkRedo;
    final target = undo ? _inkRedo : _inkUndo;
    if (source.isEmpty) return;
    final change = source.removeLast();
    final index = _nodes.indexWhere((node) => node['id'] == change.id);
    if (index < 0) return;
    _recordBeforeEdit();
    target.add(change);
    setState(
      () => _nodes[index][change.key] = _copyList(
        undo ? change.before : change.after,
      ),
    );
    _publish();
  }

  void _changeText(Map<String, dynamic> node, String value) {
    final old = node['text'] as String;
    if (old == value) return;
    _recordBeforeEdit();
    final controller = _controllers[node['id']]!;
    final selection = controller.selection;
    final composing = controller.value.composing;
    final cursor = selection.extentOffset;
    final insertedNewline =
        const {'bullet', 'numbered', 'check'}.contains(node['style']) &&
        (!composing.isValid || composing.isCollapsed) &&
        selection.isValid &&
        selection.isCollapsed &&
        cursor > 0 &&
        value.length == old.length + 1 &&
        value[cursor - 1] == '\n' &&
        value.substring(0, cursor - 1) + value.substring(cursor) == old;
    if (insertedNewline) {
      final id = node['id'] as String;
      final index = _nodes.indexWhere((n) => n['id'] == id);
      if (old.isEmpty) {
        setState(() => node['style'] = 'paragraph');
        controller.value = const TextEditingValue(
          selection: TextSelection.collapsed(offset: 0),
        );
        _activeId = id;
      } else {
        final offset = cursor - 1;
        final nextId = _id();
        late Map<String, dynamic> left, right;
        if (offset == 0) {
          left = {
            ..._copy(node),
            'text': '',
            'marks': <dynamic>[],
            'annotations': <dynamic>[],
          };
          right = {..._copy(node), 'id': nextId};
        } else if (offset == old.length) {
          left = _copy(node);
          right = {
            ..._copy(node),
            'id': nextId,
            'text': '',
            'marks': <dynamic>[],
            'annotations': <dynamic>[],
          };
        } else {
          try {
            (left, right) = StudyNoteDocument.splitTextNode(
              node,
              offset,
              nextId,
            );
          } on FormatException {
            controller.value = TextEditingValue(
              text: old,
              selection: TextSelection.collapsed(
                offset: (offset + 1).clamp(0, old.length),
              ),
            );
            ScaffoldMessenger.of(context)
                .showSnackBar(const SnackBar(content: Text('请将光标移到字符之间，再换行。')));
            return;
          }
        }
        if ((left['text'] as String).isEmpty) left['keepEmpty'] = true;
        if ((right['text'] as String).isEmpty) right['keepEmpty'] = true;
        right['checked'] = false;
        setState(() {
          if (left['keepEmpty'] == true || right['keepEmpty'] == true) {
            _document['version'] = 2;
          }
          _nodes[index] = left;
          _nodes.insert(index + 1, right);
          controller.value = TextEditingValue(
            text: left['text'] as String,
            selection: TextSelection.collapsed(
              offset: (left['text'] as String).length,
            ),
          );
          controller.setMarks(left['marks'] as List? ?? []);
          _controllers[nextId] = StudyNoteTextController(
            text: right['text'] as String,
            marks: right['marks'] as List? ?? [],
          );
          _controllers[nextId]!.selection = const TextSelection.collapsed(
            offset: 0,
          );
          _activeId = nextId;
        });
        _focusText(nextId);
      }
      _inkUndo.clear();
      _inkRedo.clear();
      _typingStyleId = null;
      _typingCursor = null;
      _typingMarks.clear();
      _publish();
      return;
    }
    var prefix = 0;
    while (prefix < old.length &&
        prefix < value.length &&
        old.codeUnitAt(prefix) == value.codeUnitAt(prefix)) {
      prefix++;
    }
    if (prefix > 0 &&
        prefix < old.length &&
        old.codeUnitAt(prefix - 1) >= 0xd800 &&
        old.codeUnitAt(prefix - 1) <= 0xdbff &&
        old.codeUnitAt(prefix) >= 0xdc00 &&
        old.codeUnitAt(prefix) <= 0xdfff) {
      prefix--;
    }
    var oldEnd = old.length, newEnd = value.length;
    while (oldEnd > prefix &&
        newEnd > prefix &&
        old.codeUnitAt(oldEnd - 1) == value.codeUnitAt(newEnd - 1)) {
      oldEnd--;
      newEnd--;
    }
    if (oldEnd > 0 &&
        oldEnd < old.length &&
        old.codeUnitAt(oldEnd - 1) >= 0xd800 &&
        old.codeUnitAt(oldEnd - 1) <= 0xdbff &&
        old.codeUnitAt(oldEnd) >= 0xdc00 &&
        old.codeUnitAt(oldEnd) <= 0xdfff) {
      oldEnd++;
    }
    if (newEnd > 0 &&
        newEnd < value.length &&
        value.codeUnitAt(newEnd - 1) >= 0xd800 &&
        value.codeUnitAt(newEnd - 1) <= 0xdbff &&
        value.codeUnitAt(newEnd) >= 0xdc00 &&
        value.codeUnitAt(newEnd) <= 0xdfff) {
      newEnd++;
    }
    if ((_typingStyleId != node['id'] || _typingCursor != prefix) &&
        oldEnd == prefix &&
        newEnd > prefix &&
        selection.isValid &&
        selection.isCollapsed &&
        selection.extentOffset == newEnd) {
      final inherited = <String>{};
      for (final mark in node['marks'] as List? ?? []) {
        if (mark is Map && mark['start'] < prefix && mark['end'] >= prefix) {
          inherited.add(mark['type'] as String);
        }
      }
      if (inherited.isNotEmpty) {
        _typingStyleId = node['id'] as String;
        _typingCursor = prefix;
        _typingMarks
          ..clear()
          ..addAll(inherited);
      }
    }
    final useTypingStyle =
        _typingStyleId == node['id'] &&
        _typingCursor != null &&
        prefix <= _typingCursor! &&
        oldEnd >= _typingCursor! &&
        selection.isValid &&
        selection.isCollapsed &&
        selection.extentOffset == newEnd;
    StudyNoteDocument.applyTextChange(node, value);
    if (useTypingStyle && newEnd > prefix) {
      final result = <dynamic>[];
      for (final raw in node['marks'] as List? ?? []) {
        final mark = _copy(raw as Map);
        final type = mark['type'] as String;
        final start = mark['start'] as int, end = mark['end'] as int;
        if (!_typingMarks.contains(type) && start < newEnd && end > prefix) {
          if (start < prefix) result.add({...mark, 'end': prefix});
          if (end > newEnd) result.add({...mark, 'start': newEnd});
        } else {
          result.add(mark);
        }
      }
      for (final type in _typingMarks) {
        if (!result.any(
          (raw) =>
              raw['type'] == type &&
              raw['start'] <= prefix &&
              raw['end'] >= newEnd,
        )) {
          result.add({'type': type, 'start': prefix, 'end': newEnd});
        }
      }
      node['marks'] = _mergeMarks(result);
    }
    if (useTypingStyle) {
      _typingCursor = newEnd;
    } else {
      _typingStyleId = null;
      _typingCursor = null;
      _typingMarks.clear();
    }
    _controllers[node['id']]?.setMarks(node['marks'] as List? ?? []);
    // Undo snapshots contain offsets from the previous text; never restore
    // them blindly after the text has changed.
    _inkUndo.clear();
    _inkRedo.clear();
    _activeId = node['id'] as String;
    _publish();
  }

  String _id() => 'n${DateTime.now().microsecondsSinceEpoch}-${_nextId++}';

  (Map<String, dynamic>, Map<String, dynamic>) _splitAtBoundary(
    Map<String, dynamic> node,
    int offset,
  ) {
    final text = node['text'] as String;
    final nextId = _id();
    if (offset == 0) {
      return (
        {
          ..._copy(node),
          'text': '',
          'marks': <dynamic>[],
          'annotations': <dynamic>[],
        },
        {..._copy(node), 'id': nextId},
      );
    }
    if (offset == text.length) {
      return (
        _copy(node),
        {
          ..._copy(node),
          'id': nextId,
          'text': '',
          'marks': <dynamic>[],
          'annotations': <dynamic>[],
        },
      );
    }
    return StudyNoteDocument.splitTextNode(node, offset, nextId);
  }

  int _insertionIndex({bool splitText = true}) {
    final index = _nodes.indexWhere((node) => node['id'] == _activeId);
    if (index < 0) return _nodes.length;
    final node = _nodes[index];
    final controller = _controllers[node['id']];
    final selection = controller?.selection;
    if (splitText &&
        node['type'] == 'text' &&
        selection != null &&
        selection.isValid) {
      final offset = selection.extentOffset;
      final text = node['text'] as String;
      if (offset > 0 && offset < text.length) {
        try {
          final (left, right) = StudyNoteDocument.splitTextNode(
            node,
            offset,
            _id(),
          );
          _nodes[index] = left;
          _nodes.insert(index + 1, right);
          controller!.value = TextEditingValue(
            text: left['text'] as String,
            selection: TextSelection.collapsed(
              offset: (left['text'] as String).length,
            ),
          );
          controller.setMarks(left['marks'] as List? ?? []);
          _controllers[right['id'] as String] = StudyNoteTextController(
            text: right['text'] as String,
            marks: right['marks'] as List? ?? [],
          );
          _inkUndo.clear();
          _inkRedo.clear();
        } on FormatException {
          // A cursor cannot split a Unicode character. Keep the original text
          // intact and place the new content after this paragraph instead.
        }
      }
    }
    return index + 1;
  }

  void _insertText({bool afterNodeOnly = false}) {
    final id = _id();
    _recordBeforeEdit();
    setState(() {
      _nodes.insert(_insertionIndex(splitText: !afterNodeOnly), {
        'id': id,
        'type': 'text',
        'text': '',
        'style': 'paragraph',
        'marks': <dynamic>[],
        'annotations': <dynamic>[],
      });
      _controllers[id] = StudyNoteTextController();
      _activeId = id;
    });
    _publish();
    _focusText(id);
  }

  void _ensureTextAfter(int index) {
    if (index + 1 < _nodes.length && _nodes[index + 1]['type'] == 'text') {
      _activeId = _nodes[index + 1]['id'] as String;
      _focusText(_activeId!);
      return;
    }
    final id = _id();
    _nodes.insert(index + 1, {
      'id': id,
      'type': 'text',
      'text': '',
      'style': 'paragraph',
      'marks': <dynamic>[],
      'annotations': <dynamic>[],
    });
    _controllers[id] = StudyNoteTextController();
    _activeId = id;
    _focusText(id);
  }

  void _format(String value) {
    if (value == 'makeCard') {
      _createCard();
      return;
    }
    final index = _nodes.indexWhere(
      (node) => node['id'] == _activeId && node['type'] == 'text',
    );
    if (index < 0) return;
    final node = _nodes[index];
    if (StudyNoteDocument.textStyles.contains(value)) {
      _formatLine(index, value);
      return;
    }
    final controller = _controllers[node['id']]!;
    final selection = controller.selection;
    if (!selection.isValid) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('请先点击正文，选择输入位置')));
      return;
    }
    if (selection.isCollapsed) {
      final offset = selection.extentOffset.clamp(0, controller.text.length);
      if (_typingStyleId != node['id'] || _typingCursor != offset) {
        _typingMarks.clear();
        for (final raw in node['marks'] as List? ?? []) {
          if (raw is Map &&
              raw['start'] is int &&
              raw['end'] is int &&
              raw['start'] < offset &&
              raw['end'] >= offset) {
            _typingMarks.add(raw['type'] as String);
          }
        }
      }
      setState(() {
        _typingStyleId = node['id'] as String;
        _typingCursor = offset;
        if (!_typingMarks.add(value)) _typingMarks.remove(value);
      });
      _focusText(_typingStyleId!);
      return;
    }
    final start = selection.start.clamp(0, controller.text.length);
    final end = selection.end.clamp(0, controller.text.length);
    if (start >= end) return;
    final current = _copyList(node['marks'] as List? ?? []);
    final covered = current.any(
      (raw) =>
          raw is Map &&
          raw['type'] == value &&
          (raw['start'] as int) <= start &&
          (raw['end'] as int) >= end,
    );
    final result = <dynamic>[];
    for (final raw in current) {
      final mark = _copy(raw as Map);
      if (covered &&
          mark['type'] == value &&
          (mark['start'] as int) < end &&
          (mark['end'] as int) > start) {
        if ((mark['start'] as int) < start) result.add({...mark, 'end': start});
        if ((mark['end'] as int) > end) result.add({...mark, 'start': end});
      } else {
        result.add(mark);
      }
    }
    if (!covered) result.add({'type': value, 'start': start, 'end': end});
    _typingStyleId = null;
    _typingCursor = null;
    _typingMarks.clear();
    _recordBeforeEdit();
    final normalized = _mergeMarks(result);
    setState(() => node['marks'] = normalized);
    controller.setMarks(normalized);
    _publish();
  }

  void _formatLine(int index, String style) {
    final original = _nodes[index];
    final text = original['text'] as String;
    final controller = _controllers[original['id']]!;
    final selection = controller.selection;
    final start = selection.isValid
        ? selection.start.clamp(0, text.length)
        : text.length;
    final end = selection.isValid ? selection.end.clamp(0, text.length) : start;
    final multipleLines =
        start != end && text.substring(start, end).contains('\n');
    final lineStart = start == 0 ? 0 : text.lastIndexOf('\n', start - 1) + 1;
    final lineSearchEnd = end > start && text.codeUnitAt(end - 1) == 10
        ? end - 1
        : end;
    final nextBreak = text.indexOf('\n', lineSearchEnd);
    final lineEnd = nextBreak < 0 ? text.length : nextBreak;
    if (lineStart == 0 && lineEnd == text.length && !text.contains('\n')) {
      if (original['style'] == style) return;
      _recordBeforeEdit();
      setState(() => original['style'] = style);
      _publish();
      return;
    }
    var target = _copy(original);
    final parts = <Map<String, dynamic>>[];
    if (lineStart > 0) {
      final (left, right) = _splitAtBoundary(target, lineStart);
      StudyNoteDocument.applyTextChange(
        left,
        (left['text'] as String).substring(0, lineStart - 1),
      );
      if ((left['text'] as String).isEmpty) left['keepEmpty'] = true;
      parts.add(left);
      target = right;
    }
    final targetLength = lineEnd - lineStart;
    Map<String, dynamic>? after;
    if (lineEnd < text.length) {
      final split = _splitAtBoundary(target, targetLength + 1);
      target = split.$1;
      after = split.$2;
      StudyNoteDocument.applyTextChange(
        target,
        (target['text'] as String).substring(0, targetLength),
      );
      if ((after['text'] as String).isEmpty) after['keepEmpty'] = true;
    }
    final styled = <Map<String, dynamic>>[];
    while ((target['text'] as String).contains('\n')) {
      final breakAt = (target['text'] as String).indexOf('\n');
      final split = _splitAtBoundary(target, breakAt + 1);
      final line = split.$1;
      StudyNoteDocument.applyTextChange(
        line,
        (line['text'] as String).substring(0, breakAt),
      );
      if ((line['text'] as String).isEmpty) line['keepEmpty'] = true;
      line['style'] = style;
      if (style == 'check' && original['style'] != 'check') {
        line['checked'] = false;
      }
      styled.add(line);
      target = split.$2;
    }
    target['style'] = style;
    if ((target['text'] as String).isEmpty) target['keepEmpty'] = true;
    if (style == 'check' && original['style'] != 'check') {
      target['checked'] = false;
    }
    styled.add(target);
    parts.addAll(styled);
    if (after != null) parts.add(after);
    if (parts.map((n) => n['text'] as String).join('\n') != text) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('该行暂时无法设置格式，原内容已保留')));
      return;
    }
    _recordBeforeEdit();
    setState(() {
      if (parts.any((part) => part['keepEmpty'] == true)) {
        _document['version'] = 2;
      }
      _nodes.replaceRange(index, index + 1, parts);
      for (final part in parts) {
        final id = part['id'] as String;
        final c = _controllers.putIfAbsent(id, () => StudyNoteTextController());
        final value = part['text'] as String;
        c.value = TextEditingValue(
          text: value,
          selection: id == target['id'] && !multipleLines
              ? TextSelection(
                  baseOffset:
                      (selection.isValid
                              ? selection.baseOffset - lineStart
                              : value.length)
                          .clamp(0, value.length),
                  extentOffset:
                      (selection.isValid
                              ? selection.extentOffset - lineStart
                              : value.length)
                          .clamp(0, value.length),
                )
              : TextSelection.collapsed(offset: value.length),
        );
        c.setMarks(part['marks'] as List? ?? []);
      }
      _activeId = target['id'] as String;
      _inkUndo.clear();
      _inkRedo.clear();
      _typingStyleId = null;
      _typingCursor = null;
      _typingMarks.clear();
    });
    _publish();
    _focusText(_activeId!);
  }

  void _createCard() {
    final controller = _controllers[_activeId];
    final selection = controller?.selection;
    if (controller == null ||
        selection == null ||
        !selection.isValid ||
        selection.isCollapsed) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('请先选择用于制卡的文字')));
      return;
    }
    final start = selection.start.clamp(0, controller.text.length);
    final end = selection.end.clamp(0, controller.text.length);
    if (start < end) widget.onCreateCard(controller.text.substring(start, end));
  }

  Future<void> _addImages({bool afterNodeOnly = false}) async {
    if (!await widget.save()) return;
    try {
      final files = await ImagePicker().pickMultiImage();
      int? insertion;
      String? lastInsertedId;
      for (final file in files) {
        if (await file.length() > 64 * 1024 * 1024) {
          throw const FormatException('图片大于 64 MB');
        }
        final bytes = await file.readAsBytes();
        final attachment = await widget.store.putAttachment(bytes);
        if (!mounted) return;
        _recordBeforeEdit();
        setState(() {
          if (lastInsertedId != null) {
            final previous = _nodes.indexWhere(
              (node) => node['id'] == lastInsertedId,
            );
            insertion = previous < 0 ? _nodes.length : previous + 1;
          }
          insertion ??= _insertionIndex(splitText: !afterNodeOnly);
          final id = _id();
          _nodes.insert(insertion!, {
            'id': id,
            'type': 'image',
            'attachmentId': attachment,
            'strokes': <dynamic>[],
          });
          lastInsertedId = id;
          insertion = insertion! + 1;
        });
        _publish();
        if (!await widget.save()) return;
      }
      if (lastInsertedId != null && mounted) {
        final last = _nodes.indexWhere((node) => node['id'] == lastInsertedId);
        if (last >= 0) {
          setState(() => _ensureTextAfter(last));
          _publish();
          await widget.save();
        }
      }
    } catch (error) {
      widget.onError('图片未能添加：$error');
    }
  }

  Future<void> _addCanvas({bool afterNodeOnly = false}) async {
    final id = _id();
    _recordBeforeEdit();
    setState(() {
      final index = _insertionIndex(splitText: !afterNodeOnly);
      _nodes.insert(index, {
        'id': id,
        'type': 'canvas',
        'strokes': <dynamic>[],
        'items': <dynamic>[],
      });
      _ensureTextAfter(index);
    });
    _publish();
    if (await widget.save()) await _openCanvas(id);
  }

  Future<void> _openCanvas(String id) async {
    if (!await widget.save()) return;
    final index = _nodes.indexWhere((node) => node['id'] == id);
    if (index < 0) return;
    final node = _copy(_nodes[index]);
    try {
      final image = node['type'] == 'image'
          ? await widget.store.readAttachment(node['attachmentId'] as String)
          : null;
      if (!mounted) return;
      _inkUndo.clear();
      _inkRedo.clear();
      await Navigator.of(context).push<List<dynamic>>(
        MaterialPageRoute(
          builder: (_) => StudyNoteCanvas(
            image: image,
            strokes: node['strokes'] as List? ?? [],
            items: node['items'] as List? ?? [],
            saveAttachment: node['type'] == 'canvas'
                ? widget.store.putAttachment
                : null,
            readAttachment: node['type'] == 'canvas'
                ? widget.store.readAttachment
                : null,
            onCanvasChanged: node['type'] == 'canvas'
                ? (strokes, items) async {
                    if (!mounted) return false;
                    final current = _nodes.indexWhere(
                      (entry) => entry['id'] == id,
                    );
                    if (current < 0) return false;
                    if (jsonEncode(_nodes[current]['strokes'] ?? []) ==
                            jsonEncode(strokes) &&
                        jsonEncode(_nodes[current]['items'] ?? []) ==
                            jsonEncode(items)) {
                      return widget.save();
                    }
                    _recordBeforeEdit();
                    setState(() {
                      _nodes[current]['strokes'] = strokes;
                      _nodes[current]['items'] = items;
                    });
                    _publish();
                    return widget.save();
                  }
                : null,
            onChanged: (strokes) async {
              if (!mounted) return false;
              final current = _nodes.indexWhere((entry) => entry['id'] == id);
              if (current < 0) return false;
              if (jsonEncode(_nodes[current]['strokes'] ?? []) ==
                  jsonEncode(strokes)) {
                return widget.save();
              }
              _recordBeforeEdit();
              setState(() => _nodes[current]['strokes'] = strokes);
              _publish();
              return widget.save();
            },
          ),
        ),
      );
    } catch (error) {
      widget.onError('无法打开画布：$error');
    }
  }

  Future<void> _remove(String id) async {
    final originalIndex = _nodes.indexWhere((node) => node['id'] == id);
    if (originalIndex < 0) return;
    final original = jsonEncode(_nodes[originalIndex]);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('移除这段内容？'),
        content: const Text('该内容会从当前笔记移除，之前保存的历史版本仍可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('移除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    if (!await widget.save() || !mounted) return;
    final currentIndex = _nodes.indexWhere((node) => node['id'] == id);
    if (currentIndex < 0 || jsonEncode(_nodes[currentIndex]) != original) {
      widget.onError('内容发生变化，请重新确认后再移除。');
      return;
    }
    _recordBeforeEdit();
    final removedController = _controllers.remove(id);
    setState(() {
      _nodes.removeWhere((node) => node['id'] == id);
      if (_activeId == id) _activeId = null;
    });
    if (removedController != null) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => removedController.dispose(),
      );
    }
    _publish();
  }

  void _moveNode(String id, int delta) {
    final index = _nodes.indexWhere((node) => node['id'] == id);
    final destination = index + delta;
    if (index < 0 || destination < 0 || destination >= _nodes.length) return;
    _recordBeforeEdit();
    setState(() => _nodes.insert(destination, _nodes.removeAt(index)));
    _publish();
  }

  Widget _nodeMenu(String id, int index, Color color) =>
      PopupMenuButton<String>(
        tooltip: '内容操作',
        padding: EdgeInsets.zero,
        onSelected: (value) {
          _activeId = id;
          switch (value) {
            case 'up':
              _moveNode(id, -1);
            case 'down':
              _moveNode(id, 1);
            case 'text':
              _insertText(afterNodeOnly: true);
            case 'image':
              _addImages(afterNodeOnly: true);
            case 'canvas':
              _addCanvas(afterNodeOnly: true);
            case 'remove':
              _remove(id);
          }
        },
        itemBuilder: (_) => [
          PopupMenuItem(
            value: 'up',
            enabled: index > 0,
            child: const Text('上移'),
          ),
          PopupMenuItem(
            value: 'down',
            enabled: index + 1 < _nodes.length,
            child: const Text('下移'),
          ),
          const PopupMenuDivider(),
          const PopupMenuItem(value: 'text', child: Text('在下方插入文字')),
          const PopupMenuItem(value: 'image', child: Text('在下方插入图片')),
          const PopupMenuItem(value: 'canvas', child: Text('在下方插入画布')),
          const PopupMenuDivider(),
          const PopupMenuItem(value: 'remove', child: Text('移除内容')),
        ],
        child: SizedBox(
          width: 32,
          height: 32,
          child: Icon(Icons.more_horiz, size: 19, color: color),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final p = paletteOf(context);
    final firstText = _nodes
        .where((node) => node['type'] == 'text')
        .firstOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) => ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
              children: [
                if (widget.showDetails && widget.footer != null)
                  widget.footer!
                else ...[
                  if (widget.header != null) widget.header!,
                  if (_nodes.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 20),
                      child: Text('从文字、图片或手写页开始记录'),
                    )
                  else
                    ReorderableListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      buildDefaultDragHandles: false,
                      itemCount: _nodes.length,
                      onReorderItem: (oldIndex, newIndex) {
                        _recordBeforeEdit();
                        setState(() {
                          _nodes.insert(newIndex, _nodes.removeAt(oldIndex));
                        });
                        _publish();
                      },
                      itemBuilder: (context, index) {
                        final node = _nodes[index];
                        final id = node['id'] as String;
                        final textStyle =
                            (node['style'] == 'heading'
                                    ? Theme.of(context).textTheme.titleLarge
                                          ?.copyWith(
                                            fontWeight: FontWeight.bold,
                                          )
                                    : Theme.of(context).textTheme.bodyLarge)
                                ?.copyWith(color: p.ink);
                        return Padding(
                          key: ValueKey('document-node:$id'),
                          padding: EdgeInsets.only(
                            bottom: node['type'] == 'text' ? 2 : 10,
                          ),
                          child: Material(
                            color: Colors.transparent,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(
                                p.pixel || p.terminal ? 2 : 12,
                              ),
                              side: BorderSide.none,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                if (_organizing && node['type'] != 'text')
                                  Row(
                                    children: [
                                      ReorderableDragStartListener(
                                        index: index,
                                        child: const Padding(
                                          padding: EdgeInsets.all(12),
                                          child: Icon(
                                            Icons.drag_indicator,
                                            size: 18,
                                          ),
                                        ),
                                      ),
                                      Expanded(
                                        child: Text(
                                          switch (node['type']) {
                                            'image' => '图片',
                                            'canvas' => '自由画布',
                                            _ => '文字',
                                          },
                                          style: TextStyle(
                                            color: p.ink2,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                      _nodeMenu(id, index, p.ink2),
                                    ],
                                  ),
                                if (node['type'] == 'text')
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      0,
                                      4,
                                      0,
                                      8,
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            if (_organizing)
                                              ReorderableDragStartListener(
                                                index: index,
                                                child: SizedBox(
                                                  width: 30,
                                                  height: 32,
                                                  child: Icon(
                                                    Icons.drag_indicator,
                                                    size: 17,
                                                    color: p.ink2,
                                                  ),
                                                ),
                                              ),
                                            if (node['style'] == 'bullet')
                                              Padding(
                                                padding: const EdgeInsets.only(
                                                  right: 8,
                                                ),
                                                child: Text(
                                                  '•',
                                                  style: textStyle,
                                                ),
                                              )
                                            else if (node['style'] ==
                                                'numbered')
                                              Padding(
                                                padding: const EdgeInsets.only(
                                                  right: 8,
                                                ),
                                                child: Text(
                                                  '${_numberAt(index)}.',
                                                  style: textStyle,
                                                ),
                                              )
                                            else if (node['style'] == 'check')
                                              SizedBox(
                                                width: 30,
                                                height: 28,
                                                child: Checkbox(
                                                  value:
                                                      node['checked'] == true,
                                                  onChanged: _inking
                                                      ? null
                                                      : (value) {
                                                          _recordBeforeEdit();
                                                          setState(
                                                            () =>
                                                                node['checked'] =
                                                                    value ==
                                                                    true,
                                                          );
                                                          _publish();
                                                        },
                                                ),
                                              ),
                                            Expanded(
                                              child: StudyNoteInkLayer(
                                                strokes:
                                                    node['annotations']
                                                        as List? ??
                                                    [],
                                                enabled: _inking,
                                                eraser: _eraser,
                                                color: _inkColor,
                                                width: _inkWidth,
                                                text: node['text'] as String,
                                                textStyle: textStyle,
                                                darkBackground:
                                                    p.bg.computeLuminance() <
                                                    0.3,
                                                textSpan: _controllers[id]!
                                                    .buildTextSpan(
                                                      context: context,
                                                      style: textStyle,
                                                      withComposing: false,
                                                    ),
                                                onChanged: (strokes) =>
                                                    _changeInk(
                                                      id,
                                                      'annotations',
                                                      strokes,
                                                    ),
                                                child: TextField(
                                                  key: node == firstText
                                                      ? const ValueKey(
                                                          'note-body',
                                                        )
                                                      : ValueKey(
                                                          'note-text:$id',
                                                        ),
                                                  controller: _controllers[id],
                                                  focusNode: _focusNodes
                                                      .putIfAbsent(
                                                        id,
                                                        () => FocusNode(),
                                                      ),
                                                  maxLines: null,
                                                  minLines:
                                                      node == _nodes.last &&
                                                          node['style'] ==
                                                              'paragraph'
                                                      ? ((constraints.maxHeight -
                                                                    115) /
                                                                27)
                                                            .floor()
                                                            .clamp(3, 30)
                                                      : 1,
                                                  style: textStyle,
                                                  onTap: () => _activeId = id,
                                                  onChanged: (value) =>
                                                      _changeText(node, value),
                                                  decoration:
                                                      const InputDecoration(
                                                        hintText: '开始书写…',
                                                        isCollapsed: true,
                                                        contentPadding:
                                                            EdgeInsets.zero,
                                                        filled: false,
                                                        border:
                                                            InputBorder.none,
                                                        enabledBorder:
                                                            InputBorder.none,
                                                        focusedBorder:
                                                            InputBorder.none,
                                                        disabledBorder:
                                                            InputBorder.none,
                                                      ),
                                                ),
                                              ),
                                            ),
                                            if (_organizing)
                                              _nodeMenu(id, index, p.ink2),
                                          ],
                                        ),
                                        if ((node['annotations'] as List? ?? [])
                                            .any(
                                              (stroke) =>
                                                  stroke is Map &&
                                                  stroke['detached'] == true,
                                            ))
                                          Padding(
                                            padding: const EdgeInsets.only(
                                              top: 8,
                                            ),
                                            child: Text(
                                              '正文已变化，部分批注位置需要检查；笔迹仍保留。',
                                              style: TextStyle(
                                                color: p.ink2,
                                                fontSize: 12,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  )
                                else if (node['type'] == 'image')
                                  InkWell(
                                    onTap: () => _openCanvas(id),
                                    child: FutureBuilder<Uint8List>(
                                      future: _attachments.putIfAbsent(
                                        node['attachmentId'] as String,
                                        () => widget.store.readAttachment(
                                          node['attachmentId'] as String,
                                        ),
                                      ),
                                      builder: (context, snapshot) {
                                        if (snapshot.hasError) {
                                          return const Padding(
                                            padding: EdgeInsets.all(16),
                                            child: Text('图片暂时无法读取，请保留原笔记。'),
                                          );
                                        }
                                        if (!snapshot.hasData) {
                                          return const SizedBox(height: 80);
                                        }
                                        return SizedBox(
                                          height: 200,
                                          child: Center(
                                            child: AspectRatio(
                                              aspectRatio: 0.8,
                                              child: ColoredBox(
                                                color: Colors.white,
                                                child: StudyNoteInkLayer(
                                                  strokes:
                                                      node['strokes']
                                                          as List? ??
                                                      [],
                                                  enabled: _inking,
                                                  eraser: _eraser,
                                                  color: _inkColor,
                                                  width: _inkWidth,
                                                  onChanged: (strokes) =>
                                                      _changeInk(
                                                        id,
                                                        'strokes',
                                                        strokes,
                                                      ),
                                                  child: Image.memory(
                                                    snapshot.data!,
                                                    fit: BoxFit.contain,
                                                    errorBuilder:
                                                        (
                                                          context,
                                                          error,
                                                          stack,
                                                        ) => const Center(
                                                          child: Text(
                                                            '图片无法预览，原文件仍保留。',
                                                          ),
                                                        ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  )
                                else
                                  InkWell(
                                    onTap: () => _openCanvas(id),
                                    child: Column(
                                      children: [
                                        StudyNoteCanvasPreview(
                                          strokes:
                                              node['strokes'] as List? ?? [],
                                          items: node['items'] as List? ?? [],
                                          readAttachment: (attachment) =>
                                              _attachments.putIfAbsent(
                                                attachment,
                                                () => widget.store
                                                    .readAttachment(attachment),
                                              ),
                                        ),
                                        const Padding(
                                          padding: EdgeInsets.all(8),
                                          child: Text('点击展开编辑'),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                ],
              ],
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: p.card,
            border: Border(top: BorderSide(color: p.hairline)),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!widget.showDetails)
                  Row(
                    children: [
                      IconButton(
                        tooltip: '撤销正文',
                        visualDensity: VisualDensity.compact,
                        onPressed: _undo.isEmpty
                            ? null
                            : () => _restoreDocument(undo: true),
                        icon: const Icon(Icons.undo, size: 20),
                      ),
                      IconButton(
                        tooltip: '重做正文',
                        visualDensity: VisualDensity.compact,
                        onPressed: _redo.isEmpty
                            ? null
                            : () => _restoreDocument(undo: false),
                        icon: const Icon(Icons.redo, size: 20),
                      ),
                      Expanded(
                        child: PopupMenuButton<String>(
                          tooltip: '文本格式',
                          onSelected: _format,
                          itemBuilder: (_) => [
                            const PopupMenuItem(
                              value: 'paragraph',
                              child: Text('正文'),
                            ),
                            const PopupMenuItem(
                              value: 'heading',
                              child: Text('标题'),
                            ),
                            const PopupMenuItem(
                              value: 'bullet',
                              child: Text('项目列表'),
                            ),
                            const PopupMenuItem(
                              value: 'numbered',
                              child: Text('编号列表'),
                            ),
                            const PopupMenuItem(
                              value: 'check',
                              child: Text('待办事项'),
                            ),
                            const PopupMenuDivider(),
                            _markItem('bold', '加粗'),
                            _markItem('italic', '斜体'),
                            _markItem('underline', '下划线'),
                            _markItem('highlight', '重点标记'),
                            const PopupMenuDivider(),
                            const PopupMenuItem(
                              value: 'makeCard',
                              child: Text('选中文字制卡'),
                            ),
                          ],
                          child: _tool(Icons.format_size, '格式'),
                        ),
                      ),
                      Expanded(
                        child: InkWell(
                          onTap: _addImages,
                          child: Tooltip(
                            message: '添加图片',
                            child: _tool(Icons.image_outlined, '图片'),
                          ),
                        ),
                      ),
                      Expanded(
                        child: InkWell(
                          onTap: () {
                            FocusScope.of(context).unfocus();
                            setState(() => _inking = !_inking);
                          },
                          child: Tooltip(
                            message: _inking ? '完成批注' : '批注正文',
                            child: _tool(
                              _inking ? Icons.check : Icons.gesture,
                              _inking ? '完成' : '批注',
                              active: _inking,
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: PopupMenuButton<String>(
                          tooltip: '更多工具',
                          onSelected: (value) {
                            switch (value) {
                              case 'canvas':
                                _addCanvas();
                              case 'text':
                                _insertText();
                              case 'organize':
                                setState(() => _organizing = !_organizing);
                            }
                          },
                          itemBuilder: (_) => [
                            const PopupMenuItem(
                              value: 'canvas',
                              child: Text('添加画布'),
                            ),
                            PopupMenuItem(
                              value: 'organize',
                              child: Text(_organizing ? '完成整理' : '整理内容'),
                            ),
                            const PopupMenuDivider(),
                            const PopupMenuItem(
                              value: 'text',
                              child: Text('插入独立段落'),
                            ),
                          ],
                          child: _tool(Icons.more_horiz, '更多'),
                        ),
                      ),
                    ],
                  ),
                if (_inking && !widget.showDetails)
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        IconButton(
                          tooltip: '撤销批注',
                          visualDensity: VisualDensity.compact,
                          onPressed: _inkUndo.isEmpty
                              ? null
                              : () => _restoreInk(undo: true),
                          icon: const Icon(Icons.undo),
                        ),
                        IconButton(
                          tooltip: '重做批注',
                          visualDensity: VisualDensity.compact,
                          onPressed: _inkRedo.isEmpty
                              ? null
                              : () => _restoreInk(undo: false),
                          icon: const Icon(Icons.redo),
                        ),
                        IconButton(
                          tooltip: _eraser ? '切换画笔' : '橡皮',
                          visualDensity: VisualDensity.compact,
                          onPressed: () => setState(() => _eraser = !_eraser),
                          icon: Icon(
                            _eraser ? Icons.edit : Icons.auto_fix_normal,
                          ),
                        ),
                        PopupMenuButton<String>(
                          tooltip: '画笔设置',
                          icon: Icon(
                            Icons.palette_outlined,
                            color: studyNoteInkColor(
                              _inkColor,
                              darkBackground: p.bg.computeLuminance() < 0.3,
                            ),
                          ),
                          onSelected: (value) => setState(() {
                            switch (value) {
                              case 'blue':
                                _inkColor = const Color(0xff244d7a);
                              case 'red':
                                _inkColor = const Color(0xffcc4b44);
                              case 'green':
                                _inkColor = const Color(0xff286b4f);
                              case 'black':
                                _inkColor = Colors.black;
                              case 'thin':
                                _inkWidth = 2;
                              case 'medium':
                                _inkWidth = 4;
                              case 'thick':
                                _inkWidth = 8;
                            }
                            _eraser = false;
                          }),
                          itemBuilder: (_) => const [
                            PopupMenuItem(value: 'blue', child: Text('蓝色')),
                            PopupMenuItem(value: 'red', child: Text('红色')),
                            PopupMenuItem(value: 'green', child: Text('绿色')),
                            PopupMenuItem(value: 'black', child: Text('黑色')),
                            PopupMenuDivider(),
                            PopupMenuItem(value: 'thin', child: Text('细笔')),
                            PopupMenuItem(value: 'medium', child: Text('中笔')),
                            PopupMenuItem(value: 'thick', child: Text('粗笔')),
                          ],
                        ),
                      ],
                    ),
                  ),
                if (_inking && !widget.showDetails)
                  Padding(
                    padding: const EdgeInsets.only(left: 8, bottom: 6),
                    child: Text(
                      '在文字或图片上写画，拖动页边滚动。',
                      style: TextStyle(color: p.ink2, fontSize: 12),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
