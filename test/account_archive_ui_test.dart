import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:homework_radar/main.dart';
import 'package:homework_radar/models/homework.dart';
import 'package:homework_radar/pages/settings_page.dart';
import 'package:homework_radar/services/storage.dart';
import 'package:homework_radar/ui/tokens.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'account archives show old task read-only without changing active data',
    (tester) async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('homework_radar/platform'),
            (_) async => null,
          );
      SharedPreferences.setMockInitialValues({
        'account_archives': jsonEncode([
          {
            'id': 'old',
            'createdAt': '2026-10-15T12:00:00',
            'platform': 'mooc',
            'homework': [
              HomeworkItem(
                id: 'oldtask',
                platform: PlatformKind.mooc,
                course: 'old course',
                title: 'archived task',
              ).toJson(),
            ],
            'hiddenItems': {},
          },
        ]),
      });
      await Storage.init();
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(Brightness.light, ThemeStyle.clean),
          home: const AccountArchivesPage(),
        ),
      );
      await tester.tap(find.textContaining('mooc').first);
      await tester.pumpAndSettle();
      expect(find.text('archived task'), findsOneWidget);
      expect(find.text('恢复'), findsNothing);
      expect(Storage.homework(), isEmpty);
    },
  );
}
