/// 作息时间设置：按学校实际作息调整每节课的上下课时间。
/// 保存后上课提醒与周视图时间轴立即按新时间重排。
library;

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../ui/theme_forms.dart';
import '../ui/settings_parts.dart';
import '../ui/tokens.dart';
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

  String _hm(int m) =>
      '${(m ~/ 60).toString().padLeft(2, '0')}:'
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
      initialTime: TimeOfDay(hour: (base ~/ 60) % 24, minute: base % 60),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          timePickerTheme: Theme.of(context).timePickerTheme.copyWith(
            backgroundColor: modalColor(context),
            shape: paletteOf(context).clean
                ? RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(22),
                  )
                : themeModalShape(paletteOf(context)),
          ),
        ),
        child: child!,
      ),
    );
    if (picked == null || !mounted) return;
    // 作息允许末节在24:00结束；选择器只接受0..23小时，用00:00表达日末。
    final pickedMinute = picked.hour * 60 + picked.minute;
    final m = !start && pickedMinute == 0 ? 24 * 60 : pickedMinute;
    // 不能与相邻节重叠：乱序/重叠的作息会让上课提醒和时刻指示线错位。
    // 相接（本节下课 = 上节下课时间）是允许的；与下一节**相等也算重叠**——
    // 只拦严格大于的话能存出零长度节，读回时被存储层静默换成默认表，
    // 页面显示与提醒/小组件实际生效时间分叉。
    if (start && section > 1 && m < _times[section - 2].$2) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '与第${section - 1}节重叠（那节 ${_hm(_times[section - 2].$2)} 才下课）',
          ),
        ),
      );
      return;
    }
    if (section < _times.length && m >= _times[section].$1) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '与第${section + 1}节重叠（那节 ${_hm(_times[section].$1)} 就上课）',
          ),
        ),
      );
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
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('这个起始时间太晚，存不下完整的节次')));
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
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('已经排到深夜，加不下了')));
      return;
    }
    setState(() => _times.add((start, start + 45)));
    await _save();
  }

  Future<void> _reset() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => SettingsAlertDialog(
        title: const Text('恢复默认作息'),
        content: const Text('放弃自定义时间，回到内置作息表？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('恢复'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await Storage.clearSectionTimes();
    if (!mounted) return;
    setState(() => _times = [...SectionTimes.current()]);
    await widget.state.refreshClassReminders();
  }

  Widget _timeRow(int index) => LayoutBuilder(
    builder: (context, constraints) {
      final (a, b) = _times[index];
      final label = Text(
        '第${index + 1}节',
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: textPrimary(context),
        ),
      );
      final controls = Row(
        children: [
          Expanded(
            child: TextButton(
              onPressed: () => _pick(section: index + 1, start: true),
              child: Text(
                _hm(a),
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w500,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
          Text('—', style: TextStyle(color: textFaint(context))),
          Expanded(
            child: TextButton(
              onPressed: () => _pick(section: index + 1, start: false),
              child: Text(
                _hm(b),
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w500,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
        ],
      );
      final stacked =
          constraints.maxWidth < 300 ||
          MediaQuery.textScalerOf(context).scale(14) > 18;
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: stacked
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [label, controls],
              )
            : Row(
                children: [
                  SizedBox(width: 64, child: label),
                  Expanded(child: controls),
                ],
              ),
      );
    },
  );

  @override
  Widget build(BuildContext context) => SettingsScaffold(
    title: '作息时间',
    actions: [
      TextButton(onPressed: _reset, child: const Text('恢复默认')),
      const SizedBox(width: 8),
    ],
    body: SettingsList(
      children: [
        SettingsSection(
          title: '每节课时间',
          footer: '点击时间即可修改，课表与上课提醒会一起更新。有 13–16 节晚课的学校请补全时刻，否则对应课程不排上课提醒。',
          children: [
            for (var i = 0; i < _times.length; i++) ...[
              if (i > 0) const SettingsDivider(),
              _timeRow(i),
            ],
            const SettingsDivider(),
            SettingsRow(
              icon: Icons.add_rounded,
              title: _times.length >= 16
                  ? '已到 16 节上限'
                  : '添加第${_times.length + 1}节',
              onTap: _times.length >= 16 ? null : _addSection,
            ),
          ],
        ),
      ],
    ),
  );
}
