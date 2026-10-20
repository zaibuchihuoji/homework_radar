import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:homework_radar/models/homework.dart';
import 'package:homework_radar/services/secure_store.dart';
import 'package:homework_radar/services/storage.dart';
import 'package:homework_radar/services/sync_service.dart';
import 'package:homework_radar/services/sync_policy.dart';
import 'package:homework_radar/services/zhihuishu_service.dart';

import 'support/synthetic_http.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  AndroidFlutterLocalNotificationsPlugin.registerWith();
  final network = SyntheticHttp();
  final secrets = <String, String>{};
  setUpAll(() => HttpOverrides.global = network);
  tearDownAll(() => HttpOverrides.global = null);
  setUp(() async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('homework_radar/platform'),
      (call) async {
        final args = call.arguments as Map?;
        if (call.method == 'secureRead') return secrets[args?['key']];
        if (call.method == 'secureWrite') {
          secrets[args?['key']] = args?['value'];
        }
        if (call.method == 'secureDelete') secrets.remove(args?['key']);
        return true;
      },
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('dexterous.com/flutter/local_notifications'),
      (_) async => true,
    );
    for (final key in [
      'cx_cookie',
      'cx_uid',
      'mooc_cookie',
      'mooc_csrf',
      'zhs_cookie',
      'xtx_cookie',
      'ykt_cookie',
      'zf_cookie',
    ]) {
      await SecureStore.delete(key);
    }
    SharedPreferences.setMockInitialValues({});
    await Storage.init();
  });

  SyntheticResponse json(Object value) => SyntheticResponse(
    jsonEncode(value),
    200,
    {'content-type': 'application/json; charset=utf-8'},
  );

  test(
    'confirmed expiry during fetch pauses retry and retains existing work',
    () async {
      var probes = 0;
      network.handler = (_, uri, body) {
        if (uri.path.contains('getMyLearnedCoursePanelList')) {
          probes++;
          return probes == 1
              ? json({
                  'code': 0,
                  'result': [
                    {'courseId': 1, 'termId': 1, 'name': 'Existing'},
                  ],
                })
              : json({'code': 1});
        }
        return json({'code': 1});
      };
      await Storage.saveMooc(cookie: 'STUDY_SESS=synthetic', csrf: 'synthetic');
      await Storage.saveHomework([
        HomeworkItem(
          id: 'old-auth',
          platform: PlatformKind.mooc,
          course: 'Existing',
          title: 'Keep me',
          note: 'Keep note',
        ),
      ]);
      final result = await SyncService.run(platforms: {PlatformKind.mooc});
      expect(result.outcomes[PlatformKind.mooc], SyncOutcome.loginExpired);
      expect(Storage.syncStatuses()[PlatformKind.mooc]!.paused, true);
      expect(Storage.syncStatuses()[PlatformKind.mooc]!.nextRetry, isNull);
      expect(Storage.homework().single.note, 'Keep note');
    },
  );

  for (final platform in [
    PlatformKind.mooc,
    PlatformKind.xuetangx,
    PlatformKind.yuketang,
    PlatformKind.zhihuishu,
  ]) {
    if (platform != PlatformKind.mooc) {
      test(
        '${platform.name}: expiry in the second session probe pauses retry',
        () async {
          var probes = 0;
          network.handler = (_, uri, body) {
            probes++;
            if (probes > 1) return SyntheticResponse('{}', 401);
            return switch (platform) {
              PlatformKind.xuetangx => json({
                'success': true,
                'data': {'product_list': []},
              }),
              PlatformKind.yuketang => json({
                'errcode': 0,
                'data': {'list': []},
              }),
              _ => json({
                'code': 200,
                'result': {'courseOpenDtos': []},
              }),
            };
          };
          switch (platform) {
            case PlatformKind.xuetangx:
              await Storage.saveXuetangx(cookie: 'synthetic');
            case PlatformKind.yuketang:
              await Storage.saveYuketang(cookie: 'synthetic');
            default:
              await Storage.saveZhihuishu(cookie: 'synthetic');
          }
          await Storage.saveHomework([
            HomeworkItem(
              id: 'keep-${platform.name}',
              platform: platform,
              course: 'Old',
              title: 'Old',
              note: 'Keep note',
            ),
          ]);
          final result = await SyncService.run(platforms: {platform});
          expect(result.outcomes[platform], SyncOutcome.loginExpired);
          expect(Storage.syncStatuses()[platform]!.paused, true);
          expect(Storage.homework().single.note, 'Keep note');
        },
      );
    }
    for (final failed in [false, true]) {
      test(
        '${platform.name}: ${failed ? "failed second course retains old work and reports partial" : "healthy course plus normal empty course completes without warning"}',
        () async {
          network.handler = (_, uri, body) {
            switch (platform) {
              case PlatformKind.mooc:
                if (uri.path.contains('getMyLearnedCoursePanelList')) {
                  return json({
                    'code': 0,
                    'result': [
                      {'courseId': 1, 'termId': 1, 'name': 'Healthy'},
                      {'courseId': 2, 'termId': 2, 'name': 'Empty or failing'},
                    ],
                  });
                }
                final second = uri.path.endsWith('.rpc')
                    ? Uri.splitQueryString(body)['termId'] == '2'
                    : body.contains('c0-param0=number:2');
                if (second && failed) {
                  return SyntheticResponse('unavailable', 503);
                }
                return json({
                  'code': 0,
                  'result': {
                    'id': second ? 2 : 1,
                    'courseId': second ? 2 : 1,
                    'chapters': second
                        ? []
                        : [
                            {
                              'lessons': [],
                              'homeworks': [
                                {
                                  'test': {
                                    'id': 8,
                                    'name': 'Fresh',
                                    'deadline': 1799765999000,
                                  },
                                },
                              ],
                              'quizs': [],
                            },
                          ],
                    'exams': [],
                  },
                });
              case PlatformKind.xuetangx:
                if (uri.path.contains('user-courses')) {
                  final first =
                      uri.queryParameters['status'] == '1' &&
                      uri.queryParameters['page'] == '1';
                  return json({
                    'success': true,
                    'data': {
                      'product_list': first
                          ? [
                              {
                                'id': 1,
                                'products_sign': 'A',
                                'product_name': 'Healthy',
                              },
                              {
                                'id': 2,
                                'products_sign': 'B',
                                'product_name': 'Empty or failing',
                              },
                            ]
                          : [],
                    },
                  });
                }
                if (uri.path.contains('/chapter')) {
                  final second = uri.queryParameters['cid'] == '2';
                  if (second && failed) {
                    return json({
                      'success': false,
                      'data': {'course_chapter': []},
                    });
                  }
                  return json({
                    'success': true,
                    'data': second
                        ? {'course_chapter': []}
                        : {
                            'leaf_list': [
                              {'leaf_type': 6, 'id': 8, 'name': 'Fresh'},
                            ],
                          },
                  });
                }
                return json({
                  'data': {'deadline': 1799765999000},
                });
              case PlatformKind.yuketang:
                if (uri.path.contains('/courses/list')) {
                  return json({
                    'errcode': 0,
                    'data': {
                      'list': [
                        {
                          'classroom_id': 1,
                          'role': 5,
                          'course_name': 'Healthy',
                        },
                        {
                          'classroom_id': 2,
                          'role': 5,
                          'course_name': 'Empty or failing',
                        },
                      ],
                    },
                  });
                }
                final second = uri.path.endsWith('/2');
                if (second && failed) {
                  return json({
                    'errcode': 1,
                    'data': {'activities': []},
                  });
                }
                return json({
                  'errcode': 0,
                  'data': {
                    'activities': second
                        ? [
                            {'type': 14, 'id': 9},
                          ]
                        : [
                            {
                              'type': 5,
                              'id': 8,
                              'title': 'Fresh',
                              'deadline': 1799765999000,
                            },
                          ],
                    'has_more': false,
                  },
                });
              case PlatformKind.zhihuishu:
                if (uri.path.endsWith('queryShareCourseInfo')) {
                  return json({
                    'code': 200,
                    'result': {
                      'courseOpenDtos': [
                        {'courseOpenId': 1, 'name': 'Healthy'},
                        {'courseOpenId': 2, 'name': 'Empty or failing'},
                      ],
                    },
                  });
                }
                final params = jsonDecode(
                  ZhihuishuService.decryptSecret(
                    Uri.splitQueryString(body)['secretStr']!,
                    0,
                  ),
                ) as Map;
                final second = params['courseId'] == '2';
                if (second && failed) {
                  return json({
                    'code': 200,
                    'result': {'tags': []},
                  });
                }
                return json({
                  'code': 200,
                  'result': {
                    'tags': [],
                    'list': second
                        ? []
                        : [
                            {
                              'id': 8,
                              'title': 'Fresh',
                              'endTime': 1799765999000,
                            },
                          ],
                  },
                });
              default:
                throw StateError('Unexpected platform');
            }
          };
          final flag = switch (platform) {
            PlatformKind.mooc => 'mooc_ok',
            PlatformKind.xuetangx => 'xtx_ok',
            PlatformKind.yuketang => 'ykt_ok',
            _ => 'zhs_ok',
          };
          switch (platform) {
            case PlatformKind.mooc:
              await Storage.saveMooc(
                cookie: 'STUDY_SESS=synthetic; NTESSTUDYSI=synthetic',
                csrf: 'synthetic',
              );
            case PlatformKind.xuetangx:
              await Storage.saveXuetangx(cookie: 'synthetic');
            case PlatformKind.yuketang:
              await Storage.saveYuketang(cookie: 'synthetic');
            case PlatformKind.zhihuishu:
              await Storage.saveZhihuishu(cookie: 'synthetic');
            default:
              throw StateError('Unexpected platform');
          }
          await Storage.setFlag(flag, true);
          await Storage.saveHomework([
            HomeworkItem(
              id: 'old',
              platform: platform,
              course: 'Empty or failing',
              title: 'Old work',
              sourceKey: '${platform.name}|old',
            ),
          ]);
          await Storage.saveChaoxing(cookie: 'unselected-synthetic');
          final previous = const PlatformSyncStatus().finish(
            SyncOutcome.success,
            DateTime(2026, 10, 19),
          );
          await Storage.saveSyncStatuses({PlatformKind.chaoxing: previous});
          final result = await SyncService.run(platforms: {platform});
          final incomplete = failed || platform == PlatformKind.zhihuishu;
          expect(result.attempted, {platform});
          expect(
            Storage.syncStatuses()[PlatformKind.chaoxing]!.lastSuccess,
            previous.lastSuccess,
          );
          final outcome = incomplete ? SyncOutcome.retry : SyncOutcome.success;
          expect(result.outcomes[platform], outcome);
          expect(Storage.syncStatuses()[platform]!.outcome, outcome);
          expect(
            Storage.syncStatuses()[platform]!.nextRetry != null,
            incomplete,
          );
          expect(result.partial, incomplete);
          expect(result.message.isNotEmpty, incomplete);
          expect(result.items.map((h) => h.title), contains('Fresh'));
          expect(result.items.any((h) => h.id == 'old'), incomplete);
          expect(Storage.flag(flag), isTrue);
          expect(Storage.homework().any((h) => h.id == 'old'), incomplete);
        },
      );
    }
  }
}
