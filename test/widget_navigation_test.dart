import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:homework_radar/services/widget_navigation.dart';

void main() {
  test(
    'round trips exact IDs without interpreting special characters as a route',
    () {
      final uri = Uri(
        scheme: 'homework-radar',
        host: 'widget',
        path: '/homework',
        queryParameters: {'id': '自定义 / & ? # 📚'},
      );
      final target = WidgetDestination.parse(uri);
      expect(target?.homeworkId, '自定义 / & ? # 📚');
      expect(target?.tab, 0);
    },
  );
  test('only known local destinations are accepted', () {
    for (final value in [
      'https://widget/homework?id=a',
      'homework-radar://other/timetable',
      'homework-radar://widget/account',
      'homework-radar://widget/homework?id=a&id=b',
    ]) {
      expect(WidgetDestination.parse(Uri.parse(value)), isNull, reason: value);
    }
    expect(
      WidgetDestination.parse(Uri.parse('homework-radar://widget/timetable'))
          ?.tab,
      1,
    );
    expect(
      WidgetDestination.parse(Uri.parse('homework-radar://widget/homework'))
          ?.homeworkId,
      isNull,
    );
  });
  test(
    'cold launch waits for the splash to finish and is consumed once',
    () async {
      final destinations = <WidgetDestination>[];
      final clicks = StreamController<Uri?>();
      final navigation = WidgetNavigation(onDestination: destinations.add);
      await navigation.bind(
        Future.value(Uri.parse('homework-radar://widget/homework?id=one')),
        clicks.stream,
      );
      expect(destinations, isEmpty);
      navigation.setReady();
      navigation.setReady();
      expect(destinations.map((d) => d.homeworkId), ['one']);
      await navigation.dispose();
      await clicks.close();
    },
  );
  test('warm click wins over a late cold-launch result', () async {
    final destinations = <WidgetDestination>[];
    final initial = Completer<Uri?>();
    final clicks = StreamController<Uri?>();
    final navigation = WidgetNavigation(onDestination: destinations.add)
      ..setReady();
    final bound = navigation.bind(initial.future, clicks.stream);
    clicks.add(Uri.parse('homework-radar://widget/timetable'));
    await Future<void>.delayed(Duration.zero);
    initial.complete(Uri.parse('homework-radar://widget/homework?id=stale'));
    await bound;
    expect(destinations.map((d) => d.tab), [1]);
    clicks.add(Uri.parse('homework-radar://widget/homework?id=next'));
    await Future<void>.delayed(Duration.zero);
    expect(destinations.last.homeworkId, 'next');
    await navigation.dispose();
    await clicks.close();
  });
  test(
    'disposing before the initial result prevents stale navigation',
    () async {
      final destinations = <WidgetDestination>[];
      final initial = Completer<Uri?>();
      final clicks = StreamController<Uri?>();
      final navigation = WidgetNavigation(onDestination: destinations.add)
        ..setReady();
      final bound = navigation.bind(initial.future, clicks.stream);
      await navigation.dispose();
      initial.complete(Uri.parse('homework-radar://widget/timetable'));
      await bound;
      expect(destinations, isEmpty);
      await clicks.close();
    },
  );
}
