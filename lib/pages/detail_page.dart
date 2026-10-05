/// 作业详情页：通知点击直达。
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../main.dart' show appStateForHome;
import '../models/homework.dart';
import '../services/storage.dart';
import '../ui/adaptive.dart';
import '../ui/hw_card.dart';
import '../ui/ink_wash.dart';
import '../ui/tokens.dart';

class HomeworkDetailPage extends StatefulWidget {
  const HomeworkDetailPage({super.key, required this.homeworkId});

  final String homeworkId;

  @override
  State<HomeworkDetailPage> createState() => _HomeworkDetailPageState();
}

class _HomeworkDetailPageState extends State<HomeworkDetailPage> {
  Timer? _clock;

  @override
  void initState() {
    super.initState();
    // 截止状态/倒计时按 build 时刻的 now 算死；停留跨过截止点也不会翻转，
    // 定时重建保持与首页一致的新鲜度
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
    // 优先读全局内存态：此前直读持久层与页面内存态脱节——恢复隐藏后列表
    // 可见、详情却报「不存在」；隐藏的条目在下次同步前照样被当存在展示
    final state = appStateForHome;
    final inMemory = state?.homework
        .where((h) => h.id == widget.homeworkId)
        .firstOrNull;
    if (inMemory != null) return inMemory;
    // 兜底直读持久层也要按 dismissedIds 过滤：隐藏名单只记 id、条目本体
    // 仍躺在 homework_json，不过滤的话内存态缺失时（如详情页直达冷启动）
    // 已隐藏的条目会被当存在展示，与「作业不存在或已被隐藏」的空态矛盾
    final dismissed = Storage.dismissedIds();
    return Storage.homework()
        .where((h) => h.id == widget.homeworkId && !dismissed.contains(h.id))
        .firstOrNull;
  }

  @override
  Widget build(BuildContext context) {
    final hw = _find();
    if (hw == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('作业详情')),
        body: const Center(child: Text('作业不存在或已被隐藏')),
      );
    }
    final pal = paletteOf(context);
    final statusColor = hwStatusColor(hw);
    return Scaffold(
      backgroundColor: bgColor(context),
      appBar: AppBar(
          title: appBarTitle(
        context,
        hw.course.isEmpty ? '作业详情' : hw.course,
      )),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: inkWashFill(context, cardRadius(context) + 2) ??
                (pal.pixel
                    ? BoxDecoration(color: cardColor(context))
                    : pal.receipt
                        ? receiptTear(context)
                        : pal.editorial
                            ? BoxDecoration(color: cardColor(context))
                            : BoxDecoration(
                                color: cardColor(context),
                                borderRadius: BorderRadius.circular(
                                    cardRadius(context) + 2),
                                border: cardBorderOf(context),
                              )),
            foregroundDecoration: paperInnerRing(context, cardRadius(context) + 2) ??
                morandiCream(context, cardRadius(context) + 2) ??
                editorialRules(context),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(hw.title,
                    style: inkTitle(
                      context,
                      serifTitle(
                        context,
                        TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: textPrimary(context),
                            height: 1.3),
                      ),
                    )),
                // 水墨：题下飞白收笔，再挂信息行
                if (isInkStyle(context)) ...[
                  const SizedBox(height: 9),
                  BrushLine(
                    color: textSecondary(context).withValues(alpha: 0.35),
                    thickness: 2.6,
                  ),
                  const SizedBox(height: 11),
                ] else
                  const SizedBox(height: 14),
                _row(
                    context,
                    Icons.schedule_rounded,
                    '截止时间',
                    hw.dueAt == null
                        ? '未设置'
                        : HomeworkItem.formatDueTime(hw.dueAt!),
                    statusColor),
                const SizedBox(height: 10),
                _row(context, Icons.info_outline_rounded, '状态', hwStatusLabel(hw),
                    statusColor),
                if (hw.score != null) ...[
                  const SizedBox(height: 10),
                  _row(
                      context,
                      Icons.grade_rounded,
                      '得分',
                      '${HomeworkItem.scoreText(hw.score)} 分',
                      statusColor),
                ],
                _row(context, Icons.link_rounded, '平台', hw.platform.label,
                    textSecondary(context)),
              ],
            ),
          ),
          if (hw.note != null && hw.note!.trim().isNotEmpty) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: inkWashFill(context, cardRadius(context) + 2) ??
                  (pal.receipt
                      ? receiptTear(context)
                      : pal.editorial
                          ? BoxDecoration(color: cardColor(context))
                          : BoxDecoration(
                              color: cardColor(context),
                              borderRadius: BorderRadius.circular(
                                  cardRadius(context) + 2),
                              border: cardBorderOf(context),
                            )),
              foregroundDecoration:
                  paperInnerRing(context, cardRadius(context) + 2) ??
                      morandiCream(context, cardRadius(context) + 2) ??
                      editorialRules(context),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('备注',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: textSecondary(context))),
                  const SizedBox(height: 6),
                  Text(hw.note!.trim(),
                      style: TextStyle(
                          fontSize: 14, color: textPrimary(context), height: 1.5)),
                ],
              ),
            ),
          ],
          const SizedBox(height: 18),
          Text(
            '如需作答或提交，请到对应平台的官方 App 中完成。',
            style: TextStyle(fontSize: 12.5, color: textSecondary(context)),
          ),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, IconData icon, String label, String value,
      Color valueColor) {
    return Row(
      children: [
        Icon(icon, size: 16, color: textSecondary(context)),
        const SizedBox(width: 8),
        Text(label,
            style: TextStyle(fontSize: 13.5, color: textSecondary(context))),
        const Spacer(),
        Text(value,
            style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: valueColor)),
      ],
    );
  }
}
