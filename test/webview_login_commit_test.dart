import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homework_radar/app_state.dart';
import 'package:homework_radar/models/homework.dart';
import 'package:homework_radar/pages/webview_login_page.dart';
import 'package:homework_radar/ui/tokens.dart';
// ignore: depend_on_referenced_packages
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

import 'support/synthetic_http.dart';

class _Controller extends PlatformWebViewController {
  _Controller(super.params, this.url) : super.implementation();
  final String url;
  @override
  Future<void> setJavaScriptMode(JavaScriptMode mode) async {}
  @override
  Future<void> setPlatformNavigationDelegate(
    PlatformNavigationDelegate delegate,
  ) async {}
  @override
  Future<void> loadRequest(LoadRequestParams params) async {}
  @override
  Future<String?> currentUrl() async => url;
}

class _Navigation extends PlatformNavigationDelegate {
  _Navigation(super.params) : super.implementation();
  @override
  Future<void> setOnPageFinished(PageEventCallback callback) async {}
}

class _View extends PlatformWebViewWidget {
  _View(super.params) : super.implementation();
  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}

class _WebPlatform extends WebViewPlatform {
  _WebPlatform(this.url);
  final String url;
  @override
  PlatformWebViewController createPlatformWebViewController(
    PlatformWebViewControllerCreationParams params,
  ) => _Controller(params, url);
  @override
  PlatformNavigationDelegate createPlatformNavigationDelegate(
    PlatformNavigationDelegateCreationParams params,
  ) => _Navigation(params);
  @override
  PlatformWebViewWidget createPlatformWebViewWidget(
    PlatformWebViewWidgetCreationParams params,
  ) => _View(params);
}

/// The controlled boundary is AppState's durable login commit, not the page.
/// Real cookie capture, service checks, navigation and error rendering still run.
class _LoginState extends AppState {
  Completer<void> commit = Completer<void>();
  int attempts = 0;
  int syncCalls = 0;
  final syncArguments = <bool>[];
  Future<void> _save(bool sync) {
    attempts++;
    syncArguments.add(sync);
    return commit.future;
  }

  @override
  Future<void> onChaoxingLogin(
    String cookie,
    String? uid, {
    bool sync = true,
  }) => _save(sync);
  @override
  Future<void> onMoocLogin(String cookie, String csrf, {bool sync = true}) =>
      _save(sync);
  @override
  Future<void> loginZhihuishu(String cookie, {bool sync = true}) => _save(sync);
  @override
  Future<void> loginXuetangx(String cookie, {bool sync = true}) => _save(sync);
  @override
  Future<void> loginYuketang(String cookie, {bool sync = true}) => _save(sync);
  @override
  Future<String> syncAll() async {
    syncCalls++;
    return '';
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final network = SyntheticHttp();
  setUpAll(() {
    HttpOverrides.global = network;
  });
  tearDownAll(() {
    HttpOverrides.global = null;
  });
  setUp(() {
    network.handler = (_, uri, _) => uri.host.endsWith('icourse163.org')
        ? SyntheticResponse('{"code":0,"result":[]}')
        : SyntheticResponse('{"code":0,"result":{},"data":{"list":[]}}');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('homework_radar/platform'),
          (call) async {
            if (call.method == 'getCookie') {
              return 'UID=123; _uid=123; STUDY_SESS=synthetic; NTESSTUDYSI=synthetic-csrf';
            }
            return true;
          },
        );
  });
  const urls = {
    PlatformKind.chaoxing: 'https://mooc1.chaoxing.com/',
    PlatformKind.mooc: 'https://www.icourse163.org/home.htm',
    PlatformKind.zhihuishu: 'https://onlineservice.zhihuishu.com/',
    PlatformKind.xuetangx: 'https://www.xuetangx.com/',
    PlatformKind.yuketang: 'https://www.yuketang.cn/web',
  };

  Future<void> advance(WidgetTester tester) async {
    // Login intentionally shows an indeterminate progress indicator. Bound pumps
    // to the route transition instead of waiting for all animations to settle.
    // Current Android PredictiveBack/FadeForwards transition lasts 450 ms.
    // Include a frame after dismissal so the route subtree is removed.
    for (var frame = 0; frame < 14; frame++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> open(
    WidgetTester tester,
    PlatformKind platform,
    _LoginState state,
  ) async {
    WebViewPlatform.instance = _WebPlatform(urls[platform]!);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          extensions: [stylePalette(ThemeStyle.clean, Brightness.light)],
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      WebviewLoginPage(platform: platform, state: state),
                ),
              ),
              child: const Text('open login'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open login'));
    await advance(tester);
  }

  for (final platform in urls.keys) {
    testWidgets(
      '${platform.name} waits for durable login commit before reporting success',
      (tester) async {
        final state = _LoginState();
        await open(tester, platform, state);
        await tester.tap(find.text('检测'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(state.attempts, 1);
        expect(find.byType(WebviewLoginPage), findsOneWidget);
        expect(state.syncCalls, 0);
        state.commit.complete();
        await advance(tester);
        expect(find.byType(WebviewLoginPage), findsNothing);
        expect(state.syncArguments, [false]);
        expect(state.syncCalls, 1);
      },
    );

    testWidgets(
      '${platform.name} keeps save failure visible and permits retry',
      (tester) async {
        final state = _LoginState();
        await open(tester, platform, state);
        await tester.tap(find.text('检测'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.byType(WebviewLoginPage), findsOneWidget);
        state.commit.completeError(
          StateError('synthetic archive/save failure'),
        );
        await advance(tester);
        expect(find.byType(WebviewLoginPage), findsOneWidget);
        expect(find.textContaining('本地保存'), findsOneWidget);
        expect(find.text('未检测到登录态，请先在页面中完成登录'), findsNothing);
        expect(state.syncCalls, 0);
        state.commit = Completer<void>();
        await tester.tap(find.text('检测'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(state.attempts, 2);
        state.commit.complete();
        await advance(tester);
        expect(find.byType(WebviewLoginPage), findsNothing);
        expect(state.syncCalls, 1);
      },
    );
  }
}
