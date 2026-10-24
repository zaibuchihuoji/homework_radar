import 'package:flutter/material.dart';

/// Rotates only the glyph, retaining the surrounding button/theme decoration.
class ActivityIcon extends StatefulWidget {
  const ActivityIcon(
    this.icon, {
    super.key,
    this.active = false,
    this.size,
    this.color,
  });

  final IconData icon;
  final bool active;
  final double? size;
  final Color? color;

  @override
  State<ActivityIcon> createState() => _ActivityIconState();
}

class _ActivityIconState extends State<ActivityIcon>
    with SingleTickerProviderStateMixin {
  late final _turns = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1000),
  );
  bool _motionAllowed = true;

  void _syncAnimation() {
    if (widget.active && _motionAllowed) {
      if (!_turns.isAnimating) _turns.repeat();
    } else {
      _turns.reset();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _motionAllowed =
        !MediaQuery.disableAnimationsOf(context) &&
        TickerMode.valuesOf(context).enabled;
    _syncAnimation();
  }

  @override
  void didUpdateWidget(covariant ActivityIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncAnimation();
  }

  @override
  void dispose() {
    _turns.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final icon = RotationTransition(
      turns: _turns,
      child: Icon(widget.icon, size: widget.size, color: widget.color),
    );
    return widget.active ? RepaintBoundary(child: icon) : icon;
  }
}
