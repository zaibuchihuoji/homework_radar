import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homework_radar/services/widget_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final calls = <MethodCall>[];
  var available = true;
  var assetsReady = true;
  setUp(() {
    calls.clear();
    available = true;
    assetsReady = true;
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('homework_radar/widgets'),
      (call) async {
        if (call.method == 'group') {
          return {
            'groupId': 'group.com.worknote.homeworkRadar.TEAM',
            'available': available,
          };
        }
        if (call.method == 'prepareAssets') return assetsReady;
        if (call.method == 'initialUrl') {
          return 'homework-radar://widget/timetable?homeWidget=1';
        }
        return null;
      },
    );
    messenger.setMockMethodCallHandler(const MethodChannel('home_widget'), (
      call,
    ) async {
      calls.add(call);
      return true;
    });
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });
  test(
    'iOS uses the signed shared group and explicit WidgetKit kind',
    () async {
      expect(
        await WidgetPlatform.refresh(androidName: 'HomeworkWidgetProvider'),
        true,
      );
      expect(
        calls.first.arguments['groupId'],
        'group.com.worknote.homeworkRadar.TEAM',
      );
      expect(calls.last.arguments['ios'], 'HomeworkWidget');
      expect((await WidgetPlatform.initialUrl)?.path, '/timetable');
    },
  );
  test(
    'missing shared entitlement never reports a successful widget reload',
    () async {
      available = false;
      expect(
        await WidgetPlatform.refresh(androidName: 'TimetableWidgetProvider'),
        false,
      );
      expect(calls.where((c) => c.method == 'updateWidget'), isEmpty);
    },
  );
  test(
    'a failed optional background image cannot block fresh homework',
    () async {
      assetsReady = false;
      expect(
        await WidgetPlatform.refresh(androidName: 'HomeworkWidgetProvider'),
        true,
      );
      expect(calls.last.method, 'updateWidget');
    },
  );
  test(
    'Android keeps the existing provider and has no iOS dependency',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      expect(
        await WidgetPlatform.refresh(androidName: 'TimetableWidgetProvider'),
        true,
      );
      expect(calls.single.method, 'updateWidget');
      expect(calls.single.arguments['android'], 'TimetableWidgetProvider');
    },
  );
}
