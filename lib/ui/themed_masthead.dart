import 'package:flutter/material.dart';

import 'tokens.dart';

/// The workbench header keeps identical geometry across themes.
class ThemedMasthead extends StatelessWidget {
  const ThemedMasthead({super.key, required this.dateLine});
  final String dateLine;
  @override
  Widget build(BuildContext context) {
    final p = paletteOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '作业通',
          style: TextStyle(
            fontSize: 22,
            fontWeight: p.comic ? FontWeight.w800 : FontWeight.w600,
            color: p.ink,
          ),
        ),
        const SizedBox(height: 3),
        Text(dateLine, style: TextStyle(fontSize: 12, color: p.ink2)),
      ],
    );
  }
}
