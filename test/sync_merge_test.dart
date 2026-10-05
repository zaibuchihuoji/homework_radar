// 同步归并（SyncService.mergePlatform）：备注保留、空结果防御、MOOC 占位状态
// 不打回——这三条是「不丢作业」承诺的核心合并语义（#36/#250）。
import 'package:flutter_test/flutter_test.dart';
import 'package:homework_radar/models/homework.dart';
import 'package:homework_radar/services/sync_service.dart';

HomeworkItem hw(
  String id,
  PlatformKind p, {
  HwStatus s = HwStatus.todo,
  String? note,
}) =>
    HomeworkItem(
        id: id, platform: p, course: '课', title: 't-$id', status: s, note: note);

void main() {
  test('备注保留：平台空备注不冲掉用户备注', () {
    final merged = {'cx_1': hw('cx_1', PlatformKind.chaoxing, note: '需交纸质版')};
    mergePlatform(merged, [hw('cx_1', PlatformKind.chaoxing)],
        PlatformKind.chaoxing,
        complete: true);
    expect(merged['cx_1']!.note, '需交纸质版');
  });

  test('complete=false（抓取失败）不清理该平台旧条目', () {
    final merged = {
      'cx_1': hw('cx_1', PlatformKind.chaoxing),
      'mooc_1': hw('mooc_1', PlatformKind.mooc),
    };
    mergePlatform(merged, [], PlatformKind.chaoxing, complete: false);
    expect(merged.containsKey('cx_1'), isTrue, reason: '失败 ≠ 确认消失');
  });

  test('complete=true 且 incoming 非空才清理消失条目；手动条目永不清理', () {
    final merged = {
      'cx_old': hw('cx_old', PlatformKind.chaoxing),
      'manual_1': hw('manual_1', PlatformKind.manual),
    };
    mergePlatform(merged, [hw('cx_1', PlatformKind.chaoxing)],
        PlatformKind.chaoxing,
        complete: true);
    expect(merged.containsKey('cx_old'), isFalse);
    expect(merged.containsKey('manual_1'), isTrue);
  });

  test('complete=true 但本次 incoming 为空（如全部单课失败）不清理', () {
    final merged = {'cx_1': hw('cx_1', PlatformKind.chaoxing)};
    mergePlatform(merged, [], PlatformKind.chaoxing, complete: true);
    expect(merged.containsKey('cx_1'), isTrue);
  });

  test('MOOC 占位 todo 不打回旧条目的已完成/已提交状态', () {
    final merged = {
      'mooc_1': hw('mooc_1', PlatformKind.mooc, s: HwStatus.done),
      'mooc_2': hw('mooc_2', PlatformKind.mooc, s: HwStatus.submitted),
    };
    mergePlatform(
        merged,
        [hw('mooc_1', PlatformKind.mooc), hw('mooc_2', PlatformKind.mooc)],
        PlatformKind.mooc,
        complete: true);
    expect(merged['mooc_1']!.status, HwStatus.done,
        reason: 'MOOC 解析恒 todo，不是平台证据，不能覆盖本地完结态');
    expect(merged['mooc_2']!.status, HwStatus.submitted);
  });

  test('学习通/智慧树状态是解析出的真实值，仍以平台为准', () {
    final merged = {'cx_1': hw('cx_1', PlatformKind.chaoxing, s: HwStatus.done)};
    mergePlatform(merged, [hw('cx_1', PlatformKind.chaoxing)],
        PlatformKind.chaoxing,
        complete: true);
    expect(merged['cx_1']!.status, HwStatus.todo,
        reason: '平台真实状态变化要如实反映，不能因本地旧值卡死');
  });

  test('MOOC 新条目照常入库，备注与状态保持规则叠加', () {
    final merged = {
      'mooc_1': hw('mooc_1', PlatformKind.mooc, s: HwStatus.done, note: '已交'),
    };
    mergePlatform(
        merged,
        [hw('mooc_1', PlatformKind.mooc, note: '')],
        PlatformKind.mooc,
        complete: true);
    expect(merged['mooc_1']!.status, HwStatus.done);
    expect(merged['mooc_1']!.note, '已交');
  });
}
