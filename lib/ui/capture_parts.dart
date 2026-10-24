import 'package:flutter/material.dart';

import 'adaptive.dart';
import 'settings_parts.dart';

/// Shared presentation for capture and review; all actions stay in the pages.
class CaptureHeading extends StatelessWidget {
  const CaptureHeading({
    super.key,
    required this.step,
    required this.title,
    required this.description,
  });
  final String step, title, description;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 12, 4, 22),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: serifTitle(
            context,
            monoText(
              context,
              TextStyle(
                fontSize: 21,
                height: 1.35,
                fontWeight: FontWeight.w600,
                color: textPrimary(context),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        SettingsNote(description),
      ],
    ),
  );
}

class CaptureBottomBar extends StatelessWidget {
  const CaptureBottomBar({
    super.key,
    required this.label,
    required this.child,
    this.busy = false,
  });
  final String label;
  final Widget child;
  final bool busy;
  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: cardColor(context),
      border: Border(top: BorderSide(color: dividerColor(context), width: .5)),
    ),
    child: SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (busy) ...[
              const LinearProgressIndicator(minHeight: 2),
              const SizedBox(height: 8),
            ],
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11.5,
                height: 1.4,
                color: textSecondary(context),
              ),
            ),
            const SizedBox(height: 8),
            child,
          ],
        ),
      ),
    ),
  );
}
