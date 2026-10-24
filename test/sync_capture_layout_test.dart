import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:homework_radar/app_state.dart';
import 'package:homework_radar/main.dart' show buildTheme;
import 'package:homework_radar/models/homework.dart';
import 'package:homework_radar/pages/background_sync_settings_page.dart';
import 'package:homework_radar/pages/home_page.dart';
import 'package:homework_radar/pages/homework_recognition_page.dart';
import 'package:homework_radar/pages/homework_recognition_review_page.dart';
import 'package:homework_radar/services/homework_recognition.dart';
import 'package:homework_radar/services/storage.dart';
import 'package:homework_radar/services/sync_policy.dart';
import 'package:homework_radar/ui/settings_parts.dart';
import 'package:homework_radar/ui/sync_status_parts.dart';
import 'package:homework_radar/ui/tokens.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppState state;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('homework_radar/platform'),
          (_) async => null,
        );
    await Storage.init();
    await Storage.saveHomework([
      HomeworkItem(
        id: 'old',
        platform: PlatformKind.manual,
        course: '数学',
        title: '旧作业',
        note: '旧备注',
      ),
    ]);
    state = AppState();
    await state.loadLocal();
  });
  tearDown(() => state.dispose());

  Widget app(
    Widget page, {
    ThemeStyle style = ThemeStyle.clean,
    bool large = false,
  }) => MaterialApp(
    key: ValueKey(page.runtimeType),
    theme: buildTheme(Brightness.light, style),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(large ? 1.5 : 1)),
      child: child!,
    ),
    home: page,
  );

  testWidgets('sync outcomes keep last success distinct from failed attempt', (
    tester,
  ) async {
    final success = DateTime(2025, 5, 17, 22, 30);
    final attempt = DateTime(2026, 10, 24, 15);
    for (final outcome in SyncOutcome.values) {
      await tester.pumpWidget(
        app(
          SettingsScaffold(
            title: '同步',
            body: SettingsList(
              children: [
                SyncPlatformStatus(
                  platform: PlatformKind.mooc,
                  status: PlatformSyncStatus(
                    lastSuccess: success,
                    lastAttempt: attempt,
                    outcome: outcome,
                    nextRetry: outcome == SyncOutcome.retry
                        ? attempt.add(const Duration(minutes: 5))
                        : null,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('上次完整同步：2025/5/17 22:30'), findsOneWidget);
      expect(find.textContaining('最近尝试：'), findsOneWidget);
      expect(
        find.text('完整同步'),
        outcome == SyncOutcome.success ? findsOneWidget : findsNothing,
      );
      expect(
        find.textContaining('计划重试'),
        outcome == SyncOutcome.retry ? findsOneWidget : findsNothing,
      );
      expect(tester.takeException(), isNull);
    }
    expect(Storage.homework().single.note, '旧备注');
  });

  testWidgets(
    'home sync notice opens details and busy progress never claims success',
    (tester) async {
      state.lastSyncMessage = '学习通未完整同步，已保留旧记录，请稍后重试。';
      await tester.pumpWidget(app(HomePage(state: state, onGoAccounts: () {})));
      await tester.tap(find.text('查看同步状态'));
      await tester.pumpAndSettle();
      expect(find.byType(BackgroundSyncSettingsPage), findsOneWidget);
      expect(find.text('尚未登录作业平台'), findsOneWidget);
      expect(find.text('完整同步'), findsNothing);
      await tester.pumpWidget(
        app(
          const SettingsScaffold(
            title: '同步',
            body: SyncProgressNotice(busy: true, progress: '3/12'),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('课程进度 3/12'), findsOneWidget);
      expect(find.text('完整同步'), findsNothing);
      expect(Storage.homework().single.id, 'old');
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final style in ThemeStyle.values) {
    testWidgets(
      '${style.name}: capture review and sync fit narrow enlarged text',
      (tester) async {
        tester.view.physicalSize = const Size(320, 740);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          app(HomeworkRecognitionPage(state: state), style: style, large: true),
        );
        await tester.pumpAndSettle();
        expect(find.text('识别并核对'), findsOneWidget);
        expect(tester.getCenter(find.text('识别并核对')).dy, lessThan(740));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(
          app(
            HomeworkRecognitionReviewPage(
              state: state,
              drafts: HomeworkRecognition.parse(
                '【数学】旧作业\n\n【大学英语】完成很长的一份阅读与写作练习，明天交',
              ),
              knownCourses: const ['数学', '大学英语'],
            ),
            style: style,
            large: true,
          ),
        );
        await tester.pumpAndSettle();
        expect(
          tester.widget<Checkbox>(find.byKey(const ValueKey('select_0'))).value,
          false,
        );
        expect(find.textContaining('截止时间待确认'), findsWidgets);
        expect(
          tester.getCenter(find.byKey(const ValueKey('review_save'))).dy,
          lessThan(740),
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(
          app(
            SettingsScaffold(
              title: '同步',
              body: SettingsList(
                children: [
                  SyncPlatformStatus(
                    platform: PlatformKind.mooc,
                    status: const PlatformSyncStatus(
                      outcome: SyncOutcome.loginExpired,
                    ),
                  ),
                ],
              ),
            ),
            style: style,
            large: true,
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('需重新登录'), findsOneWidget);
        expect(find.textContaining('尚无完整同步'), findsOneWidget);
        expect(tester.takeException(), isNull);
        expect(Storage.homework().single.note, '旧备注');
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
