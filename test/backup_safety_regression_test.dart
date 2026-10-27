import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homework_radar/models/homework.dart';
import 'package:homework_radar/services/backup_service.dart';
import 'package:homework_radar/services/storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final original = HomeworkItem(
    id: 'manual_keep',
    platform: PlatformKind.manual,
    course: '数学',
    title: '保留的作业',
  );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Storage.init();
    await Storage.saveHomework([original]);
    await Storage.saveSemesterStart(DateTime(2026, 9, 1));
    await Storage.saveSectionTimes([
      for (var i = 0; i < 8; i++) (480 + 60 * i, 525 + 60 * i),
    ]);
    await Storage.saveCourseColors({'数学': 0xff123456});
  });

  String backup(Map<String, Object?> fields) =>
      jsonEncode({'app': 'homework_radar', 'version': 3, ...fields});

  test(
    'empty lists report their actual overwrite and retain a recovery point',
    () async {
      final message = await BackupService.importJson(
        backup({'homework': [], 'courses': []}),
      );
      expect(Storage.homework(), isEmpty);
      expect(message, contains('已恢复空作业备份'));
      expect(message, contains('课表已恢复为空'));
      expect(Storage.localRecoveryPoints(), isNotEmpty);
    },
  );

  test(
    'invalid start date aborts the entire import before any write',
    () async {
      final before = BackupService.exportMap();
      await expectLater(
        BackupService.importJson(
          backup({'semesterStart': 'broken', 'homework': []}),
        ),
        throwsFormatException,
      );
      final after = BackupService.exportMap();
      expect(after['homework'], before['homework']);
      expect(after['semesterStart'], before['semesterStart']);
      expect(Storage.localRecoveryPoints(), isEmpty);
    },
  );

  test(
    'invalid section time or course color aborts without changing settings',
    () async {
      final before = BackupService.exportMap();
      for (final fields in [
        {
          'sectionTimes': <Object>[
            [480, 525],
            'broken',
            for (var i = 2; i < 8; i++) [480 + 60 * i, 525 + 60 * i],
          ],
        },
        {
          'sectionTimes': <Object>[
            [1440, 1500],
            for (var i = 1; i < 8; i++) [480 + 60 * i, 525 + 60 * i],
          ],
        },
        {
          'courseColors': {'数学': 'broken'},
        },
      ]) {
        await expectLater(
          BackupService.importJson(backup(fields)),
          throwsFormatException,
        );
      }
      final after = BackupService.exportMap();
      expect(after['sectionTimes'], before['sectionTimes']);
      expect(after['courseColors'], before['courseColors']);
    },
  );

  test(
    'invalid reminder settings cannot silently replace current settings',
    () async {
      await Storage.saveReminders(ReminderSettings(before24h: false));
      await expectLater(
        BackupService.importJson(
          backup({
            'homework': [],
            'settings': {
              'reminders': {'24': 'invalid'},
            },
          }),
        ),
        throwsFormatException,
      );
      expect(Storage.reminders().before24h, isFalse);
      expect(Storage.homework().single.id, 'manual_keep');
    },
  );

  test(
    'archive import preserves unknown fields after validating records',
    () async {
      final row = {
        ...original.toJson(),
        'futureField': {'v': 42},
      };
      final archive = {
        'id': 'archive_1',
        'platform': 'manual',
        'createdAt': '2026-01-01',
        'homework': [row],
        'hiddenItems': <String, String>{},
        'reason': 'scope',
        'futureArchive': ['keep'],
      };
      await BackupService.importJson(
        backup({
          'accountArchives': [archive],
        }),
      );
      expect(Storage.accountArchives().single, archive);
    },
  );

  test(
    'isolated logged-in platform records retain their unknown fields',
    () async {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      const channel = MethodChannel('homework_radar/platform');
      final secrets = <String, String>{};
      messenger.setMockMethodCallHandler(channel, (call) async {
        final args = call.arguments as Map?;
        if (call.method == 'secureRead') return secrets[args?['key']];
        if (call.method == 'secureWrite') {
          secrets[args?['key']] = args?['value'];
        }
        if (call.method == 'secureDelete') secrets.remove(args?['key']);
        return true;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      await Storage.saveChaoxing(cookie: 'synthetic');
      final row = {
        ...HomeworkItem(
          id: 'cx_backup',
          platform: PlatformKind.chaoxing,
          course: '数学',
          title: '备份作业',
        ).toJson(),
        'futureField': {'note': 'preserve'},
      };
      await BackupService.importJson(
        backup({
          'homework': [row],
        }),
      );
      expect(Storage.accountArchives().single['homework'], [row]);
    },
  );

  test(
    'missing start date preserves current value while explicit null clears it',
    () async {
      await BackupService.importJson(backup({}));
      expect(Storage.semesterStart(), DateTime(2026, 9, 1));
      await BackupService.importJson(backup({'semesterStart': null}));
      expect(Storage.semesterStart(), isNull);
    },
  );

  test(
    'restore keeps a recovery point even when only settings existed',
    () async {
      await Storage.saveHomework([]);
      await BackupService.importJson(backup({'semesterStart': null}));
      expect(Storage.localRecoveryPoints(), isNotEmpty);
    },
  );
}
