import 'dart:convert';
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
    this.startInMoveMode = false,
    this.imageAlignment = Alignment.center,
    this.imageSize,
  });
  final Uint8List? image;
  final List<dynamic> strokes;
  final Future<bool> Function(List<dynamic>) onChanged;
  final List<dynamic> items;
  final Future<bool> Function(List<dynamic> strokes, List<dynamic> items)?
  onCanvasChanged;
  final Future<String> Function(Uint8List bytes)? saveAttachment;
  final Future<Uint8List> Function(String id)? readAttachment;
  final bool startInMoveMode;
  final AlignmentGeometry imageAlignment;
  final Size? imageSize;
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
    _move = widget.startInMoveMode;
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
        final points = <Offset>[];
        for (final point in stroke['points'] as List) {
          if (point is! List ||
              point.length != 2 ||
              point[0] is! num ||
              point[1] is! num) {
            continue;
          }
          points.add(
            Offset(
              (point[0] as num).toDouble() * size.width,
              (point[1] as num).toDouble() * size.height,
            ),
          );
        }
        if (points.any((point) => (point - position).distance < 18)) {
          return true;
        }
        for (var i = 1; i < points.length; i++) {
          final segment = points[i] - points[i - 1];
          final lengthSquared =
              segment.dx * segment.dx + segment.dy * segment.dy;
          if (lengthSquared == 0) continue;
          final relative = position - points[i - 1];
          final t =
              ((relative.dx * segment.dx + relative.dy * segment.dy) /
                      lengthSquared)
                  .clamp(0.0, 1.0);
          if ((points[i - 1] + segment * t - position).distance < 18) {
            return true;
          }
        }
        return false;
      });
    } else {
      _current?.add([x, y]);
    }
  }

  void _startStroke(Offset position, Size size) {
    _remember();
    if (!_eraser) {
      _current = <List<double>>[];
      _strokes.add({
        'color': _color.toARGB32(),
        'width': _width,
        'points': _current,
      });
    }
    _point(position, size);
  }

  void _finishStroke() {
    _current = null;
    _persist();
  }

  Widget _modeButton({
    required String label,
    required String tooltip,
    required IconData icon,
    required bool active,
    required VoidCallback? onPressed,
  }) => Expanded(
    child: Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 20,
                color: onPressed == null
                    ? Theme.of(context).disabledColor
                    : active
                    ? Theme.of(context).colorScheme.primary
                    : null,
              ),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  color: onPressed == null
                      ? Theme.of(context).disabledColor
                      : null,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

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
            if (_selectedId == id && item['type'] == 'text') {
              _editText(index);
            } else {
              setState(() => _selectedId = id);
            }
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
      resizeToAvoidBottomInset: false,
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
          Row(
            children: [
              _modeButton(
                label: '画笔',
                tooltip: '画笔',
                icon: Icons.edit,
                active: !_move && !_eraser && !_objectMode,
                onPressed: () => setState(() {
                  _move = false;
                  _eraser = false;
                  _objectMode = false;
                }),
              ),
              _modeButton(
                label: '橡皮',
                tooltip: '橡皮',
                icon: Icons.auto_fix_normal,
                active: _eraser,
                onPressed: () => setState(() {
                  _move = false;
                  _eraser = true;
                  _objectMode = false;
                }),
              ),
              _modeButton(
                label: '缩放',
                tooltip: '移动和缩放',
                icon: Icons.zoom_in,
                active: _move,
                onPressed: () => setState(() {
                  _move = true;
                  _eraser = false;
                  _objectMode = false;
                }),
              ),
              IconButton(
                tooltip: '撤销',
                onPressed: _undo.isEmpty ? null : () => _restore(_undo, _redo),
                icon: const Icon(Icons.undo),
              ),
              IconButton(
                tooltip: '重做',
                onPressed: _redo.isEmpty ? null : () => _restore(_redo, _undo),
                icon: const Icon(Icons.redo),
              ),
              PopupMenuButton<String>(
                tooltip: '画笔设置',
                onSelected: (value) => setState(() {
                  switch (value) {
                    case 'blue':
                      _color = const Color(0xff244d7a);
                    case 'red':
                      _color = const Color(0xffcc4b44);
                    case 'green':
                      _color = const Color(0xff286b4f);
                    case 'thin':
                      _width = 2;
                    case 'medium':
                      _width = 4;
                    case 'thick':
                      _width = 8;
                    case 'reset':
                      _transform.value = Matrix4.identity();
                  }
                  if (const {'blue', 'red', 'green'}.contains(value)) {
                    _move = false;
                    _eraser = false;
                    _objectMode = false;
                  }
                }),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'blue', child: Text('蓝色画笔')),
                  PopupMenuItem(value: 'red', child: Text('红色画笔')),
                  PopupMenuItem(value: 'green', child: Text('绿色画笔')),
                  PopupMenuDivider(),
                  PopupMenuItem(value: 'thin', child: Text('细笔')),
                  PopupMenuItem(value: 'medium', child: Text('中笔')),
                  PopupMenuItem(value: 'thick', child: Text('粗笔')),
                  PopupMenuDivider(),
                  PopupMenuItem(value: 'reset', child: Text('复位画布')),
                ],
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.palette_outlined, size: 20),
                      Text('设置', style: TextStyle(fontSize: 11)),
                    ],
                  ),
                ),
              ),
            ],
          ),
          if (widget.image == null && widget.onCanvasChanged != null)
            Row(
              children: [
                _modeButton(
                  label: '添加文字',
                  tooltip: '添加画布文字',
                  icon: Icons.text_fields,
                  active: false,
                  onPressed: () => _editText(),
                ),
                if (widget.saveAttachment != null)
                  _modeButton(
                    label: '添加图片',
                    tooltip: '添加画布图片',
                    icon: Icons.add_photo_alternate_outlined,
                    active: false,
                    onPressed: _addImages,
                  ),
                _modeButton(
                  label: '移动内容',
                  tooltip: '移动画布内容',
                  icon: Icons.open_with,
                  active: _objectMode,
                  onPressed: () => setState(() {
                    _objectMode = true;
                    _move = false;
                    _eraser = false;
                  }),
                ),
                _modeButton(
                  label: '删除',
                  tooltip: '删除画布内容',
                  icon: Icons.delete_outline,
                  active: false,
                  onPressed: _objectMode && _selectedId != null
                      ? () => _removeItem(_selectedId!)
                      : null,
                ),
              ],
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
                        dragStartBehavior: DragStartBehavior.down,
                        onPanStart: _move || _objectMode
                            ? null
                            : (details) => setState(() {
                                _startStroke(details.localPosition, size);
                              }),
                        onPanUpdate: _move || _objectMode
                            ? null
                            : (details) => setState(
                                () => _point(details.localPosition, size),
                              ),
                        onPanEnd: _move || _objectMode
                            ? null
                            : (_) => _finishStroke(),
                        onPanCancel: _move || _objectMode
                            ? null
                            : _finishStroke,
                        onTapUp: _move || _objectMode
                            ? null
                            : (details) {
                                setState(
                                  () =>
                                      _startStroke(details.localPosition, size),
                                );
                                _finishStroke();
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
                                  alignment: widget.imageAlignment,
                                  cacheWidth:
                                      widget.imageSize != null &&
                                          widget.imageSize!.width /
                                                  widget.imageSize!.height <
                                              0.8
                                      ? null
                                      : (size.width *
                                                MediaQuery.devicePixelRatioOf(
                                                  context,
                                                ) *
                                                2)
                                            .round()
                                            .clamp(1, 2048),
                                  cacheHeight:
                                      widget.imageSize != null &&
                                          widget.imageSize!.width /
                                                  widget.imageSize!.height <
                                              0.8
                                      ? (size.height *
                                                MediaQuery.devicePixelRatioOf(
                                                  context,
                                                ) *
                                                2)
                                            .round()
                                            .clamp(1, 2048)
                                      : null,
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
            // Reserve the height of all status messages so saving a stroke
            // cannot resize or move the canvas underneath the user's hand.
            child: IndexedStack(
              index: _error != null
                  ? 3
                  : _saving
                  ? 2
                  : _objectMode
                  ? 1
                  : 0,
              alignment: Alignment.centerLeft,
              children: [
                const Text('切换到移动和缩放后可双指缩放；橡皮按整条笔迹擦除。'),
                const Text('点选内容后可删除或拖动，再次点击文字可编辑。'),
                const Text('正在保存…'),
                Text(_error ?? '笔迹保存失败，请检查存储空间并重试。'),
              ],
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
