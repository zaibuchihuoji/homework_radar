import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homework_radar/pages/splash_page.dart';

void main() {
  testWidgets('startup finishes after its original 1200ms hold', (
    tester,
  ) async {
    var finished = 0;
    await tester.pumpWidget(
      MaterialApp(home: SplashPage(onFinished: () => finished++)),
    );
    await tester.pump(const Duration(milliseconds: 1199));
    expect(finished, 0);
    await tester.pump(const Duration(milliseconds: 1));
    expect(finished, 1);
    await tester.pump(const Duration(seconds: 2));
    expect(finished, 1);
  });

  testWidgets('tap skips startup once without a second timer callback', (
    tester,
  ) async {
    var finished = 0;
    await tester.pumpWidget(
      MaterialApp(home: SplashPage(onFinished: () => finished++)),
    );
    await tester.tapAt(const Offset(20, 20));
    await tester.tapAt(const Offset(20, 20));
    expect(finished, 1);
    await tester.pump(const Duration(seconds: 2));
    expect(finished, 1);
  });

  testWidgets('disposed startup never triggers a delayed navigation', (
    tester,
  ) async {
    var finished = 0;
    await tester.pumpWidget(
      MaterialApp(home: SplashPage(onFinished: () => finished++)),
    );
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
    expect(finished, 0);
  });

  for (final brightness in Brightness.values) {
    testWidgets('yellow startup keeps dark system icons in $brightness', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: brightness),
          home: SplashPage(onFinished: () {}),
        ),
      );
      final region = tester.widget<AnnotatedRegion<SystemUiOverlayStyle>>(
        find
            .descendant(
              of: find.byType(SplashPage),
              matching: find.byType(AnnotatedRegion<SystemUiOverlayStyle>),
            )
            .first,
      );
      expect(region.value.statusBarIconBrightness, Brightness.dark);
      expect(region.value.systemNavigationBarIconBrightness, Brightness.dark);
      await tester.pump(const Duration(milliseconds: 1200));
      expect(tester.takeException(), isNull);
    });
  }
}
