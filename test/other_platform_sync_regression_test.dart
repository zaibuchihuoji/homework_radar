import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:homework_radar/models/homework.dart';
import 'package:homework_radar/services/mooc_service.dart';
import 'package:homework_radar/services/sync_service.dart';
import 'package:homework_radar/services/xuetangx_service.dart';
import 'package:homework_radar/services/yuketang_service.dart';
import 'package:homework_radar/services/zhihuishu_service.dart';

import 'support/synthetic_http.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final network = SyntheticHttp();
  setUpAll(() => HttpOverrides.global = network);
  tearDownAll(() => HttpOverrides.global = null);

  // A second healthy course makes incoming nonempty: the merge must still
  // preserve the old record belonging to the failed/unknown course.
  void expectOldRetained(PlatformKind platform, bool complete) {
    final old = HomeworkItem(
      id: 'old',
      platform: platform,
      course: 'Old course',
      title: 'Old work',
      sourceKey: '${platform.name}|old',
    );
    final merged = {old.id: old};
    mergePlatform(
      merged,
      [
        HomeworkItem(
          id: 'fresh',
          platform: platform,
          course: 'Healthy course',
          title: 'New work',
        ),
      ],
      platform,
      complete: complete,
    );
    expect(merged.keys, containsAll(['old', 'fresh']));
  }

  group('MOOC', () {
    test(
      'unparsed RPC JSON can still fall back to a valid DWR result',
      () async {
        network.handler = (_, uri, _) => uri.path.endsWith('.rpc')
            ? SyntheticResponse('{"code":0,"result":{"mocTermDto":{}}}')
            : SyntheticResponse(
                's0.contentType=4;s0.contentId=8;s0.name="Work";',
              );
        expect(
          await MoocService(csrfKey: 'x')
              .homeworkOf(MoocCourse('Course', '1', '2')),
          hasLength(1),
        );
      },
    );
    for (final body in [
      '<html><script>contentType=1;</script>Unavailable</html>',
      "s0.contentType=1;dwr.engine._remoteHandleException('0','0',{});",
    ]) {
      test(
        'DWR error page with assignment markers is rejected: $body',
        () async {
          network.handler = (_, _, _) => SyntheticResponse(body);
          expect(
            await MoocService(csrfKey: 'x')
                .homeworkOf(MoocCourse('Course', '1', '2')),
            isNull,
          );
        },
      );
    }
    for (final status in [429, 500, 503]) {
      test('HTTP $status is incomplete, not an expired session', () async {
        network.handler = (_, _, _) => SyntheticResponse('unavailable', status);
        final service = MoocService(
          cookie: 'NTESSTUDYSI=synthetic',
          csrfKey: 'x',
        );
        await service.courses();
        expect(service.listFailed, isTrue);
        expect(service.loginFailed, isFalse);
      });
    }
    test('explicit HTTP 401 still expires the session', () async {
      network.handler = (_, _, _) => SyntheticResponse('denied', 401);
      final service = MoocService(
        cookie: 'NTESSTUDYSI=synthetic',
        csrfKey: 'x',
      );
      await service.courses();
      expect(service.loginFailed, isTrue);
    });
    for (final body in ['{}', '{"code":0,"result":{"message":"unknown"}}']) {
      test('unknown course shape cannot authorize cleanup: $body', () async {
        network.handler = (_, _, _) => SyntheticResponse(body);
        final service = MoocService(csrfKey: 'x');
        await service.courses();
        expect(service.listFailed, isTrue);
        expectOldRetained(PlatformKind.mooc, !service.listFailed);
      });
    }
    test('recognized empty course list stays valid', () async {
      network.handler = (_, _, _) =>
          SyntheticResponse('{"code":0,"result":[]}');
      final service = MoocService(csrfKey: 'x');
      expect(await service.courses(), isEmpty);
      expect(service.listFailed, isFalse);
    });
    test('unsupported RPC JSON is not silently parsed as empty DWR', () async {
      network.handler = (_, uri, _) => uri.path.endsWith('.rpc')
          ? SyntheticResponse(
              '{"code":0,"result":{"mocTermDto":{"units":[{"contentType":4,"contentId":8}]}}}',
            )
          : SyntheticResponse('unavailable', 503);
      expect(
        await MoocService(csrfKey: 'x')
            .homeworkOf(MoocCourse('Course', '1', '2')),
        isNull,
      );
    });
    test('a rejected DWR response with markers is still failure', () async {
      network.handler = (_, uri, _) => uri.path.endsWith('.rpc')
          ? SyntheticResponse('{}')
          : SyntheticResponse('s0.contentType=4;s0.contentId=8;', 503);
      expect(
        await MoocService(csrfKey: 'x')
            .homeworkOf(MoocCourse('Course', '1', '2')),
        isNull,
      );
    });
    test('a valid video-only DWR term has no homework', () async {
      network.handler = (_, uri, _) => uri.path.endsWith('.rpc')
          ? SyntheticResponse('{}')
          : SyntheticResponse('s0.contentType=1;s0.contentId=8;');
      expect(
        await MoocService(csrfKey: 'x')
            .homeworkOf(MoocCourse('Course', '1', '2')),
        isEmpty,
      );
    });
  });

  group('Xuetangx', () {
    for (final status in [401, 403]) {
      test('explicit HTTP $status still expires the session', () async {
        network.handler = (_, _, _) => SyntheticResponse('denied', status);
        expect(
          await XuetangxService(cookie: 'synthetic').checkLogin(),
          XtSessionState.expired,
        );
      });
    }
    test('unrelated metadata arrays do not invalidate a known course list', () {
      expect(
        XuetangxService.parseCourseListJson(
          '{"success":true,"data":{"tags":["metadata"],"product_list":[{"id":1,"products_sign":"A"}]}}',
        ),
        hasLength(1),
      );
    });
    test('partly malformed courses cannot be treated as a complete list', () {
      expect(
        XuetangxService.parseCourseListJson(
          '{"data":{"product_list":[{"id":1,"products_sign":"A"},{"products_sign":"B"}]}}',
        ),
        isNull,
      );
    });
    test('metadata-only empty array is not a course list', () {
      expect(
        XuetangxService.parseCourseListJson('{"data":{"tags":[]}}'),
        isNull,
      );
    });
    test('unknown HTTP200 page keeps session status unknown', () async {
      network.handler = (_, _, _) =>
          SyntheticResponse('<html>unavailable</html>');
      expect(
        await XuetangxService(cookie: 'synthetic').checkLogin(),
        XtSessionState.unknown,
      );
    });
    for (final body in [
      '{"success":true,"data":{"course_chapter":[]}}',
      '{"data":{"course_chapter":[{"section_leaf_list":[{"leaf_list":[]}]}]}}',
    ]) {
      test(
        'recognized empty chapter tree does not report partial sync: $body',
        () async {
          network.handler = (_, _, _) => SyntheticResponse(body);
          final service = XuetangxService();
          expect(
            await service.homeworkOf(XtCourse('Course', '1', 'A')),
            isEmpty,
          );
          expect(service.failedCount, 0);
        },
      );
    }
    for (final body in [
      '{"code":401,"data":{"list":[]}}',
      '{"success":false,"data":{"product_list":[]}}',
    ]) {
      test('explicit rejection beats a data key: $body', () {
        expect(XuetangxService.envelopeOk(body), isFalse);
        expect(XuetangxService.parseCourseListJson(body), isNull);
      });
    }
    test('error chapter envelope is not authoritative empty content', () {
      expect(
        XuetangxService.parseChapterScan(
          '{"success":false,"data":{"leaf_list":[{"leaf_type":0,"id":1}]}}',
        ),
        isNull,
      );
    });
    test(
      'one malformed work leaf cannot authorize deleting the old work',
      () async {
        network.handler = (_, _, _) => SyntheticResponse(
          '{"data":{"leaf_list":[{"leaf_type":0,"id":1},{"leaf_type":6}]}}',
        );
        final service = XuetangxService();
        final result = await service.homeworkOf(XtCourse('Course', '1', 'A'));
        expect(result, isNull);
        expectOldRetained(
          PlatformKind.xuetangx,
          result != null && service.failedCount == 0,
        );
      },
    );
    test('nonempty malformed course list is not an empty course list', () {
      expect(
        XuetangxService.parseCourseListJson(
          '{"data":{"product_list":[{"id":1}]}}',
        ),
        isNull,
      );
    });
  });

  group('Yuketang', () {
    for (final status in [401, 403]) {
      test(
        'explicit HTTP $status on both origins still expires the session',
        () async {
          network.handler = (_, _, _) => SyntheticResponse('denied', status);
          expect(
            await YuketangService(cookie: 'synthetic').checkLogin(),
            YktSessionState.expired,
          );
        },
      );
    }
    test('unknown HTTP200 pages keep session status unknown', () async {
      network.handler = (_, _, _) =>
          SyntheticResponse('<html>unavailable</html>');
      expect(
        await YuketangService(cookie: 'synthetic').checkLogin(),
        YktSessionState.unknown,
      );
    });
    test(
      'an explicit last page avoids requesting a spurious extra page',
      () async {
        var requests = 0;
        network.handler = (_, _, _) {
          requests++;
          if (requests > 1) return SyntheticResponse('unavailable', 503);
          return SyntheticResponse(
            jsonEncode({
              'errcode': 0,
              'data': {
                'activities': [
                  for (var i = 0; i < 200; i++) {'type': 14, 'id': i},
                ],
                'has_more': false,
              },
            }),
          );
        };
        expect(
          await YuketangService().homeworkOf(YktCourse('Course', '1')),
          isEmpty,
        );
        expect(requests, 1);
      },
    );
    test(
      'main-origin network failure followed by working pro is complete',
      () async {
        network.handler = (_, uri, _) {
          if (uri.host.startsWith('www.')) {
            throw const SocketException('synthetic offline');
          }
          return SyntheticResponse('{"errcode":0,"data":{"list":[]}}');
        };
        final service = YuketangService();
        expect(await service.courses(), isEmpty);
        expect(service.listFailed, isFalse);
      },
    );
    test('explicit has_more overrides a short activity page', () async {
      network.handler = (_, uri, _) => SyntheticResponse(
        jsonEncode({
          'errcode': 0,
          'data': {
            'activities': uri.queryParameters['page'] == '0'
                ? [
                    {'type': 14, 'id': 1},
                  ]
                : [
                    {'type': 5, 'id': 2, 'deadline': 1799765999000},
                  ],
            'has_more': uri.queryParameters['page'] == '0',
          },
        }),
      );
      final service = YuketangService();
      expect(await service.homeworkOf(YktCourse('Course', '1')), hasLength(1));
      expect(service.failedCount, 0);
    });
    test(
      'only teaching activities are a valid empty homework result',
      () async {
        network.handler = (_, _, _) => SyntheticResponse(
          '{"errcode":0,"data":{"activities":[{"type":14,"id":1}],"has_more":false}}',
        );
        final service = YuketangService();
        expect(await service.homeworkOf(YktCourse('Course', '1')), isEmpty);
        expect(service.failedCount, 0);
      },
    );
    test('errcode failure with list shape is rejected', () {
      const body = '{"errcode":1,"data":{"list":[]}}';
      expect(YuketangService.courseListOk(body), isFalse);
      expect(YuketangService.parseCourseList(body), isNull);
    });
    for (final body in [
      '{"errcode":1,"data":{"activities":[]}}',
      '{"data":{"activities":[null]}}',
      '{"data":{"activities":[{"id":1}]}}',
    ]) {
      test('invalid activity feed is not empty homework: $body', () {
        expect(
          YuketangService.parseLogActivities(body, courseName: 'Course'),
          isNull,
        );
      });
    }
    test('partly malformed course list cannot authorize cleanup', () async {
      network.handler = (_, _, _) => SyntheticResponse(
        '{"errcode":0,"data":{"list":[{"role":5,"classroom_id":1},{"role":5}]}}',
      );
      final service = YuketangService();
      await service.courses();
      expect(service.listFailed, isTrue);
      expectOldRetained(PlatformKind.yuketang, !service.listFailed);
    });
  });

  group('Zhihuishu', () {
    test('partly malformed course page cannot authorize cleanup', () {
      expect(
        ZhihuishuService.parseCourseListJson(
          '{"code":200,"result":{"courseOpenDtos":[{"courseOpenId":1,"name":"Good"},{"courseOpenId":2}]}}',
        ),
        isNull,
      );
    });
    test('unique nonempty alternate work array remains supported', () {
      expect(
        ZhihuishuService.parseWorkListJson(
          '{"code":200,"result":{"tags":[],"alternateWorks":[{"id":1,"endTime":1799765999000}]}}',
          courseName: 'Course',
        ),
        hasLength(1),
      );
    });
    for (final field in ['list', 'records', 'rows']) {
      test('metadata array cannot hide $field work', () {
        final parsed = ZhihuishuService.parseWorkListJson(
          jsonEncode({
            'code': 200,
            'result': {
              'tags': [],
              field: [
                {'id': 1, 'endTime': 1799765999000},
              ],
            },
          }),
          courseName: 'Course',
        );
        expect(parsed, hasLength(1));
      });
    }
    test('unknown empty metadata alone is not a homework response', () {
      expect(
        ZhihuishuService.parseWorkListJson(
          '{"code":200,"result":{"tags":[]}}',
          courseName: 'Course',
        ),
        isNull,
      );
    });
    test('malformed recognized list cannot fall through to metadata', () {
      expect(
        ZhihuishuService.parseWorkListJson(
          '{"code":200,"result":{"list":"unknown","tags":[]}}',
          courseName: 'Course',
        ),
        isNull,
      );
    });
    test('recognized empty homework list remains valid', () {
      expect(
        ZhihuishuService.parseWorkListJson(
          '{"code":200,"result":{"list":[]}}',
          courseName: 'Course',
        ),
        isEmpty,
      );
    });
    test(
      'ambiguous course payload is not proof of an empty course list',
      () async {
        network.handler = (_, _, _) =>
            SyntheticResponse('{"code":200,"result":{"message":"unknown"}}');
        final service = ZhihuishuService();
        await service.courses();
        expect(service.listFailed, isTrue);
        expectOldRetained(PlatformKind.zhihuishu, !service.listFailed);
      },
    );
  });
}
