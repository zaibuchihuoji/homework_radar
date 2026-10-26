import 'dart:convert';
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:homework_radar/app_state.dart';
import 'package:homework_radar/models/homework.dart';
import 'package:homework_radar/models/course.dart';
import 'package:homework_radar/services/storage.dart';
import 'package:homework_radar/services/backup_service.dart';
import 'package:homework_radar/services/secure_store.dart';
import 'package:homework_radar/services/sync_service.dart';

class LocalState extends AppState {
  @override
  Future<String> syncAll() async {
    await loadLocal();
    return '';
  }
}

class FailingStore extends InMemorySharedPreferencesStore {
  FailingStore() : super.empty();
  String? failOnce;
  bool failRecovery = false;
  @override
  Future<bool> setValue(String type, String key, Object value) async {
    if (failRecovery) return false;
    if (key == failOnce) {
      failOnce = null;
      return false;
    }
    return super.setValue(type, key, value);
  }

  @override
  Future<bool> remove(String key) async =>
      failRecovery ? false : super.remove(key);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  AndroidFlutterLocalNotificationsPlugin.registerWith();
  final secure = <String, String>{};
  var rejectUid = false;
  String? unreadableKey;
  var rejectLegacyDelete = false;
  setUp(() async {
    rejectUid = false;
    unreadableKey = null;
    rejectLegacyDelete = false;
    secure.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('dexterous.com/flutter/local_notifications'),
          (call) async => call.method == 'pendingNotificationRequests' ? <Map<String, Object?>>[] : true,
        );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('homework_radar/platform'),
          (call) async {
            final args = call.arguments as Map?;
            switch (call.method) {
              case 'secureRead':
                if (unreadableKey != null && args!['key'] == unreadableKey) {
                  throw PlatformException(code: 'locked');
                }
                return secure[args!['key']];
              case 'secureWrite':
                if (rejectUid &&
                    (args!['value'] as String).contains('new-uid')) {
                  throw PlatformException(code: 'disk_full');
                }
                secure[args!['key']] = args['value'];
                return true;
              case 'secureDelete':
                if (rejectLegacyDelete && args!['key'] == 'cx_cookie') {
                  throw PlatformException(code: 'disk');
                }
                secure.remove(args!['key']);
                return true;
            }
            return null;
          },
        );
    SharedPreferences.setMockInitialValues({});
    await Storage.init();
  });
  HomeworkItem task(String id, {String? sourceKey, String note = 'my note'}) =>
      HomeworkItem(
        id: id,
        platform: PlatformKind.chaoxing,
        course: 'course',
        title: id,
        note: note,
        sourceKey: sourceKey,
      );
  Course course(
    String name, {
    String room = '',
    bool edited = false,
    List<int> weeks = const [1, 2],
  }) => Course(
    id: name,
    name: name,
    weekday: 1,
    startSection: 1,
    endSection: 2,
    weeks: weeks,
    room: room,
    edited: edited,
  );

  test('different account has no old active or hidden data; archive preserves notes without credentials', () async {
    await Storage.saveChaoxing(cookie: 'unique-old-cookie-secret', uid: 'A');
    await Storage.saveHomework([task('old')]);
    await Storage.dismiss('hidden', jsonEncode(task('hidden').toJson()));
    await LocalState().onChaoxingLogin('new-cookie', 'B');
    expect(Storage.homework(), isEmpty);
    expect(Storage.hiddenItems(), isEmpty);
    final archives = Storage.accountArchives();
    expect((archives.single['homework'] as List).single['note'], 'my note');
    expect((archives.single['hiddenItems'] as Map).keys, contains('hidden'));
    expect(jsonEncode(archives), isNot(contains('unique-old-cookie-secret')));
  });

  test(
    'same verified uid with renewed cookie retains local notes and hidden data',
    () async {
      await Storage.saveChaoxing(cookie: 'old-cookie', uid: 'A');
      await Storage.saveHomework([task('old')]);
      await LocalState().onChaoxingLogin('renewed-cookie', 'A');
      expect(Storage.homework().single.note, 'my note');
      expect(Storage.accountArchives(), isEmpty);
    },
  );

  test('source identity survives course rename and retains legacy id, note and completion', () {
    final old = task(
      'old-name-id',
      sourceKey: 'cx|c|a|work|1',
    ).copyWith(status: HwStatus.done);
    final map = {old.id: old};
    mergePlatform(
      map,
      [task('new-name-id', sourceKey: old.sourceKey, note: '')],
      PlatformKind.chaoxing,
      complete: true,
    );
    expect(map.keys, ['old-name-id']);
    expect(map.values.single.note, 'my note');
  });

  test('ambiguous source identity never deletes either old candidate', () {
    final a = task('a', sourceKey: 'duplicate');
    final b = task('b', sourceKey: 'duplicate');
    final map = {'a': a, 'b': b};
    mergePlatform(
      map,
      [task('c', sourceKey: 'duplicate')],
      PlatformKind.chaoxing,
      complete: true,
    );
    expect(map.keys, containsAll(['a', 'b', 'c']));
  });

  test('legacy named identity cannot silently delete a note before first source upgrade', () {
    final old = task('old-name-with-note');
    final map = {old.id: old};
    mergePlatform(
      map,
      [task('renamed-id', sourceKey: 'cx|c|a|work|1', note: '')],
      PlatformKind.chaoxing,
      complete: true,
    );
    expect(map['old-name-with-note']?.note, 'my note');
    expect(map['renamed-id']?.sourceKey, 'cx|c|a|work|1');
  });

  test('failed preference write rolls an entire backup import back', () async {
    SharedPreferences.setMockInitialValues({});
    final store = FailingStore();
    SharedPreferencesStorePlatform.instance = store;
    await Storage.init();
    await Storage.saveCourses([course('before')]);
    await Storage.saveHomework([task('before')]);
    await Storage.saveSemesterStart(DateTime(2026, 8, 31));
    store.failOnce = 'flutter.course_colors';
    final raw = jsonEncode({
      'app': 'homework_radar',
      'version': 1,
      'courses': [course('after').toJson()],
      'homework': [task('after').toJson()],
      'semesterStart': DateTime(2027, 2, 22).millisecondsSinceEpoch,
      'courseColors': {},
    });
    await expectLater(BackupService.importJson(raw), throwsStateError);
    expect(Storage.courses().single.name, 'before');
    expect(Storage.homework().single.id, 'before');
    expect(Storage.semesterStart(), DateTime(2026, 8, 31));
    expect(
      (await SharedPreferences.getInstance()).containsKey(
        'business_transaction',
      ),
      isFalse,
    );
  });

  test('failed journal deletion and failed rollback block further mutation until recovery', () async {
    SharedPreferences.setMockInitialValues({});
    final store = FailingStore();
    SharedPreferencesStorePlatform.instance = store;
    await Storage.init();
    await Storage.saveHomework([task('before')]);
    await expectLater(
      Storage.businessTransaction(() async {
        await Storage.saveHomework([task('intermediate')]);
        store.failRecovery = true;
      }),
      throwsStateError,
    );
    try {
      await expectLater(Storage.waitForBusinessTransaction(), throwsStateError);
      await expectLater(
        Storage.businessTransaction(() async {}),
        throwsStateError,
      );
    } finally {
      store.failRecovery = false;
      await Storage.init();
    }
    expect(Storage.homework().single.id, 'before');
  });

  test('unfinished import journal recovers original data on startup', () async {
    SharedPreferences.setMockInitialValues({
      'homework_json': jsonEncode([task('half-imported').toJson()]),
      'business_transaction': jsonEncode({
        'homework_json': jsonEncode([task('before').toJson()]),
      }),
    });
    await Storage.init();
    expect(Storage.homework().single.id, 'before');
    expect(
      (await SharedPreferences.getInstance()).containsKey(
        'business_transaction',
      ),
      isFalse,
    );
  });

  test('sync waits for a rolling-back transaction rather than reviving its intermediate snapshot', () async {
    await Storage.saveHomework([task('before')]);
    final entered = Completer<void>(), release = Completer<void>();
    final transaction = Storage.businessTransaction(() async {
      await Storage.saveHomework([task('intermediate')]);
      entered.complete();
      await release.future;
      throw StateError('synthetic interrupted import');
    });
    final failure = expectLater(transaction, throwsStateError);
    await entered.future;
    var finished = false;
    final sync = SyncService.run().then((r) {
      finished = true;
      return r;
    });
    await Future<void>.delayed(Duration.zero);
    expect(finished, isFalse);
    release.complete();
    await failure;
    await sync;
    expect(Storage.homework().single.id, 'before');
  });

  test('startup restores credentials and business snapshot after interrupted cross-store commit', () async {
    await Storage.saveChaoxing(cookie: 'before-cookie', uid: 'before-uid');
    await SecureStore.beginTransaction();
    await Storage.saveChaoxing(cookie: 'half-cookie', uid: 'half-uid');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'business_transaction',
      jsonEncode({
        '_credentials': true,
        'homework_json': jsonEncode([task('before').toJson()]),
      }),
    );
    await Storage.saveHomework([task('half-written')]);
    await Storage.init();
    expect(Storage.chaoxingCookie(), 'before-cookie');
    expect(Storage.chaoxingUid(), 'before-uid');
    expect(Storage.homework().single.id, 'before');
    expect(
      jsonEncode(prefs.getString('business_transaction')),
      isNot(contains('before-cookie')),
    );
  });

  test(
    'deleted v2 credential never falls back to an obsolete v1 native cookie',
    () async {
      secure['cx_cookie'] = 'obsolete';
      await Storage.saveChaoxing(cookie: 'active', uid: 'A');
      await Storage.clearChaoxing();
      await Storage.init();
      expect(Storage.chaoxingCookie(), isNull);
      expect(Storage.chaoxingUid(), isNull);
    },
  );

  test('malformed backup entry rejects whole import instead of overwriting with a subset', () async {
    await Storage.saveHomework([task('before')]);
    final raw = jsonEncode({
      'app': 'homework_radar',
      'version': 1,
      'homework': [
        task('after').toJson(),
        {'id': 'broken', 'dueAt': 'not-a-timestamp'},
      ],
    });
    await expectLater(BackupService.importJson(raw), throwsFormatException);
    expect(Storage.homework().single.id, 'before');
  });

  test(
    'explicit empty backup restores empty lists rather than mixing target data',
    () async {
      await Storage.saveHomework([task('before')]);
      await Storage.saveCourses([course('before')]);
      await BackupService.importJson(
        jsonEncode({
          'app': 'homework_radar',
          'version': 1,
          'homework': [],
          'courses': [],
        }),
      );
      expect(Storage.homework(), isEmpty);
      expect(Storage.courses(), isEmpty);
    },
  );

  test('backup with unknown owner cannot attach notes or hidden ids to an already logged in account', () async {
    await Storage.saveChaoxing(cookie: 'account-B', uid: 'B');
    await Storage.saveHomework([task('shared-task', note: 'B note')]);
    final foreign = task('shared-task', note: 'A private note');
    await BackupService.importJson(
      jsonEncode({
        'app': 'homework_radar',
        'version': 1,
        'homework': [foreign.toJson()],
        'hiddenItems': {'shared-task': jsonEncode(foreign.toJson())},
      }),
    );
    expect(Storage.homework().single.note, 'B note');
    expect(Storage.hiddenItems(), isEmpty);
    expect(
      (Storage.accountArchives().single['homework'] as List).single['note'],
      'A private note',
    );
    expect(
      (Storage.accountArchives().single['hiddenItems'] as Map).keys,
      contains('shared-task'),
    );
  });

  test('non-object backup entries cannot erase healthy target lists', () async {
    await Storage.saveHomework([task('before')]);
    await Storage.saveCourses([course('before')]);
    await expectLater(
      BackupService.importJson(
        jsonEncode({
          'app': 'homework_radar',
          'version': 1,
          'courses': [null],
          'homework': ['broken'],
        }),
      ),
      throwsFormatException,
    );
    expect(Storage.homework().single.id, 'before');
    expect(Storage.courses().single.name, 'before');
  });

  test('account credentials never become a mixed old uid and new cookie after write failure', () async {
    await Storage.saveChaoxing(cookie: 'old-cookie', uid: 'old-uid');
    rejectUid = true;
    await expectLater(
      Storage.saveChaoxing(cookie: 'new-cookie', uid: 'new-uid'),
      throwsStateError,
    );
    expect(Storage.chaoxingCookie(), 'old-cookie');
    expect(Storage.chaoxingUid(), 'old-uid');
    rejectUid = false;
    await Storage.init();
    expect(Storage.chaoxingCookie(), 'old-cookie');
    expect(Storage.chaoxingUid(), 'old-uid');
  });

  test('timetable transaction rolls credentials back with business data on disk failure', () async {
    SharedPreferences.setMockInitialValues({});
    final store = FailingStore();
    SharedPreferencesStorePlatform.instance = store;
    await Storage.init();
    await Storage.saveZf(cookie: 'old-zf', xh: 'A');
    await Storage.saveCourses([course('before')]);
    store.failOnce = 'flutter.courses_json';
    await expectLater(
      LocalState().onTimetableCaptured(
        cookie: 'new-zf',
        xh: 'B',
        courses: [course('after')],
        rawPage: '',
        fullImport: true,
      ),
      throwsStateError,
    );
    expect(Storage.zfCookie(), 'old-zf');
    expect(Storage.zfXh(), 'A');
    expect(Storage.courses().single.name, 'before');
  });

  test('real semester change without detected week clears old semester calibration', () async {
    await Storage.saveCourses([course('before')]);
    await Storage.saveTimetableSemester('2025-2026第1学期');
    await Storage.saveSemesterStart(DateTime(2025, 9, 1));
    await Storage.setFlag('semester_start_manual', true);
    await LocalState().onTimetableCaptured(
      courses: [course('after')],
      rawPage: '',
      semesterText: '2025-2026第2学期',
      fullImport: true,
    );
    expect(Storage.semesterStart(), isNull);
    expect(Storage.flag('semester_start_manual'), isFalse);
  });

  test('changing school cannot apply previous school edited room', () async {
    await Storage.saveJwConfigRaw(
      jsonEncode({'name': 'new', 'url': 'https://new.edu.cn'}),
    );
    await Storage.saveTimetableSource('old.edu.cn#A');
    await Storage.saveCourses([course('Math', room: 'old room', edited: true)]);
    final state = LocalState();
    await state.loadLocal();
    await state.onTimetableCaptured(
      courses: [course('Math', room: 'new room')],
      rawPage: '',
      fullImport: true,
    );
    expect(Storage.courses().single.room, 'new room');
    expect(
      (Storage.accountArchives().single['courses'] as List).single['room'],
      'old room',
    );
  });

  test(
    'timetable write rollback does not leave uncommitted courses in app state',
    () async {
      SharedPreferences.setMockInitialValues({});
      final store = FailingStore();
      SharedPreferencesStorePlatform.instance = store;
      await Storage.init();
      await Storage.saveCourses([course('before')]);
      final state = LocalState();
      await state.loadLocal();
      store.failOnce = 'flutter.zf_raw_page';
      await expectLater(
        state.onTimetableCaptured(
          courses: [course('after')],
          rawPage: 'html',
          fullImport: true,
        ),
        throwsStateError,
      );
      expect(state.courses.single.name, 'before');
      expect(Storage.courses().single.name, 'before');
    },
  );

  test('stale course deletion cannot remove other week twins', () async {
    final a = course('same', weeks: [2]), b = course('same', weeks: [3]);
    await Storage.saveCourses([a, b]);
    await expectLater(
      LocalState().deleteCourse(course('same', weeks: [1])),
      throwsStateError,
    );
    expect(Storage.courses(), hasLength(2));
  });
  test('unreadable legacy credentials block creating an authoritative incomplete account bundle', () async {
    secure['zhs_cookie'] = 'legacy-session';
    unreadableKey = 'zhs_cookie';
    try {
      await expectLater(Storage.init(), throwsA(isA<PlatformException>()));
      await expectLater(
        Storage.saveMooc(cookie: 'new-session', csrf: 'new-csrf'),
        throwsStateError,
      );
      expect(secure.containsKey('account_credentials_v2'), isFalse);
    } finally {
      unreadableKey = null;
      await Storage.init();
    }
    expect(Storage.zhihuishuCookie(), 'legacy-session');
  });
  test('legacy deletion failure reports failure and preserves the previous active credential bundle', () async {
    await Storage.saveChaoxing(cookie: 'old-session', uid: 'A');
    rejectLegacyDelete = true;
    try {
      await expectLater(
        Storage.clearChaoxing(),
        throwsA(isA<PlatformException>()),
      );
      expect(Storage.chaoxingCookie(), 'old-session');
    } finally {
      rejectLegacyDelete = false;
      await Storage.init();
    }
    expect(Storage.chaoxingCookie(), 'old-session');
  });
}
