import 'dart:convert';

import 'package:flutter/material.dart';

import '../ui/settings_parts.dart';
import '../ui/focus_parts.dart';

class StudyNoteReview extends StatefulWidget {
  const StudyNoteReview({
    super.key,
    required this.cards,
    required this.onChanged,
  });
  final List<dynamic> cards;
  final Future<bool> Function(List<dynamic>) onChanged;
  @override
  State<StudyNoteReview> createState() => _StudyNoteReviewState();
}

class _StudyNoteReviewState extends State<StudyNoteReview> {
  late List<dynamic> _cards;
  int _index = 0;
  bool _answer = false, _hardOnly = false, _saving = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _cards = jsonDecode(jsonEncode(widget.cards)) as List;
  }

  @override
  Widget build(BuildContext context) {
    final indexes = [
      for (var i = 0; i < _cards.length; i++)
        if (_cards[i] is Map &&
            (!_hardOnly || (_cards[i] as Map)['hard'] == true))
          i,
    ];
    if (_index >= indexes.length) _index = 0;
    final card = indexes.isEmpty
        ? null
        : Map<String, dynamic>.from(_cards[indexes[_index]] as Map);
    return SettingsScaffold(
      title: '自测复习',
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            SwitchListTile(
              title: const Text('只看需要再看的卡片'),
              value: _hardOnly,
              onChanged: (v) => setState(() {
                _hardOnly = v;
                _index = 0;
                _answer = false;
              }),
            ),
            if (card == null)
              const Expanded(child: Center(child: Text('没有符合条件的卡片')))
            else ...[
              Text('${_index + 1} / ${indexes.length}'),
              Expanded(
                child: Center(
                  child: WorkbenchPanel(
                    padding: EdgeInsets.zero,
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => setState(() => _answer = !_answer),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(24),
                          child: SingleChildScrollView(
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 220),
                              child: Column(
                                key: ValueKey(_answer),
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    _answer ? '答案' : '问题',
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelLarge,
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    (_answer
                                                ? card['answer']
                                                : card['question'])
                                            as String? ??
                                        '',
                                    textAlign: TextAlign.center,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleLarge,
                                  ),
                                  const SizedBox(height: 16),
                                  const Text('点击翻面'),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              if (_error != null) Text(_error!),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                children: [
                  TextButton(
                    onPressed: _index == 0
                        ? null
                        : () => setState(() {
                            _index--;
                            _answer = false;
                          }),
                    child: const Text('上一张'),
                  ),
                  OutlinedButton(
                    onPressed: _saving
                        ? null
                        : () async {
                            final actual = indexes[_index];
                            setState(() {
                              _cards[actual] = {
                                ...card,
                                'hard': card['hard'] != true,
                              };
                              _saving = true;
                              _error = null;
                            });
                            final success = await widget.onChanged(
                              jsonDecode(jsonEncode(_cards)) as List,
                            );
                            if (mounted) {
                              setState(() {
                                _saving = false;
                                if (!success) _error = '标记未保存，请重试。';
                              });
                            }
                          },
                    child: Text(card['hard'] == true ? '取消需要再看' : '需要再看'),
                  ),
                  TextButton(
                    onPressed: _index + 1 >= indexes.length
                        ? null
                        : () => setState(() {
                            _index++;
                            _answer = false;
                          }),
                    child: const Text('下一张'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
