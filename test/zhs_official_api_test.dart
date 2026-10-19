import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:encrypt/encrypt.dart' as enc;
import 'package:flutter_test/flutter_test.dart';
import 'package:pointycastle/export.dart';
import 'package:homework_radar/models/homework.dart';
import 'package:homework_radar/services/zhihuishu_exam_api.dart';
import 'package:homework_radar/services/zhihuishu_service.dart';
import 'package:homework_radar/services/sync_service.dart';

import 'support/synthetic_http.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final network = SyntheticHttp();
  late RSAPublicKey pub;
  late RSAPrivateKey priv;
  const aesKey = 'synthetic-key123';
  late List<Map> requests;
  var malformed = false;
  var failedExam = false;
  var examType = 1;
  setUpAll(() {
    HttpOverrides.global = network;
    final random = FortunaRandom()
      ..seed(KeyParameter(Uint8List.fromList(List.generate(32, (i) => i))));
    final generator = RSAKeyGenerator()
      ..init(
        ParametersWithRandom(
          RSAKeyGeneratorParameters(BigInt.from(65537), 1024, 12),
          random,
        ),
      );
    final keys = generator.generateKeyPair();
    pub = keys.publicKey as RSAPublicKey;
    priv = keys.privateKey as RSAPrivateKey;
  });
  tearDownAll(() => HttpOverrides.global = null);
  setUp(() {
    requests = [];
    malformed = false;
    failedExam = false;
    examType = 1;
    network.handler = (_, uri, body) {
      if (uri.path.endsWith('/c/has')) {
        final rsa = PKCS1Encoding(RSAEngine())
          ..init(true, PrivateKeyParameter<RSAPrivateKey>(priv));
        final signature = base64Encode(
          rsa.process(
            Uint8List.fromList(utf8.encode(jsonEncode({'cKey': aesKey}))),
          ),
        );
        return SyntheticResponse(
          jsonEncode({
            'status': 200,
            'rt': {'sl': signature},
          }),
        );
      }
      final form = Uri.splitQueryString(body);
      final payload = jsonDecode(
        enc.Encrypter(enc.AES(enc.Key.fromUtf8(aesKey), mode: enc.AESMode.cbc))
            .decrypt64(
              form['secretStr']!,
              iv: enc.IV.fromUtf8('1g3qqdh4jvbskb9x'),
            ),
      ) as Map;
      requests.add({'path': uri.path, ...payload});
      if (uri.path.endsWith('listAllRecruits')) {
        return SyntheticResponse(
          '{"status":200,"rt":[{"courseId":1,"recruitId":2,"schoolId":3,"courseName":"Course"},{"courseId":1,"recruitId":4,"schoolId":3,"courseName":"Course"}]}',
        );
      }
      if (uri.path.endsWith('getStudentHomework')) {
        final flag = payload['flag'];
        final page = payload['pageNum'];
        return SyntheticResponse(
          jsonEncode({
            'status': 200,
            'rt': {
              'studentHomeworkList': flag == 1
                  ? [
                      {
                        'examId': page == 0 ? 8 : 9,
                        'examName': 'Work $page',
                        'endDate': malformed ? 'bad' : '2026-12-01 23:59',
                      },
                    ]
                  : [
                      {'examId': 10, 'examName': 'Submitted', 'endDate': null},
                    ],
              'next': flag == 1 && page == 0 ? 1 : -1,
            },
          }),
        );
      }
      if (uri.path.endsWith('getExamType')) {
        return SyntheticResponse(jsonEncode({'status': 200, 'rt': examType}));
      }
      if (uri.path.endsWith('hasMakeupExam')) {
        return SyntheticResponse('{"status":200,"rt":1}');
      }
      if (failedExam) return SyntheticResponse('unavailable', 503);
      if (uri.path.endsWith('getStudentRoomExam') ||
          uri.path.endsWith('getStudentOfflineExam')) {
        return SyntheticResponse(
          '{"status":200,"rt":{"examId":12,"examName":"Onsite","endDate":"2026-12-02 10:00"}}',
        );
      }
      return SyntheticResponse(
        '{"status":200,"rt":[{"examId":11,"examName":"Final","endDate":"2026-12-03 23:59"}]}',
      );
    };
  });
  test(
    'official string success statuses work for both key and data envelopes',
    () async {
      final prior = network.handler;
      network.handler = (method, uri, body) async {
        final response = await prior(method, uri, body);
        final value = jsonDecode(response.body);
        if (value is Map && value['status'] == 200) {
          value['status'] = '200';
        }
        return SyntheticResponse(
          jsonEncode(value),
          response.status,
          response.headers,
        );
      };
      final result =
          await ZhihuishuExamApi(
            cookie: 'synthetic',
            bootstrapKey: pub,
          ).homeworkOf(
            courseName: 'Course',
            courseId: '1',
            recruitId: '2',
            schoolId: '3',
          );
      expect(result.complete, isTrue);
    },
  );
  ZhihuishuExamApi api() =>
      ZhihuishuExamApi(cookie: 'synthetic', bootstrapKey: pub);
  Future<ZhsExamSnapshot> fetch() => api().homeworkOf(
    courseName: 'Course',
    courseId: '1',
    recruitId: '2',
    schoolId: '3',
  );

  test(
    'two enrollment workers share a key but retain separate work identities',
    () async {
      final service = ZhihuishuService(cookie: 'synthetic', examApi: api());
      final result = await service.allHomework();
      expect(result, hasLength(8));
      expect(result.map((h) => h.id).toSet(), hasLength(8));
      expect(service.listFailed, isFalse);
      expect(service.failedCount, 0);
    },
  );
  test('official work endpoint loads both states and follows next despite short pages', () async {
    final result = await fetch();
    expect(result.complete, isTrue);
    expect(result.items, hasLength(4));
    expect(
      requests
          .where((r) => r['path'].toString().endsWith('getStudentHomework'))
          .map((r) => [r['flag'], r['pageNum']]),
      [
        [1, 0],
        [1, 1],
        [2, 0],
      ],
    );
    expect(
      result.items.singleWhere((h) => h.title == 'Submitted').status,
      HwStatus.submitted,
    );
    expect(
      result.items.singleWhere((h) => h.title == 'Submitted').dueAt,
      isNull,
    );
    expect(
      result.items.every((h) => h.sourceKey!.startsWith('zhs|1|2|')),
      isTrue,
    );
  });
  test(
    'failed exam keeps new works while prohibiting old-record cleanup',
    () async {
      failedExam = true;
      final result = await fetch();
      expect(result.complete, isFalse);
      expect(result.items, hasLength(3));
    },
  );
  test(
    'malformed deadline is incomplete rather than an empty work list',
    () async {
      malformed = true;
      final result = await fetch();
      expect(result.complete, isFalse);
    },
  );
  for (final type in [2, 3]) {
    test('exam type $type includes onsite exam and its makeup', () async {
      examType = type;
      final result = await fetch();
      expect(result.complete, isTrue);
      expect(
        result.items.map((h) => h.title),
        containsAll(['Onsite', 'Final']),
      );
    });
  }
  test(
    'wrong bootstrap envelope does not produce requests with guessed keys',
    () async {
      network.handler = (_, _, _) =>
          SyntheticResponse('{"status":200,"rt":{"sl":"bad"}}');
      final result = await fetch();
      expect(result.complete, isFalse);
      expect(result.items, isEmpty);
    },
  );
  test(
    'official enrollment list keeps two offerings of the same course',
    () async {
      final result = await api().enrollments();
      expect(result.complete, isTrue);
      expect(result.courses.map((c) => c.recruitId), ['2', '4']);
    },
  );
  test('unknown enrollment payload is not proof of zero courses', () async {
    final prior = network.handler;
    network.handler = (method, uri, body) =>
        uri.path.endsWith('listAllRecruits')
        ? SyntheticResponse('{"status":200,"rt":{"unexpected":[]}}')
        : prior(method, uri, body);
    expect((await api().enrollments()).complete, isFalse);
  });
  test(
    'failed legacy catalog does not poison a complete official catalog',
    () async {
      final prior = network.handler;
      network.handler = (method, uri, body) =>
          uri.host == 'onlineservice-api.zhihuishu.com'
          ? SyntheticResponse('unavailable', 503)
          : prior(method, uri, body);
      final service = ZhihuishuService(cookie: 'synthetic', examApi: api());
      final courses = await service.courses();
      expect(courses.map((c) => c.recruitId), ['2', '4']);
      expect(service.listFailed, isFalse);
    },
  );
  test('missing course enrollment identity never authorizes cleanup', () async {
    network.handler = (_, _, _) =>
        SyntheticResponse('{"code":200,"data":{"list":[]}}');
    final service = ZhihuishuService(cookie: 'synthetic');
    await service.homeworkOf(ZhsCourse('Course', '1'));
    expect(service.failedCount, greaterThan(0));
  });
  test('course parser preserves enrollment and school identifiers', () {
    final parsed = ZhihuishuService.parseCourseListJson(
      '{"code":200,"result":{"courseOpenDtos":[{"courseId":1,"courseName":"Course","recruitId":2,"schoolId":3},{"courseId":1,"courseName":"Course","recruitId":4,"schoolId":3}]}}',
    );
    expect(parsed!.map((c) => c.recruitId), ['2', '4']);
  });
  test('service uses proven API when enrollment metadata is present', () async {
    final service = ZhihuishuService(cookie: 'synthetic', examApi: api());
    final items = await service.homeworkOf(
      ZhsCourse('Course', '1', recruitId: '2', schoolId: '3'),
    );
    expect(items, hasLength(4));
    expect(service.failedCount, 0);
  });
  test('unambiguous identity upgrade preserves legacy ID and notes', () {
    final old = HomeworkItem(
      id: 'old',
      platform: PlatformKind.zhihuishu,
      course: 'Course',
      title: 'Old',
      note: 'Keep',
      sourceKey: 'zhs|1|work|8',
    );
    final merged = {old.id: old};
    mergePlatform(
      merged,
      [
        HomeworkItem(
          id: 'new',
          platform: PlatformKind.zhihuishu,
          course: 'Renamed',
          title: 'Fresh',
          sourceKey: 'zhs|1|2|work|8',
        ),
      ],
      PlatformKind.zhihuishu,
      complete: true,
    );
    expect(merged.keys, ['old']);
    expect(merged['old']!.note, 'Keep');
    expect(merged['old']!.sourceKey, 'zhs|1|2|work|8');
  });
  test(
    'unmapped legacy assessment keeps its notes instead of guessing a new type',
    () {
      final old = HomeworkItem(
        id: 'old',
        platform: PlatformKind.zhihuishu,
        course: 'Course',
        title: 'Legacy',
        note: 'Keep',
        sourceKey: 'zhs|1|work|8',
      );
      final merged = {old.id: old};
      mergePlatform(
        merged,
        [
          HomeworkItem(
            id: 'new-exam',
            platform: PlatformKind.zhihuishu,
            course: 'Course',
            title: 'Exam',
            sourceKey: 'zhs|1|2|exam|8',
          ),
        ],
        PlatformKind.zhihuishu,
        complete: true,
      );
      expect(merged.keys, containsAll(['old', 'new-exam']));
      expect(merged['old']!.note, 'Keep');
      expect(merged['new-exam']!.note, isNull);
    },
  );
  test(
    'ambiguous enrollment upgrade preserves the old record and both new works',
    () {
      final old = HomeworkItem(
        id: 'old',
        platform: PlatformKind.zhihuishu,
        course: 'Course',
        title: 'Old',
        sourceKey: 'zhs|1|work|8',
      );
      final merged = {old.id: old};
      mergePlatform(
        merged,
        [
          for (final recruit in ['2', '3'])
            HomeworkItem(
              id: 'new-$recruit',
              platform: PlatformKind.zhihuishu,
              course: 'Course',
              title: 'Fresh',
              sourceKey: 'zhs|1|$recruit|work|8',
            ),
        ],
        PlatformKind.zhihuishu,
        complete: true,
      );
      expect(merged.keys, containsAll(['old', 'new-2', 'new-3']));
    },
  );
}
