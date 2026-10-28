import 'dart:io';

import 'support/safe_temp_directory.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homework_radar/models/homework.dart';
import 'package:homework_radar/services/notification_service.dart';
import 'package:homework_radar/services/storage.dart';
import 'package:homework_radar/services/study_note_store.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _SupportPath extends PathProviderPlatform {
  _SupportPath(this.path);
  final String path;
  @override
  Future<String?> getApplicationSupportPath() async => path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final calls = <MethodCall>[];
  late Directory root;
  late PathProviderPlatform previous;
  final now = DateTime.now().add(const Duration(days: 1));

  setUp(() async {
    root = await Directory.systemTemp.createTemp('note_alarm_');
    previous = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _SupportPath(root.path);
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    FlutterLocalNotificationsPlatform.instance =
        AndroidFlutterLocalNotificationsPlugin();
    SharedPreferences.setMockInitialValues({});
    await Storage.init();
    await Storage.setFlag('note_store_used', true);
    await Storage.saveReminders(
      ReminderSettings(before24h: false, before6h: false),
    );
    NotificationService.clock = () => now;
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('dexterous.com/flutter/local_notifications'),
          (call) async {
            calls.add(call);
            if (call.method == 'pendingNotificationRequests') {
              return <Map<String, Object?>>[];
            }
            return true;
          },
        );
  });
  tearDown(() async {
    debugDefaultTargetPlatformOverride = null;
    NotificationService.clock = DateTime.now;
    PathProviderPlatform.instance = previous;
    await deleteTestDirectory(root);
  });

  test('homework and note reminders are both scheduled', () async {
    final store = await StudyNoteStore.openDefault();
    await store.saveNotes([
      {
        'id': 'n',
        'title': '线代',
        'reminder': {
          'at': now.add(const Duration(minutes: 30)).millisecondsSinceEpoch,
          'repeat': 'none',
          'token': 'one',
        },
      },
    ]);
    final homework = HomeworkItem(
      id: 'h',
      platform: PlatformKind.manual,
      course: '数学',
      title: '作业',
      dueAt: now.add(const Duration(hours: 2)),
    );
    await NotificationService.reschedule([homework]);
    final payloads = calls
        .where((c) => c.method == 'zonedSchedule')
        .map((c) => (c.arguments as Map)['payload'] as String)
        .toList();
    expect(payloads.any((p) => p.startsWith('homework-reminder:')), isTrue);
    expect(
      payloads.any((p) => NotificationService.studyNoteId(p) == 'n'),
      isTrue,
      reason:
          'payloads=$payloads, schedule=${NotificationService.studySchedule.value}, error=${NotificationService.scheduleError.value}',
    );
  });

  test('unreadable note data never cancels existing reminders', () async {
    await expectLater(
      NotificationService.reschedule([]),
      throwsFormatException,
    );
    expect(
      calls.where((c) => c.method == 'cancelAll' || c.method == 'cancel'),
      isEmpty,
    );
  });
  test('malformed note payload is still recognized as a note notification', () {
    expect(
      NotificationService.isStudyPayload('study-note-reminder:{broken'),
      isTrue,
    );
    expect(
      NotificationService.studyNoteId('study-note-reminder:{broken'),
      isNull,
    );
  });

  test('iOS notes do not displace 64 existing homework reminders', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    FlutterLocalNotificationsPlatform.instance =
        IOSFlutterLocalNotificationsPlugin();
    await Storage.saveClassReminder(false);
    final store = await StudyNoteStore.openDefault();
    await store.saveNotes([
      {
        'id': 'n',
        'reminder': {
          'at': now.add(const Duration(minutes: 30)).millisecondsSinceEpoch,
          'repeat': 'none',
          'token': 'one',
        },
      },
    ]);
    final homework = [
      for (var i = 1; i <= 64; i++)
        HomeworkItem(
          id: 'h$i',
          platform: PlatformKind.manual,
          course: '数学',
          title: '作业$i',
          dueAt: now.add(Duration(hours: i + 1)),
        ),
    ];
    await NotificationService.reschedule(homework);
    final payloads = calls
        .where((c) => c.method == 'zonedSchedule')
        .map((c) => (c.arguments as Map)['payload'] as String)
        .toList();
    expect(
      payloads.where((p) => p.startsWith('homework-reminder:')),
      hasLength(64),
    );
    expect(
      payloads.where((p) => NotificationService.studyNoteId(p) != null),
      isEmpty,
    );
    expect(NotificationService.studySchedule.value, contains('未安排'));
  });
}
