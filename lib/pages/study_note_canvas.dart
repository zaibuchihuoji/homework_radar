import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' show PointMode;

import 'package:flutter/material.dart';

import '../ui/settings_parts.dart';

/// Strokes use normalized coordinates so the original image is never modified.
class StudyNoteCanvas extends StatefulWidget {
  const StudyNoteCanvas({
    super.key,
    this.image,
    required this.strokes,
    required this.onChanged,
  });
  final Uint8List? image;
  final List<dynamic> strokes;
  final Future<bool> Function(List<dynamic>) onChanged;
  @override
  State<StudyNoteCanvas> createState() => _StudyNoteCanvasState();
}

class _StudyNoteCanvasState extends State<StudyNoteCanvas> {
  late List<dynamic> _strokes;
  final _undo = <String>[];
  final _transform = TransformationController();
  bool _move = false, _eraser = false;
  Color _color = const Color(0xff244d7a);
  List<List<double>>? _current;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _strokes = jsonDecode(jsonEncode(widget.strokes)) as List;
  }

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  void _remember() {
    _undo.add(jsonEncode(_strokes));
    if (_undo.length > 100) _undo.removeAt(0);
  }

  Future<bool> _persist() async {
    final copy = jsonDecode(jsonEncode(_strokes)) as List;
    if (mounted) {
      setState(() {
        _saving = true;
        _error = null;
      });
    }
    final success = await widget.onChanged(copy);
    if (mounted) {
      setState(() {
        _saving = false;
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

  @override
  Widget build(BuildContext context) => SettingsScaffold(
    title: widget.image == null ? '手写页' : '图片批注',
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
                }),
                icon: Icon(
                  Icons.edit,
                  color: !_move && !_eraser
                      ? Theme.of(context).colorScheme.primary
                      : null,
                ),
              ),
              IconButton(
                tooltip: '橡皮',
                onPressed: () => setState(() {
                  _move = false;
                  _eraser = true;
                }),
                icon: Icon(
                  Icons.auto_fix_normal,
                  color: _eraser ? Theme.of(context).colorScheme.primary : null,
                ),
              ),
              IconButton(
                tooltip: '移动和缩放',
                onPressed: () => setState(() => _move = true),
                icon: Icon(
                  Icons.zoom_in,
                  color: _move ? Theme.of(context).colorScheme.primary : null,
                ),
              ),
              IconButton(
                tooltip: '撤销',
                onPressed: _undo.isEmpty
                    ? null
                    : () {
                        setState(
                          () =>
                              _strokes = jsonDecode(_undo.removeLast()) as List,
                        );
                        _persist();
                      },
                icon: const Icon(Icons.undo),
              ),
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
                  }),
                  icon: Icon(
                    _color == color ? Icons.radio_button_checked : Icons.circle,
                    color: color,
                  ),
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
                      onPanStart: _move
                          ? null
                          : (details) => setState(() {
                              _remember();
                              if (!_eraser) {
                                _current = <List<double>>[];
                                _strokes.add({
                                  'color': _color.toARGB32(),
                                  'points': _current,
                                });
                              }
                              _point(details.localPosition, size);
                            }),
                      onPanUpdate: _move
                          ? null
                          : (details) => setState(
                              () => _point(details.localPosition, size),
                            ),
                      onPanEnd: _move
                          ? null
                          : (_) {
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
                            CustomPaint(painter: _StrokePainter(_strokes)),
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
            _error ?? (_saving ? '正在保存笔迹…' : '切换到移动和缩放后可双指缩放；橡皮按整条笔迹擦除。'),
          ),
        ),
      ],
    ),
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
        ..strokeWidth = 2.5
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
