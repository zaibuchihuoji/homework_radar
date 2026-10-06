// 雨课堂解析器：课程列表（role 5/6 + 漂移兜底）/学习日志活动（type 5 真机
// 形状 + 19/20 社区形状）/截止校验 + 合并状态保留。
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
    test('收 role 5/6 的学生课程，跨字段取名字，按 classroom_id 去重', () {
      const body = '''
      {"data":{"list":[
        {"classroom_id":1001,"role":6,"course_name":"线性代数"},
        {"classroom_id":1001,"role":6,"course_name":"线性代数副本"},
        {"classroom_id":1002,"role":3,"course_name":"我是老师"},
        {"classroom_id":1003,"role":"6","name":"字符串角色也算"},
        {"classroom_id":1004,"role":6,"title":"标题兜底"},
        {"classroom_id":1005,"role":6},
        {"classroom_id":1006,"role":5,"course_name":"真机实证5也是学生"}
      ]}}
      ''';
      final courses = YuketangService.parseCourseList(body);
      expect(courses, isNotNull);
      expect(courses!.length, 5);
      expect(courses[0].name, '线性代数');
      expect(courses[0].classroomId, '1001');
      expect(courses[1].name, '字符串角色也算');
      expect(courses[2].name, '标题兜底');
      expect(courses[3].name, '课程 1005', reason: '缺名字用「课程 {cid}」兜底');
      expect(courses[4].name, '真机实证5也是学生');
    });

    test('列表非空但无 role 命中 → 兜底全收（role 口径漂移保护）', () {
      const body = '''
      {"data":{"list":[
        {"classroom_id":2001,"role":7,"course_name":"未知角色课"},
        {"classroom_id":2002,"role":"5x"}
      ]}}
      ''';
      final courses = YuketangService.parseCourseList(body);
      expect(courses, isNotNull);
      expect(courses!.length, 2);
      expect(courses[0].name, '未知角色课');
    });

    test('list 为空数组 = 权威无课；list 缺失 = 形状陌生 null', () {
      expect(YuketangService.parseCourseList('{"data":{"list":[]}}'), isEmpty);
      expect(YuketangService.parseCourseList('{"data":{}}'), isNull);
      expect(YuketangService.parseCourseList('nope'), isNull);
    });
  });

  group('parseLogActivities 学习日志解析', () {
    test('真机形状 type=5：顶层 deadline/score/status，判分完=done；type14 课件跳过', () {
      const body = '''
      {"data":{"IS_SIMPLE":false,"prev_id":56926900,"activities":[
        {"type":5,"id":56926900,"courseware_id":"4564610",
         "title":"体育学院实验室安全考核二（2）","create_time":1789305548000,
         "status":3,"score":98,"limit":3600,"deadline":1789383600000,
         "total_score":100,"problem_count":50,"progress":50,
         "is_single_paper":true,"unfinished":0},
        {"type":14,"id":44261788,"courseware_id":"1369",
         "title":"第一章 课件","create_time":1741047352000,
         "attend_status":true,"is_finished":true}
      ]}}
      ''';
      final items = YuketangService.parseLogActivities(body, courseName: '课');
      expect(items, isNotNull);
      expect(items!.length, 1, reason: 'type14 课件无截止概念，直接跳过');
      expect(items[0].title, '体育学院实验室安全考核二（2）');
      expect(items[0].dueAt, DateTime.fromMillisecondsSinceEpoch(1789383600000));
      expect(items[0].status, HwStatus.done,
          reason: 'status=3 且有 score = 已判分完成');
      expect(items[0].platform, PlatformKind.yuketang);
    });

    test('type=5 未判分（无 status3/score）= todo；缺标题缺省「考试」', () {
      const body = '''
      {"data":{"activities":[
        {"type":5,"id":9001,"deadline":1799765999000}
      ]}}
      ''';
      final items = YuketangService.parseLogActivities(body, courseName: '课');
      expect(items!.single.status, HwStatus.todo);
      expect(items.single.title, '考试');
    });

    test('社区文档形状 type 19/20：截止 content.score_d，恒 todo', () {
      const body = '''
      {"data":{"activities":[
        {"id":"a1","type":19,"title":"第一章作业","content":{"score_d":1799765999000}},
        {"id":"a2","type":20,"content":{"score_d":1799000000000}},
        {"id":"a3","type":0,"title":"视频","content":{"score_d":1799000000000}}
      ]}}
      ''';
      final items = YuketangService.parseLogActivities(body, courseName: '线性代数');
      expect(items, isNotNull);
      expect(items!.length, 2);
      expect(items[0].title, '第一章作业');
      expect(items[0].dueAt!.year, 2027);
      expect(items[0].status, HwStatus.todo);
      expect(items[1].title, '考试', reason: 'type 20 缺标题缺省「考试」');
      expect(items[1].platform, PlatformKind.yuketang);
      expect(items[0].id, startsWith('ykt_'));
    });

    test('score_d 为 0/负数/字符串数字：0 与负数拒收，字符串数字可解析', () {
      expect(
        YuketangService.parseLogActivities(
          '{"data":{"activities":[{"id":"x","type":19,"content":{"score_d":0}}]}}',
          courseName: '课',
        ),
        isNull,
        reason: '截止型条目存在却零解析 → 字段漂移保护 null',
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

    test('全是教学内容（type14）= 权威空列表；截止型条目无截止 = null 保护', () {
      expect(
        YuketangService.parseLogActivities(
          '{"data":{"activities":[{"id":"x","type":14,"title":"课件","is_finished":true}]}}',
          courseName: '课',
        ),
        isEmpty,
        reason: '本就无截止概念的教学课 = 权威「本课无截止条目」',
      );
      expect(
        YuketangService.parseLogActivities(
          '{"data":{"activities":[{"id":"x","type":5,"title":"练习"}]}}',
          courseName: '课',
        ),
        isNull,
        reason: '考核存在却没有截止字段 → 疑似口径漂移，null 保护',
      );
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
