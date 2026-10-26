import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:homework_radar/services/chaoxing_service.dart';
import 'package:homework_radar/services/yuketang_service.dart';

import 'support/synthetic_http.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final network = SyntheticHttp();
  setUpAll(() => HttpOverrides.global = network);
  tearDownAll(() => HttpOverrides.global = null);

  test(
    'YKT only official student role 5 is imported; role 6 is an auditor',
    () {
      final result = YuketangService.parseCourseList(
        jsonEncode({
          'errcode': 0,
          'data': {
            'list': [
              {'classroom_id': 1, 'role': 5, 'course_name': 'School class'},
              {'classroom_id': 2, 'role': 6, 'course_name': 'Auditing class'},
              {'classroom_id': 3, 'role': 1, 'course_name': 'Teaching class'},
            ],
          },
        }),
      );
      expect(result!.map((c) => c.classroomId), ['1']);
    },
  );

  test(
    'YKT auditors only cannot turn into student courses through fallback',
    () {
      expect(
        YuketangService.parseCourseList(
          '{"data":{"list":[{"classroom_id":1,"role":6},{"classroom_id":2,"role":1}]}}',
        ),
        isEmpty,
      );
    },
  );

  for (final rows in [
    [
      {'classroom_id': 7, 'role': 7},
    ],
    [
      {'classroom_id': 7},
    ],
    [
      {'classroom_id': 1, 'role': 5},
      {'classroom_id': 7, 'role': '5x'},
    ],
  ]) {
    test(
      'YKT unknown role cannot import or authorize cleanup: $rows',
      () async {
        network.handler = (_, _, _) => SyntheticResponse(
          jsonEncode({
            'data': {'list': rows},
          }),
        );
        final service = YuketangService(cookie: 'synthetic');
        expect(await service.allHomework(), isEmpty);
        expect(service.listFailed, isTrue);
      },
    );
  }

  for (final broken in [
    '<li class="course"><span class="course-name">Missing link</span></li>',
    '<li class="course"><a href="/course/2">Missing name</a></li>',
    '<li class="course"><a href=""><span class="course-name">Empty link</span></a></li>',
  ]) {
    test('CX incomplete course row is not a complete enrollment scan: $broken', () async {
      network.handler = (_, uri, _) {
        if (uri.path.endsWith('/courses/list')) {
          return SyntheticResponse(
            '<li class="course"><a href="/course/1"><span class="course-name">Known class</span></a></li>$broken',
          );
        }
        if (uri.path == '/course/1') {
          return SyntheticResponse(
            '<input id="courseid" value="1"><input id="clazzid" value="1"><input id="oldenc" value="x">',
          );
        }
        if (uri.path.contains('getAllWork')) {
          return SyntheticResponse(
            '<div class="ulDiv"><li><div class="titTxt"><a data="1">Current work</a></div></li></div>',
          );
        }
        return SyntheticResponse(
          '<html><title>考试列表</title><div class="task-list"><div class="has-content"><div class="null-data">暂无考试</div></div></div></html>',
        );
      };
      final service = ChaoxingService(cookie: 'synthetic');
      final result = await service.allHomework();
      expect(result.map((h) => h.title), contains('Current work'));
      expect(service.listFailed, isTrue);
      expect(service.failureDetails, isNotEmpty);
    });
  }
}
