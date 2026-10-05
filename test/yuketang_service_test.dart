// 雨课堂解析器：课程列表（role=6）/学习日志活动（type 19/20）/score_d 截止
// 校验 + 合并状态保留。
import 'package:flutter_test/flutter_test.dart';
import 'package:homework_radar/models/homework.dart';
import 'package:homework_radar/services/sync_service.dart';
import 'package:homework_radar/services/yuketang_service.dart';

void main() {
  group('courseListOk 课程列表信封', () {
    test('data.list 数组 / 顶层 list 数组都认', () {
      expect(YuketangService.courseListOk('{"data":{"list":[]}}'), isTrue);
      expect(YuketangService.courseListOk('{"list":[1,2]}'), isTrue);
    });

    test('非 JSON / 非 Map / list 缺失或非数组拒绝', () {
      expect(YuketangService.courseListOk('<html>403</html>'), isFalse);
      expect(YuketangService.courseListOk('{"data":{}}'), isFalse);
      expect(YuketangService.courseListOk('{"data":{"list":"x"}}'), isFalse);
    });
  });

  group('parseCourseList 课程列表解析', () {
    test('只收 role==6 的学生课程，跨字段取名字，按 classroom_id 去重', () {
      const body = '''
      {"data":{"list":[
        {"classroom_id":1001,"role":6,"course_name":"线性代数"},
        {"classroom_id":1001,"role":6,"course_name":"线性代数副本"},
        {"classroom_id":1002,"role":3,"course_name":"我是老师"},
        {"classroom_id":1003,"role":"6","name":"字符串角色也算"},
        {"classroom_id":1004,"role":6,"title":"标题兜底"},
        {"classroom_id":1005,"role":6}
      ]}}
      ''';
      final courses = YuketangService.parseCourseList(body);
      expect(courses, isNotNull);
      expect(courses!.length, 4);
      expect(courses[0].name, '线性代数');
      expect(courses[0].classroomId, '1001');
      expect(courses[1].name, '字符串角色也算');
      expect(courses[2].name, '标题兜底');
      expect(courses[3].name, '课程 1005', reason: '缺名字用「课程 {cid}」兜底');
    });

    test('list 为空数组 = 权威无课；list 缺失 = 形状陌生 null', () {
      expect(YuketangService.parseCourseList('{"data":{"list":[]}}'), isEmpty);
      expect(YuketangService.parseCourseList('{"data":{}}'), isNull);
      expect(YuketangService.parseCourseList('nope'), isNull);
    });
  });

  group('parseLogActivities 学习日志解析', () {
    test('只收 type 19/20，截止取 content.score_d，标题缺省「作业/考试」', () {
      const body = '''
      {"data":{"activities":[
        {"id":"a1","type":19,"title":"第一章作业","content":{"score_d":1799765999000}},
        {"id":"a2","type":20,"content":{"score_d":1799000000000}},
        {"id":"a3","type":0,"title":"视频","content":{"score_d":1799000000000}},
        {"id":"a4","type":19,"title":"无截止作业","content":{"score_d":0}}
      ]}}
      ''';
      final items = YuketangService.parseLogActivities(body, courseName: '线性代数');
      expect(items, isNotNull);
      expect(items!.length, 2);
      expect(items[0].title, '第一章作业');
      expect(items[0].dueAt!.year, 2027);
      expect(items[1].title, '考试', reason: 'type 20 缺标题缺省「考试」');
      expect(items[1].platform, PlatformKind.yuketang);
      expect(items[0].id, startsWith('ykt_'));
    });

    test('score_d 为 0/负数/字符串数字：0 与负数拒收，字符串数字可解析', () {
      expect(
        YuketangService.parseLogActivities(
          '{"data":{"activities":[{"id":"x","type":19,"content":{"score_d":0}}]}}',
          courseName: '课',
        )!.length,
        0,
        reason: '0 = 未设置，绝不能变 1970 假截止',
      );
      final ok = YuketangService.parseLogActivities(
        '{"data":{"activities":[{"id":"x","type":19,"content":{"score_d":"1799765999000"}}]}}',
        courseName: '课',
      );
      expect(ok!.single.dueAt!.year, 2027);
    });

    test('activities 缺失/非数组 = 形状陌生 null（不能当无作业清库）', () {
      expect(
        YuketangService.parseLogActivities('{"data":{}}', courseName: '课'),
        isNull,
      );
      expect(
        YuketangService.parseLogActivities('nope', courseName: '课'),
        isNull,
      );
    });

    test('有活动但全部无截止 = 空列表（调用方按「字段可能漂移」处理）', () {
      final items = YuketangService.parseLogActivities(
        '{"data":{"activities":[{"id":"x","type":19,"title":"无截止","content":{}}]}}',
        courseName: '课',
      );
      expect(items, isEmpty);
    });
  });

  group('mergePlatform 雨课堂合并语义', () {
    test('恒 todo 的解析结果不打回旧条目的已完成状态', () {
      final old = HomeworkItem(
        id: 'ykt_1_2',
        platform: PlatformKind.yuketang,
        course: '课',
        title: '作业',
        dueAt: DateTime(2027, 1, 10),
        status: HwStatus.done,
        note: '纸质提交',
      );
      final merged = <String, HomeworkItem>{'ykt_1_2': old};
      mergePlatform(merged, [
        HomeworkItem(
          id: 'ykt_1_2',
          platform: PlatformKind.yuketang,
          course: '课',
          title: '作业',
          dueAt: DateTime(2027, 1, 10),
          status: HwStatus.todo,
        ),
      ], PlatformKind.yuketang, complete: true);
      expect(merged['ykt_1_2']!.status, HwStatus.done);
      expect(merged['ykt_1_2']!.note, '纸质提交');
    });

    test('complete 且条目消失时清理平台旧条目', () {
      final old = HomeworkItem(
        id: 'ykt_1_2',
        platform: PlatformKind.yuketang,
        course: '课',
        title: '旧作业',
        dueAt: DateTime(2027, 1, 10),
      );
      final merged = <String, HomeworkItem>{'ykt_1_2': old};
      mergePlatform(merged, [
        HomeworkItem(
          id: 'ykt_1_9',
          platform: PlatformKind.yuketang,
          course: '课',
          title: '新作业',
          dueAt: DateTime(2027, 1, 11),
        ),
      ], PlatformKind.yuketang, complete: true);
      expect(merged.containsKey('ykt_1_2'), isFalse);
      expect(merged.containsKey('ykt_1_9'), isTrue);
    });
  });
}
