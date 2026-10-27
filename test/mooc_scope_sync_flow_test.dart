import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:homework_radar/models/homework.dart';
import 'package:homework_radar/services/notification_service.dart';
import 'package:homework_radar/services/storage.dart';
import 'package:homework_radar/services/stable_hash.dart';
import 'package:homework_radar/services/sync_service.dart';
import 'package:homework_radar/services/sync_policy.dart';

import 'support/mooc_school_fixture.dart';
import 'support/synthetic_http.dart';

class _ArchiveFailingStore extends InMemorySharedPreferencesStore {
  _ArchiveFailingStore() : super.empty();
  bool failArchive = false;
  @override
  Future<bool> setValue(String type, String key, Object value) async {
    if (failArchive && key == 'flutter.account_archives') return false;
    return super.setValue(type, key, value);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  AndroidFlutterLocalNotificationsPlugin.registerWith();
  final network = SyntheticHttp();
  final secrets = <String, String>{};
  final notificationCalls = <MethodCall>[];
  Map<String, dynamic>? widget;
  late _ArchiveFailingStore store;
  setUpAll(() => HttpOverrides.global = network);
  tearDownAll(() => HttpOverrides.global = null);

  HomeworkItem item(String id, String? source, {String? note}) => HomeworkItem(
    id: id,
    platform: PlatformKind.mooc,
    course: 'Course 1',
    title: id,
    sourceKey: source,
    note: note,
    status: HwStatus.done,
  );
  setUp(() async {
    widget = null;
    notificationCalls.clear();
    secrets.clear();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('homework_radar/platform'),
      (call) async {
        final args = call.arguments as Map?;
        if (call.method == 'secureRead') return secrets[args?['key']];
        if (call.method == 'secureWrite') {
          secrets[args?['key']] = args?['value'];
        }
        if (call.method == 'secureDelete') secrets.remove(args?['key']);
        return true;
      },
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('dexterous.com/flutter/local_notifications'),
      (call) async {
            if (call.method == 'pendingNotificationRequests') { return <Map<String, Object?>>[]; }
        notificationCalls.add(call);
        return true;
      },
    );
    messenger.setMockMethodCallHandler(const MethodChannel('home_widget'), (
      call,
    ) async {
      if (call.method == 'saveWidgetData' &&
          call.arguments['id'] == 'homework_snapshot') {
        widget = (jsonDecode(call.arguments['data']) as Map)
            .cast<String, dynamic>();
      }
      return true;
    });
    SharedPreferences.setMockInitialValues({});
    store = _ArchiveFailingStore();
    SharedPreferencesStorePlatform.instance = store;
    await Storage.init();
    await Storage.saveMooc(cookie: 'STUDY_SESS=synthetic', csrf: 'synthetic');
    await Storage.saveHomework([
      item('current', 'mooc|1|1001|4|8', note: 'Current note'),
      item('old-public', 'mooc|2|1002|4|9', note: 'Keep historical note'),
      item('legacy', null, note: 'Keep legacy note'),
      HomeworkItem(
        id: 'manual',
        platform: PlatformKind.manual,
        course: 'Mine',
        title: 'Manual',
      ),
    ]);
    await Storage.dismiss(
      'hidden',
      jsonEncode(item('hidden', 'mooc|3|1003|4|10').toJson()),
    );
  });

  SyntheticResponse json(Object value) => SyntheticResponse(jsonEncode(value));
  void respond({
    bool empty = false,
    bool unknown = false,
    bool failTerm = false,
    bool expire = false,
  }) {
    var probes = 0;
    network.handler = (_, uri, body) {
      if (uri.path.contains('getMyLearnedCoursePanelList')) {
        if (Uri.splitQueryString(body)['psize'] == '1' &&
            ++probes == 3 &&
            expire) {
          return json({'code': 1});
        }
        final row = moocSchoolPanel(1);
        if (unknown) (row['termPanel'] as Map).remove('endTime');
        return json({
          'code': 0,
          'result': empty ? [] : [row],
        });
      }
      if (failTerm) return SyntheticResponse('unavailable', 503);
      return json({
        'code': 0,
        'result': {
          'id': 1001,
          'courseId': 1,
          'chapters': [
            {
              'lessons': [],
              'quizs': [],
              'homeworks': [
                {
                  'test': {
                    'id': 8,
                    'name': 'Current school work',
                    'deadline': null,
                  },
                },
              ],
            },
          ],
          'exams': [],
        },
      });
    };
  }

