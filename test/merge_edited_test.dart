// 重新导入时人工修正课程（edited）优先保留的合并策略。
import 'package:flutter_test/flutter_test.dart';
import 'package:homework_radar/app_state.dart';
import 'package:homework_radar/models/course.dart';

Course c(String id, {bool edited = false}) => Course(
      id: id,
      name: '课$id',
      weekday: 1,
      startSection: 1,
      endSection: 2,
      weeks: const [1, 2],
      edited: edited,
    );

/// 模拟教务真实形状的课：id 由 makeId 生成（同名同槽同 id）。
Course zf(String name, int wd, int s, int e, {List<int>? weeks}) => Course(
      id: Course.makeId(name: name, weekday: wd, startSection: s, endSection: e),
      name: name,
      weekday: wd,
      startSection: s,
      endSection: e,
      weeks: weeks ?? const [1, 2, 3],
    );

/// 模拟编辑表单保存链路（course_edit_sheet._save）：保留 id、带 edited 标记，
/// 首次编辑把编辑前的 key 记成锚点（已有锚点不覆盖）。
Course editedLikeSheet(Course old,
        {String? name,
        String? teacher,
        int? weekday,
        int? start,
        int? end,
        List<int>? weeks}) =>
    Course(
      id: old.id,
      name: name ?? old.name,
      teacher: teacher ?? old.teacher,
      room: old.room,
      weekday: weekday ?? old.weekday,
      startSection: start ?? old.startSection,
      endSection: end ?? old.endSection,
      weeks: weeks ?? old.weeks,
      edited: true,
      anchorKey: old.anchorKey ?? old.editKey,
    );

