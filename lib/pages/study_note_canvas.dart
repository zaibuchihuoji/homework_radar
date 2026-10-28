import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' show PointMode;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../ui/settings_parts.dart';

/// Strokes use normalized coordinates so the original image is never modified.
class StudyNoteCanvas extends StatefulWidget {
  const StudyNoteCanvas({
    super.key,
    this.image,
    required this.strokes,
    required this.onChanged,
    this.items = const [],
    this.onCanvasChanged,
    this.saveAttachment,
    this.readAttachment,
  });
  final Uint8List? image;
  final List<dynamic> strokes;
  final Future<bool> Function(List<dynamic>) onChanged;
  final List<dynamic> items;
  final Future<bool> Function(List<dynamic> strokes, List<dynamic> items)?
  onCanvasChanged;
  final Future<String> Function(Uint8List bytes)? saveAttachment;
  final Future<Uint8List> Function(String id)? readAttachment;
  @override
  State<StudyNoteCanvas> createState() => _StudyNoteCanvasState();
}

class _StudyNoteCanvasState extends State<StudyNoteCanvas> {
  late List<dynamic> _strokes;
  late List<dynamic> _items;
  final _undo = <String>[];
  final _redo = <String>[];
  final _images = <String, Future<Uint8List>>{};
  final _transform = TransformationController();
  bool _move = false, _eraser = false, _objectMode = false;
  Color _color = const Color(0xff244d7a);
  double _width = 3;
  String? _selectedId;
  int _nextId = 0;
  List<List<double>>? _current;
  bool _saving = false;
  int _pendingSaves = 0;
  Future<void> _persistTail = Future<void>.value();
  String? _error;

  @override
  void initState() {
    super.initState();
    _strokes = jsonDecode(jsonEncode(widget.strokes)) as List;
    _items = jsonDecode(jsonEncode(widget.items)) as List;
  }

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  void _remember() {
    _undo.add(jsonEncode({'strokes': _strokes, 'items': _items}));
    if (_undo.length > 100) _undo.removeAt(0);
    _redo.clear();
  }

  String _snapshot() => jsonEncode({'strokes': _strokes, 'items': _items});

  void _restore(List<String> source, List<String> destination) {
    if (source.isEmpty) return;
    destination.add(_snapshot());
    final data = jsonDecode(source.removeLast()) as Map;
    setState(() {
      _strokes = data['strokes'] as List;
      _items = data['items'] as List;
      _selectedId = null;
    });
    _persist();
  }

  Future<bool> _persist() async {
    final copy = jsonDecode(jsonEncode(_strokes)) as List;
    final items = jsonDecode(jsonEncode(_items)) as List;
    _pendingSaves++;
    if (mounted) {
      setState(() {
        _saving = true;
        _error = null;
      });
    }
    final task = _persistTail.then((_) async {
      try {
        return widget.onCanvasChanged == null
            ? await widget.onChanged(copy)
            : await widget.onCanvasChanged!(copy, items);
      } catch (_) {
        return false;
      }
    });
    _persistTail = task.then<void>(
      (_) {},
      onError: (Object _, StackTrace stack) {},
    );
    final success = await task;
    _pendingSaves--;
    if (mounted) {
      setState(() {
        _saving = _pendingSaves > 0;
        if (!success) _error = '笔迹保存失败，请检查存储空间并重试。';
      });
    }
    return success;
  }

  void _point(Offset position, Size size) {
    final x = (position.dx / size.width).clamp(0.0, 1.0);
    final y = (position.dy / size.height).clamp(0.0, 1.0);
    if (_eraser) {
      _strokes.removeWhere((stroke) {
        if (stroke is! Map || stroke['points'] is! List) return false;
        return (stroke['points'] as List).any((point) {
          if (point is! List ||
              point.length != 2 ||
              point[0] is! num ||
              point[1] is! num) {
            return false;
          }
          final dx = ((point[0] as num).toDouble() - x) * size.width;
          final dy = ((point[1] as num).toDouble() - y) * size.height;
          return sqrt(dx * dx + dy * dy) < 18;
        });
      });
    } else {
      _current?.add([x, y]);
    }
  }

