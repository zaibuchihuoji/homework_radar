import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'app_state.dart';
import 'pages/accounts_page.dart';
import 'pages/calendar_page.dart';
import 'pages/detail_page.dart';
import 'pages/home_page.dart';
import 'pages/settings_page.dart';
import 'pages/splash_page.dart';
import 'pages/timetable_page.dart';
import 'services/notification_service.dart';
import 'services/storage.dart';
import 'services/timetable_widget.dart';
import 'ui/adaptive.dart';
import 'ui/tokens.dart';

final _navigatorKey = GlobalKey<NavigatorState>();

/// 冷启动首帧是否显示启动动画（每次进程启动只播一次）。
/// 热重启（debug 下的 reload）会重置这个变量，但真实用户只有冷启动，
/// 行为正确；通知跳转详情不受影响。
bool showSplashOnStart = true;

/// main() 里挂好的全局 AppState，供启动页交接时取用。
AppState? appStateForHome;

void _openDetail(String homeworkId) {
  _navigatorKey.currentState?.push(
    MaterialPageRoute(
      builder: (_) => HomeworkDetailPage(homeworkId: homeworkId),
    ),
  );
}

/// 冷启动由通知拉起时挂上的回调：启动页撤除（主页就位）后跳详情。
/// 只消费一次，用完即清。
VoidCallback? onSplashFinished;

/// 冷启动深链交接通道：main() 拿到通知启动 payload 后 complete 它，
/// 启动页撤除时等它（最多 3 秒）。不能让撤除回调直接读一个可能尚未
/// 赋值的 onSplashFinished——通知 init 内含 Android 13+ 权限弹窗
/// （必超启动页 1.2s 停留），先到点的 Timer/整屏点按会把深链读成
/// null 而永久丢失；等待通道让「点按早到」只是晚几秒跳详情。
final Completer<String?> launchPayloadReady = Completer<String?>();

Future<void> main() async {
  // 启动关键路径此前全程裸奔：runApp 前任何一步抛错就是一块死屏
  // （原生 4 秒兜底后无内容），runApp 后抛错会静默砍掉深链/提醒重排/
  // 小组件推送/自动同步。统一挂上全局兜底，错误走 FlutterError 报告。
  await runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    FlutterError.onError = (details) {
      FlutterError.presentError(details);
    };
    ui.PlatformDispatcher.instance.onError = (e, st) {
      return true; // 已由 zone 兜底记录，不交给默认处理器再炸一次
    };

    // 首帧路径上只留必要的本地读取：通知、小组件、同步全部让路到 runApp 之后。
    // 系统启动屏会定格到首帧出现为止——之前这里串行等完五件事，开屏后半段
    // 全是静止画面，是"启动墨迹"的主因。
    await Storage.init();
    final state = AppState();
    appStateForHome = state;
    // 先上屏本地已有数据（作业 + 课表），主页一出来就有内容
    await state.loadLocal();
    runApp(HomeworkRadarApp(state: state));

    // ---- 以下都在首帧之后进行，不挡开屏 ----
    // 深链交接先挂上：必须排在通知 init（内含权限弹窗，await 必超启动页
    // 1.2s）与 initialPayload 之前——否则启动页撤除回调还是 null，深链必丢。
    // 回调里等 launchPayloadReady（最多 3 秒）：点按/Timer 早到只是等
    // payload，不会再读到空值。
    onSplashFinished = () async {
      final payload = await launchPayloadReady.future.timeout(
        const Duration(seconds: 3),
        onTimeout: () => null,
      );
      if (payload != null && payload.isNotEmpty) _openDetail(payload);
    };
    // 通知初始化失败（权限通道异常等）不能连坐深链交接与冷启动收尾：
    // 补排/小组件/自动同步照常执行，payload 按没有拉起处理
    String? launchPayload;
    try {
      await NotificationService.init();
      NotificationService.onSelect = _openDetail;
      launchPayload = await NotificationService.initialPayload();
    } catch (e, st) {
      debugPrint('notification init failed: $e\n$st');
    }
    // payload 就绪（含「没有通知拉起」的 null）：放行等待中的撤除回调
    if (!launchPayloadReady.isCompleted) {
      launchPayloadReady.complete(launchPayload);
    }
    // 提醒只会在打开 App 时重排：冷启动先按本地数据补排一次，
    // 上次把上课提醒清掉的操作不会一直生效到下次同步
    unawaited(
      NotificationService.reschedule(state.homework, courses: state.courses),
    );
    unawaited(TimetableWidget.push(state.courses));
    if (state.hasAnyAccount) {
      Future.microtask(state.syncAll);
    }
  }, (e, st) {
    // 同步/通知/小组件链路的未捕获异步异常：记到 debug 控制台即可，
    // 不允许再向上炸穿（老实现会让 syncing 卡死、深链丢失）
    debugPrint('uncaught zone error: $e\n$st');
  });
}

