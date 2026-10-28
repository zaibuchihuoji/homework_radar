import 'dart:convert';
import 'dart:ui' show PointMode;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Keep ink visible in dark themes without changing the saved pen color.
Color studyNoteInkColor(Color color, {required bool darkBackground}) {
  if (!darkBackground || color.computeLuminance() >= 0.3) return color;
  final hsl = HSLColor.fromColor(color);
  return hsl
      .withLightness(hsl.lightness < 0.68 ? 0.68 : hsl.lightness)
      .toColor();
}

/// A transparent, editable ink layer. Strokes remain separate from the text
/// and original image so neither is flattened or overwritten.
class StudyNoteInkLayer extends StatefulWidget {
  const StudyNoteInkLayer({
    super.key,
    required this.child,
    required this.strokes,
    required this.enabled,
    required this.eraser,
    required this.color,
    required this.width,
    required this.onChanged,
    this.text,
    this.textStyle,
    this.textSpan,
    this.darkBackground = false,
  });

  final Widget child;
  final List<dynamic> strokes;
  final bool enabled;
  final bool eraser;
  final Color color;
  final double width;
  final ValueChanged<List<dynamic>> onChanged;
  final String? text;
  final TextStyle? textStyle;
  final TextSpan? textSpan;
  final bool darkBackground;

  @override
  State<StudyNoteInkLayer> createState() => _StudyNoteInkLayerState();
}

class _StudyNoteInkLayerState extends State<StudyNoteInkLayer> {
  final _key = GlobalKey();
  List<dynamic>? _working;
  List<dynamic>? _points;
  Size? _size;

  List<dynamic> _copy(List<dynamic> value) =>
      jsonDecode(jsonEncode(value)) as List;

  Offset _normalized(Offset point, Size size) => Offset(
    (point.dx / size.width).clamp(0.0, 1.0),
    (point.dy / size.height).clamp(0.0, 1.0),
  );

  void _point(Offset point) {
    final size = _size;
    if (size == null || size.width <= 0 || size.height <= 0) return;
    final normalized = _normalized(point, size);
    if (widget.eraser) {
      final painter = widget.text != null && widget.textStyle != null
          ? _textPainter(
              context,
              widget.text!,
              widget.textStyle!,
              size.width,
              span: widget.textSpan,
            )
          : null;
      _working?.removeWhere((raw) {
        if (raw is! Map || raw['points'] is! List) return false;
        final points = _strokePoints(raw, size, painter, widget.text?.length);
        if (points.any((p) => (p - point).distance < 20)) return true;
        for (var i = 1; i < points.length; i++) {
          final segment = points[i] - points[i - 1];
          final lengthSquared =
              segment.dx * segment.dx + segment.dy * segment.dy;
          if (lengthSquared == 0) continue;
          final relative = point - points[i - 1];
          final t =
              ((relative.dx * segment.dx + relative.dy * segment.dy) /
                      lengthSquared)
                  .clamp(0.0, 1.0);
          if ((points[i - 1] + segment * t - point).distance < 20) return true;
        }
        return false;
      });
      painter?.dispose();
    } else {
      _points?.add([normalized.dx, normalized.dy]);
    }
  }

  void _start(Offset position) {
    final box = _key.currentContext?.findRenderObject();
    if (box is! RenderBox || box.size.isEmpty) return;
    _size = box.size;
    _working = _copy(widget.strokes);
    if (!widget.eraser) {
      _points = <dynamic>[];
      final stroke = <String, dynamic>{
        'color': widget.color.toARGB32(),
        'width': widget.width,
        'points': _points,
      };
      if (widget.text != null && widget.textStyle != null) {
        final painter = _textPainter(
          context,
          widget.text!,
          widget.textStyle!,
          box.size.width,
          span: widget.textSpan,
        );
        final anchor = painter.getPositionForOffset(position).offset;
        final anchorPoint = painter.getOffsetForCaret(
          TextPosition(offset: anchor),
          Rect.zero,
        );
        painter.dispose();
        stroke.addAll({
          'anchor': anchor,
          'anchorX': (anchorPoint.dx / box.size.width).clamp(0.0, 1.0),
          'anchorY': (anchorPoint.dy / box.size.height).clamp(0.0, 1.0),
          'basisWidth': box.size.width,
          'basisHeight': box.size.height,
        });
      }
      _working!.add(stroke);
    }
    _point(position);
    setState(() {});
  }

