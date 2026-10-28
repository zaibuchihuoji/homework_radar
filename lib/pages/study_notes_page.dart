import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';

import '../services/study_note_document.dart';
import '../services/study_note_store.dart';
import '../services/storage.dart';
import '../services/notification_service.dart';
import '../ui/settings_parts.dart';
import '../ui/study_note_filter_picker.dart';
import '../ui/tokens.dart';
import 'study_note_document_editor.dart';
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
  List<Map<String, dynamic>> _folders = [];
  Object? _error;
  String _query = '';
  String? _courseFilter;
  String? _folderFilter;
  bool _uncategorized = false;
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
      final library = await store.readLibrary(
        requireInitialized: widget.store == null,
      );
      final notes = library.notes;
      if (mounted) {
        setState(() {
          _store = store;
          _notes = notes;
          _folders = library.folders;
          if (_folderFilter != null &&
              !_folders.any((f) => f['id'] == _folderFilter)) {
            _folderFilter = null;
          }
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
      'course': widget.course ?? _courseFilter ?? '',
      'courseTeacher': widget.courseTeacher,
      'courseAnchor': widget.courseAnchor,
      'chapter': '',
      if (_folderFilter != null) 'notebookId': _folderFilter,
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
          builder: (_) =>
              StudyNoteEditor(store: store, note: note, folders: _folders),
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
        builder: (_) =>
            StudyNoteEditor(store: store, note: note, folders: _folders),
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

  Future<String?> _folderName({String initial = ''}) => showDialog<String>(
    context: context,
    builder: (_) => _FolderNameDialog(initial: initial),
  );

  Future<void> _manageFolder({Map<String, dynamic>? folder}) async {
    final store = _store;
    if (store == null) return;
    final name = await _folderName(initial: folder?['name'] as String? ?? '');
    if (!mounted || name == null) return;
    if (name.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('请输入文件夹名称')));
      return;
    }
    try {
      final random = Random.secure();
      final id =
          folder?['id'] as String? ??
          'folder-${DateTime.now().microsecondsSinceEpoch}-${List.generate(12, (_) => random.nextInt(16).toRadixString(16)).join()}';
      await store.updateLibrary((library) {
        if (folder != null &&
            !library.folders.any(
              (f) => f['id'] == id && f['name'] == folder['name'],
            )) {
          throw StateError('文件夹已变化，请重新选择');
        }
        if (library.folders.any(
          (f) =>
              f['id'] != id &&
              (f['name'] as String).trim().toLowerCase() == name.toLowerCase(),
        )) {
          throw StateError('文件夹名称已存在');
        }
        return StudyNoteLibrary(
          notes: library.notes,
          folders: folder == null
              ? [
                  ...library.folders,
                  {'id': id, 'name': name},
                ]
              : [
                  for (final f in library.folders)
                    if (f['id'] == id) {...f, 'name': name} else f,
                ],
        );
      });
      await _load();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error is StateError && error.message == '文件夹名称已存在'
                  ? '文件夹名称已存在，请换一个名称。'
                  : '文件夹未保存，请重试。',
            ),
          ),
        );
      }
    }
  }

  Future<void> _deleteFolder(Map<String, dynamic> folder) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dc) => AlertDialog(
        title: const Text('删除文件夹？'),
        content: Text('“${folder['name']}”中的笔记将移到未分类，笔记内容会保留。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dc, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dc, true),
            child: const Text('删除文件夹'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || _store == null) return;
    try {
      await _store!.updateLibrary((library) {
        if (!library.folders.any(
          (f) => f['id'] == folder['id'] && f['name'] == folder['name'],
        )) {
          throw StateError('文件夹已变化');
        }
        return StudyNoteLibrary(
          folders: [
            for (final f in library.folders)
              if (f['id'] != folder['id']) f,
          ],
          notes: [
            for (final note in library.notes)
              if (note['notebookId'] == folder['id'])
                (Map<String, dynamic>.from(note)..remove('notebookId'))
              else
                note,
          ],
        );
      });
      await _load();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('文件夹未删除，笔记已保留。')));
      }
    }
  }

  Future<void> _moveToFolder(Map<String, dynamic> note) async {
    final store = _store;
    if (store == null) return;
    final selected = await showDialog<String>(
      context: context,
      builder: (dc) => SimpleDialog(
        title: const Text('移动笔记到'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(dc, ''),
            child: const Text('未分类'),
          ),
          for (final folder in _folders)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(dc, folder['id'] as String),
              child: Text(folder['name'] as String),
            ),
        ],
      ),
    );
    if (selected == null || !mounted) return;
    try {
      await store.updateLibrary((library) {
        if (selected.isNotEmpty &&
            !library.folders.any((f) => f['id'] == selected)) {
          throw StateError('文件夹已不存在');
        }
        if (!library.notes.any(
          (n) => n['id'] == note['id'] && n['deleted'] != true,
        )) {
          throw StateError('笔记已不存在');
        }
        final updated = <Map<String, dynamic>>[];
        for (final n in library.notes) {
          if (n['id'] != note['id']) {
            updated.add(n);
          } else {
            final moved = Map<String, dynamic>.from(n);
            if (selected.isEmpty) {
              moved.remove('notebookId');
            } else {
              moved['notebookId'] = selected;
            }
            updated.add(moved);
          }
        }
        return StudyNoteLibrary(folders: library.folders, notes: updated);
      });
      await _load();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('笔记未移动，请刷新后重试。')));
      }
    }
  }

  Future<void> _browseCourses(
    List<Map<String, dynamic>> available,
    List<String> courses,
  ) async {
    final p = paletteOf(context);
    final selection = await showGeneralDialog<String>(
      context: context,
      barrierDismissible: true,
      barrierLabel: '关闭分类',
      transitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (context, _, _) => Align(
        alignment: Alignment.centerLeft,
        child: Material(
          color: p.modal,
          child: SafeArea(
            child: SizedBox(
              width: min(320, MediaQuery.sizeOf(context).width * .82),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 22, 20, 16),
                    child: Text(
                      '笔记分类',
                      style: Theme.of(context).textTheme.titleLarge
                          ?.copyWith(color: p.ink, fontWeight: FontWeight.w600),
                    ),
                  ),
                  ListTile(
                    leading: const Icon(Icons.notes),
                    title: const Text('全部笔记'),
                    trailing: Text('${available.length}'),
                    selected:
                        _courseFilter == null &&
                        _folderFilter == null &&
                        !_uncategorized,
                    onTap: () => Navigator.pop(context, 'all'),
                  ),
                  ListTile(
                    leading: const Icon(Icons.folder_outlined),
                    title: const Text('未分类'),
                    trailing: Text(
                      '${available.where((n) => n['notebookId'] == null).length}',
                    ),
                    selected: _uncategorized,
                    onTap: () => Navigator.pop(context, 'none'),
                  ),
                  Expanded(
                    child: ListView(
                      children: [
                        const Divider(),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 4, 8, 4),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '我的文件夹',
                                  style: TextStyle(color: p.ink2),
                                ),
                              ),
                              IconButton(
                                tooltip: '新建文件夹',
                                onPressed: () =>
                                    Navigator.pop(context, 'create-folder'),
                                icon: const Icon(
                                  Icons.create_new_folder_outlined,
                                ),
                              ),
                            ],
                          ),
                        ),
                        for (final folder in _folders)
                          ListTile(
                            leading: Icon(
                              Icons.folder_outlined,
                              color: p.accent,
                            ),
                            title: Text(
                              folder['name'] as String,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            selected: _folderFilter == folder['id'],
                            onTap: () => Navigator.pop(
                              context,
                              'folder:${folder['id']}',
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '${available.where((n) => n['notebookId'] == folder['id']).length}',
                                ),
                                PopupMenuButton<String>(
                                  tooltip: '文件夹操作',
                                  onSelected: (v) => Navigator.pop(
                                    context,
                                    '$v:${folder['id']}',
                                  ),
                                  itemBuilder: (_) => const [
                                    PopupMenuItem(
                                      value: 'rename-folder',
                                      child: Text('重命名'),
                                    ),
                                    PopupMenuItem(
                                      value: 'delete-folder',
                                      child: Text('删除文件夹'),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        const Divider(),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                          child: Text('课程', style: TextStyle(color: p.ink2)),
                        ),
                        for (final course in courses)
                          ListTile(
                            leading: const Icon(Icons.folder_outlined),
                            title: Text(course),
                            trailing: Text(
                              '${available.where((n) => n['course'] == course).length}',
                            ),
                            selected:
                                _courseFilter == course &&
                                _folderFilter == null &&
                                !_uncategorized,
                            onTap: () =>
                                Navigator.pop(context, 'course:$course'),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      transitionBuilder: (context, animation, _, child) => SlideTransition(
        position: Tween(begin: const Offset(-1, 0), end: Offset.zero).animate(
          CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
        ),
        child: child,
      ),
    );
    if (!mounted || selection == null) return;
    if (selection == 'create-folder') {
      await _manageFolder();
      return;
    }
    if (selection.startsWith('rename-folder:') ||
        selection.startsWith('delete-folder:')) {
      final id = selection.substring(selection.indexOf(':') + 1);
      final folder = _folders.where((f) => f['id'] == id).firstOrNull;
      if (folder == null) return;
      if (selection.startsWith('rename-folder:')) {
        await _manageFolder(folder: folder);
      } else {
        await _deleteFolder(folder);
      }
      return;
    }
    setState(() {
      _uncategorized = selection == 'none';
      _folderFilter = selection.startsWith('folder:')
          ? selection.substring(7)
          : null;
      _courseFilter = selection.startsWith('course:')
          ? selection.substring(7)
          : null;
      _chapterFilter = null;
    });
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
          if (_uncategorized && note['notebookId'] != null) {
            return false;
          }
          if (_folderFilter != null && note['notebookId'] != _folderFilter) {
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
          if (_uncategorized || _folderFilter != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  const Icon(Icons.folder_outlined, size: 17),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _uncategorized
                          ? '未分类'
                          : (_folders
                                        .where((f) => f['id'] == _folderFilter)
                                        .firstOrNull?['name']
                                    as String? ??
                                '文件夹'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  TextButton(
                    onPressed: () => setState(() {
                      _folderFilter = null;
                      _uncategorized = false;
                    }),
                    child: const Text('查看全部'),
                  ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                if (widget.course == null) ...[
                  IconButton(
                    key: const ValueKey('note-category-picker'),
                    tooltip: '浏览笔记分类',
                    onPressed: () => _browseCourses(available, courses),
                    icon: const Icon(Icons.folder_outlined),
                  ),
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
                  ),
                ] else
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
                  final body = (note['body'] as String? ?? '').trim();
                  final date = DateTime.tryParse(
                    note['updatedAt'] as String? ?? '',
                  );
                  final course = (note['course'] as String? ?? '').trim();
                  final p = paletteOf(context);
                  final document = note['document'];
                  final nodes = document is Map && document['nodes'] is List
                      ? document['nodes'] as List
                      : note['blocks'] as List? ?? const [];
                  String? imageId;
                  for (final node in nodes) {
                    if (node is Map &&
                        node['type'] == 'image' &&
                        node['attachmentId'] is String) {
                      imageId = node['attachmentId'] as String;
                      break;
                    }
                  }
                  return Column(
                    children: [
                      InkWell(
                        onTap: _trash ? null : () => _edit(note),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 16,
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        if (note['favorite'] == true)
                                          Padding(
                                            padding: const EdgeInsets.only(
                                              right: 6,
                                            ),
                                            child: Icon(
                                              Icons.star,
                                              size: 16,
                                              color: p.accent,
                                            ),
                                          ),
                                        Expanded(
                                          child: Text(
                                            title.isEmpty ? '未命名笔记' : title,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: Theme.of(context)
                                                .textTheme
                                                .titleMedium
                                                ?.copyWith(
                                                  fontWeight: FontWeight.w600,
                                                  color: p.ink,
                                                ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    if (body.isNotEmpty) ...[
                                      const SizedBox(height: 5),
                                      Text(
                                        body,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodyMedium
                                            ?.copyWith(color: p.ink2),
                                      ),
                                    ],
                                    const SizedBox(height: 9),
                                    Text(
                                      [
                                        if (date != null)
                                          '${date.year}/${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}',
                                        if (course.isNotEmpty) course,
                                      ].join(' · '),
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(color: p.ink3),
                                    ),
                                  ],
                                ),
                              ),
                              if (imageId != null && _store != null)
                                Padding(
                                  padding: const EdgeInsets.only(left: 12),
                                  child: FutureBuilder(
                                    future: _store!.readAttachment(imageId),
                                    builder: (context, snapshot) =>
                                        snapshot.hasData
                                        ? ClipRRect(
                                            borderRadius: BorderRadius.circular(
                                              p.radius.clamp(2.0, 8.0),
                                            ),
                                            child: Image.memory(
                                              snapshot.data!,
                                              width: 56,
                                              height: 56,
                                              fit: BoxFit.cover,
                                              errorBuilder: (_, _, _) =>
                                                  const SizedBox.shrink(),
                                            ),
                                          )
                                        : const SizedBox.shrink(),
                                  ),
                                ),
                              PopupMenuButton<String>(
                                tooltip: '笔记操作',
                                onSelected: (value) {
                                  if (value == 'favorite') {
                                    _change(
                                      note['id'] as String,
                                      'favorite',
                                      note['favorite'] != true,
                                    );
                                  } else if (value == 'move') {
                                    _moveToFolder(note);
                                  } else if (value == 'deleted') {
                                    _change(
                                      note['id'] as String,
                                      'deleted',
                                      !_trash,
                                    );
                                  }
                                },
                                itemBuilder: (_) => [
                                  if (!_trash)
                                    const PopupMenuItem(
                                      value: 'move',
                                      child: Text('移动到文件夹'),
                                    ),
                                  if (!_trash)
                                    PopupMenuItem(
                                      value: 'favorite',
                                      child: Text(
                                        note['favorite'] == true
                                            ? '取消重点'
                                            : '标记重点',
                                      ),
                                    ),
                                  PopupMenuItem(
                                    value: 'deleted',
                                    child: Text(_trash ? '恢复笔记' : '移入回收站'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                      Divider(height: 1, color: p.hairline),
                    ],
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _FolderNameDialog extends StatefulWidget {
  const _FolderNameDialog({required this.initial});
  final String initial;

  @override
  State<_FolderNameDialog> createState() => _FolderNameDialogState();
}

class _FolderNameDialogState extends State<_FolderNameDialog> {
  late final TextEditingController controller;
  @override
  void initState() {
    super.initState();
    controller = TextEditingController(text: widget.initial);
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.initial.isEmpty ? '新建文件夹' : '重命名文件夹'),
    content: TextField(
      controller: controller,
      autofocus: true,
      maxLength: 80,
      decoration: const InputDecoration(labelText: '文件夹名称'),
      onSubmitted: (_) => Navigator.pop(context, controller.text.trim()),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, controller.text.trim()),
        child: const Text('保存'),
      ),
    ],
  );
}

class StudyNoteEditor extends StatefulWidget {
  const StudyNoteEditor({
    super.key,
    required this.store,
    required this.note,
    this.folders = const [],
  });
  final StudyNoteStore store;
  final Map<String, dynamic> note;
  final List<Map<String, dynamic>> folders;
  @override
  State<StudyNoteEditor> createState() => _StudyNoteEditorState();
}

class _StudyNoteEditorState extends State<StudyNoteEditor>
    with WidgetsBindingObserver {
  late final TextEditingController _title, _course, _chapter;
  late Map<String, dynamic> _baseline;
  late Map<String, dynamic> _document;
  late bool _documentEdited;
  late List<dynamic> _cards;
  Map<String, dynamic>? _reminder;
  String? _notebookId;
  late List<Map<String, dynamic>> _availableFolders;
  Timer? _timer;
  Future<void> _tail = Future<void>.value();
  int _revision = 0, _saved = 0;
  bool _saving = false;
  bool _showDetails = false;
  String? _error;

  String? get _updatedLabel {
    final value = DateTime.tryParse(_baseline['updatedAt'] as String? ?? '')
        ?.toLocal();
    if (value == null) return null;
    String two(int number) => number.toString().padLeft(2, '0');
    return '${value.year}/${two(value.month)}/${two(value.day)} ${two(value.hour)}:${two(value.minute)}';
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _baseline = Map<String, dynamic>.from(
      jsonDecode(jsonEncode(widget.note)) as Map,
    );
    _document = StudyNoteDocument.fromNote(widget.note);
    _documentEdited = widget.note.containsKey('document');
    _notebookId = widget.note['notebookId'] as String?;
    _availableFolders = [...widget.folders];
    _cards = jsonDecode(jsonEncode(widget.note['cards'] ?? [])) as List;
    if (widget.note['reminder'] is Map) {
      _reminder = Map<String, dynamic>.from(widget.note['reminder'] as Map);
    }
    _title = TextEditingController(text: widget.note['title'] as String? ?? '');
    _course = TextEditingController(
      text: widget.note['course'] as String? ?? '',
    );
    _chapter = TextEditingController(
      text: widget.note['chapter'] as String? ?? '',
    );
    for (final controller in [_title, _course, _chapter]) {
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
    final title = _title.text, course = _course.text, chapter = _chapter.text;
    final notebookId = _notebookId;
    Map<String, dynamic>? document;
    late String body;
    late List<dynamic> blocks;
    try {
      document = _documentEdited
          ? Map<String, dynamic>.from(jsonDecode(jsonEncode(_document)) as Map)
          : null;
      body = document == null
          ? _baseline['body'] as String? ?? ''
          : StudyNoteDocument.plainText(document);
      blocks = document == null
          ? jsonDecode(jsonEncode(_baseline['blocks'] ?? [])) as List
          : StudyNoteDocument.legacyBlocks(document);
    } catch (_) {
      if (mounted) {
        setState(() => _error = '内容暂时无法保存，当前编辑仍保留在此页面，请检查后重试。');
      }
      return false;
    }
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
          ...?(document == null ? null : {'document': document}),
          'cards': cards,
          'reminder': reminder,
          'updatedAt': DateTime.now().toIso8601String(),
        };
        if (notebookId == null) {
          written!.remove('notebookId');
        } else {
          written!['notebookId'] = notebookId;
        }
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
    if (_showDetails) {
      setState(() => _showDetails = false);
      return;
    }
    if (await _save() && mounted) Navigator.of(context).pop();
  }

  Future<void> _selectFolder() async {
    late List<Map<String, dynamic>> folders;
    try {
      folders = (await widget.store.readLibrary()).folders;
    } catch (_) {
      if (mounted) setState(() => _error = '文件夹暂时无法读取，请保留当前内容并重试。');
      return;
    }
    if (!mounted) return;
    setState(() => _availableFolders = folders);
    final selected = await showDialog<String>(
      context: context,
      builder: (dc) => SimpleDialog(
        title: const Text('选择文件夹'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(dc, ''),
            child: const Text('未分类'),
          ),
          for (final folder in folders)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(dc, folder['id'] as String),
              child: Text(folder['name'] as String),
            ),
          if (folders.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('可在笔记列表中新建文件夹'),
            ),
        ],
      ),
    );
    if (!mounted || selected == null) return;
    setState(() => _notebookId = selected.isEmpty ? null : selected);
    _changed();
  }

  Future<void> _editCard([int? index, String? question]) async {
    final existing = index == null
        ? <String, dynamic>{'question': question ?? ''}
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
    for (final controller in [_title, _course, _chapter]) {
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
      title: _showDetails ? '笔记信息' : '',
      actions: [
        IconButton(
          tooltip: _showDetails ? '返回正文' : '笔记信息与复习',
          onPressed: () {
            FocusScope.of(context).unfocus();
            setState(() => _showDetails = !_showDetails);
          },
          icon: Icon(_showDetails ? Icons.edit_note : Icons.info_outline),
        ),
        TextButton(onPressed: _saving ? null : _save, child: const Text('保存')),
      ],
      body: StudyNoteDocumentEditor(
        showDetails: _showDetails,
        header: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              key: const ValueKey('note-title'),
              controller: _title,
              style: Theme.of(context).textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w600),
              maxLines: null,
              decoration: InputDecoration(
                hintText: '标题',
                hintStyle: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: paletteOf(context).ink3,
                  fontWeight: FontWeight.w600,
                ),
                isCollapsed: true,
                contentPadding: EdgeInsets.zero,
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                disabledBorder: InputBorder.none,
              ),
            ),
            const SizedBox(height: 12),
            InkWell(
              key: const ValueKey('note-folder-selector'),
              onTap: _selectFolder,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        [
                          _availableFolders
                                      .where((f) => f['id'] == _notebookId)
                                      .firstOrNull?['name']
                                  as String? ??
                              '未分类',
                          '${StudyNoteDocument.plainText(_document).characters.length} 字',
                          ?_updatedLabel,
                        ].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    const Icon(Icons.keyboard_arrow_down, size: 18),
                  ],
                ),
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            const SizedBox(height: 20),
          ],
        ),
        footer: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 12),
            ExpansionTile(
              title: const Text('复习与笔记信息'),
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.folder_outlined),
                  title: const Text('所在文件夹'),
                  subtitle: Text(
                    _availableFolders
                                .where((f) => f['id'] == _notebookId)
                                .firstOrNull?['name']
                            as String? ??
                        '未分类',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _selectFolder,
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
                      title: Text(
                        (_cards[i] as Map)['question'] as String? ?? '',
                      ),
                      subtitle: Text(
                        (_cards[i] as Map)['hard'] == true
                            ? '需要再看'
                            : '点击编辑问题与答案',
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
                ExpansionTile(
                  title: const Text('课程与章节'),
                  children: [
                    TextField(
                      controller: _course,
                      decoration: const InputDecoration(labelText: '课程（可选）'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _chapter,
                      decoration: const InputDecoration(labelText: '章节（可选）'),
                    ),
                  ],
                ),
              ],
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
        document: _document,
        store: widget.store,
        save: _save,
        onChanged: (document) {
          _document = document;
          _documentEdited = true;
          _changed();
        },
        onError: (message) {
          if (mounted) setState(() => _error = message);
        },
        onCreateCard: (text) => _editCard(null, text),
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
