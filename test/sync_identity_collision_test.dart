import 'package:flutter_test/flutter_test.dart';
import 'package:homework_radar/models/homework.dart';
import 'package:homework_radar/services/sync_service.dart';

HomeworkItem task(
  String id,
  String source,
  PlatformKind platform, {
  String? note,
  HwStatus status = HwStatus.todo,
}) => HomeworkItem(
  id: id,
  platform: platform,
  course: 'Same name',
  title: source,
  sourceKey: source,
  note: note,
  status: status,
);

void main() {
  for (final platform in PlatformKind.values.where(
    (p) => p != PlatformKind.manual,
  )) {
    test(
      '${platform.name} colliding legacy ID cannot overwrite another real source',
      () {
        final old = task(
          'shared-id',
          'source-A',
          platform,
          note: 'A note',
          status: HwStatus.done,
        );
        final merged = {old.id: old};
        mergePlatform(
          merged,
          [task('shared-id', 'source-B', platform)],
          platform,
          complete: true,
        );
        expect(merged, hasLength(2));
        expect(merged['shared-id']!.sourceKey, 'source-A');
        expect(merged['shared-id']!.note, 'A note');
        expect(merged['shared-id']!.status, HwStatus.done);
        final next = merged.values.singleWhere(
          (h) => h.sourceKey == 'source-B',
        );
        expect(next.note, isNull);
        expect(next.status, HwStatus.todo);
        final nextId = next.id;
        merged[nextId] = next.copyWith(note: 'B note');
        mergePlatform(
          merged,
          [task('shared-id', 'source-B', platform)],
          platform,
          complete: false,
        );
        expect(merged, hasLength(2));
        expect(merged[nextId]!.note, 'B note');
      },
    );

    test(
      '${platform.name} two new real sources sharing an ID both survive, including next sync',
      () {
        final merged = <String, HomeworkItem>{};
        final input = [
          task('same-id', 'A', platform),
          task('same-id', 'B', platform),
        ];
        mergePlatform(merged, input, platform, complete: true);
        expect(merged.values.map((h) => h.sourceKey).toSet(), {'A', 'B'});
        final ids = merged.keys.toSet();
        mergePlatform(
          merged,
          input.reversed.toList(),
          platform,
          complete: true,
        );
        expect(merged.keys.toSet(), ids);
      },
    );

    test(
      '${platform.name} duplicate source with changed IDs in one response is one task',
      () {
        final merged = <String, HomeworkItem>{};
        mergePlatform(
          merged,
          [
            task('id-1', 'same-source', platform),
            task('id-2', 'same-source', platform),
          ],
          platform,
          complete: true,
        );
        expect(merged, hasLength(1));
      },
    );
  }

  test('manual record with matching source key cannot donate its identity or note to a platform', () {
    final manual = task(
      'manual_1',
      'mooc|1|2|4|8',
      PlatformKind.manual,
      note: 'Private manual note',
    );
    final merged = {manual.id: manual};
    mergePlatform(
      merged,
      [task('mooc_new', manual.sourceKey!, PlatformKind.mooc)],
      PlatformKind.mooc,
      complete: true,
    );
    expect(merged['manual_1']!.platform, PlatformKind.manual);
    expect(merged['manual_1']!.note, 'Private manual note');
    expect(merged['mooc_new']!.note, isNull);
  });

  test('ambiguous source matching an old ID preserves both old notes and does not grow on retry', () {
    final merged = {
      'a': task('a', 'same', PlatformKind.chaoxing, note: 'A note'),
      'b': task('b', 'same', PlatformKind.chaoxing, note: 'B note'),
    };
    final input = [task('a', 'same', PlatformKind.chaoxing)];
    mergePlatform(merged, input, PlatformKind.chaoxing, complete: true);
    expect(merged, hasLength(3));
    expect(merged['a']!.note, 'A note');
    expect(merged['b']!.note, 'B note');
    mergePlatform(merged, input, PlatformKind.chaoxing, complete: true);
    expect(merged, hasLength(3));
  });
}