void main() {
  test('同 id 且 edited 的旧课覆盖新抓取结果', () {
    final incoming = [c('a'), c('b'), c('c')];
    final existing = [c('a', edited: true), c('b')];
    final merged = AppState.mergeEdited(incoming, existing);
    expect(merged.map((e) => e.id), ['a', 'b', 'c']);
    expect(merged.firstWhere((e) => e.id == 'a').edited, isTrue,
        reason: '人工修正过的课程要保留');
    expect(merged.firstWhere((e) => e.id == 'b').edited, isFalse,
        reason: '没修正过的以新抓取为准');
  });

  test('没有 edited 课程时原样返回', () {
    final incoming = [c('a'), c('b')];
    expect(AppState.mergeEdited(incoming, [c('x'), c('y')]), same(incoming));
  });

  test('手动添加的课程在重抓后保留（教务里没有对应条目）', () {
    final incoming = [c('a'), c('b')];
    final existing = [
      c('a'),
      c('manual_1', edited: true),
      c('manual_2'),
    ];
    final merged = AppState.mergeEdited(incoming, existing);
    expect(merged.map((e) => e.id), containsAll(['a', 'b', 'manual_1', 'manual_2']),
        reason: '手动课程教务抓取拿不回来，合并时必须追加保留');
    expect(merged.length, 4);
  });

  test('只有手动课程、没有修正课时也走追加', () {
    final incoming = [c('a')];
    final merged = AppState.mergeEdited(incoming, [c('manual_9')]);
    expect(merged.map((e) => e.id), ['a', 'manual_9']);
  });

  test('union 模式：部分导入不清掉未提及的旧课（兜底导入场景）', () {
    // existing 模拟完整课表（同名同槽，模拟真实 makeId），incoming 只补一门
    Course real(String name, int wd, int s, {bool edited = false}) => Course(
          id: Course.makeId(name: name, weekday: wd, startSection: s, endSection: s + 1),
          name: name,
          weekday: wd,
          startSection: s,
          endSection: s + 1,
          weeks: const [1, 2, 3],
          edited: edited,
        );
    final existing = [
      real('高等数学', 1, 1),
      real('大学英语', 3, 1),
      real('数据结构', 5, 3),
      real('大学英语', 3, 1, edited: true), // 同 key 的人工修正版
      real('体育课', 6, 5),
    ];
    final incoming = [real('Math101', 2, 1)];
    final merged = AppState.mergeEdited(incoming, existing, union: true);

    expect(merged.map((e) => e.name), containsAll([
      '高等数学', '数据结构', '体育课', 'Math101',
    ]), reason: '未提及的旧课必须保留');
    expect(merged.where((e) => e.name == '大学英语').length, 1,
        reason: '同 key 只留一份，且优先人工修正版');
    expect(merged.firstWhere((e) => e.name == '大学英语').edited, isTrue);

    // 非 union（完整抓取）：以 incoming 为主干，未提及的旧课清掉
    //（体育课不是 manual_ 前缀，不豁免）
    final full = AppState.mergeEdited(incoming, existing);
    expect(full.map((e) => e.name), ['Math101']);
  });

  test('改名后重抓：修正按锚点找回，不静默丢失', () {
    final original = zf('高等数学', 1, 1, 2);
    final renamed = editedLikeSheet(original, name: '高数（强化）', weeks: const [1, 2, 3, 4]);
    // 编辑保存后存储里只有改名后的那一份；重抓时教务还叫旧名
    final incoming = [zf('高等数学', 1, 1, 2), zf('数据结构', 5, 3, 4)];
    final merged = AppState.mergeEdited(incoming, [renamed]);
    expect(merged.map((e) => e.name), ['高数（强化）', '数据结构'],
        reason: 'incoming 的 key 对不上修正课，必须按 anchorKey 兜底应用修正');
    final got = merged.first;
    expect(got.edited, isTrue);
    expect(got.weeks, [1, 2, 3, 4], reason: '修正值（改过的周次）随锚点一起保留');
    expect(got.anchorKey, original.editKey, reason: '锚点是编辑前的 key');
  });

  test('挪课后重抓：修正按锚点应用，旧槽位的原课不再并存', () {
    final original = zf('大学英语', 3, 1, 2);
    final moved = editedLikeSheet(original, weekday: 5, start: 6, end: 7);
    final incoming = [zf('大学英语', 3, 1, 2), zf('数据结构', 5, 3, 4)];
    final merged = AppState.mergeEdited(incoming, [moved]);
    expect(merged.where((e) => e.name == '大学英语').length, 1,
        reason: '旧槽位的原课被挪课后的修正课顶替，不是两条并存');
    final got = merged.firstWhere((e) => e.name == '大学英语');
    expect(got.weekday, 5);
    expect(got.startSection, 6);
    expect(got.edited, isTrue);
    expect(merged.map((e) => e.name), contains('数据结构'),
        reason: '无关课程不受牵连');
  });

  test('union 部分导入：锚点命中的旧课不再 kept 成同槽双份', () {
    final original = zf('高等数学', 1, 1, 2);
    final renamed = editedLikeSheet(original, name: '高数（强化）');
    // 兜底导入只贴了旧槽位（改名前的 key）那门课
    final incoming = [zf('高等数学', 1, 1, 2)];
    final merged = AppState.mergeEdited(incoming, [renamed], union: true);
    expect(merged.length, 1,
        reason: '修正课经锚点应用后，其旧课不得再按 kept 保留（同槽双份幽灵）');
    expect(merged.single.name, '高数（强化）');
    expect(merged.single.edited, isTrue);

    // 锚点槽位未被本次导入提到时，修正课照常按 kept 保留（不误伤）
    final untouched =
        AppState.mergeEdited([zf('数据结构', 5, 3, 4)], [renamed], union: true);
    expect(untouched.where((e) => e.name == '高数（强化）').length, 1);
  });

  test('同 key 撞键（endSection 不同）：修正只落到对应节次的那条，不互相吞', () {
    // 前半学期 1-2 节、后半延到 1-3 节：两条同 key（name#weekday#start）、不同 id
    final short = zf('大学英语', 3, 1, 2, weeks: const [1, 2, 3, 4, 5, 6, 7, 8]);
    final long = zf('大学英语', 3, 1, 3, weeks: const [9, 10, 11, 12, 13, 14, 15, 16]);
    // 用户改了 short 的教师（key 未变，无需锚点）
    final editedShort = editedLikeSheet(short, teacher: '张三');
    final incoming = [zf('大学英语', 3, 1, 2), zf('大学英语', 3, 1, 3)];
    final merged = AppState.mergeEdited(incoming, [editedShort, long]);
    expect(merged.length, 2, reason: '撞键的两条都要在，不能整组折叠成一条');
    final applied = merged.where((e) => identical(e, editedShort)).toList();
    expect(applied.length, 1, reason: '同一条修正只应用一次');
    expect(applied.single.endSection, 2, reason: '优先落到 endSection 与修正一致的 incoming');
    expect(merged.where((e) => e.endSection == 3).single.edited, isFalse,
        reason: '另一条按普通 incoming 保留，不被修正吞掉');
  });

  test('anchorKey 持久化往返：带锚点带出、缺失读回 null（向后兼容）', () {
    final renamed = editedLikeSheet(zf('高等数学', 1, 1, 2), name: '高数（强化）');
    final back = Course.fromJson(renamed.toJson());
    expect(back.anchorKey, '高等数学#1#1');
    expect(back.edited, isTrue);
    // 旧版本落盘的数据没有该键，读回 null
    expect(Course.fromJson(zf('数据结构', 5, 3, 4).toJson()).anchorKey, isNull);
  });

  test('union：同槽单双周双胞胎（同 key 同 id 不同周次）都要保留，不按 key 折叠', () {
    final odd = zf('大学英语', 3, 1, 2, weeks: const [1, 3, 5, 7]);
    final even = zf('大学英语', 3, 1, 2, weeks: const [2, 4, 6, 8]);
    expect(odd.id, even.id, reason: '前置：makeId 不含周次，双胞胎同 id');
    final incoming = [zf('高等数学', 1, 1, 2)];
    final merged = AppState.mergeEdited(incoming, [odd, even], union: true);
    expect(merged.where((e) => e.name == '大学英语').length, 2,
        reason: 'kept 去重按 editKey 折叠会把第二条静默挤掉（丢课）');
  });

  test('union：双胞胎之一被编辑，另一条不被修正对象顶替', () {
    final odd = zf('大学英语', 3, 1, 2, weeks: const [1, 3, 5, 7]);
    final even = zf('大学英语', 3, 1, 2, weeks: const [2, 4, 6, 8]);
    final editedOdd = editedLikeSheet(odd, teacher: '张三');
    final incoming = [zf('高等数学', 1, 1, 2)];
    final merged = AppState.mergeEdited(incoming, [editedOdd, even], union: true);
    final twins = merged.where((e) => e.name == '大学英语').toList();
    expect(twins.length, 2);
    expect(twins.where((e) => identical(e, editedOdd)).length, 1,
        reason: '编辑版保留');
    expect(twins.where((e) => identical(e, even)).length, 1,
        reason: '修正解析按 key 撞车时另一条会被编辑版顶替成双份');
  });
}
