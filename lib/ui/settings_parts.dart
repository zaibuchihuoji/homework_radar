import 'package:flutter/material.dart';

import 'adaptive.dart';
import 'activity_icon.dart';
import 'dashed_line.dart';
import 'ink_wash.dart';
import 'style_background.dart';
import 'theme_forms.dart';
import 'theme_page_parts.dart';
import 'tokens.dart';
import 'focus_parts.dart';

/// Settings presentation only. Persistence and actions stay in their pages.
class SettingsScaffold extends StatelessWidget {
  const SettingsScaffold({
    super.key,
    required this.title,
    required this.body,
    this.actions,
    this.bottomNavigationBar,
    this.root = false,
  });

  final String title;
  final Widget body;
  final List<Widget>? actions;
  final Widget? bottomNavigationBar;
  final bool root;

  @override
  Widget build(BuildContext context) => StyleBackground(
    child: Scaffold(
      backgroundColor: scaffoldBgOf(context),
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        backgroundColor: scaffoldBgOf(context),
        titleSpacing: root ? 20 : null,
        toolbarHeight: root ? 68 : 60,
        title: DefaultTextStyle.merge(
          style: TextStyle(
            fontSize: root ? 22 : 19,
            fontWeight: FontWeight.w600,
            color: textPrimary(context),
          ),
          child: paletteOf(context).clean
              ? Text(title)
              : appBarTitle(context, title, root: root),
        ),
        actions: actions,
      ),
      body: body,
      bottomNavigationBar: bottomNavigationBar,
    ),
  );
}

class SettingsList extends StatelessWidget {
  const SettingsList({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
    children: children,
  );
}

class SettingsSection extends StatelessWidget {
  const SettingsSection({
    super.key,
    required this.children,
    this.title,
    this.footer,
  });
  final String? title, footer;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null) FocusSectionTitle(title!),
          content,
          if (footer != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: SettingsNote(footer!),
            ),
        ],
      ),
    );
  }
}

class SettingsDivider extends StatelessWidget {
  const SettingsDivider({super.key, this.indent = 54});
  final double indent;
  @override
  Widget build(BuildContext context) {
    if (isInkStyle(context)) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: BrushLine(color: dividerColor(context)),
      );
    }
    if (isPaperStyle(context) ||
        isReceiptStyle(context) ||
        isJournalStyle(context) ||
        isTerminalStyle(context)) {
      return Padding(
        padding: EdgeInsets.only(left: indent, right: 16),
        child: DashedLine(color: dividerColor(context)),
      );
    }
    return Divider(
      height: 1,
      thickness: .5,
      indent: indent,
      endIndent: 16,
      color: dividerColor(context),
    );
  }
}

class SettingsRow extends StatelessWidget {
  const SettingsRow({
    super.key,
    required this.title,
    this.icon,
    this.subtitle,
    this.value,
    this.trailing,
    this.onTap,
    this.onLongPress,
    this.navigation = false,
    this.iconSpinning = false,
  });

  final String title;
  final IconData? icon;
  final String? subtitle, value;
  final Widget? trailing;
  final VoidCallback? onTap, onLongPress;
  final bool navigation;
  final bool iconSpinning;

