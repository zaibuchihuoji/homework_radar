import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:homework_radar/models/homework.dart';
import 'package:homework_radar/services/chaoxing_service.dart';
import 'package:homework_radar/services/secure_store.dart';
import 'package:homework_radar/services/storage.dart';
import 'package:homework_radar/services/sync_service.dart';

import 'support/synthetic_http.dart';

// Structure reduced from an existing captured real CX empty-exam response.
// All account parameters, scripts and personal course information are removed.
const emptyExamPage = '''
<!doctype html><html><head><title>考试列表</title></head><body>
<div class="box"><div class="content"><div class="main task-list">
  <div class="has-content"><div class="null-data">暂无考试</div></div>
</div></div></div></body></html>
''';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final network = SyntheticHttp();
  final secrets = <String, String>{};
  AndroidFlutterLocalNotificationsPlugin.registerWith();
  var examBody = emptyExamPage;
  var examStatus = 200;

  setUpAll(() => HttpOverrides.global = network);
  tearDownAll(() => HttpOverrides.global = null);
  setUp(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
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
    for (final key in [
      'cx_cookie',
      'cx_uid',
      'mooc_cookie',
      'mooc_csrf',
      'zhs_cookie',
      'xtx_cookie',
      'ykt_cookie',
      'zf_cookie',
    ]) {
      await SecureStore.delete(key);
    }
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('dexterous.com/flutter/local_notifications'),
          (_) async => true,
        );
    SharedPreferences.setMockInitialValues({});
    await Storage.init();
    examBody = emptyExamPage;
    examStatus = 200;
    SyntheticResponse html(String body, [int status = 200]) =>
        SyntheticResponse(body, status, {
          'content-type': 'text/html; charset=utf-8',
        });
    network.handler = (_, uri, _) {
      if (uri.path.endsWith('/backclazzdata')) {
        return html('{"result":1}');
      }
      if (uri.path.endsWith('/courses/list')) {
        return html(
          '<li class="course"><a href="https://mooc1.chaoxing.com/course">'
          '<span class="course-name">示例课程</span></a></li>',
        );
      }
      if (uri.path == '/course') {
        return html(
          '<input id="courseid" value="1"><input id="clazzid" value="2">'
          '<input id="oldenc" value="synthetic-old">'
          '<input id="enc" value="synthetic-plain"><input id="t" value="123">',
        );
      }
      if (uri.path.contains('getAllWork')) {
        return html(
          '<div class="ulDiv"><li><div class="titTxt">'
          '<a data="8">本次更新的作业</a></div></li></div>',
        );
      }
      return html(examBody, examStatus);
    };
  });

  test(
    'real CX no-exam template is complete and keeps fetched homework',
    () async {
      final service = ChaoxingService(cookie: 'synthetic');
      final items = await service.allHomework();
      expect(items.single.title, '本次更新的作业');
      expect(service.listFailed, isFalse);
      expect(service.failedCount, 0);
    },
  );

  for (final response in [
    '<html><title>登录</title><body>请先登录</body></html>',
    '<html><title>考试列表</title><script>const empty="暂无考试";</script></html>',
    '<html><title>考试列表</title><body>暂无考试</body></html>',
    '<html><title>提示</title><div class="task-list"><div class="has-content">'
        '<div class="null-data">暂无考试</div></div></div></html>',
  ]) {
    test(
      'HTTP 200 unrecognized exam response still fails: $response',
      () async {
        examBody = response;
        final service = ChaoxingService(cookie: 'synthetic');
        final items = await service.allHomework();
        expect(items.single.title, '本次更新的作业');
        expect(service.failedCount, 1);
      },
    );
  }

  test('non-200 response cannot authorize an empty exam list', () async {
    examStatus = 503;
    final service = ChaoxingService(cookie: 'synthetic');
    await service.allHomework();
    expect(service.failedCount, 1);
  });

  test('normal empty exams do not produce the partial-sync banner', () async {
    await Storage.saveChaoxing(cookie: 'synthetic', uid: 'synthetic-user');
    final result = await SyncService.run();
    expect(result.partial, isFalse);
    expect(result.message, isEmpty);
    expect(result.items.single.title, '本次更新的作业');
  });

  test(
    'real exam failure names the course and preserves the old exam',
    () async {
      examStatus = 503;
      await Storage.saveChaoxing(cookie: 'synthetic', uid: 'synthetic-user');
      await Storage.saveHomework([
        HomeworkItem(
          id: 'cxe_old',
          platform: PlatformKind.chaoxing,
          course: '示例课程',
          title: '之前的考试',
          sourceKey: 'cx|1|2|exam|9',
        ),
      ]);
      final result = await SyncService.run();
      expect(result.partial, isTrue);
      expect(result.items.map((item) => item.title), contains('之前的考试'));
      expect(result.message, contains('示例课程'));
      expect(result.message, contains('考试列表'));
      expect(result.message, isNot(contains('synthetic-old')));
      expect(result.message, isNot(contains('synthetic-plain')));
    },
  );
}
