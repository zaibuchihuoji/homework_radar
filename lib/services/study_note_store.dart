import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show RootIsolateToken;

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

import 'study_note_bundle.dart';

class StudyNoteLibrary {
  const StudyNoteLibrary({required this.notes, required this.folders});
  final List<Map<String, dynamic>> notes;
  final List<Map<String, dynamic>> folders;
}

/// Append-only snapshots. A completed rename is the commit point.
class StudyNoteStore {
  StudyNoteStore(this.directory);

  static Future<StudyNoteStore> openDefault() async {
    final root = await getApplicationSupportDirectory();
    return StudyNoteStore(
      Directory('${root.path}${Platform.pathSeparator}study_notes_v1'),
    );
  }

  final Directory directory;
  static final Map<String, Future<void>> _tails = {};
  static final _snapshotName = RegExp(r'^snapshot_(\d{20})\.json$');

  String _path(String name) =>
      '${directory.path}${Platform.pathSeparator}$name';

  Future<List<File>> _snapshots() async {
    if (!await directory.exists()) return [];
    final files = <File>[];
    await for (final entry in directory.list(followLinks: false)) {
      if (entry is File &&
          _snapshotName.hasMatch(entry.uri.pathSegments.last)) {
        files.add(entry);
      }
    }
    files.sort((a, b) => a.path.compareTo(b.path));
    return files;
  }

  Future<List<Map<String, dynamic>>> _read(File file) async =>
      (await _readLibrary(file)).notes;

  Future<StudyNoteLibrary> _readLibrary(File file) async {
    try {
      final outer = jsonDecode(await file.readAsString());
      if (outer is! Map ||
          (outer['version'] != 1 &&
              outer['version'] != 2 &&
              outer['version'] != 3) ||
          outer['data'] is! String ||
          outer['sha256'] !=
              sha256.convert(utf8.encode(outer['data'] as String)).toString()) {
        throw const FormatException('笔记版本校验失败');
      }
      final raw = jsonDecode(outer['data'] as String);
      final folders = <Map<String, dynamic>>[];
      dynamic data = raw;
      if (outer['version'] == 3) {
        if (raw is! Map || raw['notes'] is! List || raw['folders'] is! List) {
          throw const FormatException('笔记文件夹清单损坏');
        }
        data = raw['notes'];
        for (final folder in raw['folders'] as List) {
          if (folder is! Map) throw const FormatException('笔记文件夹清单损坏');
          folders.add(Map<String, dynamic>.from(folder));
        }
      }
      if (data is! List) throw const FormatException('笔记数据格式无效');
      final ids = <String>{};
      final result = <Map<String, dynamic>>[];
      for (final item in data) {
        if (item is! Map ||
            item['id'] is! String ||
            (item['id'] as String).isEmpty ||
            !ids.add(item['id'] as String)) {
          throw const FormatException('笔记编号无效或重复');
        }
        if (outer['version'] == 1) {
          result.add(Map<String, dynamic>.from(item));
          continue;
        }
        final hash = item['hash'];
        if (hash is! String || !RegExp(r'^[0-9a-f]{64}$').hasMatch(hash)) {
          throw const FormatException('笔记内容引用损坏');
        }
        final bytes = await File(_path('notes${Platform.pathSeparator}$hash'))
            .readAsBytes();
        if (sha256.convert(bytes).toString() != hash) {
          throw const FormatException('笔记内容校验失败');
        }
        final body = jsonDecode(utf8.decode(bytes));
        if (body is! Map || body['id'] != item['id']) {
          throw const FormatException('笔记内容编号不匹配');
        }
        result.add(Map<String, dynamic>.from(body));
      }
      StudyNoteBundle.referencedAttachments(result);
      StudyNoteBundle.validateFolders(folders, result);
      return StudyNoteLibrary(notes: result, folders: folders);
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('笔记文件无法读取，请保留文件并从历史版本恢复');
    }
  }

  Future<String> initialize({String? expectedRevision}) => _locked(() async {
    final snapshots = await _snapshots();
    final actual = snapshots.isEmpty
        ? ''
        : snapshots.last.uri.pathSegments.last;
    if (expectedRevision != null && expectedRevision != actual) {
      throw StateError('笔记已发生变化，请重新打开备份预览');
    }
    if (snapshots.isEmpty) {
      await _commit(snapshots, []);
    } else {
      await _read(snapshots.last);
    }
    return (await _snapshots()).last.uri.pathSegments.last;
  });

  Future<List<Map<String, dynamic>>> readNotes({
    bool requireInitialized = false,
  }) async {
    final snapshots = await _snapshots();
    if (snapshots.isEmpty && requireInitialized) {
      throw const FormatException('笔记目录缺少已保存的版本');
    }
    return snapshots.isEmpty ? [] : _read(snapshots.last);
  }

