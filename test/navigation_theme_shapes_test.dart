import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homework_radar/main.dart' show buildTheme;
import 'package:homework_radar/ui/themed_navigation.dart';
import 'package:homework_radar/ui/tokens.dart';

void main() {
  for (final style in ThemeStyle.values) {
    for (final brightness in Brightness.values) {
      for (final scale in [1.0, 1.6]) {
        testWidgets(
          '${style.name}/${brightness.name}/$scale: compact selection keeps every tab usable',
          (tester) async {
            tester.view.physicalSize = const Size(320, 740);
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.reset);
            var selected = 0;
            await tester.pumpWidget(
              MaterialApp(
                theme: buildTheme(brightness, style),
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!,
                ),
                home: StatefulBuilder(
                  builder: (context, setState) => Scaffold(
                    bottomNavigationBar: ThemedNavigationBar(
                      selectedIndex: selected,
                      onSelected: (i) => setState(() => selected = i),
                    ),
                  ),
                ),
              ),
            );
            for (var i = 0; i < ThemedNavigationBar.labels.length; i++) {
              await tester.tap(find.text(ThemedNavigationBar.labels[i]));
              await tester.pumpAndSettle();
              expect(selected, i);
              final icon = find.byIcon(ThemedNavigationBar.icons[i].$2);
              final indicator = find
                  .ancestor(of: icon, matching: find.byType(AnimatedContainer))
                  .first;
              final box = tester.getSize(indicator);
              expect(
                box.width / box.height,
                closeTo(1, .05),
                reason: 'selected surface must be full rather than flat',
              );
              final hit = find
                  .ancestor(of: icon, matching: find.byType(InkWell))
                  .first;
              expect(tester.getSize(hit).width, greaterThanOrEqualTo(48));
              expect(tester.getSize(hit).height, greaterThanOrEqualTo(48));
              expect(tester.takeException(), isNull);
            }
          },
        );
      }
    }
  }
}
