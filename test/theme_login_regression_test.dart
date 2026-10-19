import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homework_radar/app_state.dart';
import 'package:homework_radar/models/homework.dart';
import 'package:homework_radar/pages/jw_setup_page.dart';
import 'package:homework_radar/pages/webview_login_page.dart';
import 'package:homework_radar/pages/zf_login_page.dart';
import 'package:homework_radar/services/timetable_parser.dart';
import 'package:webview_flutter/webview_flutter.dart' show WebViewWidget;
import 'package:homework_radar/services/jw_config.dart';
import 'package:homework_radar/services/storage.dart';
import 'package:homework_radar/ui/tokens.dart';
import 'package:shared_preferences/shared_preferences.dart';
// ignore: depend_on_referenced_packages
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

class _Controller extends PlatformWebViewController {
  _Controller(super.params) : super.implementation();
  @override
  Future<void> setJavaScriptMode(JavaScriptMode mode) async {}
  @override
  Future<void> setPlatformNavigationDelegate(
    PlatformNavigationDelegate delegate,
  ) async {}
  @override
  Future<void> loadRequest(LoadRequestParams params) async {}
  @override
  Future<String?> currentUrl() async => 'https://mooc1.chaoxing.com/';
  @override
  Future<Object> runJavaScriptReturningResult(String script) async =>
      script == TimetableParser.hasTimetableJs
      ? 1
      : 'malformed-synthetic-table';
}

class _Navigation extends PlatformNavigationDelegate {
  _Navigation(super.params) : super.implementation();
  @override
  Future<void> setOnPageFinished(PageEventCallback callback) async {}
  @override
  Future<void> setOnWebResourceError(WebResourceErrorCallback callback) async {}
}

class _View extends PlatformWebViewWidget {
  _View(super.params) : super.implementation();
  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}

class _Platform extends WebViewPlatform {
  @override
  PlatformWebViewController createPlatformWebViewController(
    PlatformWebViewControllerCreationParams params,
  ) => _Controller(params);
  @override
  PlatformNavigationDelegate createPlatformNavigationDelegate(
    PlatformNavigationDelegateCreationParams params,
  ) => _Navigation(params);
  @override
  PlatformWebViewWidget createPlatformWebViewWidget(
    PlatformWebViewWidgetCreationParams params,
  ) => _View(params);
}

