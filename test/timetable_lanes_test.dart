// 课表周视图的泳道排版：时间重叠的课程并排分列。
import 'package:flutter_test/flutter_test.dart';
import 'package:homework_radar/models/course.dart';
import 'package:homework_radar/pages/timetable_page.dart' show placeInLanes;

Course cs(int start, int end, {String name = '课'}) => Course(
      id: '$name#$start',
      name: name,
      weekday: 1,
      startSection: start,
      endSection: end,
      weeks: const [1],
    );

void main() {
  test('互不重叠的课各占满列宽', () {
    final placed = placeInLanes([cs(1, 2, name: 'A'), cs(3, 4, name: 'B')]);
    expect(placed.map((p) => p.course.name).toList(), ['A', 'B']);
    for (final p in placed) {
      expect(p.lane, 0, reason: '相接不重叠共占一列（1-2节 与 3-4节）');
      expect(p.lanes, 1);
    }
  });

  test('同节次两门课分两道并排', () {
    final placed = placeInLanes([cs(5, 6, name: 'A'), cs(5, 6, name: 'B')]);
    expect(placed.map((p) => p.lane), [0, 1]);
    expect(placed.every((p) => p.lanes == 2), isTrue, reason: '同簇的课按相同总数等分列宽');
  });

  test('部分重叠（5-6 与 6-7）分两道', () {
    final placed = placeInLanes([cs(5, 6, name: 'A'), cs(6, 7, name: 'B')]);
    expect(placed.map((p) => p.lane), [0, 1]);
    expect(placed.every((p) => p.lanes == 2), isTrue);
  });

  test('错开时间可复用泳道，簇互不影响', () {
    // A(1-3) 与 B(2-4) 重叠成两道；C(5-6) 是新簇占满宽
    final placed = placeInLanes([cs(1, 3, name: 'A'), cs(2, 4, name: 'B'), cs(5, 6, name: 'C')]);
    final byName = {for (final p in placed) p.course.name: p};
    expect(byName['A']!.lane, 0);
    expect(byName['B']!.lane, 1);
    expect(byName['A']!.lanes, 2);
    expect(byName['B']!.lanes, 2);
    expect(byName['C']!.lane, 0);
    expect(byName['C']!.lanes, 1, reason: '与前面不重叠，不应被前面的簇拖累变窄');
  });

  test('三门连环重叠分三道', () {
    final placed =
        placeInLanes([cs(1, 3, name: 'A'), cs(2, 4, name: 'B'), cs(3, 5, name: 'C')]);
    expect(placed.map((p) => p.lane), [0, 1, 2]);
    expect(placed.every((p) => p.lanes == 3), isTrue);
  });

  test('乱序输入也能正确排版', () {
    final placed = placeInLanes([cs(6, 7, name: 'late'), cs(5, 6, name: 'early')]);
    expect(placed.first.course.name, 'early', reason: '按开始节次排序后分配');
    expect(placed.map((p) => p.lane), [0, 1]);
  });
}
