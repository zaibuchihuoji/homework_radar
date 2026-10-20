import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homework_radar/pages/update_dialog.dart';
import 'package:homework_radar/services/app_update_controller.dart';
import 'package:homework_radar/services/update_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('homework_radar/updater');
  final calls = <String>[];
  var task = <String, dynamic>{'phase': 'idle'};
  Map<dynamic, dynamic>? startArgs;
  final controller = AppUpdateController.instance;
  setUp(() {
    calls.clear();
    startArgs = null;
    task = {'phase': 'idle'};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call.method);
          switch (call.method) {
            case 'device':
              return ['arm64-v8a'];
            case 'consumeOpen':
              return false;
            case 'start':
              startArgs = call.arguments as Map;
              task = {
                'phase': 'downloading',
                'version': '1.2.0',
                'bytes': 25,
                'total': 100,
                'source': 'Gitee',
              };
            case 'cancel':
              task = {'phase': 'idle'};
          }
          return task;
        });
  });
  tearDown(() async {
    await controller.cancel();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('unknown-length progress is indeterminate; waiting and failure remain explicit', () {
    expect(
      const UpdateDownloadStatus({
        'phase': 'downloading',
        'bytes': 20,
        'total': -1,
      }).progress,
      isNull,
    );
    expect(
      const UpdateDownloadStatus({
        'phase': 'downloading',
        'bytes': 200,
        'total': 100,
      }).progress,
      1,
    );
    expect(const UpdateDownloadStatus({'phase': 'paused'}).active, true);
    expect(
      const UpdateDownloadStatus({'phase': 'failed', 'retryable': false})
          .retryable,
      false,
    );
  });

  testWidgets(
    'closing progress keeps the native task; reopening restores ready/install',
    (tester) async {
      await controller.initialize();
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showAppUpdateDialog(
                  context,
                  info: const UpdateInfo(
                    version: '1.2.0',
                    releaseUrl: '',
                    apkUrl: 'https://gitee.com/zaibuchihuoji/homework_radar/releases/download/v1.2.0/app-arm64-v8a-release.apk',
                    fallbackApkUrl: 'https://github.com/zaibuchihuoji/homework_radar/releases/download/v1.2.0/app-arm64-v8a-release.apk',
                    notes: '更新说明',
                    apkSize: 100,
                  ),
                ),
                child: const Text('更新'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('更新'));
      await tester.pumpAndSettle();
      expect(find.text('发现新版本'), findsOneWidget);
      expect(find.text('0.0 MB · Gitee'), findsOneWidget);
      await tester.tap(find.text('下载更新'));
      await tester.pump();
      expect(find.text('正在下载 25%'), findsOneWidget);
      expect(
        startArgs!['fallbackUrl'],
        'https://github.com/zaibuchihuoji/homework_radar/releases/download/v1.2.0/app-arm64-v8a-release.apk',
      );
      task = {...task, 'source': 'GitHub', 'switchedSource': true, 'bytes': 50};
      await controller.refresh();
      await tester.pump();
      expect(find.text('正在下载 50%'), findsOneWidget);
      expect(find.text('已自动切换到 GitHub'), findsOneWidget);
      await tester.tap(find.text('后台下载'));
      await tester.pumpAndSettle();
      expect(calls.where((c) => c == 'start').length, 1);
      expect(calls, isNot(contains('cancel')));
      expect(controller.status.phase, 'downloading');
      task = {'phase': 'ready', 'version': '1.2.0', 'total': 100};
      await controller.refresh();
      await tester.tap(find.text('更新'));
      await tester.pumpAndSettle();
      expect(find.text('立即安装'), findsOneWidget);
      expect(find.text('删除安装包'), findsOneWidget);
      await tester.tap(find.text('立即安装'));
      await tester.pump();
      expect(calls.where((c) => c == 'install').length, 1);
      await tester.tap(find.text('稍后'));
      await tester.pumpAndSettle();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets(
    'failed transfer retries and explicit cancel only clears download',
    (tester) async {
      task = {
        'phase': 'failed',
        'version': '1.2.0',
        'error': '下载中断，请重试',
        'retryable': true,
      };
      await controller.refresh();
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showAppUpdateDialog(context),
                child: const Text('更新'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('更新'));
      await tester.pumpAndSettle();
      expect(find.text('下载中断，请重试'), findsOneWidget);
      await tester.tap(find.text('重试下载'));
      await tester.pump();
      expect(calls, contains('retry'));
      await tester.tap(find.text('取消下载'));
      await tester.pumpAndSettle();
      expect(calls, contains('cancel'));
      expect(controller.status.phase, 'idle');
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );
}