class _LoginState extends AppState {
  Completer<void> commit = Completer<void>();
  @override
  Future<void> onChaoxingLogin(
    String cookie,
    String? uid, {
    bool sync = true,
  }) => commit.future;
  @override
  Future<String> syncAll() async => '';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  var cookie = '';
  final routeResults = <Object?>[];
  setUp(() async {
    cookie = '';
    routeResults.clear();
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('homework_radar/platform'),
          (call) async {
            if (call.method == 'getCookie') return cookie;
            return null;
          },
        );
    await Storage.init();
    WebViewPlatform.instance = _Platform();
  });
  Future<void> advance(WidgetTester tester) async {
    for (var i = 0; i < 14; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Widget app(
    ThemeStyle style,
    Widget page, {
    Brightness brightness = Brightness.light,
  }) => MaterialApp(
    theme: ThemeData(
      brightness: brightness,
      extensions: [stylePalette(style, brightness)],
    ),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: const TextScaler.linear(1.4)),
      child: child!,
    ),
    home: Builder(
      builder: (context) => Scaffold(
        body: TextButton(
          onPressed: () async {
            routeResults.add(
              await Navigator.of(
                context,
              ).push<Object?>(MaterialPageRoute<Object?>(builder: (_) => page)),
            );
          },
          child: const Text('open'),
        ),
      ),
    ),
  );
  for (final style in ThemeStyle.values.where(
    (s) => !stylePalette(s, Brightness.light).clean,
  )) {
    testWidgets(
      '${style.name} login keeps status legible and retry distinct from commit failure',
      (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final state = _LoginState();
        await tester.pumpWidget(
          app(
            style,
            WebviewLoginPage(platform: PlatformKind.chaoxing, state: state),
            brightness: Brightness.dark,
          ),
        );
        await tester.tap(find.text('open'));
        await advance(tester);
        tester.view.viewInsets = const FakeViewPadding(bottom: 220);
        addTearDown(tester.view.resetViewInsets);
        await tester.pump();
        expect(
          tester.getSize(find.byType(WebViewWidget)).height,
          greaterThan(140),
        );
        final status = tester.widget<Text>(find.text('请在页面中登录你的账号'));
        expect(status.style?.color, stylePalette(style, Brightness.dark).ink2);
        await tester.tap(find.text('检测'));
        await advance(tester);
        expect(find.text('未检测到登录态，请先在页面中完成登录'), findsOneWidget);
        cookie = 'UID=123; _uid=123';
        await tester.tap(find.text('检测'));
        await tester.pump();
        expect(find.text('正在保存登录状态…'), findsOneWidget);
        state.commit.completeError(StateError('synthetic save failure'));
        await advance(tester);
        expect(find.textContaining('本地保存或归档失败'), findsOneWidget);
        expect(find.text('未检测到登录态，请先在页面中完成登录'), findsNothing);
        expect(tester.takeException(), isNull);
        state.commit = Completer<void>();
        await tester.tap(find.text('检测'));
        await tester.pump();
        state.commit.complete();
        await advance(tester);
        expect(find.byType(WebviewLoginPage), findsNothing);
      },
    );
    testWidgets(
      '${style.name} timetable parsing error keeps text fallback reachable above keyboard',
      (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await JwStore.save(
          const JwConfig(name: '合成学校', url: 'https://jw.synthetic.edu.cn/'),
        );
        await tester.pumpWidget(
          app(style, const ZfLoginPage(), brightness: Brightness.dark),
        );
        await tester.tap(find.text('open'));
        await advance(tester);
        tester.view.viewInsets = const FakeViewPadding(bottom: 220);
        addTearDown(tester.view.resetViewInsets);
        await tester.pump();
        await tester.tap(find.text('检测'));
        await advance(tester);
        expect(find.textContaining('课表解析失败'), findsOneWidget);
        expect(
          tester.getSize(find.byType(WebViewWidget)).height,
          greaterThan(140),
        );
        await tester.ensureVisible(find.text('粘贴文本导入'));
        await tester.tap(find.text('粘贴文本导入'));
        await advance(tester);
        expect(routeResults.last, ZfExit.openTextImport);
        expect(find.byType(ZfLoginPage), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
    testWidgets(
      '${style.name} setup deletion requires confirmation and cancel preserves configuration',
      (tester) async {
        const config = JwConfig(
          name: '合成学校',
          url: 'https://jw.synthetic.edu.cn/',
        );
        await JwStore.save(config);
        await tester.pumpWidget(app(style, const JwSetupPage(initial: config)));
        await tester.tap(find.text('open'));
        await advance(tester);
        await tester.ensureVisible(find.text('删除该教务配置'));
        await tester.tap(find.text('删除该教务配置'));
        await advance(tester);
        await tester.tap(find.text('取消'));
        await advance(tester);
        expect(JwStore.load()?.url, 'https://jw.synthetic.edu.cn/');
        expect(find.byType(JwSetupPage), findsOneWidget);
        await tester.tap(find.text('删除该教务配置'));
        await advance(tester);
        await tester.tap(find.text('删除'));
        await advance(tester);
        expect(JwStore.load(), isNull);
        expect(Storage.jwConfigRaw(), '');
        expect(find.byType(JwSetupPage), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
    testWidgets(
      '${style.name} setup validates URL and preserves save and cancel at narrow width',
      (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(app(style, const JwSetupPage()));
        await tester.tap(find.text('open'));
        await advance(tester);
        await tester.enterText(find.byType(TextField).last, 'invalid');
        await tester.pump();
        await tester.ensureVisible(find.text('下一步：登录教务'));
        await tester.tap(find.text('下一步：登录教务'));
        await advance(tester);
        expect(find.textContaining('网址看起来不对'), findsOneWidget);
        expect(Storage.jwConfigRaw(), isNull);
        await tester.enterText(
          find.byType(TextField).last,
          'jw.synthetic.edu.cn',
        );
        await tester.pump();
        await tester.ensureVisible(find.text('下一步：登录教务'));
        await tester.tap(find.text('下一步：登录教务'));
        await advance(tester);
        expect(JwStore.load()?.url, 'https://jw.synthetic.edu.cn');
        expect(JwStore.load()?.name, 'jw.synthetic.edu.cn');
        expect(find.byType(JwSetupPage), findsNothing);
        await tester.tap(find.text('open'));
        await advance(tester);
        await tester.enterText(
          find.byType(TextField).last,
          'changed.synthetic.edu.cn',
        );
        await tester.pageBack();
        await advance(tester);
        expect(JwStore.load()?.url, 'https://jw.synthetic.edu.cn');
        expect(tester.takeException(), isNull);
      },
    );
  }
}
