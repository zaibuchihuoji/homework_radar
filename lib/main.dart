import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:home_widget/home_widget.dart';

import 'app_state.dart';
import 'pages/accounts_page.dart';
import 'pages/calendar_page.dart';
import 'pages/detail_page.dart';
import 'pages/home_page.dart';
import 'pages/settings_page.dart';
import 'pages/splash_page.dart';
import 'pages/startup_recovery_page.dart';
import 'pages/timetable_page.dart';
import 'services/notification_service.dart';
import 'services/background_sync.dart';
import 'services/app_update_controller.dart';
import 'pages/update_dialog.dart';
import 'services/storage.dart';
import 'services/timetable_widget.dart';
import 'services/sync_service.dart';
import 'services/widget_navigation.dart';
import 'services/widget_theme.dart';
import 'ui/themed_navigation.dart';
import 'ui/theme_forms.dart';
import 'ui/tokens.dart';

final _navigatorKey = GlobalKey<NavigatorState>();

/// 冷启动首帧是否显示启动动画（每次进程启动只播一次）。
/// 热重启（debug 下的 reload）会重置这个变量，但真实用户只有冷启动，
/// 行为正确；通知跳转详情不受影响。
bool showSplashOnStart = true;

/// main() 里挂好的全局 AppState，供启动页交接时取用。
AppState? appStateForHome;
BackgroundSync? backgroundSyncForApp;

void _openDetail(String homeworkId) {
  homeworkId = NotificationService.navigationPayload(homeworkId);
  if (homeworkId.isEmpty) return;
  if (NotificationService.isClassPayload(homeworkId)) {
    final state = appStateForHome;
    if (state != null) {
      _navigatorKey.currentState?.push(
        MaterialPageRoute<void>(builder: (_) => TimetablePage(state: state)),
      );
    }
    return;
  }
  _navigatorKey.currentState?.push(
    MaterialPageRoute(
      builder: (_) => HomeworkDetailPage(homeworkId: homeworkId),
    ),
  );
}

/// 冷启动由通知拉起时挂上的回调：启动页撤除（主页就位）后跳详情。
/// 只消费一次，用完即清。
VoidCallback? onSplashFinished;

/// 首次前台页面等通知启动 payload 就绪后再交接，避免启动页先撤导致深链丢失。
/// 后台引擎不提前消费启动信息；之后打开 Activity 时才读取。
final Completer<String?> launchPayloadReady = Completer<String?>();

