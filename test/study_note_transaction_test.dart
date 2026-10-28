import 'dart:convert';
import 'dart:io';

import 'support/safe_temp_directory.dart';

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:homework_radar/services/backup_service.dart';
import 'package:homework_radar/services/storage.dart';
import 'package:homework_radar/services/study_note_store.dart';
import 'package:homework_radar/services/study_note_bundle.dart';
import 'package:homework_radar/services/study_note_document.dart';
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
  test('failed import restores both notes and their folders', () async {
    final directory = await Directory.systemTemp.createTemp(
      'notes_folder_rollback_',
    );
    addTearDown(() => deleteTestDirectory(directory));
    SharedPreferences.setMockInitialValues({});
    await Storage.init();
    final store = StudyNoteStore(directory);
    final before = StudyNoteLibrary(
      folders: [
        {'id': 'f', 'name': '我的文件夹'},
      ],
      notes: [
        {'id': 'old', 'body': '原内容', 'notebookId': 'f'},
      ],
    );
    await store.updateLibrary((_) => before);
    await expectLater(
      store.restoreTransaction(
        [
          {'id': 'new', 'notebookId': 'new-folder'},
        ],
        (version, apply, rollback) => Storage.businessTransaction(
          () async {
            await apply();
            throw StateError('模拟导入失败');
          },
          noteRollbackVersion: version,
          rollbackNotes: rollback,
        ),
        folders: [
          {'id': 'new-folder', 'name': '其他文件夹'},
        ],
      ),
      throwsStateError,
    );
    final after = await store.readLibrary();
    expect(after.folders, before.folders);
    expect(after.notes, before.notes);
  });
  test(
    'backup and restore keep folder assignments, empty folders and history',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'notes_folder_backup_',
      );
      final oldProvider = PathProviderPlatform.instance;
      PathProviderPlatform.instance = TestSupportPath(root.path);
      addTearDown(() async {
        PathProviderPlatform.instance = oldProvider;
        await deleteTestDirectory(root);
      });
      SharedPreferences.setMockInitialValues({});
      await Storage.init();
      final store = await StudyNoteStore.openDefault();
      await store.saveNotes([
        {'id': 'n', 'body': '原文'},
      ]);
      await store.updateLibrary(
        (library) => StudyNoteLibrary(
          folders: [
            {'id': 'math', 'name': '数学'},
            {'id': 'empty', 'name': '空文件夹'},
          ],
          notes: [
            for (final note in library.notes) {...note, 'notebookId': 'math'},
          ],
        ),
      );
      final backup = await BackupService.exportBundle();
      await store.updateLibrary(
        (library) => const StudyNoteLibrary(notes: [], folders: []),
      );
      await BackupService.importBundle(backup);
      final restored = await store.readLibrary();
      expect(restored.folders.map((f) => f['name']), ['数学', '空文件夹']);
      expect(restored.notes.single['notebookId'], 'math');
      final history = await store.history();
      var foundLegacy = false;
      for (final version in history) {
        final old = await store.readHistoryLibrary(version);
        if (old.notes.any((n) => n['id'] == 'n' && n['notebookId'] == null) &&
            old.folders.isEmpty) {
          foundLegacy = true;
        }
      }
      expect(foundLegacy, isTrue);
    },
  );
  test(
    'failed joined import rolls back business data and notes together',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'notes_transaction_',
      );
      addTearDown(() => deleteTestDirectory(directory));
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
      await deleteTestDirectory(root);
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
        await deleteTestDirectory(root);
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
        await deleteTestDirectory(root);
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
        await deleteTestDirectory(root);
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
        await deleteTestDirectory(root);
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
        await deleteTestDirectory(root);
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
        await deleteTestDirectory(root);
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

  test(
    'complete backup restores mixed document, canvas images and old history',
    () async {
      final root = await Directory.systemTemp.createTemp('document_bundle_');
      final oldProvider = PathProviderPlatform.instance;
      addTearDown(() async {
        PathProviderPlatform.instance = oldProvider;
        await deleteTestDirectory(root);
      });
      PathProviderPlatform.instance = TestSupportPath(
        '${root.path}${Platform.pathSeparator}source',
      );
      SharedPreferences.setMockInitialValues({});
      await Storage.init();
      final source = await StudyNoteStore.openDefault();
      await source.saveNotes([
        {'id': 'n', 'body': '旧正文', 'blocks': <dynamic>[]},
      ]);
      final bytes = Uint8List.fromList([5, 6, 7, 8]);
      final imageId = await source.putAttachment(bytes);
      final document = <String, dynamic>{
        'version': 1,
        'nodes': [
          {
            'id': 'p',
            'type': 'text',
            'style': 'paragraph',
            'text': '新正文',
            'marks': [
              {'type': 'bold', 'start': 0, 'end': 1},
            ],
            'annotations': [
              {
                'color': 1,
                'anchor': 0,
                'points': [
                  [0.2, 0.3],
                ],
              },
            ],
          },
          {
            'id': 'c',
            'type': 'canvas',
            'strokes': <dynamic>[],
            'items': [
              {
                'id': 'i',
                'type': 'image',
                'attachmentId': imageId,
                'x': 0.1,
                'y': 0.1,
                'width': 0.4,
                'height': 0.3,
              },
            ],
          },
        ],
      };
      final note = <String, dynamic>{
        'id': 'n',
        'body': StudyNoteDocument.plainText(document),
        'blocks': StudyNoteDocument.legacyBlocks(document),
        'document': document,
        'cards': [
          {'question': '问题', 'answer': '答案'},
        ],
      };
      await source.saveNotes([note]);
      final backup = await BackupService.exportBundle();
      PathProviderPlatform.instance = TestSupportPath(
        '${root.path}${Platform.pathSeparator}target',
      );
      SharedPreferences.setMockInitialValues({});
      await Storage.init();
      await BackupService.importBundle(backup);
      final target = await StudyNoteStore.openDefault();
      expect((await target.readNotes()).single, note);
      expect(await target.readAttachment(imageId), bytes);
      var oldVersionFound = false;
      for (final version in await target.history()) {
        final rows = await target.readHistory(version);
        if (rows.any((row) => row['body'] == '旧正文')) oldVersionFound = true;
      }
      expect(oldVersionFound, isTrue);
    },
  );
}
