import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../services/study_note_store.dart';
import '../services/storage.dart';
import '../services/notification_service.dart';
import '../ui/settings_parts.dart';
import '../ui/focus_parts.dart';
import '../ui/study_note_filter_picker.dart';
import 'study_note_canvas.dart';
import 'study_note_review.dart';

Future<void> _rescheduleStudyReminders() {
  final dismissed = Storage.dismissedIds();
  return NotificationService.reschedule(
    Storage.homework().where((item) => !dismissed.contains(item.id)).toList(),
    courses: Storage.courses(),
  );
}

class StudyNotesPage extends StatefulWidget {
  const StudyNotesPage({
    super.key,
    this.store,
    this.course,
    this.courseTeacher,
    this.courseAnchor,
    this.active = true,
    this.initialNoteId,
  });
  final StudyNoteStore? store;
  final String? course;
  final String? courseTeacher;
  final String? courseAnchor;
  final bool active;
  final String? initialNoteId;
  @override
  State<StudyNotesPage> createState() => _StudyNotesPageState();
}

class _StudyNotesPageState extends State<StudyNotesPage> {
  StudyNoteStore? _store;
  List<Map<String, dynamic>>? _notes;
  Object? _error;
  String _query = '';
  String? _courseFilter;
  String? _chapterFilter;
  bool _trash = false;
  bool _busy = false;
  bool _openedInitial = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant StudyNotesPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.active && widget.active) _load();
  }

  Future<void> _load() async {
    try {
      final store = widget.store ?? await StudyNoteStore.openDefault();
      _store = store;
      if (widget.store == null && !Storage.flag('note_store_used')) {
        await store.initialize();
        await Storage.setFlag('note_store_used', true);
      }
      final notes = await store.readNotes(
        requireInitialized: widget.store == null,
      );
      if (mounted) {
        setState(() {
          _store = store;
          _notes = notes;
          _error = null;
        });
        if (!_openedInitial && widget.initialNoteId != null) {
          _openedInitial = true;
          final matches = notes.where(
            (note) =>
                note['id'] == widget.initialNoteId && note['deleted'] != true,
          );
          if (matches.isNotEmpty) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _edit(matches.first);
            });
          } else {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('这篇笔记已移入回收站或不存在。')),
                );
              }
            });
          }
        }
      }
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  Future<void> _create() async {
    final store = _store;
    if (store == null || _busy) return;
    setState(() => _busy = true);
    final random = Random.secure();
    final id =
        '${DateTime.now().microsecondsSinceEpoch}_${List.generate(16, (_) => random.nextInt(16).toRadixString(16)).join()}';
    final note = <String, dynamic>{
      'id': id,
      'title': '',
      'body': '',
      'course': widget.course ?? '',
      'courseTeacher': widget.courseTeacher,
      'courseAnchor': widget.courseAnchor,
      'chapter': '',
      'favorite': false,
      'deleted': false,
      'blocks': <dynamic>[],
      'cards': <dynamic>[],
      'updatedAt': DateTime.now().toIso8601String(),
    };
    try {
      await store.updateNotes((notes) => [...notes, note]);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => StudyNoteEditor(store: store, note: note),
        ),
      );
      await _load();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('笔记未能保存，请检查存储空间后重试。')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _edit(Map<String, dynamic> note) async {
    final store = _store;
    if (store == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => StudyNoteEditor(store: store, note: note),
      ),
    );
    await _load();
  }

  Future<void> _change(String id, String key, bool value) async {
    final store = _store;
    if (store == null) return;
    try {
      await store.updateNotes(
        (notes) => [
          for (final note in notes)
            if (note['id'] == id) {...note, key: value} else note,
        ],
      );
      await _load();
      if (key == 'deleted') {
        try {
          await _rescheduleStudyReminders();
        } catch (_) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('笔记已保存，但提醒未能更新，请检查通知设置。')),
            );
          }
        }
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('操作未保存，请重试。')));
      }
    }
  }

  Future<void> _history() async {
    final store = _store;
    if (store == null) return;
    try {
      final versions = await store.history();
      final revision = await store.revision();
      if (!mounted) return;
      final selected = await showDialog<String>(
        context: context,
        builder: (dc) => AlertDialog(
          title: const Text('笔记历史版本'),
          content: SizedBox(
            width: 360,
            child: versions.isEmpty
                ? const Text('没有可用的历史版本。')
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: versions.length,
                    itemBuilder: (_, i) {
                      final version = versions[versions.length - 1 - i];
                      return ListTile(
                        title: Text('版本 ${versions.length - i}'),
                        subtitle: Text(i == 0 ? '当前版本' : '选择后可恢复'),
                        onTap: () => Navigator.pop(dc, version),
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dc),
              child: const Text('取消'),
            ),
          ],
        ),
      );
      if (!mounted || selected == null) return;
      final confirm = await showDialog<bool>(
        context: context,
        builder: (dc) => AlertDialog(
          title: const Text('恢复历史版本？'),
          content: const Text('会将整个笔记库恢复到选中的版本。现有版本仍会保留，可再次恢复。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dc, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dc, true),
              child: const Text('恢复'),
            ),
          ],
        ),
      );
      if (confirm != true || !mounted) return;
      await store.restoreHistory(selected, expectedRevision: revision);
      await _load();
      try {
        await _rescheduleStudyReminders();
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('笔记已恢复，但提醒未能更新。')));
        }
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('历史版本未能恢复，当前数据已保留。')));
      }
    }
  }

  Future<void> _reviewVisible(List<Map<String, dynamic>> notes) async {
    final store = _store;
    if (store == null) return;
    final cards = <Map<String, dynamic>>[];
    final baseline = <String, String>{};
    for (final note in notes) {
      final rows = note['cards'];
      if (rows is! List || note['id'] is! String) continue;
      for (var i = 0; i < rows.length; i++) {
        if (rows[i] is! Map) continue;
        final key = '${note['id']}#$i';
        baseline[key] = jsonEncode(rows[i]);
        cards.add({
          ...Map<String, dynamic>.from(rows[i] as Map),
          '_sourceNoteId': note['id'],
          '_sourceIndex': i,
        });
      }
    }
    if (cards.isEmpty) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => StudyNoteReview(
          cards: cards,
          onChanged: (changed) async {
            final nextBaseline = <String, String>{};
            try {
              await store.updateNotes((current) {
                final indexed = {for (final note in current) note['id']: note};
                for (final row in changed) {
                  if (row is! Map ||
                      row['_sourceNoteId'] is! String ||
                      row['_sourceIndex'] is! int) {
                    throw StateError('卡片来源无效');
                  }
                  final id = row['_sourceNoteId'] as String;
                  final index = row['_sourceIndex'] as int;
                  final note = indexed[id];
                  final existing = note?['cards'];
                  if (note == null ||
                      note['deleted'] == true ||
                      existing is! List ||
                      index < 0 ||
                      index >= existing.length ||
                      existing[index] is! Map ||
                      jsonEncode(existing[index]) != baseline['$id#$index']) {
                    throw StateError('卡片已在其他页面修改');
                  }
                  final updated = [...existing];
                  updated[index] = {
                    ...Map<String, dynamic>.from(existing[index] as Map),
                    'hard': row['hard'] == true,
                  };
                  indexed[id] = {...note, 'cards': updated};
                  nextBaseline['$id#$index'] = jsonEncode(updated[index]);
                }
                return [for (final note in current) indexed[note['id']]!];
              });
              baseline.addAll(nextBaseline);
              return true;
            } catch (_) {
              return false;
            }
          },
        ),
      ),
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final available = (_notes ?? [])
        .where((n) => (n['deleted'] == true) == _trash)
        .toList();
    final courses =
        available
            .map((n) => n['course'])
            .whereType<String>()
            .where((s) => s.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    final chapters =
        available
            .where(
              (n) =>
                  (widget.course ?? _courseFilter) == null ||
                  n['course'] == (widget.course ?? _courseFilter),
            )
            .map((n) => n['chapter'])
            .whereType<String>()
            .where((s) => s.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    final notes =
        (_notes ?? []).where((note) {
          if ((note['deleted'] == true) != _trash) return false;
          if (widget.course != null &&
              (note['course'] != widget.course ||
                  note['courseTeacher'] != widget.courseTeacher ||
                  note['courseAnchor'] != widget.courseAnchor)) {
            return false;
          }
          if (_courseFilter != null && note['course'] != _courseFilter) {
            return false;
          }
          if (_chapterFilter != null && note['chapter'] != _chapterFilter) {
            return false;
          }
          final text = [
            note['title'],
            note['body'],
            note['course'],
            note['chapter'],
            note['cards'],
          ].join(' ').toLowerCase();
          return text.contains(_query.toLowerCase());
        }).toList()..sort((a, b) {
          final favorite =
              (b['favorite'] == true ? 1 : 0) - (a['favorite'] == true ? 1 : 0);
          return favorite != 0
              ? favorite
              : (b['updatedAt'] as String? ?? '').compareTo(
                  a['updatedAt'] as String? ?? '',
                );
        });
    return SettingsScaffold(
      title: '笔记',
      root: widget.course == null,
      actions: [
        IconButton(
          tooltip: '笔记历史版本',
          onPressed: _store == null ? null : _history,
          icon: const Icon(Icons.history),
        ),
        IconButton(
          tooltip: _trash ? '返回笔记' : '笔记回收站',
          onPressed: () => setState(() => _trash = !_trash),
          icon: Icon(_trash ? Icons.arrow_back : Icons.delete_outline),
        ),
        IconButton(
          tooltip: '新建笔记',
          onPressed: _store == null || _busy ? null : _create,
          icon: const Icon(Icons.add),
        ),
      ],
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
            child: TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: '搜索标题、正文、课程或卡片',
              ),
              onChanged: (value) => setState(() => _query = value),
            ),
          ),
          if (!_trash &&
              notes.any(
                (n) => n['cards'] is List && (n['cards'] as List).isNotEmpty,
              ))
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => _reviewVisible(notes),
                icon: const Icon(Icons.quiz_outlined),
                label: const Text('复习筛选卡片'),
              ),
            ),
          if (widget.course != null)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: Text('这里只显示关联当前课程和教师的笔记；其他同名笔记可在全部课程中查找。'),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                if (widget.course == null)
                  Expanded(
                    child: StudyNoteFilterMenu(
                      label: _courseFilter ?? '全部课程',
                      tooltip: '按课程筛选',
                      allLabel: '全部课程',
                      selected: _courseFilter,
                      choices: courses,
                      optionKeyPrefix: 'note-course-option',
                      onSelected: (value) => setState(() {
                        _courseFilter = value.isEmpty ? null : value;
                        _chapterFilter = null;
                      }),
                    ),
                  )
                else
                  Expanded(
                    child: Text(
                      widget.course!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                Expanded(
                  child: StudyNoteFilterMenu(
                    label: _chapterFilter ?? '全部章节',
                    tooltip: '按章节筛选',
                    allLabel: '全部章节',
                    selected: _chapterFilter,
                    choices: chapters,
                    optionKeyPrefix: 'note-chapter-option',
                    onSelected: (value) => setState(
                      () => _chapterFilter = value.isEmpty ? null : value,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_error != null)
            const Expanded(child: Center(child: Text('笔记读取失败，请保留本地数据并重试。')))
          else if (_notes == null)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else if (notes.isEmpty)
            Expanded(
              child: Center(child: Text(_trash ? '回收站是空的' : '还没有笔记，点击右上角开始记录')),
            )
          else
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                itemCount: notes.length,
                itemBuilder: (context, index) {
                  final note = notes[index];
                  final title = (note['title'] as String? ?? '').trim();
                  final detail = [
                    note['course'],
                    note['chapter'],
                  ].whereType<String>().where((s) => s.isNotEmpty).join(' · ');
                  return WorkbenchPanel(
                    padding: EdgeInsets.zero,
                    child: Material(
                      color: Colors.transparent,
                      child: ListTile(
                        title: Text(title.isEmpty ? '未命名笔记' : title),
                        subtitle: Text(
                          detail.isEmpty
                              ? (note['body'] as String? ?? '')
                              : detail,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: _trash ? null : () => _edit(note),
                        trailing: Wrap(
                          spacing: 0,
                          children: [
                            if (!_trash)
                              IconButton(
                                tooltip: note['favorite'] == true
                                    ? '取消重点'
                                    : '标记重点',
                                icon: Icon(
                                  note['favorite'] == true
                                      ? Icons.star
                                      : Icons.star_border,
                                ),
                                onPressed: () => _change(
                                  note['id'] as String,
                                  'favorite',
                                  note['favorite'] != true,
                                ),
                              ),
                            IconButton(
                              tooltip: _trash ? '恢复笔记' : '移入回收站',
                              icon: Icon(
                                _trash ? Icons.restore : Icons.delete_outline,
                              ),
                              onPressed: () => _change(
                                note['id'] as String,
                                'deleted',
                                !_trash,
                              ),
                            ),
                          ],
                        ),
                      ),
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

class StudyNoteEditor extends StatefulWidget {
  const StudyNoteEditor({super.key, required this.store, required this.note});
  final StudyNoteStore store;
  final Map<String, dynamic> note;
  @override
  State<StudyNoteEditor> createState() => _StudyNoteEditorState();
}

class _StudyNoteEditorState extends State<StudyNoteEditor>
    with WidgetsBindingObserver {
  late final TextEditingController _title, _body, _course, _chapter;
  late Map<String, dynamic> _baseline;
  late List<dynamic> _blocks;
  late List<dynamic> _cards;
  Map<String, dynamic>? _reminder;
  Timer? _timer;
  Future<void> _tail = Future<void>.value();
  int _revision = 0, _saved = 0;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _baseline = Map<String, dynamic>.from(
      jsonDecode(jsonEncode(widget.note)) as Map,
    );
    _blocks = jsonDecode(jsonEncode(widget.note['blocks'] ?? [])) as List;
    _cards = jsonDecode(jsonEncode(widget.note['cards'] ?? [])) as List;
    if (widget.note['reminder'] is Map) {
      _reminder = Map<String, dynamic>.from(widget.note['reminder'] as Map);
    }
    _title = TextEditingController(text: widget.note['title'] as String? ?? '');
    _body = TextEditingController(text: widget.note['body'] as String? ?? '');
    _course = TextEditingController(
      text: widget.note['course'] as String? ?? '',
    );
    _chapter = TextEditingController(
      text: widget.note['chapter'] as String? ?? '',
    );
    for (final controller in [_title, _body, _course, _chapter]) {
      controller.addListener(_changed);
    }
  }

  void _changed() {
    _revision++;
    _timer?.cancel();
    _timer = Timer(const Duration(seconds: 1), () => unawaited(_save()));
    setState(() {});
  }

  Future<bool> _save() async {
    _timer?.cancel();
    final revision = _revision;
    if (revision == _saved) return true;
    final title = _title.text,
        body = _body.text,
        course = _course.text,
        chapter = _chapter.text;
    final blocks = jsonDecode(jsonEncode(_blocks)) as List;
    final cards = jsonDecode(jsonEncode(_cards)) as List;
    final reminder = _reminder == null
        ? null
        : Map<String, dynamic>.from(_reminder!);
    if (mounted) {
      setState(() {
        _saving = true;
        _error = null;
      });
    }
    var success = false;
    final task = _tail.then((_) async {
      Map<String, dynamic>? written;
      await widget.store.updateNotes((notes) {
        final current = notes
            .where((note) => note['id'] == widget.note['id'])
            .toList();
        if (current.length != 1) throw StateError('笔记不存在');
        if (jsonEncode(current.single) != jsonEncode(_baseline)) {
          throw StateError('笔记已在其他页面修改');
        }
        written = {
          ...current.single,
          'title': title,
          'body': body,
          'course': course,
          'courseTeacher': course == (current.single['course'] as String? ?? '')
              ? current.single['courseTeacher']
              : null,
          'courseAnchor': course == (current.single['course'] as String? ?? '')
              ? current.single['courseAnchor']
              : null,
          'chapter': chapter,
          'blocks': blocks,
          'cards': cards,
          'reminder': reminder,
          'updatedAt': DateTime.now().toIso8601String(),
        };
        final updated = [
          for (final note in notes)
            if (note['id'] == widget.note['id']) written! else note,
        ];
        return updated;
      });
      _baseline = written!;
      _saved = max(_saved, revision);
      success = true;
    });
    _tail = task.then<void>((_) {}, onError: (Object _, StackTrace stack) {});
    try {
      await task;
    } catch (error) {
      if (mounted) {
        _error = error is StateError && error.message == '笔记已在其他页面修改'
            ? '笔记已在其他页面修改，当前编辑仍保留在此页面，请先复制内容再退出。'
            : '保存失败，内容仍在当前页面，请检查存储空间后重试。';
      }
    }
    if (mounted) setState(() => _saving = false);
    return success;
  }

  Future<void> _leave() async {
    if (await _save() && mounted) Navigator.of(context).pop();
  }

  Future<void> _addImages() async {
    if (!await _save()) return;
    try {
      final files = await ImagePicker().pickMultiImage();
      for (final file in files) {
        if (await file.length() > 64 * 1024 * 1024) {
          throw const FormatException('图片大于 64 MB');
        }
        final bytes = await file.readAsBytes();
        final id = await widget.store.putAttachment(bytes);
        if (!mounted) return;
        setState(
          () => _blocks.add({
            'type': 'image',
            'attachmentId': id,
            'strokes': <dynamic>[],
          }),
        );
        _changed();
      }
      if (files.isNotEmpty) await _save();
    } catch (error) {
      if (mounted) setState(() => _error = '图片未能添加：$error');
    }
  }

  Future<void> _addDrawing() async {
    setState(() => _blocks.add({'type': 'drawing', 'strokes': <dynamic>[]}));
    _changed();
    if (await _save()) await _openCanvas(_blocks.length - 1);
  }

  Future<void> _openCanvas(int index) async {
    if (!await _save()) return;
    final block = Map<String, dynamic>.from(_blocks[index] as Map);
    try {
      final image = block['type'] == 'image'
          ? await widget.store.readAttachment(block['attachmentId'] as String)
          : null;
      if (!mounted) return;
      final strokes = await Navigator.of(context).push<List<dynamic>>(
        MaterialPageRoute(
          builder: (_) => StudyNoteCanvas(
            image: image,
            strokes: block['strokes'] as List? ?? [],
            onChanged: (strokes) async {
              if (!mounted) return false;
              setState(() => _blocks[index] = {...block, 'strokes': strokes});
              _changed();
              return _save();
            },
          ),
        ),
      );
      if (!mounted || strokes == null) return;
    } catch (error) {
      if (mounted) setState(() => _error = '无法打开画布：$error');
    }
  }

  Future<void> _editCard([int? index]) async {
    final existing = index == null
        ? <String, dynamic>{}
        : Map<String, dynamic>.from(_cards[index] as Map);
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (_) =>
          _CardEditorDialog(existing: existing, isNew: index == null),
    );
    if (!mounted || result == null) return;
    setState(() {
      final card = {...existing, ...result, 'hard': existing['hard'] == true};
      if (index == null) {
        _cards.add(card);
      } else {
        _cards[index] = card;
      }
    });
    _changed();
    await _save();
  }

  Future<void> _reviewCards() async {
    if (!await _save() || !mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => StudyNoteReview(
          cards: _cards,
          onChanged: (cards) async {
            if (!mounted) return false;
            setState(() => _cards = cards);
            _changed();
            return _save();
          },
        ),
      ),
    );
  }

  Future<void> _setReminder() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: now.add(const Duration(days: 1)),
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 3650)),
    );
    if (!mounted || date == null) return;
    final time = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 19, minute: 0),
    );
    if (!mounted || time == null) return;
    final at = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
    if (!at.isAfter(DateTime.now())) {
      setState(() => _error = '请选择未来的提醒时间。');
      return;
    }
    final repeat = await showDialog<String>(
      context: context,
      builder: (dc) => SimpleDialog(
        title: const Text('选择重复方式'),
        children: [
          for (final item in const [
            ('none', '只提醒一次'),
            ('daily', '每天'),
            ('weekly', '每周'),
          ])
            SimpleDialogOption(
              onPressed: () => Navigator.pop(dc, item.$1),
              child: Text(item.$2),
            ),
        ],
      ),
    );
    if (!mounted || repeat == null) return;
    setState(
      () => _reminder = {
        'at': at.millisecondsSinceEpoch,
        'repeat': repeat,
        'token':
            '${DateTime.now().microsecondsSinceEpoch}_${Random.secure().nextInt(1 << 32)}',
      },
    );
    _changed();
    if (!await _save()) return;
    try {
      await NotificationService.rerequestPermission();
      await _rescheduleStudyReminders();
      if (mounted && NotificationService.notificationsEnabled == false) {
        setState(() => _error = '提醒已保存，但系统通知权限未开启。');
      }
    } catch (_) {
      if (mounted) setState(() => _error = '提醒已保存，但系统排期失败，请检查通知设置后重试。');
    }
  }

  Future<void> _clearReminder() async {
    setState(() => _reminder = null);
    _changed();
    if (!await _save()) return;
    try {
      await _rescheduleStudyReminders();
    } catch (_) {
      if (mounted) setState(() => _error = '设置已保存，但提醒未能更新，请检查通知设置。');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      unawaited(_save());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    for (final controller in [_title, _body, _course, _chapter]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop) unawaited(_leave());
    },
    child: SettingsScaffold(
      title: '编辑笔记',
      actions: [
        TextButton(onPressed: _saving ? null : _save, child: const Text('保存')),
      ],
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 36),
        children: [
          TextField(
            key: const ValueKey('note-title'),
            controller: _title,
            decoration: const InputDecoration(labelText: '标题'),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: _addImages,
                icon: const Icon(Icons.add_photo_alternate_outlined),
                label: const Text('添加图片'),
              ),
              OutlinedButton.icon(
                onPressed: _addDrawing,
                icon: const Icon(Icons.draw_outlined),
                label: const Text('添加手写页'),
              ),
            ],
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.notifications_outlined),
            title: const Text('复习提醒'),
            subtitle: Text(
              _reminder == null
                  ? '由你指定时间和重复方式'
                  : '${DateTime.fromMillisecondsSinceEpoch(_reminder!['at'] as int)} · ${switch (_reminder!['repeat']) {
                      'daily' => '每天',
                      'weekly' => '每周',
                      _ => '一次',
                    }}',
            ),
            onTap: _setReminder,
            trailing: _reminder == null
                ? const Icon(Icons.chevron_right)
                : IconButton(
                    tooltip: '关闭复习提醒',
                    onPressed: _clearReminder,
                    icon: const Icon(Icons.notifications_off_outlined),
                  ),
          ),
          ValueListenableBuilder<String?>(
            valueListenable: NotificationService.studySchedule,
            builder: (context, status, _) =>
                Text(status ?? '提醒受系统权限和后台限制影响；iOS 需要定期打开应用。'),
          ),
          for (var i = 0; i < _blocks.length; i++)
            if (_blocks[i] is Map)
              WorkbenchPanel(
                padding: EdgeInsets.zero,
                child: Material(
                  color: Colors.transparent,
                  child: ListTile(
                    leading: Icon(
                      (_blocks[i] as Map)['type'] == 'image'
                          ? Icons.image_outlined
                          : Icons.draw_outlined,
                    ),
                    title: Text(
                      (_blocks[i] as Map)['type'] == 'image'
                          ? '图片 ${i + 1}'
                          : '手写页 ${i + 1}',
                    ),
                    subtitle: const Text('点击编辑批注'),
                    onTap: () => _openCanvas(i),
                    trailing: IconButton(
                      tooltip: '移除内容',
                      icon: const Icon(Icons.remove_circle_outline),
                      onPressed: () {
                        setState(() => _blocks.removeAt(i));
                        _changed();
                      },
                    ),
                  ),
                ),
              ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: () => _editCard(),
                icon: const Icon(Icons.add),
                label: const Text('新建自测卡片'),
              ),
              OutlinedButton.icon(
                onPressed: _cards.isEmpty ? null : _reviewCards,
                icon: const Icon(Icons.quiz_outlined),
                label: const Text('开始自测'),
              ),
            ],
          ),
          for (var i = 0; i < _cards.length; i++)
            if (_cards[i] is Map)
              ListTile(
                title: Text((_cards[i] as Map)['question'] as String? ?? ''),
                subtitle: Text(
                  (_cards[i] as Map)['hard'] == true ? '需要再看' : '点击编辑问题与答案',
                ),
                onTap: () => _editCard(i),
                trailing: IconButton(
                  tooltip: '删除卡片',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () {
                    setState(() => _cards.removeAt(i));
                    _changed();
                  },
                ),
              ),
          TextField(
            controller: _course,
            decoration: const InputDecoration(labelText: '课程（可选）'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _chapter,
            decoration: const InputDecoration(labelText: '章节（可选）'),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('note-body'),
            controller: _body,
            minLines: 10,
            maxLines: null,
            decoration: const InputDecoration(
              labelText: '记录知识与复习内容',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            _error ??
                (_saving
                    ? '正在保存…'
                    : _revision == _saved
                    ? '已保存到本机'
                    : '等待自动保存'),
          ),
        ],
      ),
    ),
  );
}

class _CardEditorDialog extends StatefulWidget {
  const _CardEditorDialog({required this.existing, required this.isNew});
  final Map<String, dynamic> existing;
  final bool isNew;
  @override
  State<_CardEditorDialog> createState() => _CardEditorDialogState();
}

class _CardEditorDialogState extends State<_CardEditorDialog> {
  late final TextEditingController _question, _answer;
  @override
  void initState() {
    super.initState();
    _question = TextEditingController(
      text: widget.existing['question'] as String? ?? '',
    );
    _answer = TextEditingController(
      text: widget.existing['answer'] as String? ?? '',
    );
  }

  @override
  void dispose() {
    _question.dispose();
    _answer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.isNew ? '新建自测卡片' : '编辑自测卡片'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _question,
            maxLines: null,
            decoration: const InputDecoration(labelText: '问题'),
          ),
          TextField(
            controller: _answer,
            maxLines: null,
            decoration: const InputDecoration(labelText: '答案'),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: () {
          if (_question.text.trim().isEmpty || _answer.text.trim().isEmpty) {
            return;
          }
          Navigator.pop(context, {
            'question': _question.text,
            'answer': _answer.text,
          });
        },
        child: const Text('保存'),
      ),
    ],
  );
}
