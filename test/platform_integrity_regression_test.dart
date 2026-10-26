import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:homework_radar/models/homework.dart';
import 'package:homework_radar/services/chaoxing_service.dart';
import 'package:homework_radar/services/mooc_service.dart';
import 'package:homework_radar/services/safe_http.dart';
import 'package:homework_radar/services/xuetangx_service.dart';
import 'package:homework_radar/services/yuketang_service.dart';
import 'package:homework_radar/services/zhihuishu_service.dart';

import 'support/synthetic_http.dart';
import 'support/mooc_school_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final network = SyntheticHttp();
  setUpAll(() => HttpOverrides.global = network);
  tearDownAll(() => HttpOverrides.global = null);

  test(
    '15 activity count, not homework count, controls YKT pagination',
    () async {
      network.handler = (_, uri, _) {
        final page = int.parse(uri.queryParameters['page']!);
        return SyntheticResponse(
          jsonEncode({
            'activities': page == 0
                ? [
                    for (var n = 0; n < 199; n++) {'type': 14, 'id': n},
                    {'type': 5, 'id': 900, 'deadline': 1799765999000},
                  ]
                : [
                    {'type': 5, 'id': 901, 'deadline': 1799765999000},
                  ],
          }),
        );
      };
      final result = await YuketangService().homeworkOf(
        YktCourse('Course', '1'),
      );
      expect(result!.map((h) => h.id.split('_').last), ['900', '901']);
    },
  );

  test('16 a later XT course page failure invalidates completeness', () async {
    network.handler = (_, uri, _) => uri.queryParameters['page'] == '1'
        ? SyntheticResponse('{"data":{"list":[{"cid":1,"sign":"A"}]}}')
        : SyntheticResponse('unavailable', 503);
    final service = XuetangxService();
    expect(await service.courses(), hasLength(1));
    expect(service.listFailed, isTrue);
  });

  test(
    '17 one failed XT leaf cannot authorize deleting that old leaf',
    () async {
      network.handler = (_, uri, _) {
        if (uri.path.contains('/chapter')) {
          return SyntheticResponse(
            '{"data":{"leaf_list":['
            '{"id":1,"leaf_type":6},{"id":2,"leaf_type":6}]}}',
          );
        }
        if (uri.path.endsWith('/1/1/')) {
          return SyntheticResponse('{"data":{"deadline":1799765999000}}');
        }
        return SyntheticResponse('unavailable', 503);
      };
      final service = XuetangxService();
      final result = await service.homeworkOf(XtCourse('Course', '1', 'A'));
      expect(result, hasLength(1));
      expect(service.failedCount, greaterThan(0));
    },
  );

  test(
    '18 CX HTTP200 error HTML is failure, not an empty homework list',
    () async {
      network.handler = (_, uri, _) {
        if (uri.path.endsWith('/courses/list')) {
          return SyntheticResponse(
            '<li class="course"><a href="https://mooc1.chaoxing.com/course">'
            '<span class="course-name">Course</span></a></li>',
          );
        }
        if (uri.path == '/course') {
          return SyntheticResponse(
            '<input id="courseid" value="1">'
            '<input id="clazzid" value="2"><input id="enc" value="x">'
            '<input id="t" value="123">',
          );
        }
        if (uri.path.contains('getAllWork')) {
          return SyntheticResponse('<html><body>请先登录</body></html>');
        }
        return SyntheticResponse('<div class="bottomList"><ul></ul></div>');
      };
      final service = ChaoxingService(cookie: 'synthetic');
      await service.allHomework();
      expect(service.failedCount, greaterThan(0));
    },
  );

  test('19 partial invalid ZHS deadlines are an incomplete response', () {
    final result = ZhihuishuService.parseWorkListJson(
      jsonEncode({
        'code': 200,
        'data': [
          {'id': 1, 'title': 'Good', 'endTime': 1799765999000},
          {'id': 2, 'title': 'Unknown', 'endTime': 'unrecognized'},
        ],
      }),
      courseName: 'Course',
    );
    expect(result, isNull);
  });

  test('19 partial invalid YKT deadlines are an incomplete response', () {
    final result = YuketangService.parseLogActivities(
      jsonEncode({
        'activities': [
          {'id': 1, 'type': 5, 'deadline': 1799765999000},
          {'id': 2, 'type': 5, 'deadline': 'unrecognized'},
        ],
      }),
      courseName: 'Course',
    );
    expect(result, isNull);
  });

  test('20 ZHS retrieves homework after the full first 50 rows', () async {
    network.handler = (_, _, body) {
      final form = Uri.splitQueryString(body);
      final params = jsonDecode(
        ZhihuishuService.decryptSecret(form['secretStr']!, 0),
      ) as Map;
      final page = '${params['pageIndex']}';
      return SyntheticResponse(
        jsonEncode({
          'code': 200,
          'data': page == '1'
              ? [
                  for (var n = 0; n < 50; n++)
                    {'id': n, 'endTime': 1799765999000},
                ]
              : [
                  {'id': 50, 'endTime': 1799765999000},
                ],
        }),
      );
    };
    expect(
      await ZhihuishuService().homeworkOf(ZhsCourse('Course', '1')),
      hasLength(51),
    );
  });

  test('21 reaching XT pagination cap is incomplete', () async {
    network.handler = (_, uri, _) => SyntheticResponse(
      jsonEncode({
        'data': {
          'list': [
            {
              'cid':
                  '${uri.queryParameters['status']}-${uri.queryParameters['page']}',
              'sign': 'A',
            },
          ],
        },
      }),
    );
    final service = XuetangxService();
    await service.courses();
    expect(service.listFailed, isTrue);
  });

  test('21 reaching MOOC course cap is incomplete', () async {
    network.handler = (_, _, body) {
      final page = int.parse(Uri.splitQueryString(body)['p']!);
      return SyntheticResponse(
        jsonEncode({
          'result': [
            for (var n = 0; n < 32; n++) moocSchoolPanel(page * 32 + n),
          ],
        }),
      );
    };
    final service = MoocService(csrfKey: 'synthetic');
    expect(await service.courses(), hasLength(640));
    expect(service.listFailed, isTrue);
  });

  test('21 reaching ZHS course cap is incomplete', () async {
    network.handler = (_, _, body) {
      final params = jsonDecode(
        ZhihuishuService.decryptSecret(
          Uri.splitQueryString(body)['secretStr']!,
          0,
        ),
      ) as Map;
      final page = int.parse('${params['pageIndex']}');
      return SyntheticResponse(
        jsonEncode({
          'code': 200,
          'data': [
            for (var n = 0; n < 20; n++)
              {'name': 'Course', 'courseId': page * 20 + n},
          ],
        }),
      );
    };
    final service = ZhihuishuService();
    expect(await service.courses(), hasLength(600));
    expect(service.listFailed, isTrue);
  });

  test('21 reaching YKT activity cap is incomplete', () async {
    network.handler = (_, uri, _) {
      final page = int.parse(uri.queryParameters['page']!);
      return SyntheticResponse(
        jsonEncode({
          'activities': [
            for (var n = 0; n < 200; n++)
              {'id': page * 200 + n, 'type': 5, 'deadline': 1799765999000},
          ],
        }),
      );
    };
    final service = YuketangService();
    expect(await service.homeworkOf(YktCourse('Course', '1')), hasLength(4000));
    expect(service.failedCount, greaterThan(0));
  });

  test('21 reaching CX fixed course cap is incomplete', () async {
    network.handler = (_, _, _) =>
        SyntheticResponse(List.filled(500, '<li class="course"></li>').join());
    final service = ChaoxingService();
    await service.allHomework();
    expect(service.listFailed, isTrue);
  });

  test('21 repeated full ZHS pages are not proof of completeness', () async {
    network.handler = (_, _, _) => SyntheticResponse(
      jsonEncode({
        'code': 200,
        'data': [
          for (var n = 0; n < 20; n++) {'name': 'Course', 'courseId': n},
        ],
      }),
    );
    final service = ZhihuishuService();
    expect(await service.courses(), hasLength(20));
    expect(service.listFailed, isTrue);
  });

  test('21 repeated XT pages are not proof of completeness', () async {
    network.handler = (_, _, _) =>
        SyntheticResponse('{"data":{"list":[{"cid":1,"sign":"A"}]}}');
    final service = XuetangxService();
    expect(await service.courses(), hasLength(1));
    expect(service.listFailed, isTrue);
  });

  test(
    '16 MOOC HTTP200 business rejection on a later page is incomplete',
    () async {
      network.handler = (_, _, body) => Uri.splitQueryString(body)['p'] == '1'
          ? SyntheticResponse(
              jsonEncode({
                'code': 200,
                'result': [for (var n = 0; n < 32; n++) moocSchoolPanel(n + 1)],
              }),
            )
          : SyntheticResponse('{"code":500,"message":"Unavailable"}');
      final service = MoocService(csrfKey: 'synthetic');
      expect(await service.courses(), hasLength(32));
      expect(service.listFailed, isTrue);
    },
  );

  test(
    '20 a failing later ZHS homework page cannot authorize cleanup',
    () async {
      network.handler = (_, _, body) {
        final params = jsonDecode(
          ZhihuishuService.decryptSecret(
            Uri.splitQueryString(body)['secretStr']!,
            0,
          ),
        ) as Map;
        return '${params['pageIndex']}' == '1'
            ? SyntheticResponse(
                jsonEncode({
                  'code': 200,
                  'data': [
                    for (var n = 0; n < 50; n++)
                      {'id': n, 'endTime': 1799765999000},
                  ],
                }),
              )
            : SyntheticResponse('Unavailable', 503);
      };
      expect(
        await ZhihuishuService().homeworkOf(ZhsCourse('Course', '1')),
        isNull,
      );
    },
  );

  test('22 MOOC final exam cursor never skips or overruns the input', () async {
    network.handler = (_, _, _) => SyntheticResponse(
      's0.contentType=2;s0.contentId=1;s0.name="Work";'
      's0.endTime=1799765999000;prefix examId=123;',
    );
    final result = await MoocService(csrfKey: 'x')
        .homeworkOf(MoocCourse('Course', '1', '2'));
    expect(
      result!.where((h) => h.title.startsWith('考试') || h.id.endsWith('考试123')),
      hasLength(1),
    );
  });

  test('23 cached MOOC CSRF cookie is not proof of a live session', () async {
    network.handler = (_, _, _) =>
        SyntheticResponse('{"code":401,"message":"登录失效"}', 401);
    final service = MoocService(
      cookie: 'STUDY_SESS=expired; NTESSTUDYSI=cached',
      csrfKey: 'cached',
    );
    expect(await service.checkLogin(), isFalse);
  });

  test(
    '24 YKT pro session is tried after the main origin rejects it',
    () async {
      network.handler = (_, uri, _) => uri.host.startsWith('www.')
          ? SyntheticResponse('Unauthorized', 401)
          : SyntheticResponse('{"list":[]}');
      expect(
        await YuketangService(cookie: 'synthetic').checkLogin(),
        YktSessionState.ok,
      );
    },
  );

  for (final platform in ['mooc', 'xt', 'ykt', 'zhs']) {
    test(
      '16 $platform failed in-flight session probe stays incomplete',
      () async {
        network.handler = (_, _, _) => SyntheticResponse('Unavailable', 503);
        final dynamic service = switch (platform) {
          'mooc' => MoocService(
            cookie: 'STUDY_SESS=synthetic',
            csrfKey: 'synthetic',
          ),
          'xt' => XuetangxService(cookie: 'synthetic'),
          'ykt' => YuketangService(cookie: 'synthetic'),
          _ => ZhihuishuService(cookie: 'synthetic'),
        };
        expect(await service.allHomework(), isEmpty);
        expect(service.listFailed, isTrue);
      },
    );
  }

  test('25 unfinished and incomplete are not completed ZHS work', () {
    final items = ZhihuishuService.parseWorkListJson(
      jsonEncode({
        'code': 200,
        'data': [
          {'id': 1, 'endTime': 1799765999000, 'status': 'unfinished'},
          {'id': 2, 'endTime': 1799765999000, 'status': 'incomplete'},
        ],
      }),
      courseName: 'Course',
    );
    expect(items!.map((h) => h.status), [HwStatus.todo, HwStatus.todo]);
  });

  test('26 ZHS source identity survives a course rename', () {
    const body = '{"code":200,"data":[{"id":8,"endTime":1799765999000}]}';
    final a = ZhihuishuService.parseWorkListJson(
      body,
      courseName: 'Old',
      courseId: '17',
    )!.single;
    final b = ZhihuishuService.parseWorkListJson(
      body,
      courseName: 'New',
      courseId: '17',
    )!.single;
    expect(a.sourceKey, 'zhs|17|work|8');
    expect(b.sourceKey, a.sourceKey);
  });

  test('26 YKT source identity includes the classroom instead of its name', () {
    const body = '{"activities":[{"id":8,"type":5,"deadline":1799765999000}]}';
    final item = YuketangService.parseLogActivities(
      body,
      courseName: 'Renamed',
      classroomId: '17',
    )!.single;
    expect(item.sourceKey, 'ykt|17|5|8');
  });

  test('26 XT source identity comes from classroom sign and leaf', () async {
    network.handler = (_, uri, _) => SyntheticResponse(
      uri.path.contains('/chapter')
          ? '{"data":{"leaf_list":[{"id":8,"leaf_type":6}]}}'
          : '{"data":{"deadline":1799765999000}}',
    );
    final item = (await XuetangxService().homeworkOf(
      XtCourse('Renamed', '17', 'SIGN'),
    ))!.single;
    expect(item.sourceKey, 'xtx|17|SIGN|leaf|8');
  });

  test('26 MOOC source identity includes the real course and term', () async {
    network.handler = (_, _, _) => SyntheticResponse(
      's0.contentType=2;s0.contentId=8;'
      's0.name="Work";s0.endTime=1799765999000;',
    );
    final item = (await MoocService(
      csrfKey: 'synthetic',
    ).homeworkOf(MoocCourse('Renamed', '17', '21')))!.single;
    expect(item.sourceKey, 'mooc|17|21|2|8');
  });

  test('26 CX exam source identity includes class and actual exam id', () {
    final item = ChaoxingService.parseExamListHtml(
      '<li data="examId=8">'
      '<h3>Exam</h3><p>2026-10-20 12:00</p></li>',
      courseName: 'Renamed',
      courseId: '17',
      clazzId: '21',
    ).single;
    expect(item.sourceKey, 'cx|17|21|exam|8');
  });

  testWidgets('40 response headers are included in the overall HTTP timeout', (
    tester,
  ) async {
    network.handler = (_, _, _) => Completer<SyntheticResponse>().future;
    var completed = false;
    unawaited(
      SafeHttp.get('https://www.icourse163.org/stalled')
          .then((_) => completed = true),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 31));
    expect(completed, isTrue);
  });

  for (final method in ['form', 'json']) {
    testWidgets('40 $method response headers have the same deadline', (
      tester,
    ) async {
      network.handler = (_, _, _) => Completer<SyntheticResponse>().future;
      var completed = false;
      final request = method == 'form'
          ? SafeHttp.postForm('https://www.icourse163.org/stalled')
          : SafeHttp.postJson('https://www.icourse163.org/stalled');
      unawaited(request.then((_) => completed = true));
      await tester.pump();
      await tester.pump(const Duration(seconds: 31));
      expect(completed, isTrue);
    });
  }
}
