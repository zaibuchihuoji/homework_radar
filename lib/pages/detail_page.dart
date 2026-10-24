/// Homework detail shared by list, calendar, notifications and widgets.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../main.dart' show appStateForHome;
import '../models/homework.dart';
import '../services/storage.dart';
import '../ui/adaptive.dart';
import '../ui/hw_card.dart';
import '../ui/settings_parts.dart';
import '../ui/tokens.dart';
import 'homework_edit_dialogs.dart';

class HomeworkDetailPage extends StatefulWidget {
  const HomeworkDetailPage({super.key, required this.homeworkId, this.state});
  final String homeworkId;
  final AppState? state;
  @override
  State<HomeworkDetailPage> createState() => _HomeworkDetailPageState();
}

class _HomeworkDetailPageState extends State<HomeworkDetailPage> {
  Timer? _clock;
  AppState? get _state => widget.state ?? appStateForHome;

  @override
  void initState() {
    super.initState();
    _clock = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  HomeworkItem? _find() {
    final inMemory = _state?.homework
        .where((h) => h.id == widget.homeworkId)
        .firstOrNull;
    if (inMemory != null) return inMemory;
    final dismissed = Storage.dismissedIds();
    return Storage.homework()
        .where((h) => h.id == widget.homeworkId && !dismissed.contains(h.id))
        .firstOrNull;
  }

  @override
  Widget build(BuildContext context) {
    final state = _state;
    return state == null
        ? _content(context)
        : ListenableBuilder(
            listenable: state,
            builder: (context, _) => _content(context),
          );
  }

  Future<void> _hide(HomeworkItem hw) async {
    final state = _state;
    if (state == null) return;
    await state.dismissHomework(hw);
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    if (Navigator.of(context).canPop()) Navigator.of(context).pop();
    messenger.showSnackBar(
      SnackBar(
        content: Text('已隐藏「${hw.title}」'),
        action: SnackBarAction(
          label: '撤销',
          onPressed: () => state.restoreHomework(hw.id),
        ),
      ),
    );
  }

  Widget _content(BuildContext context) {
    final hw = _find();
    if (hw == null) {
      return const SettingsScaffold(
        title: '作业详情',
        body: Center(child: Text('作业不存在或已被隐藏')),
      );
    }
    final state = _state;
    final manual = hw.platform == PlatformKind.manual;
    final note = hw.note?.trim() ?? '';
    if (paletteOf(context).sunny) return _focusContent(context, hw, state);
    final dueColor = hw.dueAt == null || hwIsDone(hw)
        ? textSecondary(context)
        : hwDueTone(hw, dark: isDark(context)).$1;
    return SettingsScaffold(
      title: '作业详情',
      body: SettingsList(
        children: [
          SettingsSection(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      hw.course.isEmpty ? '未指定课程' : hw.course,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.4,
                        color: textSecondary(context),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SelectableText(
                      hw.title,
                      style: TextStyle(
                        fontSize: 23,
                        height: 1.35,
                        fontWeight: FontWeight.w600,
                        color: textPrimary(context),
                      ),
                    ),
                  ],
                ),
              ),
              const SettingsDivider(indent: 20),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 16,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Icon(
                        Icons.schedule_rounded,
                        size: 20,
                        color: dueColor,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '截止时间',
                            style: TextStyle(
                              fontSize: 12,
                              color: textSecondary(context),
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            hw.dueAt == null
                                ? '未设置截止时间'
                                : HomeworkItem.formatDueTime(hw.dueAt!),
                            style: TextStyle(
                              fontSize: 17,
                              height: 1.4,
                              fontWeight: FontWeight.w600,
                              color: dueColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SettingsDivider(indent: 20),
              SettingsRow(
                icon: Icons.info_outline_rounded,
                title: '状态',
                value: hwStatusLabel(hw),
              ),
              const SettingsDivider(),
              SettingsRow(
                icon: Icons.link_rounded,
                title: '来源',
                value: hw.platform.label,
              ),
              if (hw.score != null) ...[
                const SettingsDivider(),
                SettingsRow(
                  icon: Icons.grade_outlined,
                  title: '得分',
                  value: '${HomeworkItem.scoreText(hw.score)} 分',
                ),
              ],
            ],
          ),
          if (note.isNotEmpty || state != null)
            SettingsSection(
              title: '我的备注',
              children: [
                if (note.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: SelectableText(
                      note,
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.6,
                        color: textPrimary(context),
                      ),
                    ),
                  ),
                if (state != null)
                  SettingsRow(
                    icon: Icons.sticky_note_2_outlined,
                    title: note.isEmpty ? '添加备注' : '编辑备注',
                    subtitle: note.isEmpty ? '记录提交要求、分工或待办事项' : null,
                    navigation: true,
                    onTap: () => showHomeworkNoteEditor(context, state, hw),
                  ),
              ],
            ),
          if (state != null)
            SettingsSection(
              title: '作业操作',
              footer: manual
                  ? '手动作业的完成状态仅保存在本机。'
                  : '平台状态由同步更新。作答与提交请在${hw.platform.label}官方 App 中完成。',
              children: [
                if (manual) ...[
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        icon: Icon(
                          hwIsDone(hw)
                              ? Icons.undo_rounded
                              : Icons.check_rounded,
                        ),
                        label: Text(hwIsDone(hw) ? '标记未完成' : '标记完成'),
                        onPressed: () => state.setHomeworkStatus(
                          hw.id,
                          hwIsDone(hw) ? HwStatus.todo : HwStatus.done,
                        ),
                      ),
                    ),
                  ),
                  SettingsRow(
                    icon: Icons.edit_outlined,
                    title: '编辑作业',
                    subtitle: '修改课程、内容和截止时间',
                    navigation: true,
                    onTap: () =>
                        showManualHomeworkEditor(context, state, edit: hw),
                  ),
                  const SettingsDivider(),
                ],
                SettingsRow(
                  icon: Icons.visibility_off_outlined,
                  title: '隐藏这条作业',
                  subtitle: '停止提醒，可在设置的数据管理中恢复',
                  onTap: () => _hide(hw),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _focusContent(BuildContext context, HomeworkItem hw, AppState? state) {
    final p = paletteOf(context);
    final manual = hw.platform == PlatformKind.manual;
    final note = hw.note?.trim() ?? '';
    return SettingsScaffold(
      title: '作业详情',
      actions: state == null
          ? null
          : [
              PopupMenuButton<String>(
                tooltip: '更多作业操作',
                icon: const Icon(Icons.more_horiz_rounded),
                onSelected: (_) => _hide(hw),
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'hide', child: Text('隐藏这条作业')),
                ],
              ),
            ],
      bottomNavigationBar: state == null
          ? null
          : Material(
              color: p.bg,
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                  child: manual
                      ? Row(
                          children: [
                            Expanded(
                              flex: 2,
                              child: OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  backgroundColor: p.ink.withValues(alpha: .04),
                                  foregroundColor: p.ink,
                                  side: BorderSide.none,
                                ),
                                onPressed: () => showManualHomeworkEditor(
                                  context,
                                  state,
                                  edit: hw,
                                ),
                                icon: const Icon(Icons.edit_outlined, size: 19),
                                label: const Text('编辑作业'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              flex: 3,
                              child: FilledButton.icon(
                                onPressed: () => state.setHomeworkStatus(
                                  hw.id,
                                  hwIsDone(hw) ? HwStatus.todo : HwStatus.done,
                                ),
                                icon: Icon(
                                  hwIsDone(hw)
                                      ? Icons.undo_rounded
                                      : Icons.check_circle_outline_rounded,
                                  size: 20,
                                  color: isDark(context)
                                      ? p.onAccent
                                      : p.accentFill,
                                ),
                                label: Text(hwIsDone(hw) ? '标记未完成' : '标记完成'),
                              ),
                            ),
                          ],
                        )
                      : Text(
                          '作答与提交请在${hw.platform.label}官方 App 中完成',
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.5,
                            color: p.ink2,
                          ),
                        ),
                ),
              ),
            ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(22, 16, 22, 32),
        children: [
          MergeSemantics(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hw.course.isEmpty ? '未指定课程' : hw.course,
                  style: TextStyle(fontSize: 13, color: p.ink2),
                ),
                const SizedBox(height: 12),
                SelectableText(
                  hw.title,
                  style: TextStyle(
                    fontSize: 24,
                    height: 1.4,
                    fontWeight: FontWeight.w600,
                    color: p.ink,
                  ),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 12,
                  runSpacing: 5,
                  children: [
                    Text(
                      hwStatusLabel(hw),
                      style: TextStyle(
                        fontSize: 13,
                        color: hwIsOverdue(hw)
                            ? Theme.of(context).colorScheme.error
                            : p.ink2,
                      ),
                    ),
                    Text(
                      hw.platform.label,
                      style: TextStyle(fontSize: 13, color: p.ink2),
                    ),
                    if (hw.score != null)
                      Text(
                        '${HomeworkItem.scoreText(hw.score)} 分',
                        style: TextStyle(fontSize: 13, color: p.ink2),
                      ),
                  ],
                ),
                const SizedBox(height: 24),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 18,
                  ),
                  decoration: BoxDecoration(
                    color: p.accentFill,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.schedule_outlined,
                        size: 28,
                        color: p.onAccent,
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '截止时间',
                              style: TextStyle(fontSize: 12, color: p.onAccent),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              hw.dueAt == null
                                  ? '未设置截止时间'
                                  : HomeworkItem.formatDueTime(hw.dueAt!),
                              style: TextStyle(
                                fontSize: 18,
                                height: 1.4,
                                fontWeight: FontWeight.w600,
                                color: p.onAccent,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          Row(
            children: [
              Expanded(
                child: Text(
                  '我的备注',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: p.ink,
                  ),
                ),
              ),
              if (state != null)
                TextButton.icon(
                  onPressed: () => showHomeworkNoteEditor(context, state, hw),
                  icon: const Icon(Icons.edit_note_outlined, size: 20),
                  label: Text(note.isEmpty ? '添加备注' : '编辑备注'),
                ),
            ],
          ),
          const SizedBox(height: 8),
          SelectableText(
            note.isEmpty ? '暂无备注' : note,
            style: TextStyle(
              fontSize: 14,
              height: 1.7,
              color: note.isEmpty ? p.ink2 : p.ink,
            ),
          ),
          if (state != null) ...[
            const SizedBox(height: 24),
            Text(
              manual ? '手动作业的完成状态仅保存在本机。' : '平台状态由同步更新。',
              style: TextStyle(fontSize: 11.5, color: p.ink2),
            ),
          ],
        ],
      ),
    );
  }
}
