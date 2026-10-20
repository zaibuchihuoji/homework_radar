import 'dart:convert';
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:homework_radar/models/homework.dart';
import 'package:homework_radar/services/storage.dart';
import 'package:homework_radar/services/sync_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final cache = <String, dynamic>{};
  setUp(() async {
    cache.clear();
    SharedPreferences.setMockInitialValues({});
    await Storage.init();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('home_widget'), (
          call,
        ) async {
          if (call.method == 'saveWidgetData') {
            final args = call.arguments as Map;
            cache[args['id'] as String] = args['data'];
          }
          return true;
        });
  });
  HomeworkItem task(
    String id, {
    DateTime? due,
    HwStatus status = HwStatus.todo,
  }) => HomeworkItem(
    id: id,
    platform: PlatformKind.manual,
    course: '计算机网络',
    title: '作业 $id',
    dueAt: due,
    status: status,
    note: '旧备注',
  );
  List<dynamic> rows() => jsonDecode(cache['items_json'] as String) as List;

  test('widget includes current-semester overdue, unknown and undated work without historic filler', () async {
    final now = DateTime.now();
    await SyncService.updateHomeWidget([
      task('past', due: DateTime(now.year, now.month, now.day)),
      task('older-semester', due: DateTime(2020)),
      task('future', due: DateTime(now.year, now.month, now.day, 23, 59)),
      task('undated'),
      task('unknown', status: HwStatus.unknown),
      task('done', status: HwStatus.done),
      task('submitted', status: HwStatus.submitted),
    ]);
    expect(rows().map((e) => e['id']).toSet(), {
      'past',
      'future',
      'undated',
      'unknown',
    });
  });
  test('widget does not truncate assignments after twenty entries', () async {
    await SyncService.updateHomeWidget(List.generate(75, (i) => task('$i')));
    expect(rows().length, 75);
  });
  test(
    'snapshot preserves exact IDs and course names for unambiguous clicks',
    () async {
      await SyncService.updateHomeWidget([task('自定义 / & ? # 📚')]);
      expect(rows().single['id'], '自定义 / & ? # 📚');
      expect(rows().single['course'], '计算机网络');
      expect(rows().single['status'], 'todo');
    },
  );
  test('publishes an atomic snapshot and retains legacy cache keys', () async {
    await SyncService.updateHomeWidget([task('a')]);
    expect(cache, contains('homework_snapshot'));
    final snapshot = jsonDecode(cache['homework_snapshot'] as String) as Map;
    expect(snapshot['version'], 2);
    expect(snapshot['items'], rows());
    expect(snapshot['updatedAt'], isA<int>());
    expect(cache, contains('stats'));
    expect(cache, contains('updated'));
  });
  test(
    'overlapping exports finish with the newest visible account data',
    () async {
      final entered = Completer<void>(), release = Completer<void>();
      var blocked = false;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel('home_widget'), (
            call,
          ) async {
            if (call.method == 'saveWidgetData') {
              final args = call.arguments as Map;
              if (args['id'] == 'items_json' && !blocked) {
                blocked = true;
                entered.complete();
                await release.future;
              }
              cache[args['id'] as String] = args['data'];
            }
            return true;
          });
      final old = SyncService.updateHomeWidget([task('old-account')]);
      await entered.future;
      final current = SyncService.updateHomeWidget([task('current-account')]);
      await Future<void>.delayed(Duration.zero);
      release.complete();
      await Future.wait([old, current]);
      expect(
        (jsonDecode(cache['homework_snapshot'] as String)['items'] as List).map(
          (e) => e['id'],
        ),
        ['current-account'],
      );
      expect(rows().map((e) => e['id']), ['current-account']);
    },
  );
  test(
    'a legacy compatibility-key failure cannot retain hidden or deleted rows',
    () async {
      await SyncService.updateHomeWidget([task('hidden'), task('keep')]);
      var updates = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel('home_widget'), (
            call,
          ) async {
            if (call.method == 'saveWidgetData') {
              final args = call.arguments as Map;
              if (args['id'] == 'stats') {
                throw PlatformException(code: 'legacy-write');
              }
              cache[args['id'] as String] = args['data'];
            }
            if (call.method == 'updateWidget') updates++;
            return true;
          });
      await SyncService.updateHomeWidget([task('keep')]);
      final snapshot = jsonDecode(cache['homework_snapshot'] as String);
      expect((snapshot['items'] as List).map((r) => r['id']), ['keep']);
      expect(updates, 1);
    },
  );

  test(
    'false atomic commit is retried before requesting a widget refresh',
    () async {
      var attempts = 0, updates = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel('home_widget'), (
            call,
          ) async {
            if (call.method == 'saveWidgetData') {
              final args = call.arguments as Map;
              if (args['id'] == 'homework_snapshot' && ++attempts == 1) {
                return false;
              }
              cache[args['id'] as String] = args['data'];
            }
            if (call.method == 'updateWidget') {
              expect(cache['homework_snapshot'], isNotNull);
              updates++;
            }
            return true;
          });
      await SyncService.updateHomeWidget([task('current')]);
      expect(attempts, 2);
      expect(updates, 1);
    },
  );

  test('failed atomic writes do not poison later widget exports', () async {
    var fail = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('home_widget'), (
          call,
        ) async {
          if (call.method == 'saveWidgetData') {
            final args = call.arguments as Map;
            if (args['id'] == 'homework_snapshot' && fail) {
              throw PlatformException(code: 'disk');
            }
            cache[args['id'] as String] = args['data'];
          }
          return true;
        });
    await SyncService.updateHomeWidget([task('old')]);
    fail = false;
    await SyncService.updateHomeWidget([task('latest')]);
    final snapshot = jsonDecode(cache['homework_snapshot'] as String);
    expect((snapshot['items'] as List).map((r) => r['id']), ['latest']);
  });

  test('widget export leaves existing homework notes, courses and hidden data unchanged', () async {
    final original = [task('keep'), task('finished', status: HwStatus.done)];
    await Storage.saveHomework(original);
    final prefs = await SharedPreferences.getInstance();
    final before = {for (final key in prefs.getKeys()) key: prefs.get(key)};
    final inputBefore = original.map((e) => jsonEncode(e.toJson())).toList();
    await SyncService.updateHomeWidget(original);
    expect({for (final key in prefs.getKeys()) key: prefs.get(key)}, before);
    expect(original.map((e) => jsonEncode(e.toJson())).toList(), inputBefore);
  });
}
