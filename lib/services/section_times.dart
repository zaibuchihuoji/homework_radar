/// 作息时间表：默认内置一套常见作息，用户可在设置里按自己学校调整。
/// 上课提醒、周视图时间轴、课程详情时刻都从这里取值。
library;

import '../models/course.dart';
import 'storage.dart';

class SectionTimes {
  SectionTimes._();

  /// 当前生效的作息：用户自定义优先，否则用默认表。
  static List<(int, int)> current() =>
      Storage.sectionTimes() ?? Course.sectionTimes;

  /// 第 [section] 节的 (开始, 结束) 距 0 点的分钟数。
  ///
  /// 【契约】节次超出当前作息表长度（或 <1）时返回 null，调用方必须按
  /// 「该节不存在」处理，各消费方约定如下：
  /// - notification_service：跳过该课该日的排课；
  /// - timetable_widget：开始/结束时间传空串；
  /// - timetable_page：时间轴沟槽显示「—」。
  /// 为什么不再 clamp 到末节：编辑表单允许选 1-16 节，而学校作息表可能只有
  /// 12 节——表外节次没有真实时刻，钳到末节是把猜测当事实（提醒在错误的
  /// 时刻响、小组件显示编造的时间），交给调用方显式降级才不出假数据。
  static (int, int)? slotOf(int section) {
    final times = current();
    final i = section - 1;
    if (i < 0 || i >= times.length) return null;
    return times[i];
  }

  /// 某节上课的具体时刻；节次超出作息表长度时返回 null（契约见 [slotOf]）。
  static DateTime? startOfDay(DateTime day, int section) {
    final slot = slotOf(section);
    if (slot == null) return null;
    final (startMin, _) = slot;
    return DateTime(day.year, day.month, day.day, startMin ~/ 60, startMin % 60);
  }
}
