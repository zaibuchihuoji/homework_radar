import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:homework_radar/services/mooc_service.dart';
import 'package:homework_radar/services/xuetangx_service.dart';

import 'support/synthetic_http.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final network = SyntheticHttp();
  setUpAll(() => HttpOverrides.global = network);
  tearDownAll(() => HttpOverrides.global = null);

  group('proven MOOC RPC contract', () {
    for (final entry in [
      ('{"code":1}', false),
      ('{"code":2}', null),
      ('{"code":0,"result":{}}', null),
    ]) {
      test('official login envelope ${entry.$1}', () async {
        network.handler = (_, _, _) => SyntheticResponse(entry.$1);
        expect(
          await MoocService(
            cookie: 'STUDY_SESS=synthetic',
            csrfKey: 'x',
          ).checkLogin(),
          entry.$2,
        );
      });
    }
    test('second live response hierarchy includes all 36 tests and one deduplicated final exam', () async {
      final body = File('test/fixtures/mooc_public_assessments.json')
          .readAsStringSync();
      final payload = jsonDecode(body)['result'];
      network.handler = (_, _, _) => SyntheticResponse(body);
      final result = await MoocService(csrfKey: 'x').homeworkOf(
        MoocCourse('Course', '${payload['courseId']}', '${payload['id']}'),
      );
      expect(result, hasLength(37));
      expect(result!.where((h) => h.sourceKey!.contains('|4|')), hasLength(10));
      expect(result.where((h) => h.sourceKey!.contains('|2|')), hasLength(26));
      expect(
        result.where((h) => h.sourceKey!.contains('|exam|')),
        hasLength(1),
      );
    });
    late Map<String, dynamic> fixture;
    test(
      'session expiration after public term fetch cannot authorize cleanup',
      () async {
        var probes = 0;
        network.handler = (_, uri, body) {
          if (uri.path.contains('getMyLearnedCoursePanelList')) {
            if (Uri.splitQueryString(body)['psize'] == '1' && ++probes > 1) {
              return SyntheticResponse('{"code":401}', 401);
            }
            return SyntheticResponse(
              '{"code":0,"result":[{"courseId":1,"termId":2,"name":"Course"}]}',
            );
          }
          return SyntheticResponse(jsonEncode(fixture));
        };
        final service = MoocService(
          cookie: 'STUDY_SESS=synthetic',
          csrfKey: 'synthetic',
        );
        expect(await service.allHomework(), hasLength(1));
        expect(service.listFailed, isTrue);
        expect(service.loginFailed, isTrue);
      },
    );
    setUp(() {
      fixture = jsonDecode(
        File('test/fixtures/mooc_public_term.json').readAsStringSync(),
      ) as Map<String, dynamic>;
      network.handler = (_, uri, body) {
        if (uri.path.endsWith('.dwr')) {
          return SyntheticResponse('unavailable', 503);
        }
        final form = Uri.splitQueryString(body);
        expect(form, {
          'termId': '2',
          'isDraft': '0',
          'excludeUnrelease': 'false',
        });
        return SyntheticResponse(jsonEncode(fixture), 200, {
          'content-type': 'application/json; charset=utf-8',
        });
      };
    });
    test(
      'real response shape yields chapter homework and its own deadline',
      () async {
        final items = await MoocService(csrfKey: 'synthetic')
            .homeworkOf(MoocCourse('Course', '1', '2'));
        expect(items, hasLength(1));
        expect(items!.single.title, 'Homework');
        expect(
          items.single.dueAt,
          DateTime.fromMillisecondsSinceEpoch(1799765999000),
        );
        expect(items.single.sourceKey, 'mooc|1|2|4|8');
      },
    );
    test('wrong term identity cannot authorize cleanup', () async {
      fixture['result']['id'] = 3;
      expect(
        await MoocService(csrfKey: 'x')
            .homeworkOf(MoocCourse('Course', '1', '2')),
        isNull,
      );
    });
    test(
      'partly malformed assessment prevents authoritative cleanup',
      () async {
        fixture['result']['chapters'][0]['homeworks'].add({
          'test': {'id': 9, 'name': 'Broken', 'deadline': 'invalid'},
        });
        expect(
          await MoocService(csrfKey: 'x')
              .homeworkOf(MoocCourse('Course', '1', '2')),
          isNull,
        );
      },
    );
    test('normal empty recognized term remains valid', () async {
      fixture['result']['chapters'] = [];
      expect(
        await MoocService(csrfKey: 'x')
            .homeworkOf(MoocCourse('Course', '1', '2')),
        isEmpty,
      );
    });
    test('empty preview without the assessment lists is incomplete', () async {
      fixture['result'].remove('exams');
      expect(
        await MoocService(csrfKey: 'x')
            .homeworkOf(MoocCourse('Course', '1', '2')),
        isNull,
      );
    });
  });

  group('official XT leaf types and deadlines', () {
    test(
      'official chapter layout can place an exam directly in section_leaf_list',
      () {
        final scan = XuetangxService.parseChapterScan(
          '{"data":{"course_chapter":[{"section_leaf_list":[{"id":8,"leaf_type":5,"name":"Exam"},{"leaf_list":[{"id":9,"leaf_type":0}]}]}]}}',
        );
        expect(scan!.examLeaves.map((e) => e.id), ['8']);
      },
    );
    test(
      'exam detail uses exam cover, not the homework exercise endpoint',
      () async {
        network.handler = (_, uri, _) {
          if (uri.path.endsWith('/chapter')) {
            return SyntheticResponse(
              '{"data":{"leaf_list":[{"id":8,"leaf_type":5,"name":"Exam"}]}}',
            );
          }
          if (uri.path.contains('/leaf_info/')) {
            return SyntheticResponse(
              '{"data":{"content_info":{"leaf_type_id":99}}}',
            );
          }
          expect(uri.path, '/api/v1/lms/exam/cover');
          expect(uri.queryParameters['exam_id'], '99');
          return SyntheticResponse(
            '{"errcode":0,"data":{"deadline":1799765999000}}',
          );
        };
        expect(
          await XuetangxService().homeworkOf(XtCourse('Course', '1', 'A')),
          hasLength(1),
        );
      },
    );
    test(
      'explicit exam error envelope cannot expose a bogus deadline',
      () async {
        network.handler = (_, uri, _) {
          if (uri.path.endsWith('/chapter')) {
            return SyntheticResponse(
              '{"data":{"leaf_list":[{"id":8,"leaf_type":5}]}}',
            );
          }
          if (uri.path.contains('/leaf_info/')) {
            return SyntheticResponse(
              '{"data":{"content_info":{"leaf_type_id":99}}}',
            );
          }
          return SyntheticResponse(
            '{"errcode":1,"data":{"deadline":1799765999000}}',
          );
        };
        expect(
          await XuetangxService().homeworkOf(XtCourse('Course', '1', 'A')),
          isNull,
        );
      },
    );
    test('exam type is 5 rather than the guessed 7', () {
      final scan = XuetangxService.parseChapterScan(
        '{"success":true,"data":{"leaf_list":[{"leaf_type":5,"id":8,"name":"Exam","score_deadline":1799765999000}]}}',
      );
      expect(scan, isNotNull);
      expect(scan!.examLeaves.map((e) => e.id), ['8']);
    });
    test(
      'chapter deadline remains usable if the detail request is unavailable',
      () async {
        network.handler = (_, uri, _) => uri.path.endsWith('/chapter')
            ? SyntheticResponse(
                '{"success":true,"data":{"leaf_list":[{"leaf_type":6,"id":8,"name":"Work","score_deadline":1799765999000}]}}',
              )
            : SyntheticResponse('unavailable', 503);
        final service = XuetangxService();
        final items = await service.homeworkOf(XtCourse('Course', '1', 'A'));
        expect(items, hasLength(1));
        expect(
          items!.single.dueAt,
          DateTime.fromMillisecondsSinceEpoch(1799765999000),
        );
        expect(service.failedCount, 0);
      },
    );
    test(
      'an explicit no-deadline exercise is retained, not silently skipped',
      () async {
        network.handler = (_, uri, _) => uri.path.endsWith('/chapter')
            ? SyntheticResponse(
                '{"success":true,"data":{"leaf_list":[{"leaf_type":6,"id":8,"score_deadline":0}]}}',
              )
            : SyntheticResponse('unavailable', 503);
        final service = XuetangxService();
        final items = await service.homeworkOf(XtCourse('Course', '1', 'A'));
        expect(items, hasLength(1));
        expect(items!.single.dueAt, isNull);
        expect(service.failedCount, 0);
      },
    );
    test('unrecognized type cannot authorize dropping old assessments', () {
      expect(
        XuetangxService.parseChapterScan(
          '{"data":{"leaf_list":[{"leaf_type":7,"id":8}]}}',
        ),
        isNull,
      );
    });
  });
}
