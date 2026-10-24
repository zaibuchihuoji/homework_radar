import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:homework_radar/models/homework.dart';
import 'package:homework_radar/services/storage.dart';
import 'package:homework_radar/services/sync_service.dart';

import 'support/synthetic_http.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  AndroidFlutterLocalNotificationsPlugin.registerWith();
  final network = SyntheticHttp();
  final secrets = <String, String>{};
  setUpAll(() => HttpOverrides.global = network);
  tearDownAll(() => HttpOverrides.global = null);
  setUp(() async {
    secrets.clear();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('homework_radar/platform'),
      (call) async {
        final a = call.arguments as Map?;
        if (call.method == 'secureRead') return secrets[a?['key']];
        if (call.method == 'secureWrite') secrets[a?['key']] = a?['value'];
        if (call.method == 'secureDelete') secrets.remove(a?['key']);
        return true;
      },
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('dexterous.com/flutter/local_notifications'),
      (_) async => true,
    );
    SharedPreferences.setMockInitialValues({});
    await Storage.init();
    await Storage.saveChaoxing(cookie: 'synthetic-cx');
    await Storage.saveMooc(cookie: 'STUDY_SESS=synthetic', csrf: 'synthetic');
    await Storage.saveHomework([
      for (final p in [PlatformKind.chaoxing, PlatformKind.mooc])
        HomeworkItem(
          id: 'old-${p.name}',
          platform: p,
          course: '旧课程',
          title: '旧作业',
          note: '保留备注',
        ),
    ]);
  });
  test('a slow platform does not delay the other platform; partial failures keep data', () async {
    final held = Completer<void>();
    final started = Completer<void>();
    final other = Completer<void>();
    network.handler = (_, uri, _) async {
      if (uri.host.endsWith('chaoxing.com')) {
        if (!started.isCompleted) started.complete();
        await held.future;
      } else if (uri.host.endsWith('icourse163.org')) {
        if (!other.isCompleted) other.complete();
      }
      return SyntheticResponse('', 503);
    };
    final work = SyncService.run();
    await started.future;
    var parallel = false;
    try {
      parallel = await other.future
          .then((_) => true)
          .timeout(const Duration(milliseconds: 100), onTimeout: () => false);
    } finally {
      held.complete();
      await work;
    }
    expect(
      parallel,
      isTrue,
      reason: 'independent platforms should overlap network waits',
    );
    expect(
      Storage.homework().map((h) => h.id),
      containsAll(['old-chaoxing', 'old-mooc']),
    );
    expect(Storage.homework().every((h) => h.note == '保留备注'), isTrue);
  });

  test('two platform cap and account-generation cancellation preserve concurrent edits', () async {
    await Storage.saveXuetangx(cookie: 'synthetic-xt');
    final held = Completer<void>(), started = Completer<void>();
    final hosts = <String>[];
    network.handler = (_, uri, _) async {
      hosts.add(uri.host);
      if (hosts.length == 2) started.complete();
      await held.future;
      return SyntheticResponse('', 503);
    };
    final pending = SyncService.run();
    await started.future;
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(hosts, hasLength(2));
    Storage.invalidateSync();
    final edited = [
      ...Storage.homework(),
      HomeworkItem(
        id: 'new-manual',
        platform: PlatformKind.manual,
        course: '数学',
        title: '同步期间新增',
        note: '保留新增备注',
      ),
    ];
    await Storage.saveHomework(edited);
    held.complete();
    final result = await pending;
    expect(result.cancelled, isTrue);
    expect(hosts.any((h) => h.endsWith('xuetangx.com')), isFalse);
    expect(Storage.homework().length, edited.length);
    expect(Storage.homework().last.note, '保留新增备注');
  });
}
