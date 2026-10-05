// 同 id 双胞胎课程（makeId 不含周次）的字段身份定位：删除/更新只动目标那一条，
// 不能像 removeWhere(c.id == id) 那样把两条一起带走（#45）。
// 注意不能按 identical 匹配：Storage.courses() 每次从 JSON 重反序列化，
// 真实链路里对象都是新的——按「id+周次」字段身份才是稳的。
import 'package:flutter_test/flutter_test.dart';
import 'package:homework_radar/app_state.dart';
import 'package:homework_radar/models/course.dart';

Course twin(List<int> weeks) => Course(
      id: Course.makeId(name: '大学英语', weekday: 3, startSection: 1, endSection: 2),
      name: '大学英语',
      weekday: 3,
      startSection: 1,
      endSection: 2,
      weeks: weeks,
    );

void main() {
  test('同 id 不同周次的两条课按字段身份各自定位', () {
    final odd = twin(const [1, 3, 5]);
    final even = twin(const [2, 4, 6]);
    final list = [odd, even];
    expect(odd.id, even.id, reason: '前置：makeId 不含周次，双胞胎同 id');
    expect(AppState.courseIndex(list, even), 1,
        reason: '删除双胞胎之一不得命中另一条');
    expect(AppState.courseIndex(list, odd), 0);
  });

  test('周次相同但对象不同（真实链路：Storage 重反序列化的新对象）也能定位', () {
    final list = [twin(const [1, 3, 5])];
    final reparsed = Course.fromJson(list.first.toJson());
    expect(identical(reparsed, list.first), isFalse,
        reason: '前置：反序列化产生新对象，identical 必然失配');
    expect(AppState.courseIndex(list, reparsed), 0,
        reason: '字段身份匹配必须命中，否则退化成按 id 连删');
  });

  test('不在列表中的周次组合返回 -1（调用方自行退化处理）', () {
    final list = [twin(const [1, 2])];
    expect(AppState.courseIndex(list, twin(const [9, 10])), -1);
    expect(AppState.courseIndex(const [], twin(const [1])), -1);
  });
}
