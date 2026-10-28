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
  });

  final Map<String, dynamic> document;
  final StudyNoteStore store;
  final ValueChanged<Map<String, dynamic>> onChanged;
  final Future<bool> Function() save;
  final ValueChanged<String> onError;
  final Future<void> Function(String text) onCreateCard;
  final Widget? header;
  final Widget? footer;

  @override
  State<StudyNoteDocumentEditor> createState() =>
      _StudyNoteDocumentEditorState();
}

class _StudyNoteDocumentEditorState extends State<StudyNoteDocumentEditor> {
  late Map<String, dynamic> _document;
  final _controllers = <String, StudyNoteTextController>{};
  final _attachments = <String, Future<Uint8List>>{};
  String? _activeId;
  int _nextId = 0;
  bool _inking = false;
  bool _organizing = false;
  bool _eraser = false;
  Color _inkColor = const Color(0xff244d7a);
  double _inkWidth = 3;
  final _inkUndo =
      <({String id, String key, List<dynamic> before, List<dynamic> after})>[];
  final _inkRedo =
      <({String id, String key, List<dynamic> before, List<dynamic> after})>[];

  List<Map<String, dynamic>> get _nodes =>
      (_document['nodes'] as List).cast<Map<String, dynamic>>();

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
    super.dispose();
  }

  void _publish() => widget.onChanged(_copy(_document));

  List<dynamic> _copyList(List<dynamic> value) =>
      jsonDecode(jsonEncode(value)) as List;

  void _changeInk(String id, String key, List<dynamic> value) {
    final index = _nodes.indexWhere((node) => node['id'] == id);
    if (index < 0) return;
    final before = _copyList(_nodes[index][key] as List? ?? []);
    final after = _copyList(value);
    if (jsonEncode(before) == jsonEncode(after)) return;
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
    target.add(change);
    setState(
      () => _nodes[index][change.key] = _copyList(
        undo ? change.before : change.after,
      ),
    );
    _publish();
  }

  void _changeText(Map<String, dynamic> node, String value) {
    StudyNoteDocument.applyTextChange(node, value);
    _controllers[node['id']]?.setMarks(node['marks'] as List? ?? []);
    // Undo snapshots contain offsets from the previous text; never restore
    // them blindly after the text has changed.
    _inkUndo.clear();
    _inkRedo.clear();
    _activeId = node['id'] as String;
    _publish();
  }

  String _id() => 'n${DateTime.now().microsecondsSinceEpoch}-${_nextId++}';

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
  }

  void _ensureTextAfter(int index) {
    if (index + 1 < _nodes.length && _nodes[index + 1]['type'] == 'text') {
      _activeId = _nodes[index + 1]['id'] as String;
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
      setState(() => node['style'] = value);
      _publish();
      return;
    }
    final controller = _controllers[node['id']]!;
    final selection = controller.selection;
    if (!selection.isValid || selection.isCollapsed) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('请先选择要设置格式的文字')));
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
    setState(() => node['marks'] = result);
    controller.setMarks(result);
    _publish();
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
                                        ?.copyWith(fontWeight: FontWeight.bold)
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
                                          else if (node['style'] == 'numbered')
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                right: 8,
                                              ),
                                              child: Text(
                                                '${_nodes.take(index + 1).where((n) => n['style'] == 'numbered').length}.',
                                                style: textStyle,
                                              ),
                                            )
                                          else if (node['style'] == 'check')
                                            SizedBox(
                                              width: 30,
                                              height: 28,
                                              child: Checkbox(
                                                value: node['checked'] == true,
                                                onChanged: _inking
                                                    ? null
                                                    : (value) {
                                                        setState(
                                                          () =>
                                                              node['checked'] =
                                                                  value == true,
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
                                                  p.bg.computeLuminance() < 0.3,
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
                                                    : ValueKey('note-text:$id'),
                                                controller: _controllers[id],
                                                maxLines: null,
                                                minLines:
                                                    (node['text'] as String)
                                                        .isEmpty
                                                    ? 5
                                                    : 1,
                                                style: textStyle,
                                                onTap: () => _activeId = id,
                                                onChanged: (value) =>
                                                    _changeText(node, value),
                                                decoration:
                                                    const InputDecoration(
                                                      hintText: '记录知识与复习内容',
                                                      isCollapsed: true,
                                                      contentPadding:
                                                          EdgeInsets.zero,
                                                      filled: false,
                                                      border: InputBorder.none,
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
                                                    node['strokes'] as List? ??
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
                                                      (context, error, stack) =>
                                                          const Center(
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
                                        strokes: node['strokes'] as List? ?? [],
                                        items: node['items'] as List? ?? [],
                                        readAttachment: (attachment) =>
                                            _attachments.putIfAbsent(
                                              attachment,
                                              () => widget.store.readAttachment(
                                                attachment,
                                              ),
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
                if (widget.footer != null) widget.footer!,
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
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      Tooltip(
                        message: '插入文字',
                        child: IconButton(
                          onPressed: _insertText,
                          icon: const Icon(Icons.text_fields, size: 18),
                        ),
                      ),
                      Tooltip(
                        message: '添加图片',
                        child: IconButton(
                          onPressed: _addImages,
                          icon: const Icon(
                            Icons.add_photo_alternate_outlined,
                            size: 18,
                          ),
                        ),
                      ),
                      Tooltip(
                        message: '添加画布',
                        child: IconButton(
                          onPressed: _addCanvas,
                          icon: const Icon(Icons.draw_outlined, size: 18),
                        ),
                      ),
                      PopupMenuButton<String>(
                        tooltip: '文本格式',
                        onSelected: _format,
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: 'paragraph', child: Text('正文')),
                          PopupMenuItem(value: 'heading', child: Text('标题')),
                          PopupMenuItem(value: 'bullet', child: Text('项目列表')),
                          PopupMenuItem(value: 'numbered', child: Text('编号列表')),
                          PopupMenuItem(value: 'check', child: Text('待办事项')),
                          PopupMenuDivider(),
                          PopupMenuItem(value: 'bold', child: Text('加粗')),
                          PopupMenuItem(value: 'italic', child: Text('斜体')),
                          PopupMenuItem(value: 'underline', child: Text('下划线')),
                          PopupMenuItem(
                            value: 'highlight',
                            child: Text('重点标记'),
                          ),
                          PopupMenuDivider(),
                          PopupMenuItem(
                            value: 'makeCard',
                            child: Text('选中文字制卡'),
                          ),
                        ],
                        child: const Padding(
                          padding: EdgeInsets.all(10),
                          child: Icon(Icons.format_size, size: 20),
                        ),
                      ),
                      IconButton(
                        tooltip: _organizing ? '完成整理' : '整理内容',
                        visualDensity: VisualDensity.compact,
                        onPressed: () =>
                            setState(() => _organizing = !_organizing),
                        icon: Icon(
                          _organizing ? Icons.check : Icons.view_list_outlined,
                        ),
                      ),
                      IconButton(
                        tooltip: _inking ? '完成批注' : '批注正文',
                        visualDensity: VisualDensity.compact,
                        onPressed: () {
                          FocusScope.of(context).unfocus();
                          setState(() => _inking = !_inking);
                        },
                        icon: Icon(_inking ? Icons.check : Icons.gesture),
                      ),
                    ],
                  ),
                ),
                if (_inking)
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
                if (_inking)
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