Future<void> main() async {
  // 启动关键路径此前全程裸奔：runApp 前任何一步抛错就是一块死屏
  // （原生 4 秒兜底后无内容），runApp 后抛错会静默砍掉深链/提醒重排/
  // 小组件推送/自动同步。统一挂上全局兜底，错误走 FlutterError 报告。
  await runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      LicenseRegistry.addLicense(() async* {
        final license = await rootBundle.loadString(
          'assets/fonts/OFL-NotoSerifSC.txt',
        );
        yield LicenseEntryWithLineBreaks(['Noto Serif SC'], license);
      });
      FlutterError.onError = (details) {
        FlutterError.presentError(details);
      };
      ui.PlatformDispatcher.instance.onError = (e, st) {
        return true; // 已由 zone 兜底记录，不交给默认处理器再炸一次
      };

      Future<void> startApplication() async {
        // 前后台都先加载同一份本地数据；后台任务不创建页面或请求权限。
        await Storage.init();
        final state = AppState();
        appStateForHome = state;
        // 先上屏本地已有数据（作业 + 课表），主页一出来就有内容
        await state.loadLocal();
        Future<void>? uiStarted;
        Future<void> startUi() => uiStarted ??= () async {
          runApp(HomeworkRadarApp(state: state));
          String? payload;
          try {
            await NotificationService.init();
            payload = await NotificationService.initialPayload();
          } catch (e) {
            debugPrint('notification launch init failed: $e');
          }
          if (!launchPayloadReady.isCompleted) {
            launchPayloadReady.complete(payload);
          }
          unawaited(NotificationService.rerequestPermission());
        }();

        // 在启动任何 UI 之前挂好交接，首次 Activity 到来时才读取通知 payload。
        onSplashFinished = () async {
          final payload = await launchPayloadReady.future;
          if (payload != null && payload.isNotEmpty) _openDetail(payload);
        };
        NotificationService.onSelect = _openDetail;
        // Safe without an Activity: notification initialization never requests UI permission.
        try {
          await NotificationService.init();
        } catch (_) {}
        final background = BackgroundSync(state, onForeground: startUi);
        backgroundSyncForApp = background;
        await background.init();
        unawaited(
          NotificationService.reschedule(
            state.homework,
            courses: state.courses,
          ),
        );
        unawaited(TimetableWidget.push(state.courses));
        unawaited(SyncService.updateHomeWidget(state.homework));
      }

      Future<void> showRecovery(Object error) async {
        var shown = false;
        late Future<dynamic> Function(MethodCall) recoveryHandler;
        Future<void> show() async {
          if (shown) return;
          shown = true;
          runApp(
            StartupRecoveryApp(
              secureFailure: error is SecureStorageUnavailableException,
              canReadLocalData: Storage.localDataReadyForRecovery,
              retry: () async {
                try {
                  await startApplication();
                } catch (_) {
                  BackgroundSync.channel.setMethodCallHandler(recoveryHandler);
                  rethrow;
                }
              },
            ),
          );
        }

        // A headless Android worker must fail/retry without creating a UI;
        // opening the Activity later shows the same recovery screen.
        recoveryHandler = (call) async {
          if (call.method == 'foreground') {
            if (call.arguments == true) await show();
            return true;
          }
          if (call.method == 'run') return false;
          throw MissingPluginException();
        };
        BackgroundSync.channel.setMethodCallHandler(recoveryHandler);
        var foreground = true;
        try {
          foreground =
              await BackgroundSync.channel.invokeMethod<bool>('ready') == true;
        } on MissingPluginException {
          // iOS and other hosts run the ordinary foreground app.
        } catch (_) {
          // If the lifecycle bridge itself failed, still show a recovery UI.
        }
        if (foreground) await show();
      }

      try {
        await startApplication();
      } catch (error) {
        await showRecovery(error);
      }
    },
    (e, st) {
      // 同步/通知/小组件链路的未捕获异步异常：记到 debug 控制台即可，
      // 不允许再向上炸穿（老实现会让 syncing 卡死、深链丢失）
      debugPrint('uncaught zone error: $e\n$st');
    },
  );
}

