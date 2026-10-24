import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homework_radar/app_state.dart';
import 'package:homework_radar/main.dart' show buildTheme;
import 'package:homework_radar/models/course.dart';
import 'package:homework_radar/pages/accounts_page.dart';
import 'package:homework_radar/services/jw_config.dart';
import 'package:homework_radar/services/storage.dart';
import 'package:homework_radar/ui/tokens.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final secure = <String, String>{};
  setUp(() async {
    secure.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('homework_radar/platform'),
          (call) async {
            final args = (call.arguments as Map?) ?? {};
            switch (call.method) {
              case 'secureRead':
                return secure[args['key']];
              case 'secureWrite':
                secure[args['key'] as String] = args['value'] as String;
                return true;
              case 'secureDelete':
                secure.remove(args['key']);
                return true;
              default:
                return null;
            }
          },
        );
    SharedPreferences.setMockInitialValues({});
    await Storage.init();
    // Keep the native storage queue in the real async zone across widget tests.
    await Storage.saveChaoxing(cookie: 'synthetic-cx', uid: '123456789012345');
    await Storage.saveZf(cookie: 'synthetic-zf', xh: '202610170012345');
    await JwStore.save(
      const JwConfig(name: '一个名称需要完整换行显示的测试大学', url: 'https://jw.test.edu.cn'),
    );
    await Storage.saveCourses([
      Course(
        id: 'kept',
        name: '保留的导入课程',
        weekday: 1,
        startSection: 1,
        endSection: 2,
        weeks: [1, 2],
      ),
    ]);
  });

  Future<void> showAccounts(
    WidgetTester tester,
    AppState state,
    ThemeStyle style, {
    Brightness brightness = Brightness.light,
  }) async {
    tester.view.physicalSize = const Size(320, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(brightness, style),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(1.4)),
          child: child!,
        ),
        home: AccountsPage(state: state),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> revealCard(WidgetTester tester, Finder card) async {
    tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position
        .jumpTo(0);
    await tester.pump();
    await tester.scrollUntilVisible(
      card,
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'connection summary counts valid sessions separately from expired ones',
    (tester) async {
      final state = AppState()
        ..chaoxingState = AccountState.ok
        ..moocState = AccountState.needRelogin
        ..zfState = AccountState.ok;
      addTearDown(state.dispose);
      await showAccounts(tester, state, ThemeStyle.morandi);
      expect(find.text('2 / 6'), findsOneWidget);
      expect(find.textContaining('1 个平台需要重新登录'), findsOneWidget);
      state.chaoxingState = AccountState.needRelogin;
      state.notifyListeners();
      await tester.pumpAndSettle();
      expect(find.text('1 / 6'), findsOneWidget);
      expect(find.textContaining('2 个平台需要重新登录'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final style in ThemeStyle.values.where(
    (s) => !stylePalette(s, Brightness.light).clean,
  )) {
    for (final brightness in Brightness.values) {
      testWidgets(
        '${style.name}/${brightness.name}: account details and safe exit survive narrow text scaling',
        (tester) async {
          final course = Storage.courses().single;
          final state = AppState()
            ..chaoxingState = AccountState.ok
            ..moocState = AccountState.needRelogin
            ..xuetangxState = AccountState.ok
            ..yuketangState = AccountState.needRelogin
            ..zfState = AccountState.ok
            ..courses = [course]
            ..lastSync = DateTime(2026, 10, 17, 12, 34);
          addTearDown(state.dispose);
          await showAccounts(tester, state, style, brightness: brightness);
          expect(find.text('3 / 6'), findsOneWidget);
          expect(find.textContaining('2 个平台需要重新登录'), findsOneWidget);
          await tester.scrollUntilVisible(
            find.textContaining('10月17日 12:34'),
            200,
          );
          await tester.pumpAndSettle();
          expect(find.textContaining('10月17日 12:34'), findsOneWidget);
          const names = [
            '学习通',
            '中国大学MOOC',
            '智慧树',
            '学堂在线',
            '雨课堂',
            '教务系统 · 一个名称需要完整换行显示的测试大学',
          ];
          const statuses = [
            '已登录',
            '登录已失效，请重新登录',
            '未登录',
            '已登录',
            '登录已失效，请重新登录',
            '已登录',
          ];
          for (var i = 0; i < names.length; i++) {
            final card = find.byKey(ValueKey('account-${i + 1}'));
            await revealCard(tester, card);
            expect(
              find.descendant(of: card, matching: find.text(names[i])),
              findsOneWidget,
            );
            expect(
              find.descendant(
                of: card,
                matching: find.textContaining(statuses[i]),
              ),
              findsOneWidget,
            );
            await tester.tap(
              find.descendant(of: card, matching: find.byType(IconButton)),
            );
            await tester.pumpAndSettle();
            expect(
              find.text(i == 2 ? '登录${names[i]}' : '重新登录'),
              findsOneWidget,
            );
            expect(find.text('退出账号'), i == 2 ? findsNothing : findsOneWidget);
            if (i == 0) {
              expect(find.text('UID 123456789012345'), findsOneWidget);
            }
            if (i == 5) {
              expect(find.text('学号 202610170012345'), findsOneWidget);
            }
            await tester.tap(find.byTooltip('关闭账号详情'));
            await tester.pumpAndSettle();
            expect(
              tester.takeException(),
              isNull,
              reason: '${style.name}: ${names[i]}',
            );
          }
          // The themed action must still enter the real destructive-action guard.
          final card = find.byKey(const ValueKey('account-6'));
          await revealCard(tester, card);
          await tester.tap(
            find.descendant(of: card, matching: find.byType(IconButton)),
          );
          await tester.pumpAndSettle();
          await tester.ensureVisible(find.text('退出账号'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('退出账号'));
          await tester.pumpAndSettle();
          expect(find.text('退出教务系统'), findsOneWidget);
          expect(find.textContaining('手动添加的课程会保留'), findsOneWidget);
          await tester.tap(find.text('取消'));
          await tester.pumpAndSettle();
          expect(state.zfState, AccountState.ok);
          expect(Storage.zfCookie(), 'synthetic-zf');
          expect(Storage.zfXh(), '202610170012345');
          expect(Storage.courses().single.id, 'kept');
          expect(state.courses.single.id, 'kept');
          expect(Storage.accountArchives(), isEmpty);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
  }
}
