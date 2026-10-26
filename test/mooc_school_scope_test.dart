import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:homework_radar/services/mooc_service.dart';

import 'support/synthetic_http.dart';
import 'support/mooc_school_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final network = SyntheticHttp();
  setUpAll(() => HttpOverrides.global = network);
  tearDownAll(() => HttpOverrides.global = null);

  SyntheticResponse json(Object value) => SyntheticResponse(jsonEncode(value));

  test(
    'only enrolled school terms overlapping this semester are fetched',
    () async {
      final now = DateTime.now();
      final old = DateTime(now.year - 1, 3);
      final calls = <String>[];
      network.handler = (_, uri, body) {
        if (uri.path.contains('getMyLearnedCoursePanelList')) {
          final form = Uri.splitQueryString(body);
          calls.add('school:${form['courseType']}');
          return json({
            'code': 0,
            'result': {
              'list': [
                moocSchoolPanel(1),
                moocSchoolPanel(2, mode: 0),
                moocSchoolPanel(
                  3,
                  start: old,
                  end: old.add(const Duration(days: 90)),
                ),
              ],
            },
          });
        }
        if (uri.path.contains('getMocTermDto')) {
          final term = Uri.splitQueryString(body)['termId'];
          calls.add('term:$term');
          return json({
            'code': 0,
            'result': {
              'id': int.parse(term!),
              'courseId': 1,
              'chapters': [],
              'exams': [],
            },
          });
        }
        calls.add('PUBLIC_FALLBACK');
        return SyntheticResponse('termId:9999999');
      };
      final service = MoocService(cookie: 'STUDY_SESS=x', csrfKey: 'x');
      await service.allHomework();
      expect(calls.where((v) => v.startsWith('term:')), ['term:1001']);
      expect(calls, isNot(contains('PUBLIC_FALLBACK')));
      expect(
        calls.where((v) => v.startsWith('school:')),
        everyElement('school:2'),
      );
      expect(service.listFailed, isFalse);
    },
  );

  test(
    'school and term nested names never become extra enrolled courses',
    () async {
      network.handler = (_, _, _) => json({
        'code': 0,
        'result': {
          'list': [moocSchoolPanel(1)],
        },
      });
      final courses = await MoocService(csrfKey: 'x').courses();
      expect(courses.map((c) => '${c.courseId}|${c.termId}'), ['1|1001']);
    },
  );

  test(
    'selected school course id takes precedence over a source-course reference',
    () async {
      final row = moocSchoolPanel(1)..['courseId'] = 999;
      network.handler = (_, _, _) => json({
        'code': 0,
        'result': [row],
      });
      expect((await MoocService(csrfKey: 'x').courses()).single.courseId, '1');
    },
  );

  test(
    'all official SPOC modes retain current-semester overdue work courses',
    () async {
      final now = DateTime.now();
      final semester = now.month >= 8
          ? DateTime(now.year, 8)
          : now.month == 1
          ? DateTime(now.year - 1, 8)
          : DateTime(now.year, 2);
      network.handler = (_, _, _) => json({
        'code': 0,
        'result': [
          for (final mode in [10, 15, 20])
            moocSchoolPanel(
              mode,
              mode: mode,
              start: semester,
              end: semester.add(const Duration(days: 5)),
            ),
        ],
      });
      expect(
        (await MoocService(csrfKey: 'x').courses()).map((c) => c.courseId),
        ['10', '15', '20'],
      );
    },
  );

  test(
    'filtered full page still fetches the next enrolled school page',
    () async {
      final pages = <int>[];
      network.handler = (_, _, body) {
        final page = int.parse(Uri.splitQueryString(body)['p']!);
        pages.add(page);
        return json({
          'code': 0,
          'result': {
            'list': page == 1
                ? [for (var i = 1; i <= 32; i++) moocSchoolPanel(i, mode: 0)]
                : [moocSchoolPanel(99)],
          },
        });
      };
      final courses = await MoocService(csrfKey: 'x').courses();
      expect(pages, [1, 2]);
      expect(courses.map((c) => c.courseId), ['99']);
    },
  );

  for (final field in ['id', 'startTime', 'endTime', 'mode']) {
    test(
      'missing school term $field cannot import or authorize cleanup',
      () async {
        final unknown = moocSchoolPanel(1);
        (unknown['termPanel'] as Map).remove(field);
        if (field == 'mode') unknown.remove('mode');
        network.handler = (_, _, _) => json({
          'code': 0,
          'result': [unknown],
        });
        final service = MoocService(csrfKey: 'x');
        expect(await service.courses(), isEmpty);
        expect(service.listFailed, isTrue);
      },
    );
  }
}