ThemeData buildTheme(Brightness brightness, ThemeStyle style) {
  // 深色锁：只有清夏打磨过深色观感，其余主题统一钳回浅色——
  // 即便系统深色/用户选过深色，非清夏下深色调色板也不会生效
  //（设置页的主题模式行同步加锁说明）
  if (style != ThemeStyle.clean &&
      style != ThemeStyle.green &&
      brightness == Brightness.dark) {
    return buildTheme(Brightness.light, style);
  }
  final dark = brightness == Brightness.dark;
  final pal = stylePalette(style, brightness);
  final formFont = pal.pixel || pal.terminal || pal.receipt
      ? 'monospace'
      : pal.paper || pal.journal || pal.inkWash
      ? 'serif'
      : null;
  final controlShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(
      pal.clean || pal.clay
          ? 12
          : pal.morandi
          ? 14
          : pal.comic
          ? 9
          : pal.journal
          ? 5
          : pal.inkWash
          ? 4
          : 1,
    ),
  );
  final pickerHeader = pal.pixel || pal.terminal
      ? pal.ink
      : Color.alphaBlend(
          pal.accentFill.withValues(alpha: pal.comic ? 0.09 : 0.035),
          pal.modal,
        );
  final scheme =
      ColorScheme.fromSeed(
        seedColor: pal.accent,
        brightness: brightness,
      ).copyWith(
        primary: pal.accent,
        onPrimary: pal.clay
            ? Colors.white
            : pal.sunny
            ? (dark ? pal.onAccent : Colors.white)
            : null,
        primaryContainer: pal.clay
            ? pal.accentFill
            : pal.sunny
            ? pal.accentFill.withValues(alpha: dark ? .18 : .32)
            : null,
        onPrimaryContainer: pal.sunny || pal.clay ? pal.ink : null,
        secondaryContainer: pal.sunny || pal.clay ? pal.accentFill : null,
        onSecondaryContainer: pal.sunny || pal.clay ? pal.onAccent : null,
        surface: pal.modal,
        surfaceContainerLowest: pal.modal,
      );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: pal.bg,
    extensions: [pal],
    textSelectionTheme: pal.sunny || pal.clay
        ? TextSelectionThemeData(
            cursorColor: pal.accent,
            selectionColor: pal.accentFill.withValues(alpha: .45),
            selectionHandleColor: pal.accent,
          )
        : null,
    switchTheme: pal.sunny
        ? SwitchThemeData(
            trackColor: WidgetStateProperty.resolveWith(
              (s) => s.contains(WidgetState.disabled)
                  ? null
                  : s.contains(WidgetState.selected)
                  ? pal.accentFill
                  : null,
            ),
            thumbColor: WidgetStateProperty.resolveWith(
              (s) => s.contains(WidgetState.disabled)
                  ? null
                  : s.contains(WidgetState.selected)
                  ? pal.onAccent
                  : null,
            ),
          )
        : null,
    checkboxTheme: pal.sunny
        ? CheckboxThemeData(
            fillColor: WidgetStateProperty.resolveWith(
              (s) => s.contains(WidgetState.disabled)
                  ? null
                  : s.contains(WidgetState.selected)
                  ? pal.accentFill
                  : null,
            ),
            checkColor: WidgetStatePropertyAll(pal.onAccent),
          )
        : null,
    textTheme: TextTheme(
      bodyLarge: pal.clean || pal.clay
          ? TextStyle(fontSize: 15, height: 1.5, color: pal.ink)
          : TextStyle(fontSize: 14, color: pal.ink, fontFamily: formFont),
      displayLarge: TextStyle(
        fontSize: 30,
        height: 1.1,
        fontWeight: pal.clay ? FontWeight.w400 : FontWeight.w600,
        fontFamily: pal.clay ? 'StudySerif' : null,
        letterSpacing: -0.5,
        color: pal.ink,
      ),
      titleLarge: TextStyle(
        fontSize: 20,
        fontWeight: pal.clay ? FontWeight.w400 : FontWeight.w700,
        fontFamily: pal.clay ? 'StudySerif' : null,
        color: pal.ink,
      ),
      titleMedium: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: pal.ink,
      ),
      bodyMedium: TextStyle(fontSize: 14, height: 1.5, color: pal.ink),
      labelMedium: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: pal.ink2,
      ),
    ).apply(fontFamily: formFont),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      toolbarHeight: 60,
      titleSpacing: 20,
      foregroundColor: pal.ink,
      systemOverlayStyle: dark
          ? SystemUiOverlayStyle.light
          : SystemUiOverlayStyle.dark,
      titleTextStyle: TextStyle(
        fontSize: 20,
        fontWeight: pal.clay ? FontWeight.w400 : FontWeight.w600,
        color: pal.ink,
        fontFamily: pal.clay
            ? 'StudySerif'
            : pal.paper
            ? 'serif'
            : null,
        letterSpacing: pal.inkWash ? 5 : null,
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: pal.accentFill,
      foregroundColor: pal.onAccent,
      elevation: 0,
      highlightElevation: 0,
      // 漫画的分镜感：强调色块加一圈墨线勾边（与卡片同一勾线色）
      shape: pal.morandi
          // 莫兰迪的 FAB 是一颗奶油圆糖
          ? const CircleBorder()
          : RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(
                pal.inkWash ? 10 : pal.radius + 2,
              ),
              side: pal.comic
                  ? BorderSide(color: pal.cardBorder, width: 2)
                  : pal.paper
                  // 暖纸的 FAB 是"印章"：方角 + 墨线描边
                  ? BorderSide(
                      color: pal.ink.withValues(alpha: 0.65),
                      width: 1.4,
                    )
                  : pal.inkWash
                  // 水墨的 FAB 是"落款大印"：近方朱印 + 白文边栏
                  ? BorderSide(
                      color: Colors.white.withValues(alpha: 0.85),
                      width: 1.8,
                    )
                  : pal.pixel
                  // 像素的 FAB 是"按键"：直角 + 勾线
                  ? BorderSide(color: pal.cardBorder, width: 2)
                  : pal.terminal
                  // 终端的 FAB 是"窗格"：直角 + 1px 单线
                  ? BorderSide(color: pal.cardBorder, width: 1)
                  : BorderSide.none,
            ),
    ),
    // 次级按钮形状随样式走：票据/印刷/终端/像素都是方角，其余胶囊。
    // 只动 shape，side 留给组件级配置（账号页已登录态的描边色）。
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: ButtonStyle(
        shape: WidgetStateProperty.all(
          pal.clean || pal.clay
              ? RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
              : pal.receipt || pal.terminal || pal.editorial || pal.pixel
              ? const RoundedRectangleBorder(
                  borderRadius: BorderRadius.all(Radius.circular(2)),
                )
              : pal.morandi
              ? const StadiumBorder()
              : RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(pal.comic ? 10 : 6),
                ),
        ),
      ),
    ),
    // 主按钮 = 光源：品牌色淡淡一圈光晕，照亮周围但不抢眼。
    // 禁用态必须关掉光晕（发光的灰药丸=糊），换成干净的浅灰底+灰字。
    // 水墨例外：主按钮是"钤印"——近方朱印、落墨影（印章不发光），不是胶囊。
    filledButtonTheme: FilledButtonThemeData(
      style: ButtonStyle(
        elevation: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.disabled)
              ? 0
              : pal.clean ||
                    pal.clay ||
                    pal.pixel ||
                    pal.terminal ||
                    pal.receipt ||
                    pal.editorial ||
                    pal.paper ||
                    pal.journal
              ? 0
              : 2,
        ),
        shadowColor: WidgetStateProperty.all(
          pal.inkWash || pal.comic
              ? Colors.black.withValues(alpha: dark ? 0 : 0.16)
              : pal.accentFill.withValues(alpha: 0.55),
        ),
        backgroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.disabled)
              ? (dark
                    ? Colors.white.withValues(alpha: 0.07)
                    : Colors.black.withValues(alpha: 0.05))
              : pal.clay
              ? pal.accent
              : pal.sunny && !dark
              ? pal.ink
              : pal.accentFill,
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.disabled)
              ? (dark ? Tokens.ink2Dark : Tokens.ink2)
              : pal.clay
              ? Colors.white
              : pal.sunny && !dark
              ? Colors.white
              : pal.onAccent,
        ),
        shape: WidgetStateProperty.all(
          pal.clean || pal.clay
              ? RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
              : pal.pixel
              ? RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(2),
                  side: BorderSide(color: pal.cardBorder, width: 2),
                )
              : pal.terminal
              ? RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(2),
                  side: BorderSide(color: pal.cardBorder, width: 1),
                )
              : pal.receipt || pal.editorial
              // 小票/杂志：票据与印刷品都不用胶囊，方角
              ? const RoundedRectangleBorder(
                  borderRadius: BorderRadius.all(Radius.circular(2)),
                )
              : pal.inkWash
              ? RoundedRectangleBorder(borderRadius: BorderRadius.circular(9))
              : pal.comic
              ? RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: BorderSide(color: pal.cardBorder, width: 1.5),
                )
              : pal.paper || pal.journal
              ? RoundedRectangleBorder(borderRadius: BorderRadius.circular(6))
              : const RoundedRectangleBorder(
                  borderRadius: BorderRadius.all(Radius.circular(999)),
                ),
        ),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: pal.modal,
      shape: themeModalShape(pal),
      surfaceTintColor: pal.clean ? null : Colors.transparent,
      titleTextStyle: pal.clay
          ? TextStyle(
              fontFamily: 'StudySerif',
              fontSize: 22,
              height: 1.4,
              color: pal.ink,
            )
          : null,
    ),
    inputDecorationTheme: pal.clean && !pal.sunny
        ? null
        : themedInputTheme(pal),
    popupMenuTheme: pal.clean && !pal.sunny
        ? null
        : PopupMenuThemeData(
            color: pal.modal,
            surfaceTintColor: Colors.transparent,
            shape: themeModalShape(pal),
            elevation: pal.pixel || pal.comic ? 3 : 6,
            textStyle: TextStyle(
              color: pal.ink,
              fontSize: 13,
              fontFamily: formFont,
            ),
          ),
    chipTheme: pal.clean && !pal.sunny
        ? null
        : ChipThemeData(
            backgroundColor: pal.modal,
            selectedColor: Color.alphaBlend(
              pal.accentFill.withValues(alpha: .12),
              pal.modal,
            ),
            side: BorderSide(color: pal.cardBorder, width: pal.comic ? 1.5 : 1),
            shape: controlShape,
            checkmarkColor: pal.accent,
            labelStyle: TextStyle(
              color: pal.ink,
              fontSize: 12,
              fontFamily: formFont,
            ),
          ),
    datePickerTheme: pal.clean && !pal.sunny
        ? null
        : DatePickerThemeData(
            backgroundColor: pal.modal,
            surfaceTintColor: Colors.transparent,
            shape: themeModalShape(pal),
            headerBackgroundColor: pickerHeader,
            headerForegroundColor: pal.pixel || pal.terminal
                ? pal.modal
                : pal.ink,
            headerHeadlineStyle: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              fontFamily: formFont,
            ),
            headerHelpStyle: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              fontFamily: formFont,
            ),
            weekdayStyle: TextStyle(
              color: pal.ink2,
              fontSize: 12,
              fontFamily: formFont,
            ),
            dayStyle: TextStyle(
              fontSize: 13,
              fontWeight: pal.editorial ? FontWeight.w700 : FontWeight.w500,
              fontFamily: formFont,
            ),
            dayForegroundColor: WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.disabled)
                  ? pal.ink3.withValues(alpha: .45)
                  : states.contains(WidgetState.selected)
                  ? pal.onAccent
                  : pal.ink,
            ),
            dayBackgroundColor: WidgetStateProperty.resolveWith(
              (states) =>
                  states.contains(WidgetState.selected) ? pal.accentFill : null,
            ),
            todayBackgroundColor: WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.selected)
                  ? pal.accentFill
                  : Colors.transparent,
            ),
            yearBackgroundColor: pal.sunny
                ? WidgetStateProperty.resolveWith(
                    (states) => states.contains(WidgetState.selected)
                        ? pal.accentFill
                        : null,
                  )
                : null,
            yearForegroundColor: pal.sunny
                ? WidgetStateProperty.resolveWith(
                    (states) => states.contains(WidgetState.disabled)
                        ? pal.ink3.withValues(alpha: .45)
                        : states.contains(WidgetState.selected)
                        ? pal.onAccent
                        : pal.ink,
                  )
                : null,
            dayShape: WidgetStatePropertyAll(controlShape),
            todayForegroundColor: WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.selected)
                  ? pal.onAccent
                  : pal.accent,
            ),
            todayBorder: BorderSide(
              color: pal.accent,
              width: pal.comic ? 2 : 1,
            ),
            dividerColor: pal.cardBorder,
            inputDecorationTheme: themedInputTheme(pal),
          ),
    timePickerTheme: pal.clean && !pal.sunny
        ? null
        : TimePickerThemeData(
            backgroundColor: pal.modal,
            shape: themeModalShape(pal),
            helpTextStyle: TextStyle(
              color: pal.ink2,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              fontFamily: formFont,
            ),
            hourMinuteShape: controlShape,
            hourMinuteColor: WidgetStateColor.resolveWith(
              (states) => Color.alphaBlend(
                pal.accentFill.withValues(
                  alpha: states.contains(WidgetState.selected) ? .12 : .025,
                ),
                pal.modal,
              ),
            ),
            hourMinuteTextColor: pal.ink,
            hourMinuteTextStyle: TextStyle(
              fontSize: 38,
              fontWeight: FontWeight.w600,
              fontFamily: formFont,
            ),
            dialBackgroundColor: Color.alphaBlend(
              pal.accentFill.withValues(alpha: .04),
              pal.modal,
            ),
            dialHandColor: pal.accentFill,
            dialTextColor: WidgetStateColor.resolveWith(
              (states) => states.contains(WidgetState.selected)
                  ? pal.onAccent
                  : pal.ink,
            ),
            dialTextStyle: TextStyle(fontSize: 14, fontFamily: formFont),
            dayPeriodShape: controlShape,
            dayPeriodTextColor: pal.ink,
            dayPeriodColor: Color.alphaBlend(
              pal.accentFill.withValues(alpha: .08),
              pal.modal,
            ),
            dayPeriodBorderSide: BorderSide(color: pal.cardBorder),
            entryModeIconColor: pal.accent,
            inputDecorationTheme: themedInputTheme(pal),
          ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: pal.modal,
      modalBackgroundColor: pal.modal,
      shape: pal.clean
          ? const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
            )
          : themeModalShape(pal),
      showDragHandle: true,
      dragHandleColor: pal.clean ? null : pal.ink2,
      dragHandleSize: pal.clean
          ? null
          : Size(
              pal.pixel || pal.terminal ? 28 : 40,
              pal.editorial || pal.terminal ? 2 : 4,
            ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      backgroundColor: pal.clean ? null : pal.modal,
      contentTextStyle: pal.clean
          ? null
          : TextStyle(color: pal.ink, fontFamily: formFont, fontSize: 13),
      actionTextColor: pal.clean ? null : pal.accent,
    ),
    dividerTheme: DividerThemeData(color: pal.hairline, thickness: 0.8),
  );
}