  test('successful school scan archives out-of-scope data before removing active copies', () async {
    respond();
    final result = await SyncService.run(platforms: {PlatformKind.mooc});
    expect(result.outcomes[PlatformKind.mooc], SyncOutcome.success);
    expect(Storage.homework().map((h) => h.id).toSet(), {'current', 'manual'});
    final current = Storage.homework().firstWhere((h) => h.id == 'current');
    expect(current.note, 'Current note');
    expect(current.status, HwStatus.done);
    final archived = (Storage.accountArchives().single['homework'] as List)
        .cast<Map>();
    expect(archived.map((h) => h['id']).toSet(), {'old-public', 'legacy'});
    expect(
      archived.firstWhere((h) => h['id'] == 'old-public')['note'],
      'Keep historical note',
    );
    expect(
      archived.firstWhere((h) => h['id'] == 'legacy')['note'],
      'Keep legacy note',
    );
    expect(Storage.hiddenItems(), contains('hidden'));
    expect(Storage.dismissedIds(), contains('hidden'));
    expect(widget, isNotNull);
    expect(
      (widget!['items'] as List).map((h) => h['id']),
      isNot(contains('old-public')),
    );
    await SyncService.run(platforms: {PlatformKind.mooc});
    expect(
      Storage.accountArchives(),
      hasLength(1),
      reason: 'No duplicate archive on the next sync',
    );
  });

  test('confirmed no current school courses archives rather than leaves stale reminders', () async {
    respond(empty: true);
    await SyncService.run(platforms: {PlatformKind.mooc});
    expect(Storage.homework().map((h) => h.id), ['manual']);
    expect(Storage.accountArchives().single['homework'], hasLength(3));
    final summary = Storage.syncStatuses()[PlatformKind.mooc]!.toJson()['summary'] as Map?;
    expect(summary, isNotNull);
    expect(summary!['archived'], 3);
    expect(summary['added'], 0);
    expect(summary['removed'], 0);
  });

  for (final failure in ['unknown', 'term', 'expired']) {
    test(
      '$failure scan preserves active records and makes no scope archive',
      () async {
        respond(
          unknown: failure == 'unknown',
          failTerm: failure == 'term',
          expire: failure == 'expired',
        );
        await SyncService.run(platforms: {PlatformKind.mooc});
        expect(
          Storage.homework().map((h) => h.id),
          containsAll(['current', 'old-public', 'legacy', 'manual']),
        );
        expect(Storage.accountArchives(), isEmpty);
        final summary = Storage.syncStatuses()[PlatformKind.mooc]!.toJson()['summary'] as Map?;
        expect(summary, isNotNull);
        expect(summary!['retained'], 3);
        expect(summary['removed'], 0);
        if (failure == 'term') {
          expect(summary['details'], contains('《Course 1》作业获取未完成'));
        }
      },
    );
  }

  test('archive write failure leaves the only active copies untouched', () async {
    respond();
    store.failArchive = true;
    await expectLater(
      SyncService.run(platforms: {PlatformKind.mooc}),
      throwsStateError,
    );
    expect(
      Storage.homework().map((h) => h.id),
      containsAll(['current', 'old-public', 'legacy', 'manual']),
    );
    // SharedPreferences updates its RAM cache before the backing store rejects
    // a write; reload to verify the persisted archive, not that optimistic cache.
    await (await SharedPreferences.getInstance()).reload();
    expect(Storage.accountArchives(), isEmpty);
  });

