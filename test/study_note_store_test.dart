import 'dart:io';

import 'support/safe_temp_directory.dart';

import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:homework_radar/services/study_note_store.dart';

Future<void> addFromIsolate((String, String) input) async {
  final store = StudyNoteStore(Directory(input.$1));
  for (var i = 0; i < 10; i++) {
    await store.updateNotes(
      (notes) => [
        ...notes,
        {'id': '${input.$2}-$i'},
      ],
    );
  }
}

void main() {
  late Directory directory;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('study_notes_test_');
  });
  tearDown(() async {
    await deleteTestDirectory(directory);
  });

  test('saved notes survive opening the store again', () async {
    final store = StudyNoteStore(directory);
    await store.saveNotes([
      {'id': 'n1', 'title': '线性代数', 'text': '矩阵'},
    ]);
    expect(await StudyNoteStore(directory).readNotes(), [
      {'id': 'n1', 'title': '线性代数', 'text': '矩阵'},
    ]);
  });
  test('editing one note reuses unchanged note bodies', () async {
    final store = StudyNoteStore(directory);
    await store.saveNotes([
      {'id': 'first', 'text': '一'},
      {'id': 'second', 'text': '二'},
    ]);
    await store.updateNotes(
      (notes) => [
        {...notes.first, 'text': '新'},
        notes.last,
      ],
    );
    final bodies = Directory('${directory.path}${Platform.pathSeparator}notes');
    expect(await bodies.list().where((entry) => entry is File).length, 3);
  });

  test('invalid updates cannot replace the committed notes', () async {
    final store = StudyNoteStore(directory);
    await store.saveNotes([
      {'id': 'safe', 'title': '保留'},
    ]);
    await expectLater(
      store.saveNotes([
        {'id': 'duplicate'},
        {'id': 'duplicate'},
      ]),
      throwsFormatException,
    );
    expect((await store.readNotes()).single['title'], '保留');
  });

  test('malformed cards do not replace a readable note', () async {
    final store = StudyNoteStore(directory);
    await store.saveNotes([
      {'id': 'safe', 'title': '保留'},
    ]);
    await expectLater(
      store.saveNotes([
        {
          'id': 'safe',
          'cards': [
            {'question': 42, 'answer': '答案'},
          ],
        },
      ]),
      throwsFormatException,
    );
    expect((await store.readNotes()).single['title'], '保留');
  });

  test('a failed snapshot write keeps the previous committed version', () async {
    final store = StudyNoteStore(directory);
    await store.saveNotes([
      {'id': 'n', 'title': '原内容'},
    ]);
    await Directory(
      '${directory.path}${Platform.pathSeparator}snapshot_00000000000000000002.json.pending',
    ).create();
    await expectLater(
      store.saveNotes([
        {'id': 'n', 'title': '新内容'},
      ]),
      throwsA(isA<FileSystemException>()),
    );
    expect((await store.readNotes()).single['title'], '原内容');
  });

  test('concurrent edits see the latest version', () async {
    final first = StudyNoteStore(directory);
    final second = StudyNoteStore(directory);
    await Future.wait([
      first.updateNotes(
        (notes) => [
          ...notes,
          {'id': 'first'},
        ],
      ),
      second.updateNotes(
        (notes) => [
          ...notes,
          {'id': 'second'},
        ],
      ),
    ]);
    expect((await first.readNotes()).map((n) => n['id']), ['first', 'second']);
  });

  test('spawned isolates cannot write around the root-isolate queue', () async {
    final path = directory.path;
    await expectLater(
      Isolate.run(() => addFromIsolate((path, 'a'))),
      throwsStateError,
    );
    expect(await StudyNoteStore(directory).readNotes(), isEmpty);
  });

  test(
    'corruption does not silently turn a note collection into empty data',
    () async {
      final store = StudyNoteStore(directory);
      await store.saveNotes([
        {'id': 'safe'},
      ]);
      final snapshot =
          (await directory
                  .list()
                  .where((e) => e.path.endsWith('.json'))
                  .toList())
              .single;
      await File(snapshot.path).writeAsString('{damaged');
      await expectLater(store.readNotes(), throwsFormatException);
      await expectLater(store.saveNotes([]), throwsFormatException);
    },
  );

  test('attachment retains the original bytes and detects corruption', () async {
    final store = StudyNoteStore(directory);
    final original = Uint8List.fromList([0, 10, 128, 255]);
    final id = await store.putAttachment(original);
    expect(await StudyNoteStore(directory).readAttachment(id), original);
    final asset = File(
      '${directory.path}${Platform.pathSeparator}assets${Platform.pathSeparator}$id',
    );
    await asset.writeAsBytes([1]);
    await expectLater(store.readAttachment(id), throwsFormatException);
  });

  test('a damaged newest version can be restored from history', () async {
    final store = StudyNoteStore(directory);
    await store.saveNotes([
      {'id': 'n', 'title': '旧内容'},
    ]);
    final old = (await store.history()).single;
    await store.saveNotes([
      {'id': 'n', 'title': '新内容'},
    ]);
    final latest = (await store.history()).last;
    await File('${directory.path}${Platform.pathSeparator}$latest')
        .writeAsString('broken');
    await store.restoreHistory(old);
    expect((await store.readNotes()).single['title'], '旧内容');
  });

  test(
    'a failed joined restore can roll back to the previous snapshot',
    () async {
      final store = StudyNoteStore(directory);
      await store.saveNotes([
        {'id': 'old', 'title': '原内容'},
      ]);
      await expectLater(
        store.restoreTransaction(
          [
            {'id': 'new'},
          ],
          (version, apply, rollback) async {
            await apply();
            await rollback();
            throw StateError('业务恢复失败');
          },
        ),
        throwsStateError,
      );
      expect((await store.readNotes()).single['title'], '原内容');
    },
  );
}
