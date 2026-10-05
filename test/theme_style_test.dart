// 主题样式系统：五样式 × 明暗调色板完整性、buildTheme 装配、存储与备份接线。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homework_radar/main.dart' show buildTheme;
import 'package:homework_radar/services/backup_service.dart';
import 'package:homework_radar/services/storage.dart';
import 'package:homework_radar/services/update_service.dart';
import 'package:homework_radar/ui/tokens.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('五样式 × 明暗都能给出完整调色板', () {
    for (final style in ThemeStyle.values) {
      for (final bright in Brightness.values) {
        final pal = stylePalette(style, bright);
        final tag = '${style.name}/${bright.name}';
        expect(pal.bg.a, 1.0, reason: '$tag bg 必须不透明');
        expect(pal.modal.a, greaterThanOrEqualTo(0.9),
            reason: '$tag modal 允许微透但必须接近实底（弹层可读兜底）');
        expect(pal.accent.a, 1.0, reason: '$tag accent');
        // 像素直角 radius=0 是设计，其余样式必须大于 0（下面 pixel 分支另有断言）
        expect(pal.radius, greaterThanOrEqualTo(0), reason: '$tag radius');
        expect(pal.morandi, style == ThemeStyle.morandi, reason: tag);
        expect(pal.pixel, style == ThemeStyle.pixel, reason: tag);
        expect(pal.comic, style == ThemeStyle.comic, reason: tag);
        expect(pal.paper, style == ThemeStyle.paper, reason: tag);
        expect(pal.inkWash, style == ThemeStyle.amoled, reason: tag);
        expect(pal.receipt, style == ThemeStyle.receipt, reason: tag);
        expect(pal.editorial, style == ThemeStyle.editorial, reason: tag);
        expect(pal.terminal, style == ThemeStyle.terminal, reason: tag);
        expect(pal.journal, style == ThemeStyle.journal, reason: tag);
        // 带自绘底衬的样式必须声明 hasThemedBg（Scaffold 据此透明化，
        // 否则底衬被不透明底色盖住——莫兰迪/像素曾踩过）
        expect(
            pal.hasThemedBg,
            style == ThemeStyle.morandi ||
                style == ThemeStyle.pixel ||
                style == ThemeStyle.receipt ||
                style == ThemeStyle.terminal ||
                style == ThemeStyle.journal ||
                style == ThemeStyle.editorial,
            reason: tag);
        if (pal.inkWash) {
          expect(pal.cardWash, isNotNull, reason: '$tag 水墨必须有浓淡墨阶');
          expect(pal.cardWash!.length, 2, reason: tag);
        } else {
          expect(pal.cardWash, isNull, reason: tag);
        }
        if (pal.pixel) {
          expect(pal.radius, 0, reason: '$tag 像素直角');
        }
        if (pal.editorial) {
          expect(pal.shadow, isEmpty, reason: '$tag 杂志纯平，无阴影');
          expect(pal.radius, 0, reason: '$tag 杂志直角');
        }
        if (pal.terminal) {
          expect(pal.radius, lessThanOrEqualTo(2), reason: '$tag 终端微圆角窗格');
        }
      }
    }
  });

  test('调色板 lerp 是真插值：颜色/圆角平滑，身份开关过半切换', () {
    final a = stylePalette(ThemeStyle.clean, Brightness.light);
    final b = stylePalette(ThemeStyle.comic, Brightness.light);
    final mid = a.lerp(b, 0.5);
    expect(mid.bg.a, 1.0);
    expect(mid.bg, isNot(a.bg));
    expect(mid.bg, isNot(b.bg));
    expect(mid.radius, (a.radius + b.radius) / 2);
    expect(mid.accent, Color.lerp(a.accent, b.accent, 0.5));
    expect(mid.morandi, a.morandi, reason: 't<0.5 用 a 的身份开关');
    expect(a.lerp(b, 0.9).comic, b.comic, reason: 't>=0.5 用 b 的身份开关');
    // 墨阶渐变在两个水墨样式之间逐色插值，跨水墨/非水墨整体切换
    final i1 = stylePalette(ThemeStyle.amoled, Brightness.light);
    final i2 = stylePalette(ThemeStyle.amoled, Brightness.dark);
    expect(i1.lerp(i2, 0.5).cardWash![0],
        Color.lerp(i1.cardWash![0], i2.cardWash![0], 0.5));
    expect(a.lerp(b, 0.5).cardWash, isNull, reason: 't<0.5 用 a 的 cardWash');
    expect(stylePalette(ThemeStyle.clean, Brightness.light)
            .lerp(stylePalette(ThemeStyle.amoled, Brightness.light), 0.9)
            .inkWash,
        true, reason: 't>=0.5 用 b 的 inkWash');
  });

  test('全部样式卡不透明；墨黑无描边、层次靠墨阶', () {
    for (final style in ThemeStyle.values) {
      for (final bright in Brightness.values) {
        expect(stylePalette(style, bright).card.a, 1.0,
            reason: '${style.name}/${bright.name}');
      }
    }
    final amoled = stylePalette(ThemeStyle.amoled, Brightness.dark);
    expect(amoled.bg, Colors.black);
    expect(amoled.shadow, isEmpty, reason: '纯黑上阴影不可见');
    expect(amoled.cardBorder.a, 0, reason: '水墨无描边，层次全靠浓淡墨阶');
    // 浅色不再回退清夏：宣纸玉白底 + 墨晕阴影，是独立的水墨浅色语言
    final amoledLight = stylePalette(ThemeStyle.amoled, Brightness.light);
    expect(amoledLight.bg,
        isNot(stylePalette(ThemeStyle.clean, Brightness.light).bg),
        reason: '墨黑浅色必须是独立水墨语言，不能回退清夏');
    expect(amoledLight.shadow, isNotEmpty, reason: '浅色墨晕负责卡面分层');
  });

  test('buildTheme 注入 StylePalette，强调色/背景随样式走', () {
    for (final style in ThemeStyle.values) {
      final theme = buildTheme(Brightness.light, style);
      final pal = theme.extension<StylePalette>();
      expect(pal, isNotNull, reason: '${style.name} 必须挂上扩展');
      expect(pal!.accent, stylePalette(style, Brightness.light).accent);
      expect(theme.colorScheme.primary, pal.accent,
          reason: '${style.name} 组件主色必须与调色板一致');
      expect(theme.scaffoldBackgroundColor, pal.bg);
    }
  });

  test('深色锁：非清夏主题即使请求深色也返回浅色主题', () {
    for (final style in ThemeStyle.values) {
      final dark = buildTheme(Brightness.dark, style);
      if (style == ThemeStyle.clean) {
        expect(dark.scaffoldBackgroundColor,
            stylePalette(style, Brightness.dark).bg,
            reason: '清夏保留独立深色语言');
      } else {
        expect(dark.scaffoldBackgroundColor,
            stylePalette(style, Brightness.light).bg,
            reason: '${style.name} 未打磨深色观感，必须钳回浅色');
      }
    }
  });

  test('更新版本号比较：逐段数值比较，兼容 v 前缀与缺段', () {
    expect(compareVersions('1.0.1', '1.0.0'), greaterThan(0));
    expect(compareVersions('v1.1.0', '1.0.9'), greaterThan(0),
        reason: 'v 前缀要剥掉；9→10 是数值比较不是字典序');
    expect(compareVersions('1.0', '1.0.0'), 0, reason: '缺段补 0');
    expect(compareVersions('1.0.0', '1.0.0'), 0);
    expect(compareVersions('1.0.0', '0.9.9'), greaterThan(0));
    expect(compareVersions('0.9.9', '1.0.0'), lessThan(0));
    final info = UpdateInfo(
        version: '1.0.1',
        releaseUrl: 'https://github.com/x/y/releases',
        apkUrl: 'https://github.com/x/y/releases/download/v1.0.1/app.apk',
        notes: '');
    expect(info.isNewerThan('1.0.0'), true);
    expect(info.isNewerThan('1.0.1'), false);
    expect(info.isNewerThan('1.0.2'), false);
  });

  test('样式名解析：未知/空值回落 clean', () {
    expect(themeStyleFromName(null), ThemeStyle.clean);
    expect(themeStyleFromName('paper'), ThemeStyle.paper);
    expect(themeStyleFromName('amoled'), ThemeStyle.amoled);
    expect(themeStyleFromName('nonsense'), ThemeStyle.clean);
  });

  test('ui_style 存储往返', () async {
    SharedPreferences.setMockInitialValues({});
    await Storage.init();
    expect(Storage.uiStyle(), 'clean');
    await Storage.saveUiStyle('morandi');
    expect(Storage.uiStyle(), 'morandi');
  });

  test('备份携带并恢复界面样式', () async {
    SharedPreferences.setMockInitialValues({});
    await Storage.init();
    await Storage.saveUiStyle('paper');
    final exported = BackupService.encode();

    SharedPreferences.setMockInitialValues({});
    await Storage.init();
    expect(BackupService.exportMap()['settings']['uiStyle'], 'clean',
        reason: '默认样式也要随备份走，恢复端才能确定还原');
    await BackupService.importJson(exported);
    expect(Storage.uiStyle(), 'paper');
  });
}
