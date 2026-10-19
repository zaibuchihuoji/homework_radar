import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homework_radar/pages/zf_login_page.dart';
import 'package:homework_radar/services/jw_config.dart';
import 'package:homework_radar/services/storage.dart';
import 'package:homework_radar/ui/tokens.dart';
import 'package:shared_preferences/shared_preferences.dart';
// The fake exercises the public WebView boundary without starting a native browser.
// ignore: depend_on_referenced_packages
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

class _Controller extends PlatformWebViewController {
  _Controller(super.params, this.events) : super.implementation();
  final List<String> events;
  @override
  Future<void> setJavaScriptMode(JavaScriptMode mode) async {}
  @override
  Future<void> setPlatformNavigationDelegate(
    PlatformNavigationDelegate handler,
  ) async {}
  @override
  Future<void> loadRequest(LoadRequestParams params) async {
    events.add('load');
  }
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
  _Platform(this.events);
  final List<String> events;
  @override
  PlatformWebViewController createPlatformWebViewController(
    PlatformWebViewControllerCreationParams params,
  ) => _Controller(params, events);
  @override
  PlatformNavigationDelegate createPlatformNavigationDelegate(
    PlatformNavigationDelegateCreationParams params,
  ) => _Navigation(params);
  @override
  PlatformWebViewWidget createPlatformWebViewWidget(
    PlatformWebViewWidgetCreationParams params,
  ) => _View(params);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final events = <String>[];
  final secure = <String, String>{};
  setUp(() async {
    events.clear();
    secure.clear();
    WebViewPlatform.instance = _Platform(events);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('homework_radar/platform'),
          (call) async {
            final args = (call.arguments as Map?) ?? {};
            if (call.method == 'secureRead') return secure[args['key']];
            if (call.method == 'clearDomainCookies') {
              expect(args['domains'], ['jw.test.edu.cn']);
              events.add('clear');
              return true;
            }
            return null;
          },
        );
    SharedPreferences.setMockInitialValues({
      'jw_config': const JwConfig(
        name: '合成学校',
        url: 'https://jw.test.edu.cn/',
      ).encode(),
    });
    await Storage.init();
  });
  Widget app() => MaterialApp(
    theme: ThemeData(
      extensions: [stylePalette(ThemeStyle.clean, Brightness.light)],
    ),
    home: const ZfLoginPage(),
  );
  testWidgets('new school login clears only the target school before loading', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await tester.pump();
    await tester.pump();
    expect(events, ['clear', 'load']);
  });
  testWidgets(
    'normal timetable recapture preserves the existing school session',
    (tester) async {
      secure['zf_cookie'] = 'synthetic-session';
      await tester.runAsync(Storage.init);
      await tester.pumpWidget(app());
      await tester.pump();
      await tester.pump();
      expect(events, ['load']);
    },
  );
  testWidgets(
    'changed school clears its cookie jar even while previous school credential remains',
    (tester) async {
      secure['zf_cookie'] = 'old-school-session';
      await Storage.saveTimetableSource('old.edu.cn#A');
      await tester.runAsync(Storage.init);
      await tester.pumpWidget(app());
      await tester.pump();
      await tester.pump();
      expect(events, ['clear', 'load']);
    },
  );
}
