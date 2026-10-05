/// 作息时间设置：按学校实际作息调整每节课的上下课时间。
/// 保存后上课提醒与周视图时间轴立即按新时间重排。
library;

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../services/section_times.dart';
import '../services/storage.dart';
import '../ui/adaptive.dart';

class SectionTimesPage extends StatefulWidget {
  const SectionTimesPage({super.key, required this.state});

  final AppState state;

  @override
  State<SectionTimesPage> createState() => _SectionTimesPageState();
}

class _SectionTimesPageState extends State<SectionTimesPage> {
  late List<(int, int)> _times;

  @override
  void initState() {
    super.initState();
    _times = [...SectionTimes.current()];
  }

  String _hm(int m) => '${(m ~/ 60).toString().padLeft(2, '0')}:'
      '${(m % 60).toString().padLeft(2, '0')}';

  Future<void> _save() async {
    await Storage.saveSectionTimes(_times);
    await widget.state.refreshClassReminders();
    if (mounted) setState(() {});
  }

  Future<void> _pick({required int section, required bool start}) async {
    final cur = _times[section - 1];
    final base = start ? cur.$1 : cur.$2;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: base ~/ 60, minute: base % 60),
    );
    if (picked == null || !mounted) return;
    final m = picked.hour * 60 + picked.minute;
    // 不能与相邻节重叠：乱序/重叠的作息会让上课提醒和时刻指示线错位。
    // 相接（本节下课 = 上节下课时间）是允许的；与下一节**相等也算重叠**——
    // 只拦严格大于的话能存出零长度节，读回时被存储层静默换成默认表，
    // 页面显示与提醒/小组件实际生效时间分叉。
    if (start && section > 1 && m < _times[section - 2].$2) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('与第${section - 1}节重叠（那节 ${_hm(_times[section - 2].$2)} 才下课）')));
      return;
    }
    if (section < _times.length && m >= _times[section].$1) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('与第${section + 1}节重叠（那节 ${_hm(_times[section].$1)} 就上课）')));
      return;
    }
    if (!start && m <= cur.$1) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('下课时间要晚于上课时间')));
      return;
    }
    (int, int)? next;
    if (start) {
      var end = m >= cur.$2 ? m + 45 : cur.$2;
      if (end > 24 * 60) end = 24 * 60 - 1;
      // 自动延长的下课时间不能越过下一节的开始
      if (section < _times.length && end > _times[section].$1) {
        end = _times[section].$1;
      }
      if (end <= m) {
        // 末节选到 23:59 这类时刻：挤不出合法的结束时间，拒掉而不是
        // 存出 start==end 的零长度节
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('这个起始时间太晚，存不下完整的节次')));
        return;
      }
      next = (m, end);
    } else {
      next = (cur.$1, m);
    }
    setState(() {
      _times[section - 1] = next!;
    });
    await _save();
  }

  /// 追加一节：默认时刻接在最后一节下课 +5 分钟起，时长 45 分钟。
  /// （+5 而非更宽的间隔：晚课排得密，间隔越大越早撞上 23:59 上限，
  /// 16 节就越加不满。）
  /// 作息表锁死当前节数的话，13-16 节（晚课/16 节制学校）的时刻
  /// 用户无法自救——提醒与小组件只能一直错用钳位时刻。
  /// 上限 16 与课表网格/解析器一致。
  Future<void> _addSection() async {
    if (_times.length >= 16) return;
    final last = _times.last;
    var start = last.$2 + 5;
    if (start + 45 > 24 * 60) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('已经排到深夜，加不下了')));
      return;
    }
    setState(() => _times.add((start, start + 45)));
    await _save();
  }

  Future<void> _reset() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('恢复默认作息'),
        content: const Text('放弃自定义时间，回到内置作息表？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('恢复')),
        ],
      ),
    );
    if (ok != true) return;
    await Storage.clearSectionTimes();
    if (!mounted) return;
    setState(() => _times = [...SectionTimes.current()]);
    await widget.state.refreshClassReminders();
  }

  Widget _addSectionTile(BuildContext context) {
    final full = _times.length >= 16;
    return ListTile(
      leading: Icon(
        Icons.add_circle_outline_rounded,
        color: full ? textFaint(context) : _brandOf(context),
      ),
      title: Text(
        full ? '已到 16 节上限' : '添加第${_times.length + 1}节',
        style: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
            color: full ? textFaint(context) : _brandOf(context)),
      ),
      subtitle: Text(
        full ? '与课表网格一致' : '晚课/16 节制学校在这里补齐时刻',
        style: TextStyle(fontSize: 12, color: textSecondary(context)),
      ),
      onTap: full ? null : _addSection,
    );
  }

  Color _brandOf(BuildContext context) => Theme.of(context).colorScheme.primary;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('作息时间'),
        actions: [
          TextButton(onPressed: _reset, child: const Text('恢复默认')),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
            child: Text(
              '教务课表通常不带具体时间。按自己学校的作息调整后，'
              '上课提醒和课表时间轴都会使用这里的时间。\n'
              // 表外节次取不到时刻：对应课程不排上课提醒、小组件/课表
              // 不显示时间——必须在页面明说，否则用户无从自救
              '有 13-16 节晚课的学校请在这里补全时刻，'
              '否则对应课程不排上课提醒。',
              style: TextStyle(
                  fontSize: 12.5, height: 1.6, color: textSecondary(context)),
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 24),
              itemCount: _times.length + 1,
              itemBuilder: (context, i) {
                if (i == _times.length) {
                  return _addSectionTile(context);
                }
                final (a, b) = _times[i];
                return ListTile(
                  leading: SizedBox(
                    width: 46,
                    child: Text('第${i + 1}节',
                        style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            color: textPrimary(context))),
                  ),
                  title: Row(
                    children: [
                      TextButton(
                        onPressed: () => _pick(section: i + 1, start: true),
                        child: Text(_hm(a),
                            style: const TextStyle(
                                fontSize: 16.5,
                                fontWeight: FontWeight.w700,
                                fontFeatures: [FontFeature.tabularFigures()])),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Text('–',
                            style: TextStyle(color: textFaint(context))),
                      ),
                      TextButton(
                        onPressed: () => _pick(section: i + 1, start: false),
                        child: Text(_hm(b),
                            style: const TextStyle(
                                fontSize: 16.5,
                                fontWeight: FontWeight.w700,
                                fontFeatures: [FontFeature.tabularFigures()])),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
