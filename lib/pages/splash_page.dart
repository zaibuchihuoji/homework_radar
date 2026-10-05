/// 启动页：一张白净的排版海报，静态展示 1.2s（整屏点按可跳过），无任何动画。
///
/// 构图（与原生启动屏同一套素材，撤屏零跳变）：
/// · 徽章（splash_badge：LOGO + 应用名）固定在屏幕正中——
///   与 A12+ 启动屏图标槽 / launch_background 是同一张图同一个盒子；
/// · 宋体标语（splash_slogan：该交的作业 / 一份不落）悬在徽章上方，
///   随 Flutter 首帧出现——是整版的视觉主角；
/// · 底部一行平台脚注。
/// 启动页固定浅底（与 App 内浅色背景一致，深色模式同样浅底）。
/// 停留结束只回调 onFinished，交接由宿主（main.dart 的 _SplashHome）完成：
/// 主页已在海报下层预热好，撤掉海报层即可零卡顿直进。
library;

import 'dart:async';

import 'package:flutter/material.dart';

/// 与 android:launch_bg 同色（values/colors.xml）。
const _kLaunchBg = Color(0xFFF6F7F8);
const _kInk3 = Color(0xFF9CA3AF);

class SplashPage extends StatefulWidget {
  const SplashPage({super.key, required this.onFinished});

  /// 停留到点或用户点按跳过时回调（只回调一次），宿主据此撤掉海报层。
  final VoidCallback onFinished;

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> {
  /// 海报停留时长：标语读得完、不磨蹭。
  static const _holdDuration = Duration(milliseconds: 1200);

  Timer? _timer;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer(_holdDuration, _finish);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _finish() {
    if (_finished) return;
    _finished = true;
    widget.onFinished();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      // 急用直进：整屏点按跳过停留
      behavior: HitTestBehavior.opaque,
      onTap: _finish,
      child: Scaffold(
        backgroundColor: _kLaunchBg,
        body: LayoutBuilder(
          builder: (context, cons) {
            final centerY = cons.maxHeight / 2;
            return Stack(
              children: [
                // 宋体标语：整版的视觉主角，悬在徽章上方。
                // 钳住最小边距：横屏（逻辑高约 360dp）时 centerY-247 为负，
                // 标语会被画出屏幕外
                Positioned(
                  left: 0,
                  right: 0,
                  top: (centerY - 247).clamp(16.0, double.infinity),
                  child: const Center(
                    child: Image(
                      image: AssetImage('assets/splash/splash_slogan.png'),
                      width: 320,
                      filterQuality: FilterQuality.high,
                      excludeFromSemantics: true,
                    ),
                  ),
                ),
                // 徽章固定在屏幕正中：与原生启动屏图标同位同尺寸，撤屏零跳变
                const Center(
                  child: Image(
                    image: AssetImage('assets/splash/splash_badge.png'),
                    width: 240,
                    height: 240,
                    filterQuality: FilterQuality.high,
                    excludeFromSemantics: true,
                  ),
                ),
                // 平台脚注
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 36,
                  child: const Text(
                    '学习通 · 中国大学MOOC · 智慧树 · 教务课表',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11,
                      letterSpacing: 2,
                      color: _kInk3,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
