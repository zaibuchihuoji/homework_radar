import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homework_radar/services/study_note_bundle.dart';

void main() {
  test(
    'portable bundle retains business data, notes, strokes and original image',
    () {
      final image = Uint8List.fromList([0, 8, 100, 255]);
      final id = sha256.convert(image).toString();
      final notes = <Map<String, dynamic>>[
        {
          'id': 'n1',
          'title': '笔记',
          'blocks': [
            {
              'type': 'image',
              'attachmentId': id,
              'strokes': [
                {
                  'color': 0xff244d7a,
                  'points': [
                    [0.2, 0.5],
                  ],
                },
              ],
            },
            {
              'type': 'drawing',
              'strokes': [
                {
                  'color': 0xff244d7a,
                  'points': [
                    [0.3, 0.9],
                  ],
                },
              ],
            },
          ],
          'cards': [
            {'question': '问题', 'answer': '答案'},
          ],
        },
      ];
      final bundle = StudyNoteBundle(
        businessJson: '{"app":"homework_radar"}',
        notes: notes,
        attachments: {id: image},
      );
      final decoded = StudyNoteBundle.decode(bundle.encode());
      expect(decoded.businessJson, bundle.businessJson);
      expect(decoded.notes, notes);
      expect(decoded.attachments[id], image);
    },
  );

  test('truncation or altered attachment is rejected', () {
    final image = Uint8List.fromList([1, 2, 3]);
    final id = sha256.convert(image).toString();
    final bundle = StudyNoteBundle(
      businessJson: '{}',
      notes: [
        {
          'id': 'a',
          'blocks': [
            {'type': 'image', 'attachmentId': id},
          ],
        },
      ],
      attachments: {id: image},
    );
    final encoded = bundle.encode();
    expect(
      () => StudyNoteBundle.decode(
        Uint8List.sublistView(encoded, 0, encoded.length - 1),
      ),
      throwsFormatException,
    );
    encoded[encoded.length - 1] ^= 1;
    expect(() => StudyNoteBundle.decode(encoded), throwsFormatException);
  });
}
