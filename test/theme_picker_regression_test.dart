import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homework_radar/main.dart' show buildTheme;
import 'package:homework_radar/ui/tokens.dart';

void main() {
  for (final style in ThemeStyle.values) {
    testWidgets('${style.name}: picker selection, input and cancellation', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      DateTime? date;
      TimeOfDay? time;
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(Brightness.light, style),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.3)),
            child: child!,
          ),
          home: Builder(
            builder: (context) => Scaffold(
              body: Column(
                children: [
                  TextButton(
                    onPressed: () async {
                      date = await showDatePicker(
                        context: context,
                        initialDate: DateTime(2026, 10, 17),
                        firstDate: DateTime(2026),
                        lastDate: DateTime(2027),
                      );
                    },
                    child: const Text('date'),
                  ),
                  TextButton(
                    onPressed: () async {
                      time = await showTimePicker(
                        context: context,
                        initialTime: const TimeOfDay(hour: 9, minute: 30),
                        initialEntryMode: TimePickerEntryMode.input,
                      );
                    },
                    child: const Text('time'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('date'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('18'));
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(date, DateTime(2026, 10, 18));
      await tester.tap(find.text('date'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(date, isNull);
      await tester.tap(find.text('time'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).at(0), '10');
      await tester.enterText(find.byType(TextField).at(1), '25');
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(time, const TimeOfDay(hour: 10, minute: 25));
      await tester.tap(find.text('time'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(time, isNull);
      expect(tester.takeException(), isNull);
    });
  }
}