/// 通知原生「Flutter 首帧已上屏」：A12+ 会在应用首帧一出现时撤启动屏，
/// 若窗口还没从启动尺寸过渡到全屏，画面会被劈开。原生收到后按 OnPreDraw
/// 放行（见 MainActivity），延迟 150ms 是给窗口重排留一两帧。
const MethodChannel _splashChannel = MethodChannel('homework_radar/platform');

void _notifySplashReady() {
  _splashChannel.invokeMethod<bool>('splashDone').catchError((_) => null);
}

class HomeworkRadarApp extends StatefulWidget {
  const HomeworkRadarApp({super.key, required this.state});

  final AppState state;

  @override
  State<HomeworkRadarApp> createState() => _HomeworkRadarAppState();
}

class _HomeworkRadarAppState extends State<HomeworkRadarApp>
    with WidgetsBindingObserver {
  late (ThemeStyle, ThemeMode) _appearance;
  void _stateChanged() {
    final next = (widget.state.style, widget.state.themeMode);
    if (next == _appearance) return;
    setState(() => _appearance = next);
    _syncWidgetTheme();
  }

  @override
  void initState() {
    super.initState();
    _appearance = (widget.state.style, widget.state.themeMode);
    WidgetsBinding.instance.addObserver(this);
    widget.state.addListener(_stateChanged);
    _syncWidgetTheme();
    // 进程冷启动：首帧上屏后放行启动屏
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 150), _notifySplashReady);
      AppUpdateController.instance.onOpen = () {
        final context = _navigatorKey.currentState?.overlay?.context;
        if (context != null) unawaited(showAppUpdateDialog(context));
      };
      unawaited(AppUpdateController.instance.initialize());
    });
  }

  void _syncWidgetTheme() {
    unawaited(WidgetTheme.push(widget.state.style, widget.state.themeMode));
  }

  @override
  void didUpdateWidget(HomeworkRadarApp oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state != widget.state) {
      oldWidget.state.removeListener(_stateChanged);
      widget.state.addListener(_stateChanged);
      _appearance = (widget.state.style, widget.state.themeMode);
      _syncWidgetTheme();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed &&
        defaultTargetPlatform != TargetPlatform.android) {
      unawaited(
        backgroundSyncForApp?.foreground(false) ?? Future<void>.value(),
      );
    }
    // 进程内重建 Activity 时补发一次，防止启动屏被压住不放
    if (state == AppLifecycleState.resumed) {
      if (defaultTargetPlatform != TargetPlatform.android) {
        unawaited(
          backgroundSyncForApp?.foreground(true) ?? Future<void>.value(),
        );
      }
      _syncWidgetTheme();
      _notifySplashReady();
      unawaited(NotificationService.refreshPermission());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.state.removeListener(_stateChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '作业通',
      debugShowCheckedModeBanner: false,
      locale: const Locale('zh'),
      supportedLocales: const [Locale('zh'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      navigatorKey: _navigatorKey,
      theme: buildTheme(Brightness.light, widget.state.style),
      darkTheme: buildTheme(Brightness.dark, widget.state.style),
      themeMode: widget.state.themeMode,
      // 切样式/深浅时整树颜色平滑演变（StylePalette 有逐字段 lerp），
      // 350ms easeOutCubic 比默认 200ms linear 更有"换肤"的仪式感
      themeAnimationDuration: const Duration(milliseconds: 350),
      themeAnimationCurve: Curves.easeOutCubic,
      // 冷启动首帧 = 海报盖在主壳上（首帧只有海报，原生压屏尽快放行）。
      // 通知冷启动拉起时，启动页撤除后跳详情（onSplashFinished）。
      home: showSplashOnStart
          ? const _SplashHome()
          : MainShell(state: widget.state),
    );
  }
}

/// 冷启动首屏宿主：海报层（SplashPage）盖在主壳（MainShell）上。
/// 首帧只画海报——轻，原生压屏尽快放行；首帧一过就把 MainShell 插到
/// 海报下层预热，构建耗时藏在静态海报期间（画面无任何变化）。
/// 停留到点或点按跳过时撤掉海报层即进主页：零转场、零冷构建卡顿
/// （替代原先到点 pushReplacement 的交接方式）。
class _SplashHome extends StatefulWidget {
  const _SplashHome();

  @override
  State<_SplashHome> createState() => _SplashHomeState();
}

class _SplashHomeState extends State<_SplashHome> {
  bool _warmed = false; // 主页已在海报下层建好
  bool _splashGone = false; // 海报层已撤

  @override
  void initState() {
    super.initState();
    // 首帧只画海报；这一帧之后再插入主页预热（用户最早也要在首帧可见后
    // 才点得动屏幕，届时预热必然已开始/完成，点按跳过不会撞上未就绪主页）
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _warmed = true);
    });
  }

  void _dismissSplash() {
    if (_splashGone) return;
    setState(() => _splashGone = true);
    // 冷启动由通知拉起时：主页已就位，跳详情（消费一次）
    final finished = onSplashFinished;
    onSplashFinished = null;
    finished?.call();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        if (_warmed)
          MainShell(state: appStateForHome!, widgetLaunchReady: _splashGone),
        if (!_splashGone)
          Positioned.fill(child: SplashPage(onFinished: _dismissSplash)),
      ],
    );
  }
}

