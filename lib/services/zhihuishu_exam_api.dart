/// Read-only protocol from the current official stuExamWeb client. Source and
/// live anonymous protocol checks are recorded in the platform evidence folder.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:encrypt/encrypt.dart' as enc;
import 'package:pointycastle/export.dart' show RSAPublicKey;

import '../models/homework.dart';
import 'safe_http.dart';
import 'stable_hash.dart';

class ZhsExamSnapshot {
  final List<HomeworkItem> items;
  final bool complete;
  ZhsExamSnapshot(this.items, this.complete);
}

class _Incomplete implements Exception {}

class ZhsEnrollment {
  final String name, courseId, recruitId;
  final String? schoolId;
  ZhsEnrollment(this.name, this.courseId, this.recruitId, this.schoolId);
}

class ZhsEnrollments {
  final List<ZhsEnrollment> courses;
  final bool complete;
  ZhsEnrollments(this.courses, this.complete);
}

class ZhihuishuExamApi {
  final String? cookie;
  final RSAPublicKey _bootstrapKey;
  Future<String>? _key;
  Future<ZhsEnrollments>? _enrollments;
  bool authRejected = false;
  // This public key is shipped by https://base2.zhihuishu.com/js/2.js.
  static const _publicPem = '''-----BEGIN PUBLIC KEY-----
MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQCgfZmpLpPEpEFRKBe+ZjWJUjPe+7qg7pGqcfN3j2egJ8H2mrKwaEqZEnPnpi2O3hN8HRyaFozDOp8gwZiYfiIZjWy0Jr/FNAiiKYh5bq0GsEn+ieMmRyJg/+i1rqizhvCXvFdrdGhFTw5EBwTpsGdwe1utdlrvIJUAFWj9Yh4qbQIDAQAB
-----END PUBLIC KEY-----''';
  static const _student =
      'https://studentexam-api.zhihuishu.com/studentExam/gateway/t/v1';
  static const _exam =
      'https://taurusexam-api.zhihuishu.com/taurusExam/gateway/t/v1';
  static final _iv = enc.IV.fromUtf8('1g3qqdh4jvbskb9x');

  ZhihuishuExamApi({required this.cookie, RSAPublicKey? bootstrapKey})
    : _bootstrapKey =
          bootstrapKey ?? enc.RSAKeyParser().parse(_publicPem) as RSAPublicKey;

  Map<String, String> get _headers => {
    'Cookie': SafeHttp.cookieHeader(cookie),
    'Referer': 'https://onlineexamh5new.zhihuishu.com/',
  };

  Future<String> _bootstrap() async {
    final uid = enc.Encrypter(enc.RSA(publicKey: _bootstrapKey))
        .encrypt(jsonEncode({'module': 3}))
        .base64;
    final uri = Uri.https(
      'appcomm-user.zhihuishu.com',
      '/app-commserv-user/c/has',
      {'uid': uid},
    );
    final response = await SafeHttp.get(uri.toString(), headers: _headers);
    if (response == null || response.statusCode != 200) throw _Incomplete();
    final body = jsonDecode(response.body);
    if (body is! Map ||
        !const [200, '200'].contains(body['status']) ||
        body['rt'] is! Map ||
        body['rt']['sl'] is! String) {
      throw _Incomplete();
    }
    final encrypted = base64Decode(body['rt']['sl']);
    final size = (_bootstrapKey.modulus!.bitLength + 7) ~/ 8;
    if (encrypted.length != size) throw _Incomplete();
    final number = BigInt.parse(
      encrypted.map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
      radix: 16,
    );
    if (number >= _bootstrapKey.modulus!) throw _Incomplete();
    final hex = number
        .modPow(_bootstrapKey.exponent!, _bootstrapKey.modulus!)
        .toRadixString(16)
        .padLeft(size * 2, '0');
    final decoded = Uint8List.fromList([
      for (var i = 0; i < hex.length; i += 2)
        int.parse(hex.substring(i, i + 2), radix: 16),
    ]);
    // The official server signs the key envelope using PKCS#1 type-1 padding.
    if (decoded[0] != 0 || decoded[1] != 1) throw _Incomplete();
    var separator = 2;
    while (separator < decoded.length && decoded[separator] == 255) {
      separator++;
    }
    if (separator < 10 ||
        separator >= decoded.length ||
        decoded[separator] != 0) {
      throw _Incomplete();
    }
    final payload = jsonDecode(utf8.decode(decoded.sublist(separator + 1)));
    final key = payload is Map ? payload['cKey'] : null;
    if (key is! String ||
        !const [16, 24, 32].contains(utf8.encode(key).length)) {
      throw _Incomplete();
    }
    return key;
  }

  Future<dynamic> _read(String path, Map<String, dynamic> params) async {
    final key = await (_key ??= _bootstrap());
    final cipher = enc.Encrypter(
      enc.AES(enc.Key.fromUtf8(key), mode: enc.AESMode.cbc),
    ).encrypt(jsonEncode(params), iv: _iv).base64;
    final response = await SafeHttp.postForm(
      path,
      body: {'secretStr': cipher},
      headers: _headers,
    );
    if (response?.statusCode == 401 || response?.statusCode == 403) {
      authRejected = true;
    }
    if (response == null || response.statusCode != 200) throw _Incomplete();
    final body = jsonDecode(response.body);
    if (body is Map && const [401, 403, '401', '403'].contains(body['code'])) {
      authRejected = true;
    }
    if (body is! Map ||
        !const [200, '200'].contains(body['status']) ||
        !body.containsKey('rt') ||
        (body['code'] != null &&
            !const [0, 200, '0', '200'].contains(body['code']))) {
      throw _Incomplete();
    }
    return body['rt'];
  }

