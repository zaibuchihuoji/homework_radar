// 作息时间配置：默认表兜底、自定义持久化、上课时刻计算、坏数据自愈。
// 另含本轮修复中可纯单测的 Storage（顶层损坏备份 / 日志导出脱敏）与
// 色板对比度用例——约束下唯一允许改动的测试文件，故集中在此。
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homework_radar/models/course.dart';
import 'package:homework_radar/services/safe_http.dart';
import 'package:homework_radar/services/section_times.dart';
import 'package:homework_radar/services/storage.dart';
import 'package:homework_radar/ui/tokens.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Storage.init();
  });

  test('未自定义时用默认作息表', () {
    expect(SectionTimes.current(), Course.sectionTimes);
  });

  test('自定义作息保存后生效并参与时刻计算', () async {
    // 全部 12 节平移到 9:00 开始
    final custom = <(int, int)>[
      for (var i = 0; i < 12; i++) (9 * 60 + i * 60, 9 * 60 + i * 60 + 45),
    ];
    await Storage.saveSectionTimes(custom);
    expect(SectionTimes.current(), custom);
    final t = SectionTimes.startOfDay(DateTime(2026, 9, 28), 1);
    expect(t?.hour, 9);
    expect(t?.minute, 0);
  });

  test('持久化往返', () async {
    final custom = <(int, int)>[
      for (var i = 0; i < 12; i++) (8 * 60 + i * 50, 8 * 60 + i * 50 + 45),
    ];
    await Storage.saveSectionTimes(custom);
    expect(Storage.sectionTimes(), custom);
  });

  test('存量坏数据按索引自愈：污染节替换为默认表，其余保留并写回', () async {
    // 模拟器里的真实存量：第7节被改成 [270,1035]（4:30-17:15）
    final raw = <(int, int)>[
      (480, 525),
      (535, 580),
      (600, 645),
      (655, 700),
      (870, 915),
      (925, 970),
      (270, 1035),
      (1045, 1090),
      (1140, 1185),
      (1195, 1240),
      (1250, 1295),
      (1305, 1350),
    ];
    await Storage.saveSectionTimes(raw);
    final t = Storage.sectionTimes()!;
    expect(t[6], (
      16 * 60 + 20,
      17 * 60 + 5,
    ), reason: '坏的第7节应原地替换为默认 16:20-17:05');
    expect(t[0], (480, 525), reason: '正常节保留，节次映射零错位');
    expect(t[7], (1045, 1090), reason: '后续正常节不受牵连');
    expect(t.length, 12);
    // 自愈结果写回 prefs（一次性洗净存量）。
    // 注意：mock 后端不加 flutter. 前缀（那是 Android 原生层干的），键是裸名。
    await Future<void>.delayed(const Duration(milliseconds: 100));
    final sp = await SharedPreferences.getInstance();
    final back = jsonDecode(sp.getString('section_times')!) as List;
    expect(back[6], [980, 1025]);
    expect(back[0], [480, 525]);
  });

  test('首尾相接不算重叠，不触发自愈', () async {
    final raw = <(int, int)>[
      (480, 525),
      (525, 570),
      (600, 645),
      (655, 700),
      (870, 915),
      (925, 970),
      (980, 1025),
      (1035, 1080),
      (1140, 1185),
      (1195, 1240),
      (1250, 1295),
      (1305, 1350),
    ];
    await Storage.saveSectionTimes(raw);
    final t = Storage.sectionTimes()!;
    expect(t[1], (525, 570), reason: 'start == 前一 end 是相接，合法');
  });

  test('非法区间（start>=end）同样自愈', () async {
    final raw = <(int, int)>[
      (480, 525),
      (535, 580),
      (600, 645),
      (655, 700),
      (870, 915),
      (925, 970),
      (500, 500),
      (1035, 1080),
      (1140, 1185),
      (1195, 1240),
      (1250, 1295),
      (1305, 1350),
    ];
    await Storage.saveSectionTimes(raw);
    final t = Storage.sectionTimes()!;
    expect(t[6], (16 * 60 + 20, 17 * 60 + 5), reason: 'start==end 非法，替换默认');
  });

  test('条目数不足 8 时整体回退默认表', () async {
    await Storage.saveSectionTimes([(480, 525), (535, 580)]);
    expect(Storage.sectionTimes(), isNull);
    expect(SectionTimes.current(), Course.sectionTimes);
  });

  test('表外节次返回 null（不再 clamp 到末节）', () {
    // 默认表 12 条：编辑表单允许选 1-16 节，学校只排到 12 节时
    // 13+ 节没有真实时刻，必须交调用方按「该节不存在」降级
    //（排课跳过/小组件空串/时间轴「—」），而不是把末节时刻当事实
    expect(SectionTimes.slotOf(13), isNull);
    expect(SectionTimes.slotOf(16), isNull);
    expect(SectionTimes.slotOf(0), isNull);
    expect(SectionTimes.startOfDay(DateTime(2026, 9, 28), 13), isNull);
    // 表内边界不受影响
    expect(SectionTimes.slotOf(1), isNotNull);
    expect(SectionTimes.slotOf(12), isNotNull);
    expect(SectionTimes.startOfDay(DateTime(2026, 9, 28), 12), isNotNull);
  });

  test('自定义表加长后，新表内的节次正常取值、再之外的仍为 null', () async {
    final custom = <(int, int)>[
      ...Course.sectionTimes,
      (22 * 60 + 40, 23 * 60 + 25), // 第 13 节
    ];
    await Storage.saveSectionTimes(custom);
    expect(SectionTimes.slotOf(13), (22 * 60 + 40, 23 * 60 + 25));
    expect(SectionTimes.startOfDay(DateTime(2026, 9, 28), 13)?.hour, 22);
    expect(SectionTimes.slotOf(14), isNull);
  });

  test('16 条自定义表、索引 13 损坏：只自愈该节，不整表回退', () async {
    // 16 节制学校：8:00 起、每节 45 分钟 + 10 分钟休息，排到 22:30
    final raw = <(int, int)>[
      for (var i = 0; i < 16; i++) (480 + i * 55, 480 + i * 55 + 45),
    ];
    raw[13] = (2000, 1195); // 第 14 节坏数据：start >= end
    await Storage.saveSectionTimes(raw);
    final t = Storage.sectionTimes()!;
    expect(t, hasLength(16), reason: '超出默认表的坏节不再触发整表回退——那会把前 12 节自定义时刻全灭');
    expect(t[12], (1140, 1185), reason: '坏节前的合法节原样保留');
    expect(t[13], (1185, 1230), reason: '合成占位 = (前节下课 1185, min(+45, 23:59))');
    expect(t[14], (1250, 1295), reason: '坏节后的合法节不受牵连');
    expect(t[15], (1305, 1350));
    // 自愈结果写回 prefs（表长保持 16，一次性洗净存量）
    await Future<void>.delayed(const Duration(milliseconds: 100));
    final sp = await SharedPreferences.getInstance();
    final back = jsonDecode(sp.getString('section_times')!) as List;
    expect(back, hasLength(16));
    expect(back[13], [1185, 1230]);
  });

  test('作业列表顶层损坏：原文先备份到 homework_json_corrupt_bak 再返回空', () async {
    const corrupt = '[{"id":"hw1","platform":"chaoxing"';
    SharedPreferences.setMockInitialValues({'homework_json': corrupt});
    await Storage.init();
    expect(Storage.homework(), isEmpty);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    final sp = await SharedPreferences.getInstance();
    expect(
      sp.getString('homework_json_corrupt_bak'),
      corrupt,
      reason: '下一次同步回写空列表前，唯一可恢复副本必须先落到独立键',
    );
  });

  test('作业列表 raw 为空时不产生损坏备份', () async {
    SharedPreferences.setMockInitialValues({'homework_json': ''});
    await Storage.init();
    expect(Storage.homework(), isEmpty);
    final sp = await SharedPreferences.getInstance();
    expect(sp.getString('homework_json_corrupt_bak'), isNull);
  });

  test('redactLogEntry：URL 凭据打码、body 截 600、其余字段原样', () {
    final e = SafeHttpLogEntry(
      DateTime(2026, 1, 1, 8, 30),
      'POST',
      'http://jw.example.edu.cn/login?csrfKey=SECRET&pwd=1234&t=1',
      200,
      'b' * 700,
    );
    final r = Storage.redactLogEntry(e);
    expect(r.url, 'http://jw.example.edu.cn/login?csrfKey=***&pwd=***&t=1');
    expect(r.bodySnippet, 'b' * 600);
    expect(r.method, 'POST');
    expect(r.status, 200);
    expect(r.time, e.time);
  });

  double wcagLinear(double c) =>
      c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4).toDouble();

  double wcagLuminance(Color c) =>
      0.2126 * wcagLinear(c.r) +
      0.7152 * wcagLinear(c.g) +
      0.0722 * wcagLinear(c.b);

  double wcagContrast(Color a, Color b) {
    final la = wcagLuminance(a), lb = wcagLuminance(b);
    return (max(la, lb) + 0.05) / (min(la, lb) + 0.05);
  }

  test('coursePalette 12 色互不重复，白底白字对比度全部 ≥4.5:1', () {
    expect(Tokens.coursePalette, hasLength(12));
    expect(Tokens.coursePalette.toSet(), hasLength(12), reason: '两门课撞默认色就无法区分');
    for (final c in Tokens.coursePalette) {
      expect(
        wcagContrast(c, Colors.white),
        greaterThanOrEqualTo(4.5),
        reason: '课程卡整块铺 $c，白字必须可读',
      );
    }
  });

  test('tertiary 文本色（ink3/ink3Dark）在浅深两种背景上对比度都 ≥4.5:1', () {
    expect(wcagContrast(Tokens.ink3, Tokens.card), greaterThanOrEqualTo(4.5));
    expect(wcagContrast(Tokens.ink3, Tokens.bg), greaterThanOrEqualTo(4.5));
    expect(
      wcagContrast(Tokens.ink3Dark, Tokens.cardDark),
      greaterThanOrEqualTo(4.5),
    );
    expect(
      wcagContrast(Tokens.ink3Dark, Tokens.bgDark),
      greaterThanOrEqualTo(4.5),
    );
  });
}