class MainShell extends StatefulWidget {
  const MainShell({
    super.key,
    required this.state,
    this.widgetLaunchReady = true,
  });

  final AppState state;
  final bool widgetLaunchReady;

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> with WidgetsBindingObserver {
  int _selected = 0;
  final _pageController = PageController();
  late final WidgetNavigation _widgetNavigation;
  int _widgetRouteVersion = 0;

  void _openWidgetDestination(WidgetDestination destination) {
    final version = ++_widgetRouteVersion;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || version != _widgetRouteVersion) return;
      final navigator = Navigator.of(context);
      navigator.popUntil((route) => route.isFirst);
      // Jump directly so warm launches do not leave the previous tab selected
      // during a transition underneath an immediately opened homework detail.
      _pageController.jumpToPage(destination.tab);
      final id = destination.homeworkId;
      if (id == null) return;
      if (!widget.state.homework.any((h) => h.id == id)) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('该作业已移除或隐藏，请在列表中查看当前作业')));
        return;
      }
      navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => HomeworkDetailPage(homeworkId: id),
        ),
      );
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  void _go(int i) {
    FocusManager.instance.primaryFocus?.unfocus();
    // During an animation the selected index can still be the origin. A tap
    // back to it must cancel that animation instead of being ignored.
    if (i == _selected && !_pageController.position.isScrollingNotifier.value) {
      return;
    }
    if ((i - _selected).abs() == 1) {
      _pageController.animateToPage(
        i,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    } else {
      _pageController.jumpToPage(i);
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _widgetNavigation = WidgetNavigation(onDestination: _openWidgetDestination);
    if (widget.widgetLaunchReady) _widgetNavigation.setReady();
    unawaited(
      _widgetNavigation.bind(
        HomeWidget.initiallyLaunchedFromHomeWidget(),
        HomeWidget.widgetClicked,
      ),
    );
  }

  @override
  void didUpdateWidget(covariant MainShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.widgetLaunchReady) _widgetNavigation.setReady();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_widgetNavigation.dispose());
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final state = widget.state;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: Scaffold(
        body: PageView(
          controller: _pageController,
          allowImplicitScrolling: true,
          onPageChanged: (i) {
            FocusManager.instance.primaryFocus?.unfocus();
            setState(() => _selected = i);
          },
          children: [
            KeepAlivePage(
              child: HomePage(state: state, onGoAccounts: () => _go(3)),
            ),
            KeepAlivePage(child: TimetablePage(state: state)),
            KeepAlivePage(child: CalendarPage(state: state)),
            KeepAlivePage(child: AccountsPage(state: state)),
            KeepAlivePage(child: SettingsPage(state: state)),
          ],
        ),
        bottomNavigationBar: ThemedNavigationBar(
          selectedIndex: _selected,
          onSelected: _go,
        ),
      ),
    );
  }
}

/// 让 PageView 里的页面常驻不销毁：切页保留各自状态（课表的周次选择等）。
class KeepAlivePage extends StatefulWidget {
  const KeepAlivePage({super.key, required this.child});

  final Widget child;

  @override
  State<KeepAlivePage> createState() => _KeepAlivePageState();
}

class _KeepAlivePageState extends State<KeepAlivePage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
