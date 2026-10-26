import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:homework_radar/app_state.dart';
import 'package:homework_radar/main.dart' show buildTheme;
import 'package:homework_radar/models/course.dart';
import 'package:homework_radar/pages/jw_ocr_import_page.dart';
import 'package:homework_radar/pages/jw_preview_page.dart';
import 'package:homework_radar/services/storage.dart';
import 'package:homework_radar/services/notification_service.dart';
import 'package:homework_radar/services/timetable_ocr.dart';
import 'package:homework_radar/ui/tokens.dart';

class FailOnceState extends AppState {
  int attempts = 0;
  @override
  Future<void> onTimetableCaptured({
    String? cookie,
    String xh = '',
    required List<Course> courses,
    required String rawPage,
    String semesterText = '',
    int? detectedWeek,
    String source = '教务',
    bool fullImport = false,
  }) async {
    if (++attempts == 1) throw const FormatException('test write failure');
    await super.onTimetableCaptured(
      cookie: cookie,
      xh: xh,
      courses: courses,
      rawPage: rawPage,
      semesterText: semesterText,
      detectedWeek: detectedWeek,
      source: source,
      fullImport: fullImport,
    );
  }
}

Map<String, dynamic> recognizedFixture({bool bareAxis = false}) {
  Map<String, dynamic> line(String text, double x, double y) {
    final halfWidth = x == 40 ? 10 : 30;
    final json = <String, dynamic>{
      'text': text,
      'rect': {
        'left': x - halfWidth,
        'top': y - 9,
        'right': x + halfWidth,
        'bottom': y + 9,
      },
      'recognizedLanguages': <String>[],
      'points': <Object>[],
      'symbols': <Object>[],
    };
    return {
      ...json,
      'elements': [json],
    };
  }

  return {
    'text': '测试课表',
    'blocks': [
      {
        'text': '测试课表',
        'rect': {'left': 0.0, 'top': 0.0, 'right': 1000.0, 'bottom': 600.0},
        'recognizedLanguages': <String>[],
        'points': <Object>[],
        'lines': [
          for (var d = 0; d < 7; d++)
            line('星期${'一二三四五六日'[d]}', 120.0 + d * 120, 40),
          line(bareAxis ? '1' : '第1节', 40, 100),
          line(bareAxis ? '2' : '第2节', 40, 200),
          line('识别课程', 120, 100),
          line('1-16周', 120, 120),
          line('A301', 120, 140),
        ],
      },
    ],
  };
}

