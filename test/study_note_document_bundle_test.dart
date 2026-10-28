import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homework_radar/services/study_note_bundle.dart';
import 'package:homework_radar/services/study_note_document.dart';

void main() {
  test('a document backup keeps nested canvas images and handwriting', () {
    final image = Uint8List.fromList([1, 8, 30, 250]);
    final imageId = sha256.convert(image).toString();
    final note = <String, dynamic>{
      'id': 'note',
      'body': '复习内容',
      'blocks': <dynamic>[],
      'document': {
        'version': 1,
        'nodes': [
          {
            'id': 'text-1',
            'type': 'text',
            'text': '复习内容',
            'style': 'paragraph',
            'marks': <dynamic>[],
            'annotations': [
              {
                'color': 0xff244d7a,
                'width': 3.0,
                'anchor': 0,
                'points': [
                  [0.1, 0.2],
                  [0.2, 0.3],
                ],
              },
            ],
          },
          {
            'id': 'canvas-1',
            'type': 'canvas',
            'strokes': <dynamic>[],
            'items': [
              {
                'id': 'image-1',
                'type': 'image',
                'attachmentId': imageId,
                'x': 0.1,
                'y': 0.2,
                'width': 0.4,
                'height': 0.3,
              },
            ],
          },
        ],
      },
    };
    final bundle = StudyNoteBundle(
      businessJson: '{"app":"homework_radar"}',
      notes: [note],
      attachments: {imageId: image},
      history: [
        [
          {'id': 'note', 'body': '旧正文', 'blocks': <dynamic>[]},
        ],
      ],
    );
    final restored = StudyNoteBundle.decode(bundle.encode());
    expect(restored.notes.single, note);
    expect(restored.attachments[imageId], image);
    expect(restored.history.single.single['body'], '旧正文');
  });

  test('an unsupported document version is rejected before saving', () {
    expect(
      () => StudyNoteBundle.referencedAttachments([
        {
          'id': 'n',
          'document': {'version': 999, 'nodes': <dynamic>[]},
        },
      ]),
      throwsFormatException,
    );
  });

  test(
    'invalid handwriting anchor metadata is rejected instead of being saved',
    () {
      expect(
        () => StudyNoteBundle.referencedAttachments([
          {
            'id': 'n',
            'document': {
              'version': 1,
              'nodes': [
                {
                  'id': 'p',
                  'type': 'text',
                  'text': 'abc',
                  'style': 'paragraph',
                  'annotations': [
                    {
                      'color': 1,
                      'anchor': 1,
                      'anchorX': 0.2,
                      'anchorY': 0.2,
                      'basisWidth': 0,
                      'basisHeight': 100,
                      'points': [
                        [0.2, 0.3],
                      ],
                    },
                  ],
                },
              ],
            },
          },
        ]),
        throwsFormatException,
      );
    },
  );

  test('a document cannot masquerade as an older backup format', () {
    final encoded = StudyNoteBundle(
      businessJson: '{}',
      notes: [
        {
          'id': 'n',
          'document': {'version': 1, 'nodes': <dynamic>[]},
        },
      ],
      attachments: {},
    ).encode();
    final headerLength = ByteData.sublistView(encoded, 8, 12).getUint32(0);
    final header =
        jsonDecode(utf8.decode(encoded.sublist(44, 44 + headerLength))) as Map;
    expect(header['version'], 3);
    header['version'] = 2;
    final alteredHeader = utf8.encode(jsonEncode(header));
    final length = ByteData(4)..setUint32(0, alteredHeader.length);
    final altered = BytesBuilder()
      ..add(encoded.sublist(0, 8))
      ..add(length.buffer.asUint8List())
      ..add(sha256.convert(alteredHeader).bytes)
      ..add(alteredHeader)
      ..add(encoded.sublist(44 + headerLength));
    expect(
      () => StudyNoteBundle.decode(altered.takeBytes()),
      throwsFormatException,
    );
  });

  test('legacy text, image and handwritten pages become editable without mutating the original', () {
    final old = <String, dynamic>{
      'id': 'old',
      'body': '原有正文',
      'blocks': [
        {'type': 'image', 'attachmentId': 'a' * 64, 'strokes': <dynamic>[]},
        {
          'type': 'drawing',
          'strokes': [
            {
              'color': 0xff244d7a,
              'points': [
                [0.1, 0.2],
              ],
            },
          ],
        },
      ],
      'cards': [
        {'question': '问题', 'answer': '答案'},
      ],
    };
    final before = jsonEncode(old);
    final document = StudyNoteDocument.fromNote(old);
    final nodes = document['nodes'] as List;
    expect(nodes.map((node) => node['type']), ['text', 'image', 'canvas']);
    expect(nodes.first['text'], '原有正文');
    expect(nodes[1]['attachmentId'], 'a' * 64);
    expect(nodes[2]['strokes'], (old['blocks'] as List)[1]['strokes']);
    expect(jsonEncode(old), before);
    expect(StudyNoteDocument.plainText(document), '原有正文');
    expect(StudyNoteDocument.legacyBlocks(document), old['blocks']);
  });

  test(
    'text edits move format and ink anchors without discarding detached ink',
    () {
      final node = <String, dynamic>{
        'text': 'abcdef',
        'marks': [
          {'type': 'bold', 'start': 1, 'end': 4},
        ],
        'annotations': [
          {
            'color': 1,
            'anchor': 3,
            'points': [
              [0.2, 0.3],
            ],
          },
        ],
      };
      StudyNoteDocument.applyTextChange(node, 'XXabcdef');
      expect((node['marks'] as List).single, {
        'type': 'bold',
        'start': 3,
        'end': 6,
      });
      expect((node['annotations'] as List).single['anchor'], 5);
      StudyNoteDocument.applyTextChange(node, 'XXaef');
      expect(node['marks'], isEmpty);
      final stroke = (node['annotations'] as List).single as Map;
      expect(stroke['anchor'], 3);
      expect(stroke['detached'], isTrue);
      expect(stroke['points'], [
        [0.2, 0.3],
      ]);
    },
  );

  test(
    'splitting a paragraph preserves text, formatting and anchored handwriting',
    () {
      final original = <String, dynamic>{
        'id': 'p',
        'type': 'text',
        'style': 'paragraph',
        'text': 'abcdef',
        'marks': [
          {'type': 'bold', 'start': 1, 'end': 5},
        ],
        'annotations': [
          {
            'color': 1,
            'anchor': 4,
            'points': [
              [0.2, 0.3],
            ],
          },
        ],
      };
      final before = jsonEncode(original);
      final (left, right) = StudyNoteDocument.splitTextNode(
        original,
        3,
        'next',
      );
      expect(left['text'], 'abc');
      expect(right['text'], 'def');
      expect(left['marks'], [
        {'type': 'bold', 'start': 1, 'end': 3},
      ]);
      expect(right['marks'], [
        {'type': 'bold', 'start': 0, 'end': 2},
      ]);
      expect(left['annotations'], isEmpty);
      expect((right['annotations'] as List).single['anchor'], 1);
      expect((right['annotations'] as List).single['points'], [
        [0.2, 0.3],
      ]);
      expect(jsonEncode(original), before);
    },
  );
}