  @override
  Widget build(BuildContext context) {
    final p = paletteOf(context);
    final largeText = MediaQuery.textScalerOf(context).scale(14) > 18;
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 64),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 15),
          child: Row(
            children: [
              if (icon != null) ...[
                SizedBox(
                  width: 26,
                  child: p.clean
                      ? ActivityIcon(
                          icon!,
                          active: iconSpinning,
                          size: 21,
                          color: textSecondary(context),
                        )
                      : FittedBox(
                          fit: BoxFit.scaleDown,
                          child: ThemePreferenceIcon(
                            icon: icon!,
                            spinning: iconSpinning,
                          ),
                        ),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
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
                            fontSize: 15.5,
                            height: 1.35,
                            fontWeight: FontWeight.w500,
                            color: textPrimary(context),
                          ),
                        ),
                      ),
                    ),
                    if (subtitle != null || (largeText && value != null)) ...[
                      const SizedBox(height: 5),
                      Text(
                        subtitle == null
                            ? value!
                            : '$subtitle${largeText && value != null ? ' · $value' : ''}',
                        style: TextStyle(
                          fontSize: 12.5,
                          height: 1.5,
                          color: textSecondary(context),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (value != null && !largeText) ...[
                const SizedBox(width: 10),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.sizeOf(context).width * .25,
                  ),
                  child: Text(
                    value!,
                    textAlign: TextAlign.end,
                    style: TextStyle(
                      fontSize: 13,
                      color: textSecondary(context),
                    ),
                  ),
                ),
              ],
              if (trailing != null) ...[
                const SizedBox(width: 10),
                trailing!,
              ] else if (navigation) ...[
                const SizedBox(width: 8),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 19,
                  color: textFaint(context),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class SettingsSwitchRow extends StatelessWidget {
  const SettingsSwitchRow({
    super.key,
    required this.title,
    required this.value,
    required this.onChanged,
    this.icon,
    this.subtitle,
  });
  final String title;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final IconData? icon;
  final String? subtitle;

  @override
  Widget build(BuildContext context) => SettingsRow(
    title: title,
    subtitle: subtitle,
    icon: icon,
    onTap: onChanged == null ? null : () => onChanged!(!value),
    trailing: Semantics(
      label: title,
      toggled: value,
      onTap: onChanged == null ? null : () => onChanged!(!value),
      child: ExcludeSemantics(
        child: SizedBox(
          width: isTerminalStyle(context) ? 72 : 48,
          child: paletteOf(context).clean
              ? Switch.adaptive(value: value, onChanged: onChanged)
              : IgnorePointer(
                  ignoring: onChanged == null,
                  child: Opacity(
                    opacity: onChanged == null ? .45 : 1,
                    child: ThemePreferenceToggle(
                      value: value,
                      onChanged: onChanged ?? (_) {},
                    ),
                  ),
                ),
        ),
      ),
    ),
  );
}

class SettingsNote extends StatelessWidget {
  const SettingsNote(this.text, {super.key, this.warning = false});
  final String text;
  final bool warning;
  @override
  Widget build(BuildContext context) => Text(
    text,
    style: TextStyle(
      fontSize: 12.5,
      height: 1.65,
      color: warning
          ? Theme.of(context).colorScheme.error
          : textSecondary(context),
    ),
  );
}

class SettingsAlertDialog extends StatelessWidget {
  const SettingsAlertDialog({
    super.key,
    this.title,
    this.content,
    this.actions,
    this.scrollable = true,
  });
  final Widget? title, content;
  final List<Widget>? actions;
  final bool scrollable;
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: title == null
        ? null
        : DefaultTextStyle.merge(
            style: serifTitle(
              context,
              monoText(
                context,
                const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  height: 1.4,
                ),
              ),
            ),
            child: title!,
          ),
    content: content == null
        ? null
        : DefaultTextStyle.merge(
            style: TextStyle(
              fontSize: 14,
              height: 1.6,
              color: textSecondary(context),
            ),
            child: content!,
          ),
    actions: actions,
    scrollable: scrollable,
    backgroundColor: modalColor(context),
    surfaceTintColor: Colors.transparent,
    shape: paletteOf(context).clean
        ? RoundedRectangleBorder(borderRadius: BorderRadius.circular(22))
        : themeModalShape(paletteOf(context)),
    insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
    titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 4),
    contentPadding: const EdgeInsets.fromLTRB(24, 14, 24, 20),
    actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
  );
}

class SettingsDialog extends StatelessWidget {
  const SettingsDialog({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette =
        theme.extension<StylePalette>() ??
        stylePalette(ThemeStyle.clean, theme.brightness);
    return ThemedDialog(
      backgroundColor: palette.modal,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: child,
    );
  }
}
