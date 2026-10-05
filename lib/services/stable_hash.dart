/// 稳定字符串哈希（FNV-1a 32 位）。
///
/// Dart 的 `String.hashCode` 官方契约「不保证跨程序执行一致」——当前 VM 实现是
/// 确定性的，但一旦引擎换实现（如未来随机化种子），所有按 hashCode 生成的
/// 持久化键（课程配色下标、上课提醒通知 id）会整体漂移。这里用自定义的
/// 稳定哈希把「配色/通知 id」从 SDK 实现细节里解耦。
///
/// 注意：作业条目 id（cx_/mooc_ 前缀）仍刻意沿用 String.hashCode——换算法
/// 会让已落盘 id 全部失联（备注丢、隐藏复活），必须连迁移逻辑一起改才能动。
/// 新平台（zhs_ 智慧树）的 id 从第一天起就用本文件的 stableHash，不再新增
/// hashCode 依赖。
int stableHash(String s) {
  var h = 0x811c9dc5;
  for (final unit in s.codeUnits) {
    h ^= unit;
    h = (h * 0x01000193) & 0x7fffffff;
  }
  return h;
}