ThemeData buildTheme(Brightness brightness, ThemeStyle style) {
  // 深色锁：只有清夏打磨过深色观感，其余主题统一钳回浅色——
  // 即便系统深色/用户选过深色，非清夏下深色调色板也不会生效
  //（设置页的主题模式行同步加锁说明）
  if (style != ThemeStyle.clean && brightness == Brightness.dark) {
    return buildTheme(Brightness.light, style);
  }
  final dark = brightness == Brightness.dark;
  final pal = stylePalette(style, brightness);
  final scheme = ColorScheme.fromSeed(
    seedColor: pal.accent,
    brightness: brightness,
  ).copyWith(
    primary: pal.accent,
    surface: pal.modal,
    surfaceContainerLowest: pal.modal,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: pal.bg,
    extensions: [pal],
    textTheme: TextTheme(
      displayLarge: TextStyle(
        fontSize: 30,
        height: 1.1,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.5,
        color: pal.ink,
      ),
      titleLarge: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: pal.ink,
      ),
      titleMedium: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: pal.ink,
      ),
      bodyMedium: TextStyle(fontSize: 13, height: 1.5, color: pal.ink2),
      labelMedium: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: pal.ink2,
      ),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      foregroundColor: pal.ink,
      systemOverlayStyle: dark
          ? SystemUiOverlayStyle.light
          : SystemUiOverlayStyle.dark,
      titleTextStyle: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: pal.ink,
        fontFamily: pal.paper ? 'serif' : null,
        letterSpacing: pal.inkWash ? 5 : null,
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: pal.accent,
      foregroundColor: pal.onAccent,
      elevation: 0,
      highlightElevation: 0,
      // 漫画的分镜感：强调色块加一圈墨线勾边（与卡片同一勾线色）
      shape: pal.morandi
          // 莫兰迪的 FAB 是一颗奶油圆糖
          ? const CircleBorder()
          : RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(pal.inkWash ? 10 : pal.radius + 2),
        side: pal.comic
            ? BorderSide(color: pal.cardBorder, width: 2)
            : pal.paper
                // 暖纸的 FAB 是"印章"：方角 + 墨线描边
                ? BorderSide(
                    color: pal.ink.withValues(alpha: 0.65), width: 1.4)
                : pal.inkWash
                    // 水墨的 FAB 是"落款大印"：近方朱印 + 白文边栏
                    ? BorderSide(
                        color: Colors.white.withValues(alpha: 0.85),
                        width: 1.8)
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
          pal.receipt || pal.terminal || pal.editorial || pal.pixel
              ? const RoundedRectangleBorder(
                  borderRadius: BorderRadius.all(Radius.circular(2)))
              : const StadiumBorder(),
        ),
      ),
    ),
    // 主按钮 = 光源：品牌色淡淡一圈光晕，照亮周围但不抢眼。
    // 禁用态必须关掉光晕（发光的灰药丸=糊），换成干净的浅灰底+灰字。
    // 水墨例外：主按钮是"钤印"——近方朱印、落墨影（印章不发光），不是胶囊。
    filledButtonTheme: FilledButtonThemeData(
      style: ButtonStyle(
        elevation: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.disabled) ? 0 : pal.inkWash ? 2 : 5),
        shadowColor: WidgetStateProperty.all(pal.inkWash
            ? Colors.black.withValues(alpha: dark ? 0 : 0.16)
            : pal.accent.withValues(alpha: 0.55)),
        backgroundColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.disabled)
                ? (dark ? Colors.white.withValues(alpha: 0.07) : Colors.black.withValues(alpha: 0.05))
                : pal.accent),
        foregroundColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.disabled)
                ? (dark ? Tokens.ink2Dark : Tokens.ink2)
                : pal.onAccent),
        shape: WidgetStateProperty.all(
          pal.pixel
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
                          borderRadius: BorderRadius.all(Radius.circular(2)))
                      : pal.inkWash
                          ? RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(9))
                          : const RoundedRectangleBorder(
                              borderRadius:
                                  BorderRadius.all(Radius.circular(999))),
        ),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: pal.modal,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: pal.modal,
      modalBackgroundColor: pal.modal,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      showDragHandle: true,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
    dividerTheme: DividerThemeData(
      color: pal.hairline,
      thickness: 0.8,
    ),
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
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // 进程冷启动：首帧上屏后放行启动屏
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 150), _notifySplashReady);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 进程内重建 Activity 时补发一次，防止启动屏被压住不放
    if (state == AppLifecycleState.resumed) _notifySplashReady();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.state,
      builder: (context, _) => MaterialApp(
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
      ),
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
        if (_warmed) MainShell(state: appStateForHome!),
        if (!_splashGone)
          Positioned.fill(child: SplashPage(onFinished: _dismissSplash)),
      ],
    );
  }
}