  test('scope change cancels old reminders and republishes the widget without outside work', () async {
    await Storage.saveHomework([
      ...Storage.homework().where((h) => h.id != 'old-public'),
      HomeworkItem(
        id: 'old-public',
        platform: PlatformKind.mooc,
        course: 'Public',
        title: 'Outside work',
        sourceKey: 'mooc|2|1002|4|9',
        status: HwStatus.todo,
        dueAt: DateTime.now().add(const Duration(hours: 48)),
      ),
    ]);
    // Establish a real reminder before sync, so an empty/failing scheduler
    // cannot make the removal assertion vacuous.
    await NotificationService.reschedule(Storage.homework());
    expect(
      notificationCalls
          .where((c) => c.method == 'zonedSchedule')
          .map((c) => c.arguments['payload']),
      contains('old-public'),
    );
    notificationCalls.clear();
    respond();
    await SyncService.run(platforms: {PlatformKind.mooc});
    expect(
      notificationCalls.where(
        (c) => c.method == 'cancelAllPendingNotifications',
      ),
      hasLength(1),
    );
    expect(
      notificationCalls
          .where((c) => c.method == 'zonedSchedule')
          .map((c) => c.arguments['payload']),
      isNot(contains('old-public')),
    );
    expect(
      (widget!['items'] as List).map((h) => h['id']),
      isNot(contains('old-public')),
    );
    expect(
      (Storage.accountArchives().single['homework'] as List).any(
        (h) => h['id'] == 'old-public',
      ),
      isTrue,
    );
  });

  test('same-name course task ID collision cannot hide a different course task or replace its hidden note', () async {
    final sharedId = 'mooc_${stableHash('Same course')}_作业8';
    final hidden = HomeworkItem(
      id: sharedId,
      platform: PlatformKind.mooc,
      course: 'Same course',
      title: 'Hidden course A',
      sourceKey: 'mooc|1|1001|4|8',
      note: 'Hidden A note',
      status: HwStatus.done,
    );
    await Storage.saveHomework(
      Storage.homework()
          .where((h) => h.platform == PlatformKind.manual)
          .toList(),
    );
    await Storage.restoreHiddenItems({sharedId: jsonEncode(hidden.toJson())});
    network.handler = (_, uri, body) {
      if (uri.path.contains('getMyLearnedCoursePanelList')) {
        return json({
          'code': 0,
          'result': [
            moocSchoolPanel(1, name: 'Same course'),
            moocSchoolPanel(2, name: 'Same course'),
          ],
        });
      }
      final term = int.parse(Uri.splitQueryString(body)['termId']!);
      return json({
        'code': 0,
        'result': {
          'id': term,
          'courseId': term - 1000,
          'exams': [],
          'chapters': [
            {
              'lessons': [],
              'quizs': [],
              'homeworks': [
                {
                  'test': {'id': 8, 'name': 'Task in $term', 'deadline': null},
                },
              ],
            },
          ],
        },
      });
    };
    await SyncService.run(platforms: {PlatformKind.mooc});
    final visible = Storage.homework().singleWhere(
      (h) => h.platform == PlatformKind.mooc,
    );
    expect(visible.sourceKey, 'mooc|2|1002|4|8');
    expect(visible.id, isNot(sharedId));
    expect(visible.note, isNull);
    final savedHidden = jsonDecode(Storage.hiddenItems()[sharedId]!) as Map;
    expect(savedHidden['sourceKey'], 'mooc|1|1001|4|8');
    expect(savedHidden['note'], 'Hidden A note');
    await SyncService.run(platforms: {PlatformKind.mooc});
    expect(
      Storage.homework().singleWhere((h) => h.platform == PlatformKind.mooc).id,
      visible.id,
    );
    expect(Storage.dismissedIds(), contains(sharedId));
  });

  test('account generation change during request cannot archive or replace current data', () async {
    final entered = Completer<void>(), resume = Completer<void>();
    network.handler = (_, _, _) async {
      if (!entered.isCompleted) entered.complete();
      await resume.future;
      return json({'code': 0, 'result': []});
    };
    final pending = SyncService.run(platforms: {PlatformKind.mooc});
    await entered.future;
    Storage.invalidateSync();
    resume.complete();
    expect((await pending).cancelled, isTrue);
    expect(Storage.homework(), hasLength(4));
    expect(Storage.accountArchives(), isEmpty);
  });
}