  Future<ZhsEnrollments> enrollments({bool refresh = false}) {
    if (refresh) _enrollments = null;
    return _enrollments ??= _readEnrollments();
  }

  Future<ZhsEnrollments> _readEnrollments() async {
    final courses = <ZhsEnrollment>[];
    var malformed = false;
    void walk(dynamic node) {
      if (node is List) {
        for (final row in node) {
          walk(row);
        }
      } else if (node is Map) {
        if (node.containsKey('courseId') || node.containsKey('recruitId')) {
          final course = node['courseId'],
              recruit = node['recruitId'],
              name = node['courseName'];
          if (course == null ||
              recruit == null ||
              name is! String ||
              name.trim().isEmpty ||
              '$course'.isEmpty ||
              '$recruit'.isEmpty) {
            malformed = true;
            return;
          }
          courses.add(
            ZhsEnrollment(
              name.trim(),
              '$course',
              '$recruit',
              node['schoolId']?.toString(),
            ),
          );
        } else {
          for (final value in node.values) {
            if (value is Map || value is List) walk(value);
          }
        }
      } else {
        malformed = true;
      }
    }

    try {
      final rt = await _read('$_student/exam/listAllRecruits', {});
      walk(rt);
      final recognized = courses.isNotEmpty || rt is List && rt.isEmpty;
      return ZhsEnrollments(courses, recognized && !malformed);
    } catch (_) {
      return ZhsEnrollments(courses, false);
    }
  }

  Future<ZhsExamSnapshot> homeworkOf({
    required String courseName,
    required String courseId,
    required String recruitId,
    String? schoolId,
  }) async {
    final items = <HomeworkItem>[];
    final seen = <String>{};
    void add(dynamic row, String kind, int flag) {
      if (row is! Map ||
          row['examId'] == null ||
          !RegExp(r'^[1-9]\d*$').hasMatch('${row['examId']}') ||
          !row.containsKey('endDate')) {
        throw _Incomplete();
      }
      final value = row['endDate'];
      DateTime? due;
      if (value != null && value != '') {
        if (value is! String) throw _Incomplete();
        due = DateTime.tryParse(value)?.toLocal();
        if (due == null || due.year < 2000) throw _Incomplete();
      }
      final id = '${row['examId']}';
      final source = 'zhs|$courseId|$recruitId|$kind|$id';
      final title = row['examName'];
      final item = HomeworkItem(
        id: 'zhs_${stableHash('$courseId|$recruitId')}_${kind}_$id',
        platform: PlatformKind.zhihuishu,
        course: courseName,
        title: title is String && title.trim().isNotEmpty
            ? title.trim()
            : '${kind == 'work' ? '作业' : '考试'} $id',
        dueAt: due,
        status: flag == 2 ? HwStatus.submitted : HwStatus.todo,
        sourceKey: source,
      );
      if (seen.add(source)) {
        items.add(item);
      } else if (flag == 2) {
        final index = items.indexWhere((h) => h.sourceKey == source);
        items[index] = item;
      }
    }

    try {
      if (courseId.isEmpty || recruitId.isEmpty) throw _Incomplete();
      for (final flag in [1, 2]) {
        final pageSeen = <String>{};
        for (var page = 0; page < 30; page++) {
          final rt = await _read('$_student/student/getStudentHomework', {
            'courseId': courseId,
            'recruitId': recruitId,
            'flag': flag,
            'pageNum': page,
            'pageSize': 100,
          });
          if (rt is! Map ||
              rt['studentHomeworkList'] is! List ||
              rt['next'] is! int) {
            throw _Incomplete();
          }
          final rows = rt['studentHomeworkList'] as List;
          var added = 0;
          for (final row in rows) {
            add(row, 'work', flag);
            if (pageSeen.add('${row['examId']}')) added++;
          }
          if (rt['next'] == -1) break;
          if (rt['next'] < 0 || (rows.isNotEmpty && added == 0) || page == 29) {
            throw _Incomplete();
          }
        }
      }
      var school = schoolId;
      if (school == null || school.isEmpty || school == '0') {
        final rt = await _read('$_student/exam/getLoginSchoolInfo', {});
        if (rt is! Map || rt['schoolId'] == null) throw _Incomplete();
        school = '${rt['schoolId']}';
      }
      if (school == '0' || school.isEmpty) throw _Incomplete();
      final type = await _read('$_exam/exam/getExamType', {
        'recruitId': recruitId,
        'schoolId': school,
      });
      if (!const [1, 2, 3].contains(type)) throw _Incomplete();
      for (final flag in [1, 2]) {
        final params = {
          'courseId': courseId,
          'recruitId': recruitId,
          'flag': flag,
        };
        var hasOnline = type == 1;
        if (type == 2 || type == 3) {
          final name = type == 2
              ? 'getStudentRoomExam'
              : 'getStudentOfflineExam';
          final rt = await _read('$_exam/student/$name', params);
          if (rt != null && !(rt is Map && rt.isEmpty)) add(rt, 'exam', flag);
          final makeup = await _read('$_exam/student/hasMakeupExam', {
            'recruitId': recruitId,
          });
          if (!const [0, 1].contains(makeup)) throw _Incomplete();
          hasOnline = makeup == 1;
        }
        if (hasOnline) {
          final rt = await _read('$_exam/student/getStudentFinalExam', params);
          if (rt is List) {
            for (final row in rt) {
              add(row, 'exam', flag);
            }
          } else if (rt is! Map || rt.isNotEmpty) {
            throw _Incomplete();
          }
        }
      }
      return ZhsExamSnapshot(items, true);
    } catch (_) {
      return ZhsExamSnapshot(items, false);
    }
  }
}
