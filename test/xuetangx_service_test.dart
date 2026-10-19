// 学堂在线解析器：信封/课程列表/章节树/截止时间宽松收集 + 合并状态保留。
import 'package:flutter_test/flutter_test.dart';
import 'package:homework_radar/models/homework.dart';
import 'package:homework_radar/services/sync_service.dart';
import 'package:homework_radar/services/xuetangx_service.dart';

void main() {
  group('envelopeOk 信封判定', () {
    test('code==200 / code==0 / 字符串码都认', () {
      expect(XuetangxService.envelopeOk('{"code":200,"data":{}}'), isTrue);
      expect(XuetangxService.envelopeOk('{"code":0,"data":{}}'), isTrue);
      expect(XuetangxService.envelopeOk('{"code":"200","data":{}}'), isTrue);
    });

    test('无 code 但带 data 的裸信封也认（学堂在线口径不一）', () {
      expect(XuetangxService.envelopeOk('{"data":{"a":1}}'), isTrue);
    });

    test('非 JSON / 非 Map / 无 code 无 data 拒绝', () {
      expect(XuetangxService.envelopeOk('<html>401</html>'), isFalse);
      expect(XuetangxService.envelopeOk('[1,2,3]'), isFalse);
      expect(XuetangxService.envelopeOk('{"detail":"未登录"}'), isFalse);
    });
  });

  group('parseCourseListJson 课程列表宽松解析', () {
    test('嵌套结构里走出 classroomid+sign 的课程对象', () {
      const body = courseListBody;
      final courses = XuetangxService.parseCourseListJson(body);
      expect(courses, isNotNull);
      expect(courses!.length, 2);
      expect(courses[0].cid, '4231538');
      expect(courses[0].sign, 'HNU03031001055');
      expect(courses[0].name, '思想道德与法治');
      expect(courses[1].cid, '4239999');
      expect(courses[1].name, '课程 4239999', reason: '缺名字用「课程 {cid}」兜底');
    });

    test('同 cid+sign 去重', () {
      const body = '''
      {"data":{"list":[
        {"classroomid":100,"sign":"AB1","name":"课A"},
        {"classroomid":100,"sign":"AB1","name":"课A副本"}
      ]}}
      ''';
      expect(XuetangxService.parseCourseListJson(body)!.length, 1);
    });

    test('有数组但无课程对象 = 权威空列表（授权正常无课）', () {
      const body = '{"data":{"list":[],"totalCount":0}}';
      expect(XuetangxService.parseCourseListJson(body), isEmpty);
    });

    test('product_list 真实形态：id + products_sign 组合可解析', () {
      const body = '''
      {"success":true,"data":{"product_list":[
        {"id":4231538,"products_sign":"HNU03031001055","product_name":"思想道德与法治"},
        {"id":4239999,"products_sign":"XYZ2","product_name":"政府会计"}
      ]}}
      ''';
      final courses = XuetangxService.parseCourseListJson(body);
      expect(courses, isNotNull);
      expect(courses!.length, 2);
      expect(courses[0].cid, '4231538');
      expect(courses[0].sign, 'HNU03031001055');
      expect(courses[0].name, '思想道德与法治');
    });

    test('负载里连数组都没有 = 形状陌生返回 null（不能当无课清库）', () {
      expect(XuetangxService.parseCourseListJson('{"detail":"ok"}'), isNull);
      expect(XuetangxService.parseCourseListJson('<html>err</html>'), isNull);
    });
  });

  group('parseChapterScan 章节树扫描', () {
    test('收 leaf_type==6 作业与官方类型 5 考试，其他已知类型忽略', () {
      const body = '''
      {"data":{"course_chapter":[{"section_leaf_list":[
        {"leaf_list":[
          {"id":11,"name":"视频1","leaf_type":0},
          {"id":12,"name":"绪论--单元测试","leaf_type":6},
          {"id":13,"name":"讨论","leaf_type":4},
          {"id":15,"name":"期末考试","leaf_type":5}
        ]},
        {"leaf_list":[{"id":14,"name":"第一章测试","leaf_type":6}]}
      ]}]}}
      ''';
      final scan = XuetangxService.parseChapterScan(body);
      expect(scan, isNotNull);
      expect(scan!.homeworkLeaves.map((l) => l.id), ['12', '14']);
      expect(scan.homeworkLeaves.first.name, '绪论--单元测试');
      expect(scan.examLeaves.map((l) => l.id), ['15']);
      expect(scan.examLeaves.first.name, '期末考试');
    });

    test('有类型字段但无 6/5 = 权威无作业（空列表）', () {
      const body = '''
      {"data":{"course_chapter":[{"section_leaf_list":[
        {"leaf_list":[{"id":11,"name":"视频","leaf_type":0}]}
      ]}]}}
      ''';
      final scan = XuetangxService.parseChapterScan(body)!;
      expect(scan.homeworkLeaves, isEmpty);
      expect(scan.examLeaves, isEmpty);
    });

    test('全树无 leaf_type 字段 = 结构陌生返回 null', () {
      const body = '{"data":{"course_chapter":[{"name":"怪结构"}]}}';
      expect(XuetangxService.parseChapterScan(body), isNull);
    });
  });

  group('firstDue 截止时间宽松收集', () {
    test('识别 deadline / endTime / submit_end_time 键', () {
      expect(
        XuetangxService.firstDue({
          'a': 1,
          'deadline': '2026-10-08 23:59',
        }).toString(),
        contains('2026-10-08'),
      );
      expect(
        XuetangxService.firstDue({
          'endTime': '2026-10-09T15:00:00',
        }).toString(),
        contains('2026-10-09'),
      );
      expect(
        XuetangxService.firstDue({
          'submit_end_time': '2026-10-10 08:00:00',
        }).toString(),
        contains('2026-10-10'),
      );
    });

    test('epoch 秒与毫秒都认', () {
      final ms = XuetangxService.firstDue({'endTime': 1780000000000});
      final sec = XuetangxService.firstDue({'endTime': 1780000000});
      expect(ms, isNotNull);
      expect(sec, isNotNull);
      expect(ms, sec, reason: '同一时刻的秒/毫秒时间戳应解析一致');
    });

    test('真机实证：score_deadline 毫秒时间戳可解析', () {
      final due = XuetangxService.firstDue({
        'name': '单元测试',
        'leaf_type': 6,
        'end_time': 0,
        'score_deadline': 1799765999000,
      });
      expect(due, isNotNull);
      expect(due!.year, 2027, reason: '1799765999000 ≈ 2027-01');
    });

    test('end_time=0 表示未设置：跳过它继续找真正的截止（不能产出 1970 假截止）', () {
      expect(
        XuetangxService.firstDue({'end_time': 0, 'score_deadline': 0}),
        isNull,
      );
      final due = XuetangxService.firstDue({
        'end_time': 0,
        'score_deadline': 1799765999000,
      });
      expect(due!.year, 2027);
    });

    test('跳过 start 键：提交开始不是截止', () {
      expect(
        XuetangxService.firstDue({
          'start_time': '2026-10-08 23:59',
          'name': '作业',
        }),
        isNull,
      );
    });

    test('嵌套结构 DFS 取第一个可解析的截止', () {
      final due = XuetangxService.firstDue({
        'content_info': {'x': 1},
        'homework': {'endTime': '2026-12-01 12:00'},
      });
      expect(due, isNotNull);
      expect(due!.month, 12);
    });

    test('无任何时间形态返回 null', () {
      expect(XuetangxService.firstDue({'a': 'x', 'b': [1, 2]}), isNull);
    });
  });

  group('mergePlatform 学堂在线合并语义', () {
    test('恒 todo 的解析结果不打回旧条目的已完成状态（#36 同款）', () {
      final old = HomeworkItem(
        id: 'xtx_1_2',
        platform: PlatformKind.xuetangx,
        course: '课',
        title: '作业',
        dueAt: DateTime(2026, 10, 10),
        status: HwStatus.done,
        note: '需交纸质版',
      );
      final merged = <String, HomeworkItem>{'xtx_1_2': old};
      mergePlatform(merged, [
        HomeworkItem(
          id: 'xtx_1_2',
          platform: PlatformKind.xuetangx,
          course: '课',
          title: '作业',
          dueAt: DateTime(2026, 10, 10),
          status: HwStatus.todo,
        ),
      ], PlatformKind.xuetangx, complete: true);
      expect(merged['xtx_1_2']!.status, HwStatus.done);
      expect(merged['xtx_1_2']!.note, '需交纸质版');
    });

    test('complete 且条目消失时才清理平台旧条目', () {
      final old = HomeworkItem(
        id: 'xtx_1_2',
        platform: PlatformKind.xuetangx,
        course: '课',
        title: '旧作业',
        dueAt: DateTime(2026, 10, 10),
      );
      final merged = <String, HomeworkItem>{'xtx_1_2': old};
      mergePlatform(merged, [
        HomeworkItem(
          id: 'xtx_1_9',
          platform: PlatformKind.xuetangx,
          course: '课',
          title: '新作业',
          dueAt: DateTime(2026, 10, 11),
        ),
      ], PlatformKind.xuetangx, complete: true);
      expect(merged.containsKey('xtx_1_2'), isFalse);
      expect(merged.containsKey('xtx_1_9'), isTrue);
    });
  });
}

const String courseListBody = '''
{"code":200,"data":{"list":[
  {"classroomid":4231538,"sign":"HNU03031001055","name":"思想道德与法治"},
  {"classroomid":4239999,"sign":"XYZ2"}
]}}
''';