class MainShell extends StatefulWidget {
  const MainShell({super.key, required this.state});

  final AppState state;

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  int _selected = 0;
  final _pageController = PageController();

  // 底栏：检测滚动方向——向下滚动就隐藏，向上滚动就显示。
  bool _navVisible = true;
  double _lastScrollPixels = 0;

  bool _onScrollNotification(ScrollNotification n) {
    // 页面策略：
    // - 作业页、设置页：内容可能超一屏 → 启用滚动隐藏（下滚藏并保持，上滚显）
    // - 课表页：纵向表格滚不动，横滑是切周次（横向 PageView 的滚动通知会
    //   冒泡上来且 metrics 是横向的，曾被误判成"向下滚动"触发隐藏）→ 常驻
    // - 日历页、账号页：按约定常驻
    if (_selected != 0 && _selected != 4) {
      _lastScrollPixels = n.metrics.pixels;
      if (!_navVisible) setState(() => _navVisible = true);
      return false;
    }
    final metrics = n.metrics;
    // 忽略横向滚动通知（PageView 横滑等）
    if (metrics.axis == Axis.horizontal) {
      _lastScrollPixels = metrics.pixels;
      return false;
    }
    // 内容不足一屏（不可滚动）→ 始终显示
    if (metrics.maxScrollExtent <= 0) {
      _lastScrollPixels = metrics.pixels;
      if (!_navVisible) setState(() => _navVisible = true);
      return false;
    }
    // 回到顶部附近 → 显示（页面到头了，底栏没有遮挡意义）
    if (metrics.pixels <= 24) {
      _lastScrollPixels = metrics.pixels;
      if (!_navVisible) setState(() => _navVisible = true);
      return false;
    }
    final delta = metrics.pixels - _lastScrollPixels;
    _lastScrollPixels = metrics.pixels;
    if (delta > 2 && _navVisible) {
      setState(() => _navVisible = false); // 向下滚动 → 隐藏并保持（悬停不恢复）
    } else if (delta < -2 && !_navVisible) {
      setState(() => _navVisible = true); // 向上滚动 → 显示
    }
    return false;
  }

  // 液态玻璃胶囊：切换时整块玻璃像水滴一样流到目标标签上
  late final AnimationController _flowCtrl;
  bool _flowing = false;
  double _lastPos = 0;

  static const _labels = ['作业', '课表', '日历', '账号', '设置'];
  static const _icons = <(IconData, IconData)>[
    (Icons.assignment_outlined, Icons.assignment_rounded),
    (Icons.bento_outlined, Icons.bento_rounded),
    (Icons.calendar_month_outlined, Icons.calendar_month_rounded),
    (Icons.person_outline, Icons.person_rounded),
    (Icons.settings_outlined, Icons.settings_rounded),
  ];

