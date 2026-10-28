import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:homework_radar/services/backup_service.dart';
import 'package:homework_radar/services/storage.dart';
import 'package:homework_radar/services/study_note_store.dart';
import 'package:homework_radar/services/study_note_bundle.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TestSupportPath extends PathProviderPlatform {
  TestSupportPath(this.path);
  final String path;
  @override
  Future<String?> getApplicationSupportPath() async => path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'failed joined import rolls back business data and notes together',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'notes_transaction_',
      );
      addTearDown(() => directory.delete(recursive: true));
      SharedPreferences.setMockInitialValues({});
      await Storage.init();
      await Storage.saveTimetableSource('原课表');
      final notes = StudyNoteStore(directory);
      await notes.saveNotes([
        {'id': 'old'},
      ]);
      await expectLater(
        notes.restoreTransaction(
          [
            {'id': 'new'},
          ],
          (version, apply, rollback) => Storage.businessTransaction(
            () async {
              await Storage.saveTimetableSource('新课表');
              await apply();
              throw StateError('模拟导入中断');
            },
            noteRollbackVersion: version,
            rollbackNotes: rollback,
          ),
        ),
        throwsStateError,
      );
      expect(Storage.timetableSource(), '原课表');
      expect((await notes.readNotes()).single['id'], 'old');
    },
  );
  test('complete backup restores business data and note images', () async {
    final root = await Directory.systemTemp.createTemp('notes_bundle_');
    final oldProvider = PathProviderPlatform.instance;
    PathProviderPlatform.instance = TestSupportPath(root.path);
    addTearDown(() async {
      PathProviderPlatform.instance = oldProvider;
      await root.delete(recursive: true);
    });
    SharedPreferences.setMockInitialValues({});
    await Storage.init();
    final store = await StudyNoteStore.openDefault();
    final image = await store.putAttachment(Uint8List.fromList([1, 2, 3]));
    await store.saveNotes([
      {
        'id': 'n',
        'blocks': [
          {'type': 'image', 'attachmentId': image},
        ],
      },
    ]);
    await Storage.saveTimetableSource('原课表');
    final backup = await BackupService.exportBundle();
    await store.saveNotes([
      {'id': 'new'},
    ]);
    await Storage.saveTimetableSource('新课表');
    await BackupService.importBundle(backup);
    expect((await store.readNotes()).single['id'], 'n');
    expect(await store.readAttachment(image), [1, 2, 3]);
    expect(Storage.timetableSource(), '原课表');
  });
  test(
    'a stale preview cannot overwrite newer notes or business data',
    () async {
      final root = await Directory.systemTemp.createTemp('notes_stale_');
      final oldProvider = PathProviderPlatform.instance;
      PathProviderPlatform.instance = TestSupportPath(root.path);
      addTearDown(() async {
        PathProviderPlatform.instance = oldProvider;
        await root.delete(recursive: true);
      });
      SharedPreferences.setMockInitialValues({});
      await Storage.init();
      final notes = await StudyNoteStore.openDefault();
      await notes.saveNotes([
        {'id': 'before'},
      ]);
      final backup = await BackupService.exportBundle();
      final preview = await notes.revision();
      await notes.saveNotes([
        {'id': 'after'},
      ]);
      await Storage.saveTimetableSource('当前课表');
      await expectLater(
        BackupService.importBundle(backup, expectedNoteRevision: preview),
        throwsStateError,
      );
      expect((await notes.readNotes()).single['id'], 'after');
      expect(Storage.timetableSource(), '当前课表');
    },
  );
  test(
    'startup rolls back interrupted notes and business transaction',
    () async {
      final root = await Directory.systemTemp.createTemp('notes_recovery_');
      final oldProvider = PathProviderPlatform.instance;
      PathProviderPlatform.instance = TestSupportPath(root.path);
      addTearDown(() async {
        PathProviderPlatform.instance = oldProvider;
        await root.delete(recursive: true);
      });
      final notes = await StudyNoteStore.openDefault();
      await notes.saveNotes([
        {'id': 'old'},
      ]);
      final version = (await notes.history()).last;
      await notes.saveNotes([
        {'id': 'new'},
      ]);
      SharedPreferences.setMockInitialValues({
        'timetable_source': '新课表',
        'business_transaction': jsonEncode({
          'timetable_source': '原课表',
          '_notesRollbackVersion': version,
        }),
      });
      await Storage.init();
      expect(Storage.timetableSource(), '原课表');
      expect((await notes.readNotes()).single['id'], 'old');
      expect(
        (await SharedPreferences.getInstance()).containsKey(
          'business_transaction',
        ),
        isFalse,
      );
    },
  );
  test(
    'restore on a fresh device and old JSON restore preserve notes',
    () async {
      final root = await Directory.systemTemp.createTemp('notes_new_device_');
      final oldProvider = PathProviderPlatform.instance;
      addTearDown(() async {
        PathProviderPlatform.instance = oldProvider;
        await root.delete(recursive: true);
      });
      PathProviderPlatform.instance = TestSupportPath(
        '${root.path}${Platform.pathSeparator}source',
      );
      SharedPreferences.setMockInitialValues({});
      await Storage.init();
      final original = await StudyNoteStore.openDefault();
      await original.saveNotes([
        {'id': 'n', 'body': '知识'},
      ]);
      final backup = await BackupService.exportBundle();
      PathProviderPlatform.instance = TestSupportPath(
        '${root.path}${Platform.pathSeparator}target',
      );
      SharedPreferences.setMockInitialValues({});
      await Storage.init();
      await BackupService.importBundle(backup, expectedNoteRevision: '');
      final restored = await StudyNoteStore.openDefault();
      expect((await restored.readNotes()).single['body'], '知识');
      await BackupService.importJson(
        jsonEncode({
          'app': 'homework_radar',
          'version': 3,
          'timetableSource': '旧备份',
        }),
      );
      expect((await restored.readNotes()).single['body'], '知识');
      expect(Storage.timetableSource(), '旧备份');
    },
  );

  test(
    'damaged bundle cannot replace current business data or notes',
    () async {
      final root = await Directory.systemTemp.createTemp('notes_bad_bundle_');
      final oldProvider = PathProviderPlatform.instance;
      PathProviderPlatform.instance = TestSupportPath(root.path);
      addTearDown(() async {
        PathProviderPlatform.instance = oldProvider;
        await root.delete(recursive: true);
      });
      SharedPreferences.setMockInitialValues({});
      await Storage.init();
      final notes = await StudyNoteStore.openDefault();
      await notes.saveNotes([
        {'id': 'safe'},
      ]);
      await Storage.saveTimetableSource('当前课表');
      final backup = await BackupService.exportBundle();
      backup[backup.length - 1] ^= 1;
      await expectLater(
        BackupService.importBundle(backup),
        throwsFormatException,
      );
      expect((await notes.readNotes()).single['id'], 'safe');
      expect(Storage.timetableSource(), '当前课表');
    },
  );
  test(
    'portable backup retains prior note versions and their images',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'notes_history_bundle_',
      );
      final oldProvider = PathProviderPlatform.instance;
      addTearDown(() async {
        PathProviderPlatform.instance = oldProvider;
        await root.delete(recursive: true);
      });
      PathProviderPlatform.instance = TestSupportPath(
        '${root.path}${Platform.pathSeparator}source',
      );
      SharedPreferences.setMockInitialValues({});
      await Storage.init();
      final source = await StudyNoteStore.openDefault();
      final image = await source.putAttachment(Uint8List.fromList([9, 8, 7]));
      await source.saveNotes([
        {
          'id': 'n',
          'title': '旧版',
          'blocks': [
            {'type': 'image', 'attachmentId': image},
          ],
        },
      ]);
      await source.saveNotes([
        {'id': 'n', 'title': '新版'},
      ]);
      final bundle = await BackupService.exportBundle();
      PathProviderPlatform.instance = TestSupportPath(
        '${root.path}${Platform.pathSeparator}target',
      );
      SharedPreferences.setMockInitialValues({});
      await Storage.init();
      await BackupService.importBundle(bundle);
      final target = await StudyNoteStore.openDefault();
      expect((await target.readNotes()).single['title'], '新版');
      final versions = await target.history();
      var found = false;
      for (final version in versions) {
        await target.restoreHistory(version);
        if ((await target.readNotes()).any((n) => n['title'] == '旧版')) {
          found = true;
          break;
        }
      }
      expect(found, isTrue);
      expect(await target.readAttachment(image), [9, 8, 7]);
    },
  );
  test(
    'damaged history permits an explicitly labeled current-only backup',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'notes_partial_backup_',
      );
      final oldProvider = PathProviderPlatform.instance;
      PathProviderPlatform.instance = TestSupportPath(root.path);
      addTearDown(() async {
        PathProviderPlatform.instance = oldProvider;
        await root.delete(recursive: true);
      });
      SharedPreferences.setMockInitialValues({});
      await Storage.init();
      final store = await StudyNoteStore.openDefault();
      await store.saveNotes([
        {'id': 'n', 'title': '旧版'},
      ]);
      final old = (await store.history()).last;
      await store.saveNotes([
        {'id': 'n', 'title': '当前'},
      ]);
      await File('${store.directory.path}${Platform.pathSeparator}$old')
          .writeAsString('damaged');
      await expectLater(BackupService.exportBundle(), throwsFormatException);
      final bundle = StudyNoteBundle.decode(
        await BackupService.exportBundle(includeHistory: false),
      );
      expect(bundle.historyIncluded, isFalse);
      expect(bundle.notes.single['title'], '当前');
      expect((await store.readNotes()).single['title'], '当前');
    },
  );
}