Widget harness(Widget child) => MaterialApp(
  theme: buildTheme(Brightness.light, ThemeStyle.clean),
  home: child,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  var picks = 0;
  var recognitions = 0;
  var bareAxis = false;
  var pickedPath = '/not-a-real-file/ocr.png';
  var inspectPreparedSize = false;
  (int, int)? preparedSize;
  setUp(() async {
    picks = 0;
    recognitions = 0;
    bareAxis = false;
    pickedPath = '/not-a-real-file/ocr.png';
    inspectPreparedSize = false;
    preparedSize = null;
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final name in [
      'homework_radar/platform',
      'home_widget',
      'dexterous.com/flutter/local_notifications',
    ]) {
      messenger.setMockMethodCallHandler(
        MethodChannel(name),
        (_) async => name == 'homework_radar/platform' ? null : true,
      );
    }
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/image_picker'),
      (_) async {
        picks++;
        return pickedPath;
      },
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('google_mlkit_text_recognizer'),
      (call) async {
        if (call.method == 'vision#startTextRecognizer') {
          recognitions++;
          if (inspectPreparedSize) {
            final path =
                ((call.arguments as Map)['imageData'] as Map)['path'] as String;
            final buffer = await ui.ImmutableBuffer.fromUint8List(
              await File(path).readAsBytes(),
            );
            final descriptor = await ui.ImageDescriptor.encoded(buffer);
            preparedSize = (descriptor.width, descriptor.height);
            descriptor.dispose();
            buffer.dispose();
          }
          return recognizedFixture(bareAxis: bareAxis);
        }
        return null;
      },
    );
    SharedPreferences.setMockInitialValues({});
    await Storage.init();
    await NotificationService.init();
    await Storage.saveClassReminder(false);
  });

  testWidgets('preview clearly counts incomplete candidates', (t) async {
    await t.pumpWidget(
      harness(
        JwPreviewPage(
          courses: [
            Course(
              id: 'unknown',
              name: '待核对课',
              weekday: 0,
              startSection: 1,
              endSection: 2,
              weeks: [],
              sectionsProvisional: true,
            ),
          ],
          sourceLabel: '截图导入',
        ),
      ),
    );
    expect(find.textContaining('待核对 1 条'), findsOneWidget);
  });

  testWidgets(
    'axis reinterpretation reuses OCR and cancellation preserves manual corrections',
    (t) async {
      bareAxis = true;
      final state = AppState();
      await state.loadLocal();
      addTearDown(state.dispose);
      await t.pumpWidget(harness(JwOcrImportPage(state: state)));
      await t.tap(find.text('选择课表截图'));
      for (var i = 0; i < 10; i++) {
        await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await t.pumpAndSettle();
      }
      expect(find.textContaining('待核对 1 条'), findsOneWidget);
      await t.pageBack();
      await t.pumpAndSettle();
      await t.ensureVisible(find.byType(DropdownButton<OcrSectionMode>));
      await t.tap(find.byType(DropdownButton<OcrSectionMode>));
      await t.pumpAndSettle();
      await t.tap(find.textContaining('两节一组：').last);
      await t.pumpAndSettle();
      await t.ensureVisible(find.text('继续核对识别结果'));
      await t.tap(find.text('继续核对识别结果'));
      await t.pumpAndSettle();
      expect(find.textContaining('第1-2节'), findsOneWidget);
      await t.tap(find.byTooltip('编辑').first);
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField).first, '已核对课程');
      await t.ensureVisible(find.text('保存修改'));
      await t.tap(find.text('保存修改'));
      await t.pumpAndSettle();
      await t.pageBack();
      await t.pumpAndSettle();
      await t.ensureVisible(find.byType(DropdownButton<OcrSectionMode>));
      await t.tap(find.byType(DropdownButton<OcrSectionMode>));
      await t.pumpAndSettle();
      await t.tap(find.textContaining('逐节编号：').last);
      await t.pumpAndSettle();
      expect(find.text('重新整理节次？'), findsOneWidget);
      await t.tap(find.text('取消'));
      await t.pumpAndSettle();
      await t.ensureVisible(find.text('继续核对识别结果'));
      await t.tap(find.text('继续核对识别结果'));
      await t.pumpAndSettle();
      expect(find.text('已核对课程'), findsOneWidget);
      expect(find.textContaining('第1-2节'), findsOneWidget);
      expect(picks, 1);
      expect(recognitions, 1);
      expect(Storage.courses(), isEmpty);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'a tall image is bounded before native OCR and the original is preserved',
    (t) async {
      final folder = await t.runAsync(
        () => Directory.systemTemp.createTemp('codex-ocr-size-'),
      );
      final image = await t.runAsync(
        () => createTestImage(width: 100, height: 8000, cache: false),
      );
      final data = await t.runAsync(
        () => image!.toByteData(format: ui.ImageByteFormat.png),
      );
      image!.dispose();
      final source = File('${folder!.path}/source.png');
      await t.runAsync(() => source.writeAsBytes(data!.buffer.asUint8List()));
      addTearDown(() async {
        await source.delete();
        await folder.delete();
      });
      pickedPath = source.path;
      inspectPreparedSize = true;
      final state = AppState();
      addTearDown(state.dispose);
      await t.pumpWidget(harness(JwOcrImportPage(state: state)));
      await t.tap(find.text('选择课表截图'));
      for (var i = 0; i < 40 && preparedSize == null; i++) {
        await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 25)),
        );
        await t.pump();
      }
      expect(preparedSize, (50, 4000));
      expect(await t.runAsync(source.exists), isTrue);
      // Finish the pending recognition/route before disposing the page.
      for (var i = 0; i < 4; i++) {
        await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await t.pump();
      }
      await t.pumpAndSettle();
      expect(find.text('查看原图 · 可放大核对'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'failed save retries the corrected draft without another OCR or losing old courses',
    (t) async {
      final old = Course(
        id: 'old',
        name: '原课程',
        weekday: 4,
        startSection: 7,
        endSection: 8,
        weeks: [1, 2],
      );
      await Storage.saveCourses([old]);
      final state = FailOnceState();
      await state.loadLocal();
      addTearDown(state.dispose);
      await t.pumpWidget(harness(JwOcrImportPage(state: state)));
      await t.tap(find.text('选择课表截图'));
      for (var i = 0; i < 10; i++) {
        await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await t.pumpAndSettle();
      }
      expect(find.textContaining('确认课表 ·'), findsOneWidget);
      await t.tap(find.byTooltip('编辑').first);
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField).first, '人工修正的课名');
      await t.ensureVisible(find.text('保存修改'));
      await t.tap(find.text('保存修改'));
      await t.pumpAndSettle();
      await t.tap(find.text('导入所选 1 节课'));
      await t.pump(const Duration(milliseconds: 350));
      await t.tap(find.text('确认补充导入'));
      await t.pumpAndSettle();
      expect(find.text('重试保存'), findsOneWidget);
      expect(Storage.courses().single.name, '原课程');
      await t.ensureVisible(find.text('重试保存'));
      await t.tap(find.text('重试保存'));
      await t.pump(const Duration(milliseconds: 350));
      await t.tap(find.text('确认补充导入'));
      await t.pumpAndSettle();
      expect(picks, 1);
      expect(recognitions, 1);
      expect(state.attempts, 2);
      expect(
        Storage.courses().map((c) => c.name),
        containsAll(['原课程', '人工修正的课名']),
      );
      expect(t.takeException(), isNull);
    },
  );
}
