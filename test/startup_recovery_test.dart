import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:homework_radar/main.dart' as app;
import 'package:homework_radar/models/homework.dart';
import 'package:homework_radar/app_state.dart';
import 'package:homework_radar/pages/settings_page.dart';
import 'package:homework_radar/pages/startup_recovery_page.dart';
import 'package:homework_radar/services/storage.dart';
import 'package:homework_radar/services/study_note_store.dart';
import 'package:homework_radar/services/study_note_bundle.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:homework_radar/ui/tokens.dart';

class _RecordingPicker extends FilePickerPlatform {
  Uint8List? saved;
  FileType? requestedType;

  @override
  Future<List<PlatformFile>> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    int compressionQuality = 0,
    AndroidOptions androidOptions = const AndroidOptions(),
    DarwinOptions darwinOptions = const DarwinOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async {
    requestedType = type;
    return [];
  }

  @override
  Future<Uri?> saveFile({
    required String fileName,
    required Uint8List bytes,
    required String mimeType,
    String? dialogTitle,
    String? initialDirectory,
    Function(FilePickerStatus)? onFileSaving,
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async {
    saved = bytes;
    return Uri.parse('content://test/backup.json');
  }
}

class _SupportPath extends PathProviderPlatform {
  _SupportPath(this.path);
  final String path;
  @override
  Future<String?> getApplicationSupportPath() async => path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  AndroidFlutterLocalNotificationsPlugin.registerWith();
  late Directory support;
  late PathProviderPlatform oldProvider;
  setUp(() async {
    support = await Directory.systemTemp.createTemp('startup_recovery_');
    oldProvider = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _SupportPath(support.path);
  });
  tearDown(() async {
    PathProviderPlatform.instance = oldProvider;
    await support.delete(recursive: true);
  });

  testWidgets(
    'secure storage failure exposes read-only data and retry without deleting credentials',
    (tester) async {
      var failRead = true;
      var foreground = false;
      var writes = 0;
      final previousPicker = FilePickerPlatform.instance;
      final picker = _RecordingPicker();
      FilePickerPlatform.instance = picker;
      addTearDown(() => FilePickerPlatform.instance = previousPicker);
      final secrets = <String, String>{};
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        const MethodChannel('homework_radar/platform'),
        (call) async {
          final args = call.arguments as Map?;
          if (call.method == 'secureRead') {
            if (failRead) throw PlatformException(code: 'secure');
            return secrets[args?['key']];
          }
          if (call.method == 'secureWrite') {
            writes++;
            secrets[args?['key']] = args?['value'];
          }
          if (call.method == 'secureDelete') {
            writes++;
            secrets.remove(args?['key']);
          }
          return true;
        },
      );
      messenger.setMockMethodCallHandler(
        const MethodChannel('homework_radar/background_sync'),
        (call) async => call.method == 'ready' ? foreground : true,
      );
      messenger.setMockMethodCallHandler(
        const MethodChannel('home_widget'),
        (call) async => true,
      );
      messenger.setMockMethodCallHandler(
        const MethodChannel('dexterous.com/flutter/local_notifications'),
        (call) async {
          if (call.method == 'pendingNotificationRequests') {
            return <Map<String, Object?>>[];
          }
          if (call.method == 'getNotificationAppLaunchDetails') return null;
          return true;
        },
      );
      final item = HomeworkItem(
        id: 'manual_kept',
        platform: PlatformKind.manual,
        course: '数学',
        title: '本地作业',
      );
      SharedPreferences.setMockInitialValues({
        'homework_json': jsonEncode([item.toJson()]),
        'cx_cookie': 'synthetic-legacy-credential',
        'sync_status_v1': jsonEncode({
          'chaoxing': {'outcome': 'loginExpired'},
        }),
      });
      app.showSplashOnStart = false;
      await tester.pumpWidget(const SizedBox());
      final previousFlutterError = FlutterError.onError;
      final previousPlatformError = ui.PlatformDispatcher.instance.onError;
      unawaited(app.main());
      FlutterError.onError = previousFlutterError;
      ui.PlatformDispatcher.instance.onError = previousPlatformError;
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump();
      expect(find.textContaining('安全存储暂不可用'), findsNothing);
      Future<Object?> sendToDart(MethodCall call) async {
        final response = Completer<ByteData?>();
        messenger.handlePlatformMessage(
          'homework_radar/background_sync',
          const StandardMethodCodec().encodeMethodCall(call),
          response.complete,
        );
        await tester.pump();
        return const StandardMethodCodec().decodeEnvelope(
          (await response.future)!,
        );
      }

      expect(await sendToDart(const MethodCall('run', 'reminders')), false);
      foreground = true;
      expect(await sendToDart(const MethodCall('foreground', true)), true);
      await tester.pump();
      expect(find.textContaining('安全存储暂不可用'), findsOneWidget);
      expect(find.text('本地作业'), findsOneWidget);
      expect(find.text('导出本地备份'), findsOneWidget);
      expect(writes, 0);
      expect(
        (await SharedPreferences.getInstance()).getString('cx_cookie'),
        'synthetic-legacy-credential',
      );
      await tester.runAsync(() async {
        await tester.tap(find.text('导出本地备份'));
        final deadline = DateTime.now().add(const Duration(seconds: 15));
        while (picker.saved == null && DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          await tester.pump(const Duration(milliseconds: 20));
        }
      });
      expect(picker.saved, isNotNull);
      final exported = StudyNoteBundle.decode(picker.saved!).businessJson;
      expect(jsonDecode(exported)['homework'][0]['id'], 'manual_kept');
      expect(exported, isNot(contains('synthetic-legacy-credential')));
      await tester.tap(find.text('重试'));
      await tester.pump();
      await tester.pump();
      expect(find.text('暂时无法恢复访问，请稍后重试。'), findsOneWidget);
      expect(writes, 0);
      failRead = false;
      await tester.tap(find.text('重试'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump();
      expect(find.textContaining('安全存储暂不可用'), findsNothing);
      expect(find.text('本地作业'), findsWidgets);
      await app.backgroundSyncForApp!.run('resume');
      app.backgroundSyncForApp!.dispose();
      await tester.pumpWidget(const SizedBox());
      app.appStateForHome!.dispose();
    },
  );
  testWidgets('backup picker permits private backup extensions', (
    tester,
  ) async {
    final previousPicker = FilePickerPlatform.instance;
    final picker = _RecordingPicker();
    FilePickerPlatform.instance = picker;
    addTearDown(() => FilePickerPlatform.instance = previousPicker);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('homework_radar/platform'),
          (_) async => null,
        );
    SharedPreferences.setMockInitialValues({});
    await Storage.init();
    final state = AppState();
    await tester.pumpWidget(
      MaterialApp(
        theme: app.buildTheme(Brightness.light, ThemeStyle.clean),
        home: SettingsPage(state: state),
      ),
    );
    await tester.tap(find.text('数据管理'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('导入数据'));
    await tester.pump();
    expect(picker.requestedType, FileType.any);
    await tester.pumpWidget(const SizedBox());
    state.dispose();
  });
  testWidgets(
    'recovery export labels a current-only backup when history is damaged',
    (tester) async {
      final previousPicker = FilePickerPlatform.instance;
      final picker = _RecordingPicker();
      FilePickerPlatform.instance = picker;
      addTearDown(() => FilePickerPlatform.instance = previousPicker);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('homework_radar/platform'),
            (_) async => null,
          );
      SharedPreferences.setMockInitialValues({});
      await Storage.init();
      await tester.runAsync(() async {
        final store = await StudyNoteStore.openDefault();
        await store.saveNotes([
          {'id': 'n', 'title': '旧版'},
        ]);
        final old = (await store.history()).last;
        await store.saveNotes([
          {'id': 'n', 'title': '当前'},
        ]);
        await File('${store.directory.path}${Platform.pathSeparator}$old')
            .writeAsString('damaged');
        await tester.pumpWidget(
          StartupRecoveryApp(
            retry: () async {},
            canReadLocalData: true,
            secureFailure: true,
          ),
        );
        await tester.tap(find.text('导出本地备份'));
        final deadline = DateTime.now().add(const Duration(seconds: 15));
        while (find.text('仅导出当前数据').evaluate().isEmpty &&
            DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          await tester.pump(const Duration(milliseconds: 20));
        }
        expect(find.text('完整备份未能完成'), findsOneWidget);
        await tester.tap(find.text('仅导出当前数据'));
        while (picker.saved == null && DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          await tester.pump(const Duration(milliseconds: 20));
        }
        expect(picker.saved, isNotNull);
        final bundle = StudyNoteBundle.decode(picker.saved!);
        expect(bundle.historyIncluded, isFalse);
        expect(bundle.notes.single['title'], '当前');
      });
    },
  );
}