  void _go(int i) {
    if (i == _selected) return;
    // 页面先落位：目标页首次构建的卡顿发生在玻璃流动之前，不会被看见；
    // 然后玻璃整块从旧位置流到新标签上。
    // 曲线必须出手快、落点缓（easeOutExpo 系）：跨页流动时玻璃在中间标签
    // 只是一闪而过，绝不能让它在慢加速里在前排标签上逗留。
    if ((i - _selected).abs() == 1) {
      _pageController.animateToPage(
        i,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    } else {
      _pageController.jumpToPage(i);
    }
    setState(() => _flowing = true);
    _flowCtrl
        .animateTo(
          i.toDouble(),
          duration: const Duration(milliseconds: 420),
          curve: const Cubic(0.22, 1.0, 0.36, 1.0),
        )
        .whenComplete(() => setState(() => _flowing = false));
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _flowCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
      // 值域必须是完整标签区间：控制器默认上限 1.0，会把 animateTo(4.0)
      // 钳在第二个标签上，玻璃就永远"先停在第二个再瞬移"
      lowerBound: 0,
      upperBound: (_labels.length - 1).toDouble(),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _flowCtrl.dispose();
    _pageController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 无后台同步，回到前台时补一次：有账号且超过 6 小时未同步就自动同步，
    // 让提醒在用户日常使用中保持新鲜。
    if (state != AppLifecycleState.resumed) return;
    final s = widget.state;
    if (!s.hasAnyAccount || s.syncing) return;
    final last = s.lastSync;
    if (last == null ||
        DateTime.now().difference(last) > const Duration(hours: 6)) {
      s.syncAll();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final brand = accentColor(context);
    final ink3 = textFaint(context);

    return Scaffold(
      extendBody: true,
      body: NotificationListener<ScrollNotification>(
        onNotification: _onScrollNotification,
        child: PageView(
          controller: _pageController,
          allowImplicitScrolling: true,
          onPageChanged: (i) {
            setState(() => _selected = i);
            // 切 tab 时底栏复位显示，并清掉跨页残留的滚动基准——
            // 不清的话切回作业页的首个纵向 delta 会混入横向偏移，
            // 方向误判导致上滚首帧误藏底栏（下一帧恢复，闪烁）
            _lastScrollPixels = 0;
            if (!_navVisible) setState(() => _navVisible = true);
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
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: AnimatedSlide(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          offset: _navVisible ? Offset.zero : const Offset(0, 1.4),
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 180),
            opacity: _navVisible ? 1 : 0,
            child: Container(
          // 液态玻璃悬浮栏：内容从底下穿过，实时毛玻璃 + 高光描边
          margin: const EdgeInsets.fromLTRB(14, 0, 14, 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(32),
            // 描边画在最外层（与裁剪同半径），整圈均匀、不被 ClipRRect 裁掉半像素；
            // 深色壁纸上去掉"白铁丝"感：亮度随明暗自适应且整体收敛
            border: Border.all(
              color: Colors.white.withValues(alpha: dark ? 0.10 : 0.55),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: dark ? 0.22 : 0.08),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(31),
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 22, sigmaY: 22),
              child: Container(
                height: 66,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.white.withValues(alpha: dark ? 0.14 : 0.72),
                      Colors.white.withValues(alpha: dark ? 0.05 : 0.45),
                    ],
                  ),
                ),
                child: AnimatedBuilder(
                  animation: Listenable.merge([_pageController, _flowCtrl]),
                  builder: (context, _) {
                    // 手指拖页时胶囊贴手；点按切换时玻璃整块流动过去
                    final pos = _flowing
                        ? _flowCtrl.value
                        : (_pageController.hasClients
                                  ? (_pageController.page ??
                                        _selected.toDouble())
                                  : _selected.toDouble())
                              .clamp(0.0, (_labels.length - 1).toDouble());

                    return LayoutBuilder(
                      builder: (context, cons) {
                        final itemW = cons.maxWidth / _labels.length;
                        // 玻璃整块流过去：按移动速度横向拉伸（水滴感），落定恢复
                        final v = (pos - _lastPos).abs();
                        _lastPos = pos;
                        final stretch = (1 + v * 6).clamp(1.0, 1.9);
                        final pill = Positioned(
                          left: (pos + 0.5) * itemW - 30 * stretch,
                          top: 33 - 17 / stretch,
                          width: 60 * stretch,
                          height: 34 / stretch,
                          child: Center(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: dark
                                    ? Colors.white.withValues(alpha: 0.14)
                                    : Colors.black.withValues(alpha: 0.045),
                                borderRadius: BorderRadius.circular(17),
                                border: Border.all(
                                  color: Colors.white.withValues(
                                    alpha: dark ? 0.18 : 0.85,
                                  ),
                                  width: 1,
                                ),
                              ),
                            ),
                          ),
                        );

                        return SizedBox(
                          height: 66,
                          child: Stack(
                            children: [
                              pill,
                              Row(
                                children: [
                                  for (var i = 0; i < _labels.length; i++)
                                    Expanded(
                                      // tab 角色与选中态语义：裸 GestureDetector 下
                                      // TalkBack 只能读到「未标记」，无法得知当前页
                                      child: Semantics(
                                        button: true,
                                        selected: i == _selected,
                                        label: '${_labels[i]}标签页',
                                        child: GestureDetector(
                                          behavior: HitTestBehavior.opaque,
                                          onTap: () => _go(i),
                                          child: Builder(
                                          builder: (context) {
                                            // 图标颜色随融合进度点亮/退灰
                                            var color = Color.lerp(
                                              ink3,
                                              brand,
                                              (1 - (pos - i).abs()).clamp(
                                                0.0,
                                                1.0,
                                              ),
                                            )!;
                                            final lit =
                                                (1 - (pos - i).abs()) > 0.5;
                                            return Column(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              children: [
                                                Transform.scale(
                                                  scale: lit ? 1.04 : 1.0,
                                                  // 课表页签用手绘 mini 课程表：
                                                  // 网格 + 一格实心"课程块"
                                                  child: i == 1
                                                      ? SizedBox(
                                                          width: 23,
                                                          height: 23,
                                                          child: CustomPaint(
                                                            painter:
                                                                _TimetableGlyph(
                                                              filled: lit,
                                                              color: color,
                                                            ),
                                                          ),
                                                        )
                                                      : Icon(
                                                          lit
                                                              ? _icons[i].$2
                                                              : _icons[i].$1,
                                                          size: 23,
                                                          color: color,
                                                        ),
                                                ),
                                                const SizedBox(height: 2),
                                                Text(
                                                  _labels[i],
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    fontWeight: lit
                                                        ? FontWeight.w600
                                                        : FontWeight.w500,
                                                    color: lit ? brand : ink3,
                                                  ),
                                                ),
                                              ],
                                            );
                                          },
                                        ),
                                      ),
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
        ),
      ),
    );  }
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

/// 底栏"课表"页签的手绘图标：市面课程表 App 的经典"彩色格子"隐喻——
/// 左边一块连堂长课，右边两节短课。选中态上课程色实心，
/// 未选中态灰色描边，与其他页签的轮廓风格一致。
class _TimetableGlyph extends CustomPainter {
  _TimetableGlyph({required this.filled, required this.color});

  final bool filled;
  final Color color; // 未选中态的描边灰

  @override
  void paint(Canvas canvas, Size size) {
    // Material 图标 23px 视口里墨迹只占 ~85%，按同比例内缩，
    // 否则比旁边几个页签图标显大一圈
    final s = size.shortestSide * 0.85;
    canvas.translate((size.shortestSide - s) / 2, (size.shortestSide - s) / 2);
    final gap = s * 0.10;
    final rad = Radius.circular(s * 0.12);
    final w = s * 0.42;
    final x2 = w + gap;
    final blocks = [
      (Rect.fromLTWH(0, 0, w, s), const Color(0xFF2563EB)), // 连堂·蓝
      (Rect.fromLTWH(x2, 0, s - x2, w), const Color(0xFFD97706)), // 短课·琥珀
      (Rect.fromLTWH(x2, x2, s - x2, s - x2), const Color(0xFF0D9488)), // 短课·青
    ];
    if (filled) {
      for (final (r, c) in blocks) {
        canvas.drawRRect(RRect.fromRectAndRadius(r, rad), Paint()..color = c);
      }
    } else {
      for (final (r, _) in blocks) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(r, rad),
          Paint()
            ..color = color
            ..style = PaintingStyle.stroke
            ..strokeWidth = s * 0.09,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_TimetableGlyph old) =>
      old.filled != filled || old.color != color;
}