  Future<void> _editText([int? index]) async {
    final existing = index == null
        ? ''
        : (_items[index] as Map)['text'] as String;
    final value = await showDialog<String>(
      context: context,
      builder: (context) =>
          _CanvasTextDialog(existing: existing, isNew: index == null),
    );
    if (!mounted || value == null || (index == null && value.trim().isEmpty)) {
      return;
    }
    _remember();
    setState(() {
      if (index == null) {
        final id = 'item-${DateTime.now().microsecondsSinceEpoch}-${_nextId++}';
        _items.add({
          'id': id,
          'type': 'text',
          'text': value,
          'x': 0.1,
          'y': 0.1,
          'width': 0.45,
          'height': 0.13,
        });
        _selectedId = id;
      } else {
        _items[index] = {...(_items[index] as Map), 'text': value};
      }
      _objectMode = true;
      _move = false;
      _eraser = false;
    });
    await _persist();
  }

  Future<void> _addImages() async {
    final saveAttachment = widget.saveAttachment;
    if (saveAttachment == null || !await _persist()) return;
    try {
      final files = await ImagePicker().pickMultiImage();
      for (final file in files) {
        if (await file.length() > 64 * 1024 * 1024) {
          throw const FormatException('图片大于 64 MB');
        }
        final id = await saveAttachment(await file.readAsBytes());
        if (!mounted) return;
        _remember();
        setState(() {
          final itemId =
              'item-${DateTime.now().microsecondsSinceEpoch}-${_nextId++}';
          _items.add({
            'id': itemId,
            'type': 'image',
            'attachmentId': id,
            'x': 0.1,
            'y': 0.1,
            'width': 0.45,
            'height': 0.3,
          });
          _selectedId = itemId;
          _objectMode = true;
          _move = false;
          _eraser = false;
        });
        if (!await _persist()) return;
      }
    } catch (error) {
      if (mounted) setState(() => _error = '图片未能添加：$error');
    }
  }

  Future<void> _removeItem(String id) async {
    final originalIndex = _items.indexWhere(
      (item) => item is Map && item['id'] == id,
    );
    if (originalIndex < 0) return;
    final original = jsonEncode(_items[originalIndex]);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('移除画布内容？'),
        content: const Text('可通过撤销或笔记历史版本恢复。'),
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
    if (!await _persist() || !mounted) return;
    final currentIndex = _items.indexWhere(
      (item) => item is Map && item['id'] == id,
    );
    if (currentIndex < 0 || jsonEncode(_items[currentIndex]) != original) {
      setState(() => _error = '内容发生变化，请重新确认后再移除。');
      return;
    }
    _remember();
    setState(() {
      _items.removeWhere((item) => item is Map && item['id'] == id);
      _selectedId = null;
    });
    await _persist();
  }

