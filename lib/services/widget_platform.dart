import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:home_widget/home_widget.dart';

/// Platform glue for the existing presentation cache; never touches business data.
class WidgetPlatform {
  static const _channel = MethodChannel('homework_radar/widgets');
  static final _clicks = StreamController<Uri?>.broadcast();
  static bool _available = true;
  static bool get _ios =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  static Future<void> initialize() async {
    if (!_ios) return;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'openURL' && call.arguments is String) {
        _clicks.add(Uri.tryParse(call.arguments as String));
      }
    });
    try {
      final group = await _channel.invokeMapMethod<String, dynamic>('group');
      final id = group?['groupId'] as String?;
      _available = group?['available'] == true;
      if (id != null) await HomeWidget.setAppGroupId(id);
    } catch (_) {
      _available = false;
    }
  }

  static Future<bool?> refresh({required String androidName}) async {
    if (!_ios) return HomeWidget.updateWidget(androidName: androidName);
    await initialize();
    if (!_available) return false;
    if (await _channel.invokeMethod<bool>('prepareAssets') != true) {
      return false;
    }
    return HomeWidget.updateWidget(
      iOSName: androidName == 'TimetableWidgetProvider'
          ? 'TimetableWidget'
          : 'HomeworkWidget',
    );
  }

  static Future<Uri?> get initialUrl async {
    if (!_ios) return HomeWidget.initiallyLaunchedFromHomeWidget();
    final value = await _channel.invokeMethod<String>('initialUrl');
    return value == null ? null : Uri.tryParse(value);
  }

  static Stream<Uri?> get clicks =>
      _ios ? _clicks.stream : HomeWidget.widgetClicked;
}