  Future<StudyNoteLibrary> readLibrary({
    bool requireInitialized = false,
  }) async {
    final snapshots = await _snapshots();
    if (snapshots.isEmpty && requireInitialized) {
      throw const FormatException('笔记目录缺少已保存的版本');
    }
    return snapshots.isEmpty
        ? const StudyNoteLibrary(notes: [], folders: [])
        : _readLibrary(snapshots.last);
  }

  Future<String> putAttachment(Uint8List bytes) async {
    if (bytes.length > 64 * 1024 * 1024) {
      throw const FormatException('单张图片不能超过 64 MB');
    }
    final id = sha256.convert(bytes).toString();
    await _locked(() async {
      final assets = Directory(_path('assets'));
      await assets.create(recursive: true);
      final target = File('${assets.path}${Platform.pathSeparator}$id');
      if (await target.exists()) {
        await readAttachment(id);
        return;
      }
      final pending = File('${target.path}.pending');
      await pending.writeAsBytes(bytes, flush: true);
      if (sha256.convert(await pending.readAsBytes()).toString() != id) {
        throw const FormatException('图片保存校验失败');
      }
      await pending.rename(target.path);
    });
    return id;
  }

  Future<Uint8List> readAttachment(String id) async {
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(id)) {
      throw const FormatException('附件编号无效');
    }
    final file = File(_path('assets${Platform.pathSeparator}$id'));
    if (await file.length() > 64 * 1024 * 1024) {
      throw const FormatException('笔记图片超过大小限制');
    }
    final bytes = await file.readAsBytes();
    if (sha256.convert(bytes).toString() != id) {
      throw const FormatException('附件校验失败');
    }
    return bytes;
  }

  Future<List<String>> history() async =>
      (await _snapshots()).map((file) => file.uri.pathSegments.last).toList();

  Future<List<Map<String, dynamic>>> readHistory(String version) async {
    if (!_snapshotName.hasMatch(version) ||
        !(await history()).contains(version)) {
      throw const FormatException('历史版本不存在');
    }
    return _read(File(_path(version)));
  }

  Future<StudyNoteLibrary> readHistoryLibrary(String version) async {
    if (!_snapshotName.hasMatch(version) ||
        !(await history()).contains(version)) {
      throw const FormatException('历史版本不存在');
    }
    return _readLibrary(File(_path(version)));
  }

  Future<String> revision() async {
    final versions = await history();
    return versions.isEmpty ? '' : versions.last;
  }

  Future<void> _restoreHistoryUnlocked(String version) async {
    if (!_snapshotName.hasMatch(version)) {
      throw const FormatException('历史版本编号无效');
    }
    final snapshots = await _snapshots();
    if (!snapshots.any((file) => file.uri.pathSegments.last == version)) {
      throw const FormatException('历史版本不存在');
    }
    final library = await _readLibrary(File(_path(version)));
    for (final id in StudyNoteBundle.referencedAttachments(library.notes)) {
      await readAttachment(id);
    }
    await _commit(snapshots, library.notes, folders: library.folders);
  }

  Future<void> restoreHistory(String version, {String? expectedRevision}) =>
      _locked(() async {
        final snapshots = await _snapshots();
        final actual = snapshots.isEmpty
            ? ''
            : snapshots.last.uri.pathSegments.last;
        if (expectedRevision != null && expectedRevision != actual) {
          throw StateError('笔记已发生变化，请重新选择历史版本');
        }
        await _restoreHistoryUnlocked(version);
      });

  /// Used at startup to recheck the journal while the writer is excluded.
  Future<T> withRecoveryLock<T>(
    Future<T> Function(Future<void> Function(String) restore) action,
  ) => _locked(() => action(_restoreHistoryUnlocked));

  Future<T> restoreTransaction<T>(
    List<Map<String, dynamic>> notes,
    Future<T> Function(
      String previousVersion,
      Future<void> Function() apply,
      Future<void> Function() rollback,
    )
    transaction, {
    String? expectedRevision,
    List<List<Map<String, dynamic>>> importedHistory = const [],
    List<Map<String, dynamic>>? folders,
    List<List<Map<String, dynamic>>> importedHistoryFolders = const [],
  }) => _locked(() async {
    var snapshots = await _snapshots();
    final actual = snapshots.isEmpty
        ? ''
        : snapshots.last.uri.pathSegments.last;
    if (expectedRevision != null && expectedRevision != actual) {
      throw StateError('笔记已发生变化，请重新打开备份预览');
    }
    if (snapshots.isEmpty) {
      await _commit(snapshots, []);
      snapshots = await _snapshots();
    }
    final prior = snapshots.last;
    final oldLibrary = await _readLibrary(prior);
    final version = prior.uri.pathSegments.last;
    return transaction(
      version,
      () async {
        if (importedHistoryFolders.isNotEmpty &&
            importedHistoryFolders.length != importedHistory.length) {
          throw const FormatException('文件夹历史清单不完整');
        }
        for (var i = 0; i < importedHistory.length; i++) {
          await _commit(
            await _snapshots(),
            importedHistory[i],
            folders: importedHistoryFolders.isEmpty
                ? []
                : importedHistoryFolders[i],
          );
        }
        await _commit(
          await _snapshots(),
          notes,
          folders: folders ?? oldLibrary.folders,
        );
      },
      () async => _commit(
        await _snapshots(),
        oldLibrary.notes,
        folders: oldLibrary.folders,
      ),
    );
  });

  Future<void> saveNotes(List<Map<String, dynamic>> notes) =>
      updateNotes((_) => notes);

  /// The callback runs under the lock and receives the latest committed data.
  Future<void> updateNotes(
    List<Map<String, dynamic>> Function(List<Map<String, dynamic>>) update,
  ) => _locked(() async {
    final snapshots = await _snapshots();
    final current = snapshots.isEmpty
        ? const StudyNoteLibrary(notes: [], folders: [])
        : await _readLibrary(snapshots.last);
    await _commit(snapshots, update(current.notes), folders: current.folders);
  });

  Future<void> updateLibrary(
    StudyNoteLibrary Function(StudyNoteLibrary) update,
  ) => _locked(() async {
    final snapshots = await _snapshots();
    final current = snapshots.isEmpty
        ? const StudyNoteLibrary(notes: [], folders: [])
        : await _readLibrary(snapshots.last);
    final next = update(current);
    await _commit(snapshots, next.notes, folders: next.folders);
  });

  Future<void> _commit(
    List<File> snapshots,
    List<Map<String, dynamic>> notes, {
    List<Map<String, dynamic>>? folders,
  }) async {
    folders ??= snapshots.isEmpty
        ? []
        : (await _readLibrary(snapshots.last)).folders;
    StudyNoteBundle.referencedAttachments(notes);
    StudyNoteBundle.validateFolders(folders, notes);
    final ids = <String>{};
    for (final note in notes) {
      final id = note['id'];
      if (id is! String || id.isEmpty || !ids.add(id)) {
        throw const FormatException('笔记编号无效或重复');
      }
    }
    final bodies = Directory(_path('notes'));
    await bodies.create(recursive: true);
    final index = <Map<String, String>>[];
    for (final note in notes) {
      final bytes = utf8.encode(jsonEncode(note));
      final hash = sha256.convert(bytes).toString();
      final target = File('${bodies.path}${Platform.pathSeparator}$hash');
      if (await target.exists()) {
        if (sha256.convert(await target.readAsBytes()).toString() != hash) {
          throw const FormatException('已保存的笔记内容校验失败');
        }
      } else {
        final pending = File('${target.path}.pending');
        await pending.writeAsBytes(bytes, flush: true);
        if (sha256.convert(await pending.readAsBytes()).toString() != hash) {
          throw const FormatException('笔记内容写入校验失败');
        }
        await pending.rename(target.path);
      }
      index.add({'id': note['id'] as String, 'hash': hash});
    }
    final sequence = snapshots.isEmpty
        ? 1
        : int.parse(
                _snapshotName
                    .firstMatch(snapshots.last.uri.pathSegments.last)!
                    .group(1)!,
              ) +
              1;
    final usesFolders =
        folders.isNotEmpty ||
        notes.any(
          (n) =>
              n['notebookId'] != null ||
              (n['document'] is Map && (n['document'] as Map)['version'] == 2),
        );
    final data = jsonEncode(
      usesFolders ? {'notes': index, 'folders': folders} : index,
    );
    final bytes = utf8.encode(
      jsonEncode({
        'version': usesFolders ? 3 : 2,
        'sha256': sha256.convert(utf8.encode(data)).toString(),
        'data': data,
      }),
    );
    final name = 'snapshot_${sequence.toString().padLeft(20, '0')}.json';
    final temporary = File(_path('$name.pending'));
    await temporary.writeAsBytes(bytes, flush: true);
    await _read(temporary);
    await temporary.rename(_path(name));
  }

  Future<T> _locked<T>(Future<T> Function() action) {
    // POSIX advisory locks do not serialize isolates within one process.
    // The app's UI and background jobs share the root isolate; reject writes
    // from spawned isolates rather than risk two writers replacing a version.
    if (RootIsolateToken.instance == null) {
      throw StateError('笔记写入必须在应用主隔离区执行');
    }
    final key = directory.absolute.path;
    final previous = _tails[key] ?? Future<void>.value();
    final task = previous.then((_) async {
      await directory.create(recursive: true);
      final lock = await File(_path('write.lock')).open(mode: FileMode.append);
      try {
        await lock.lock(FileLock.blockingExclusive);
        return await action();
      } finally {
        await lock.close();
      }
    });
    final tail = task.then<void>(
      (_) {},
      onError: (Object _, StackTrace stack) {},
    );
    _tails[key] = tail;
    unawaited(
      tail.then((_) {
        if (identical(_tails[key], tail)) _tails.remove(key);
      }),
    );
    return task;
  }
}
