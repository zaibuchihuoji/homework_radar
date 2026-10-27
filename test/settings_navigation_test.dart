import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homework_radar/app_state.dart';
import 'package:homework_radar/main.dart';
import 'package:homework_radar/models/homework.dart';
import 'package:homework_radar/pages/settings_page.dart';
import 'package:homework_radar/services/storage.dart';
import 'package:homework_radar/ui/tokens.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';

class _CancelledPicker extends FilePickerPlatform {
  bool opened = false;
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
    opened = true;
    return [];
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'five settings destinations keep existing data and import cancellation',
    (tester) async {
      final originalPicker = FilePickerPlatform.instance;
      final cancelledPicker = _CancelledPicker();
      FilePickerPlatform.instance = cancelledPicker;
      addTearDown(() => FilePickerPlatform.instance = originalPicker);
      SharedPreferences.setMockInitialValues({});
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('homework_radar/platform'),
            (_) async => null,
          );
      await Storage.init();
      final old = HomeworkItem(
        id: 'manual_old_keep',
        platform: PlatformKind.manual,
        course: '旧课程',
        title: '旧作业',
        status: HwStatus.todo,
        note: '保留的备注',
      );
      await Storage.saveHomework([old]);
      await Storage.dismiss(
        'hidden_old_keep',
        jsonEncode({...old.toJson(), 'id': 'hidden_old_keep'}),
      );
      final hiddenBefore = Map<String, String>.from(Storage.hiddenItems());
      final before = jsonEncode(
        Storage.homework().map((h) => h.toJson()).toList(),
      );
      final state = AppState();
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(Brightness.light, ThemeStyle.clean),
          home: SettingsPage(state: state),
        ),
      );
      await tester.pumpAndSettle();
      for (final title in ['外观与小组件', '提醒与课表', '同步与后台', '数据管理', '关于与帮助']) {
        await tester.ensureVisible(find.text(title));
        await tester.tap(find.text(title));
        await tester.pumpAndSettle();
        expect(find.text(title), findsOneWidget);
        if (title == '数据管理') {
          await tester.tap(find.text('导入数据'));
          await tester.pumpAndSettle();
          expect(cancelledPicker.opened, isTrue);
          expect(find.text('数据管理'), findsOneWidget);
          expect(
            jsonEncode(Storage.homework().map((h) => h.toJson()).toList()),
            before,
          );
          await tester.ensureVisible(find.text('已隐藏的作业'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('已隐藏的作业'));
          await tester.pumpAndSettle();
          expect(find.text('旧作业'), findsOneWidget);
          expect(find.text('恢复'), findsOneWidget);
          expect(Storage.hiddenItems(), hiddenBefore);
          await tester.pageBack();
          await tester.pumpAndSettle();
          await tester.ensureVisible(find.text('历史账号数据'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('历史账号数据'));
          await tester.pumpAndSettle();
          expect(find.text('暂无历史归档'), findsOneWidget);
          await tester.pageBack();
          await tester.pumpAndSettle();
        }
        await tester.pageBack();
        await tester.pumpAndSettle();
      }
      expect(
        jsonEncode(Storage.homework().map((h) => h.toJson()).toList()),
        before,
      );
      expect(Storage.hiddenItems(), hiddenBefore);
      await tester.pumpWidget(const SizedBox());
      state.dispose();
    },
  );
}