  Widget _itemWidget(int index, Size size) {
    final item = _items[index] as Map;
    final id = item['id'] as String;
    final selected = _objectMode && id == _selectedId;
    final x = (item['x'] as num).toDouble();
    final y = (item['y'] as num).toDouble();
    final width = (item['width'] as num).toDouble();
    final height = (item['height'] as num).toDouble();
    return Positioned(
      left: x * size.width,
      top: y * size.height,
      width: width * size.width,
      height: height * size.height,
      child: IgnorePointer(
        ignoring: !_objectMode,
        child: GestureDetector(
          key: ValueKey('canvas-item:$id'),
          behavior: HitTestBehavior.opaque,
          dragStartBehavior: DragStartBehavior.down,
          onTap: () {
            setState(() => _selectedId = id);
            if (item['type'] == 'text') _editText(index);
          },
          onPanStart: (_) {
            _remember();
            setState(() => _selectedId = id);
          },
          onPanUpdate: (details) => setState(() {
            final current = Map<String, dynamic>.from(_items[index] as Map);
            current['x'] =
                ((current['x'] as num) + details.delta.dx / size.width).clamp(
                  0.0,
                  1.0 - (current['width'] as num),
                );
            current['y'] =
                ((current['y'] as num) + details.delta.dy / size.height).clamp(
                  0.0,
                  1.0 - (current['height'] as num),
                );
            _items[index] = current;
          }),
          onPanEnd: (_) => _persist(),
          child: Container(
            decoration: BoxDecoration(
              border: selected
                  ? Border.all(
                      color: Theme.of(context).colorScheme.primary,
                      width: 1.5,
                    )
                  : null,
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (item['type'] == 'text')
                  Padding(
                    padding: const EdgeInsets.all(4),
                    child: Text(
                      item['text'] as String,
                      overflow: TextOverflow.clip,
                      style: const TextStyle(color: Colors.black87),
                    ),
                  )
                else if (widget.readAttachment != null)
                  FutureBuilder<Uint8List>(
                    future: _images.putIfAbsent(
                      item['attachmentId'] as String,
                      () => widget.readAttachment!(
                        item['attachmentId'] as String,
                      ),
                    ),
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return const Center(child: Text('图片无法读取'));
                      }
                      if (!snapshot.hasData) return const SizedBox();
                      return Image.memory(
                        snapshot.data!,
                        fit: BoxFit.contain,
                        errorBuilder: (_, _, _) =>
                            const Center(child: Text('图片无法预览')),
                      );
                    },
                  ),
                if (selected) ...[
                  Positioned(
                    right: 0,
                    top: 0,
                    child: GestureDetector(
                      onTap: () => _removeItem(id),
                      child: const DecoratedBox(
                        decoration: BoxDecoration(color: Colors.white70),
                        child: Icon(Icons.close, size: 20),
                      ),
                    ),
                  ),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: GestureDetector(
                      dragStartBehavior: DragStartBehavior.down,
                      onPanStart: (_) => _remember(),
                      onPanUpdate: (details) => setState(() {
                        final current = Map<String, dynamic>.from(
                          _items[index] as Map,
                        );
                        current['width'] =
                            ((current['width'] as num) +
                                    details.delta.dx / size.width)
                                .clamp(0.08, 1.0 - (current['x'] as num));
                        current['height'] =
                            ((current['height'] as num) +
                                    details.delta.dy / size.height)
                                .clamp(0.05, 1.0 - (current['y'] as num));
                        _items[index] = current;
                      }),
                      onPanEnd: (_) => _persist(),
                      child: const DecoratedBox(
                        decoration: BoxDecoration(color: Colors.white70),
                        child: Icon(Icons.open_in_full, size: 20),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, result) async {
      if (!didPop && await _persist() && context.mounted) {
        Navigator.of(context).pop(_strokes);
      }
    },
    child: SettingsScaffold(
      title: widget.image == null ? '自由画布' : '图片批注',
      actions: [
        TextButton(
          onPressed: _saving
              ? null
              : () async {
                  if (await _persist() && context.mounted) {
                    Navigator.pop(context, _strokes);
                  }
                },
          child: const Text('保存'),
        ),
      ],
      body: Column(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                IconButton(
                  tooltip: '画笔',
                  onPressed: () => setState(() {
                    _move = false;
                    _eraser = false;
                    _objectMode = false;
                  }),
                  icon: Icon(
                    Icons.edit,
                    color: !_move && !_eraser && !_objectMode
                        ? Theme.of(context).colorScheme.primary
                        : null,
                  ),
                ),
                IconButton(
                  tooltip: '橡皮',
                  onPressed: () => setState(() {
                    _move = false;
                    _eraser = true;
                    _objectMode = false;
                  }),
                  icon: Icon(
                    Icons.auto_fix_normal,
                    color: _eraser
                        ? Theme.of(context).colorScheme.primary
                        : null,
                  ),
                ),
                IconButton(
                  tooltip: '移动和缩放',
                  onPressed: () => setState(() {
                    _move = true;
                    _objectMode = false;
                  }),
                  icon: Icon(
                    Icons.zoom_in,
                    color: _move ? Theme.of(context).colorScheme.primary : null,
                  ),
                ),
                IconButton(
                  tooltip: '撤销',
                  onPressed: _undo.isEmpty
                      ? null
                      : () => _restore(_undo, _redo),
                  icon: const Icon(Icons.undo),
                ),
                IconButton(
                  tooltip: '重做',
                  onPressed: _redo.isEmpty
                      ? null
                      : () => _restore(_redo, _undo),
                  icon: const Icon(Icons.redo),
                ),
                if (widget.image == null && widget.onCanvasChanged != null) ...[
                  IconButton(
                    tooltip: '添加画布文字',
                    onPressed: () => _editText(),
                    icon: const Icon(Icons.text_fields),
                  ),
                  if (widget.saveAttachment != null)
                    IconButton(
                      tooltip: '添加画布图片',
                      onPressed: _addImages,
                      icon: const Icon(Icons.add_photo_alternate_outlined),
                    ),
                  IconButton(
                    tooltip: '移动画布内容',
                    onPressed: () => setState(() {
                      _objectMode = true;
                      _move = false;
                      _eraser = false;
                    }),
                    icon: Icon(
                      Icons.open_with,
                      color: _objectMode
                          ? Theme.of(context).colorScheme.primary
                          : null,
                    ),
                  ),
                ],
                IconButton(
                  tooltip: '复位画布',
                  onPressed: () =>
                      setState(() => _transform.value = Matrix4.identity()),
                  icon: const Icon(Icons.center_focus_strong),
                ),
                for (final color in [
                  const Color(0xff244d7a),
                  const Color(0xffcc4b44),
                  const Color(0xff286b4f),
                ])
                  IconButton(
                    tooltip: '选择画笔颜色',
                    onPressed: () => setState(() {
                      _color = color;
                      _move = false;
                      _eraser = false;
                      _objectMode = false;
                    }),
                    icon: Icon(
                      _color == color
                          ? Icons.radio_button_checked
                          : Icons.circle,
                      color: color,
                    ),
                  ),
                PopupMenuButton<double>(
                  tooltip: '画笔粗细',
                  onSelected: (value) => setState(() => _width = value),
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 2, child: Text('细笔')),
                    PopupMenuItem(value: 4, child: Text('中笔')),
                    PopupMenuItem(value: 8, child: Text('粗笔')),
                  ],
                  icon: const Icon(Icons.line_weight),
                ),
              ],
            ),
          ),
          Expanded(
            child: InteractiveViewer(
              transformationController: _transform,
              minScale: 1,
              maxScale: 4,
              panEnabled: _move,
              scaleEnabled: _move,
              child: Center(
                child: AspectRatio(
                  aspectRatio: 0.8,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final size = Size(
                        constraints.maxWidth,
                        constraints.maxHeight,
                      );
                      return GestureDetector(
                        key: const ValueKey('note-canvas'),
                        behavior: HitTestBehavior.opaque,
                        onPanStart: _move || _objectMode
                            ? null
                            : (details) => setState(() {
                                _remember();
                                if (!_eraser) {
                                  _current = <List<double>>[];
                                  _strokes.add({
                                    'color': _color.toARGB32(),
                                    'width': _width,
                                    'points': _current,
                                  });
                                }
                                _point(details.localPosition, size);
                              }),
                        onPanUpdate: _move || _objectMode
                            ? null
                            : (details) => setState(
                                () => _point(details.localPosition, size),
                              ),
                        onPanEnd: _move || _objectMode
                            ? null
                            : (_) {
                                _current = null;
                                _persist();
                              },
                        onPanCancel: _move || _objectMode
                            ? null
                            : () {
                                _current = null;
                                _persist();
                              },
                        child: ColoredBox(
                          color: Colors.white,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              if (widget.image != null)
                                Image.memory(
                                  widget.image!,
                                  fit: BoxFit.contain,
                                  cacheWidth:
                                      (size.width *
                                              MediaQuery.devicePixelRatioOf(
                                                context,
                                              ))
                                          .round()
                                          .clamp(1, 2048),
                                ),
                              for (var i = 0; i < _items.length; i++)
                                _itemWidget(i, size),
                              IgnorePointer(
                                child: CustomPaint(
                                  painter: _StrokePainter(_strokes),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(
              _error ??
                  (_saving
                      ? '正在保存…'
                      : _objectMode
                      ? '拖动内容移动，选中后可调整大小或移除。'
                      : '切换到移动和缩放后可双指缩放；橡皮按整条笔迹擦除。'),
            ),
          ),
        ],
      ),
    ),
  );
}

class _CanvasTextDialog extends StatefulWidget {
  const _CanvasTextDialog({required this.existing, required this.isNew});
  final String existing;
  final bool isNew;

  @override
  State<_CanvasTextDialog> createState() => _CanvasTextDialogState();
}

/// Compact read-only view of the same editable canvas contents.
class StudyNoteCanvasPreview extends StatelessWidget {
  const StudyNoteCanvasPreview({
    super.key,
    required this.strokes,
    required this.items,
    required this.readAttachment,
  });
  final List<dynamic> strokes;
  final List<dynamic> items;
  final Future<Uint8List> Function(String id) readAttachment;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 200,
    child: Center(
      child: AspectRatio(
        aspectRatio: 0.8,
        child: ColoredBox(
          color: Colors.white,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final size = Size(constraints.maxWidth, constraints.maxHeight);
              return Stack(
                clipBehavior: Clip.hardEdge,
                children: [
                  for (final raw in items)
                    if (raw is Map)
                      Positioned(
                        left: (raw['x'] as num).toDouble() * size.width,
                        top: (raw['y'] as num).toDouble() * size.height,
                        width: (raw['width'] as num).toDouble() * size.width,
                        height: (raw['height'] as num).toDouble() * size.height,
                        child: raw['type'] == 'text'
                            ? Text(
                                raw['text'] as String,
                                overflow: TextOverflow.clip,
                                style: const TextStyle(
                                  color: Colors.black87,
                                  fontSize: 10,
                                ),
                              )
                            : FutureBuilder<Uint8List>(
                                future: readAttachment(
                                  raw['attachmentId'] as String,
                                ),
                                builder: (context, snapshot) => snapshot.hasData
                                    ? Image.memory(
                                        snapshot.data!,
                                        fit: BoxFit.contain,
                                        errorBuilder: (_, _, _) =>
                                            const SizedBox(),
                                      )
                                    : const SizedBox(),
                              ),
                      ),
                  Positioned.fill(
                    child: CustomPaint(painter: _StrokePainter(strokes)),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    ),
  );
}

class _CanvasTextDialogState extends State<_CanvasTextDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.existing);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.isNew ? '添加文字' : '编辑文字'),
    content: TextField(
      key: const ValueKey('canvas-text-input'),
      controller: _controller,
      autofocus: true,
      minLines: 2,
      maxLines: 6,
      decoration: const InputDecoration(hintText: '输入画布文字'),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      TextButton(
        onPressed: () => Navigator.pop(context, _controller.text),
        child: Text(widget.isNew ? '添加' : '保存'),
      ),
    ],
  );
}

class _StrokePainter extends CustomPainter {
  _StrokePainter(this.strokes);
  final List<dynamic> strokes;
  @override
  void paint(Canvas canvas, Size size) {
    for (final stroke in strokes) {
      if (stroke is! Map ||
          stroke['points'] is! List ||
          stroke['color'] is! int) {
        continue;
      }
      final points = (stroke['points'] as List)
          .whereType<List>()
          .where((p) => p.length == 2 && p[0] is num && p[1] is num)
          .map(
            (p) => Offset(
              (p[0] as num).toDouble() * size.width,
              (p[1] as num).toDouble() * size.height,
            ),
          )
          .toList();
      if (points.isEmpty) continue;
      final paint = Paint()
        ..color = Color(stroke['color'] as int)
        ..strokeWidth = (stroke['width'] as num?)?.toDouble() ?? 2.5
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;
      if (points.length == 1) {
        canvas.drawPoints(PointMode.points, points, paint);
        continue;
      }
      final path = Path()..moveTo(points.first.dx, points.first.dy);
      for (final point in points.skip(1)) {
        path.lineTo(point.dx, point.dy);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _StrokePainter oldDelegate) => true;
}
