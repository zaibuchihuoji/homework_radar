/// 作业数据模型：各平台统一成一种结构。
library;

enum PlatformKind { chaoxing, mooc, zhihuishu, xuetangx, yuketang, manual }

extension PlatformKindX on PlatformKind {
  String get label => switch (this) {
    PlatformKind.chaoxing => '学习通',
    PlatformKind.mooc => '中国大学MOOC',
    PlatformKind.zhihuishu => '智慧树',
    PlatformKind.xuetangx => '学堂在线',
    PlatformKind.yuketang => '雨课堂',
    PlatformKind.manual => '自定义',
  };

  String get key => switch (this) {
    PlatformKind.chaoxing => 'chaoxing',
    PlatformKind.mooc => 'mooc',
    PlatformKind.zhihuishu => 'zhihuishu',
    PlatformKind.xuetangx => 'xuetangx',
    PlatformKind.yuketang => 'yuketang',
    PlatformKind.manual => 'manual',
  };
}

/// 未完成/待批阅/已完成 等，由各平台解析后归一化。
enum HwStatus { todo, submitted, done, unknown }

class HomeworkItem {
  HomeworkItem({
    required this.id,
    required this.platform,
    required this.course,
    required this.title,
    this.dueAt,
    this.status = HwStatus.unknown,
    this.url,
    this.score,
    this.note,
    this.sourceKey,
  });

  /// 平台内唯一：platform + courseId + workId。
  /// 注意：cx_/mooc_ 的兜底段用了 String.hashCode——官方契约不保证跨程序执行
  /// 一致，但当前 VM 实现是确定性的；换稳定哈希必须连「旧 id 迁移」一起做，
  /// 否则已落盘 id 全部失联（备注丢、隐藏复活）。改前先读 sync_service 的合并逻辑。
  /// 后续新增的平台（zhs_ 智慧树）直接用 stableHash，不再新增 hashCode 依赖。
  final String id;
  final PlatformKind platform;
  final String course;
  final String title;

  /// 截止时间；null 表示平台没给或解析失败
  final DateTime? dueAt;
  final HwStatus status;
  final String? url;
  final double? score;

  /// 用户备注（如「需交纸质版」）
  final String? note;

  /// 平台的课程/任务真实标识，独立于可变课程名。旧版本记录可为空。
  final String? sourceKey;

  bool get isOverdue =>
      status != HwStatus.done &&
      status != HwStatus.submitted &&
      dueAt != null &&
      dueAt!.isBefore(DateTime.now());

  /// 是否属于当前学期（8月~次年1月为秋学期，2~7月为春学期）。
  /// 无截止时间的条目无法判断，默认保留展示。
  bool get inCurrentSemester => isInSemester(DateTime.now());

  /// Shared by the app list and widget export; a supplied clock also allows
  /// semester rollover to be checked without changing stored deadlines.
  bool isInSemester(DateTime now) {
    final d = dueAt;
    if (d == null) return true;
    final (start, end) = switch (now.month) {
      >= 8 => (DateTime(now.year, 8), DateTime(now.year + 1, 2)),
      1 => (DateTime(now.year - 1, 8), DateTime(now.year, 2)),
      _ => (DateTime(now.year, 2), DateTime(now.year, 8)),
    };
    return !d.isBefore(start) && d.isBefore(end);
  }

  /// 紧急度排序权重：越紧急越靠前（当前仅测试引用，生产排序用「未完成优先+
  /// 截止升序」；submitted 与 done 同样视为完结，避免口径分叉）。
  double get urgency {
    if (status == HwStatus.done || status == HwStatus.submitted) return 0;
    final d = dueAt;
    if (d == null) return 1;
    final hours = d.difference(DateTime.now()).inHours;
    if (hours < 0) return 1000;
    return 1000 / (hours + 1);
  }

  /// 备份/落库用的稳定状态键。此前按枚举 index 序列化，枚举成员一旦
  /// 插入/重排，存量数据会被静默错译（done 读成 submitted 等）。
  String get statusKey => switch (status) {
    HwStatus.todo => 'todo',
    HwStatus.submitted => 'submitted',
    HwStatus.done => 'done',
    HwStatus.unknown => 'unknown',
  };

  static HwStatus _statusFromJson(dynamic v) {
    if (v is String) {
      for (final s in HwStatus.values) {
        if (s.name == v) return s;
      }
      return HwStatus.unknown;
    }
    // 旧版本按 index 落盘，兼容读回
    final si = (v as num?)?.toInt();
    if (si != null && si >= 0 && si < HwStatus.values.length) {
      return HwStatus.values[si];
    }
    return HwStatus.unknown;
  }

  /// 整数分显示成「95」，小数分保留原样（避免「95.0 分」）。
  static String scoreText(double? score) {
    if (score == null) return '';
    return score % 1 == 0 ? score.toInt().toString() : '$score';
  }

  /// 统一的截止时刻展示（详情页此前是另一套 YYYY-MM-DD 口径）。
  static String formatDueTime(DateTime d) => _fmt(d);

  /// 改备注/回填备注走 copyWith，别再手抄九个字段。
  HomeworkItem copyWith({
    String? id,
    String? note,
    HwStatus? status,
    String? sourceKey,
  }) => HomeworkItem(
    id: id ?? this.id,
    platform: platform,
    course: course,
    title: title,
    dueAt: dueAt,
    status: status ?? this.status,
    url: url,
    score: score,
    note: note ?? this.note,
    sourceKey: sourceKey ?? this.sourceKey,
  );

  String get countdownText {
    final d = dueAt;
    if (d == null) return '截止时间未知';
    final diff = d.difference(DateTime.now());
    if (diff.isNegative) {
      return '已截止（${_fmt(d)}）';
    }
    if (diff.inHours < 48) {
      final h = diff.inHours;
      final m = diff.inMinutes % 60;
      return '$h小时$m分钟后截止';
    }
    return '${diff.inDays}天后截止（${_fmt(d)}）';
  }

  static String _fmt(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.month}月${d.day}日 ${two(d.hour)}:${two(d.minute)}';
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'platform': platform.key,
    'course': course,
    'title': title,
    'dueAt': dueAt?.millisecondsSinceEpoch,
    'status': statusKey,
    'url': url,
    'score': score,
    if (note != null && note!.isNotEmpty) 'note': note,
    if (sourceKey != null) 'sourceKey': sourceKey,
  };

  static HomeworkItem fromJson(Map<String, dynamic> j) {
    final p = j['platform'] as String?;
    final platform = switch (p) {
      'chaoxing' => PlatformKind.chaoxing,
      'zhihuishu' => PlatformKind.zhihuishu,
      'xuetangx' => PlatformKind.xuetangx,
      'yuketang' => PlatformKind.yuketang,
      'manual' => PlatformKind.manual,
      _ => PlatformKind.mooc,
    };
    final si = j['status'];
    final status = _statusFromJson(si);
    return HomeworkItem(
      id: (j['id'] ?? '').toString(),
      platform: platform,
      course: j['course'] as String? ?? '',
      title: j['title'] as String? ?? '',
      dueAt: j['dueAt'] == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch((j['dueAt'] as num).toInt()),
      status: status,
      url: j['url'] as String?,
      score: (j['score'] as num?)?.toDouble(),
      note: j['note'] as String?,
      sourceKey: j['sourceKey'] as String?,
    );
  }
}