  void _finish() {
    final working = _working;
    _working = null;
    _points = null;
    if (working != null) widget.onChanged(working);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      widget.child,
      Positioned.fill(
        child: IgnorePointer(
          child: CustomPaint(
            painter: _InkPainter(
              strokes: _working ?? widget.strokes,
              text: widget.text,
              textStyle: widget.textStyle,
              textSpan: widget.textSpan,
              darkBackground: widget.darkBackground,
              direction: Directionality.of(context),
              scaler: MediaQuery.textScalerOf(context),
            ),
          ),
        ),
      ),
      if (widget.enabled)
        Positioned.fill(
          child: GestureDetector(
            key: _key,
            behavior: HitTestBehavior.opaque,
            dragStartBehavior: DragStartBehavior.down,
            onPanStart: (details) => _start(details.localPosition),
            onPanUpdate: (details) =>
                setState(() => _point(details.localPosition)),
            onPanEnd: (_) => _finish(),
            onPanCancel: _finish,
            onTapUp: (details) {
              _start(details.localPosition);
              _finish();
            },
          ),
        ),
    ],
  );
}

TextPainter _textPainter(
  BuildContext context,
  String text,
  TextStyle style,
  double width, {
  TextSpan? span,
}) => TextPainter(
  text: span ?? TextSpan(text: text, style: style),
  textDirection: Directionality.of(context),
  textScaler: MediaQuery.textScalerOf(context),
)..layout(maxWidth: width);

List<Offset> _strokePoints(
  Map stroke,
  Size size,
  TextPainter? painter,
  int? textLength,
) {
  final anchor = stroke['anchor'];
  final basisWidth = stroke['basisWidth'];
  final basisHeight = stroke['basisHeight'];
  final anchorX = stroke['anchorX'];
  final anchorY = stroke['anchorY'];
  Offset? currentAnchor;
  if (painter != null &&
      textLength != null &&
      anchor is int &&
      basisWidth is num &&
      basisHeight is num &&
      anchorX is num &&
      anchorY is num) {
    currentAnchor = painter.getOffsetForCaret(
      TextPosition(offset: anchor.clamp(0, textLength)),
      Rect.zero,
    );
  }
  final points = <Offset>[];
  for (final raw in stroke['points'] as List? ?? []) {
    if (raw is! List || raw.length != 2 || raw[0] is! num || raw[1] is! num) {
      continue;
    }
    if (currentAnchor != null) {
      points.add(
        currentAnchor +
            Offset(
              (((raw[0] as num) - anchorX) * basisWidth).toDouble(),
              (((raw[1] as num) - anchorY) * basisHeight).toDouble(),
            ),
      );
    } else {
      points.add(
        Offset((raw[0] as num) * size.width, (raw[1] as num) * size.height),
      );
    }
  }
  return points;
}

class _InkPainter extends CustomPainter {
  _InkPainter({
    required this.strokes,
    required this.text,
    required this.textStyle,
    required this.textSpan,
    required this.darkBackground,
    required this.direction,
    required this.scaler,
  });
  final List<dynamic> strokes;
  final String? text;
  final TextStyle? textStyle;
  final TextSpan? textSpan;
  final bool darkBackground;
  final TextDirection direction;
  final TextScaler scaler;

  @override
  void paint(Canvas canvas, Size size) {
    TextPainter? textPainter;
    if (text != null && textStyle != null && size.width > 0) {
      textPainter = TextPainter(
        text: textSpan ?? TextSpan(text: text, style: textStyle),
        textDirection: direction,
        textScaler: scaler,
      )..layout(maxWidth: size.width);
    }
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    for (final stroke in strokes) {
      if (stroke is! Map ||
          stroke['points'] is! List ||
          stroke['color'] is! int) {
        continue;
      }
      final points = _strokePoints(stroke, size, textPainter, text?.length);
      if (points.isEmpty) continue;
      final paint = Paint()
        ..color = studyNoteInkColor(
          Color(stroke['color'] as int),
          darkBackground: darkBackground,
        )
        ..strokeWidth = (stroke['width'] as num?)?.toDouble() ?? 2.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;
      if (points.length == 1) {
        canvas.drawPoints(PointMode.points, points, paint);
      } else {
        final path = Path()..moveTo(points.first.dx, points.first.dy);
        for (final point in points.skip(1)) {
          path.lineTo(point.dx, point.dy);
        }
        canvas.drawPath(path, paint);
      }
    }
    textPainter?.dispose();
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _InkPainter oldDelegate) => true;
}
