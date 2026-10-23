/// Presentation-only snapshot. Business records and transparent/photo settings
/// are deliberately outside this channel.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:home_widget/home_widget.dart';

import 'widget_platform.dart';

import '../ui/tokens.dart';

Map<String, Object> widgetThemeSnapshot(ThemeStyle style, ThemeMode mode) {
  Map<String, int> colors(Brightness brightness) {
    // Match buildTheme: only the two clean themes support dark mode.
    final p = stylePalette(
      style,
      style == ThemeStyle.clean || style == ThemeStyle.green
          ? brightness
          : Brightness.light,
    );
    return {
      'surface': p.bg.toARGB32(),
      'card': p.card.toARGB32(),
      'border': p.cardBorder.toARGB32(),
      'ink': p.ink.toARGB32(),
      'secondary': p.ink2.toARGB32(),
      'accent': p.accent.toARGB32(),
      'focus': p.accentFill.toARGB32(),
      'onFocus': p.onAccent.toARGB32(),
    };
  }

  return {
    'version': 1,
    'style': style.name,
    'mode': mode.name,
    'light': colors(Brightness.light),
    'dark': colors(Brightness.dark),
  };
}

class WidgetTheme {
  WidgetTheme._();
  static Future<void> _writes = Future<void>.value();
  static String? _published;

  static Future<void> push(ThemeStyle style, ThemeMode mode) {
    final json = jsonEncode(widgetThemeSnapshot(style, mode));
    final next = _writes.then((_) async {
      if (_published == json) return;
      try {
        await WidgetPlatform.initialize();
        final saved = await HomeWidget.saveWidgetData<String>(
          'widget_theme',
          json,
        );
        if (saved != true) return;
        if (await WidgetPlatform.refresh(
              androidName: 'HomeworkWidgetProvider',
            ) ==
            false) {
          return;
        }
        await WidgetPlatform.refresh(androidName: 'TimetableWidgetProvider');
        _published = json;
      } catch (_) {
        // Retry on the next appearance/lifecycle event; never block app use.
      }
    });
    _writes = next;
    return next;
  }
}
