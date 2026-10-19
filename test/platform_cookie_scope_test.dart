import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homework_radar/services/platform_cookie.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'logout deletes only selected platform domains without reseeding others',
    () async {
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('homework_radar/platform'),
            (call) async {
              calls.add(call);
              return true;
            },
          );
      await PlatformCookie.clearPlatformCookies('mooc');
      expect(calls.length, 1);
      expect(calls.single.method, 'clearDomainCookies');
      final args = calls.single.arguments as Map;
      expect(args['domains'], ['icourse163.org']);
      expect(
        (args['origins'] as List).every(
          (url) => Uri.parse(url as String).host.endsWith('icourse163.org'),
        ),
        isTrue,
      );
    },
  );
}
