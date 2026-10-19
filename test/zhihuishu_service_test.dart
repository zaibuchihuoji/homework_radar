// 智慧树服务纯函数级测试（无网络、无 mock 框架，参照现有 test/ 风格）。
import 'package:flutter_test/flutter_test.dart';

import 'package:homework_radar/models/homework.dart';
import 'package:homework_radar/services/stable_hash.dart';
import 'package:homework_radar/services/zhihuishu_service.dart';

void main() {
  group('parseWorkListJson', () {
    test('标准信封 code=0 + data.list：字段映射（标题/截止/状态/id 前缀 zhs_）', () {
      final body =
          '{"code":0,"message":"请求成功","data":{"list":['
          '{"workId":"901","workName":"第一章作业","endTime":"2026-10-10 23:59",'
          '"submitted":true},'
          '{"workId":"902","name":"第二章测验","submitEndTime":"2026-11-01 12:30"}'
          ']}}';
      final list = ZhihuishuService.parseWorkListJson(body, courseName: '高等数学');
      expect(list, isNotNull);
      final items = list!; // 解包一次：`!` 不产生类型提升，后续裸用 list 编译不过
      expect(items, hasLength(2));
      final first = items[0];
      expect(first.platform, PlatformKind.zhihuishu);
      expect(first.course, '高等数学');
      expect(first.title, '第一章作业');
      expect(first.dueAt, DateTime(2026, 10, 10, 23, 59));
      expect(first.status, HwStatus.submitted);
      expect(first.id, 'zhs_${stableHash('高等数学')}_901');
      final second = items[1];
      expect(second.title, '第二章测验');
      expect(second.dueAt, DateTime(2026, 11, 1, 12, 30));
      // 数值/布尔状态字段缺失时不猜，默认未完成
      expect(second.status, HwStatus.todo);
    });

    test('data 直接为数组的变体 + ISO 截止时间', () {
      final body =
          '{"code":0,"data":['
          '{"homeworkId":"77","title":"实验报告","deadline":"2026-12-01T08:00:00"}'
          ']}';
      final list = ZhihuishuService.parseWorkListJson(body, courseName: '物理');
      final items = list!;
      expect(items, hasLength(1));
      expect(items[0].id, 'zhs_${stableHash('物理')}_77');
      expect(items[0].dueAt, DateTime(2026, 12, 1, 8, 0));
      expect(items[0].status, HwStatus.todo);
    });

    test('毫秒时间戳截止时间', () {
      final body =
          '{"code":0,"data":['
          '{"workId":"5","workName":"毫秒口径","endTime":1791580800000}'
          ']}';
      final list = ZhihuishuService.parseWorkListJson(body, courseName: 'c');
      expect(
        list![0].dueAt,
        DateTime.fromMillisecondsSinceEpoch(1791580800000),
      );
    });

    test('部分条目没有截止时，整页不具备完整性证据', () {
      final body =
          '{"code":0,"data":['
          '{"workId":"1","workName":"没有截止"},'
          '{"workId":"2","workName":"有截止","endTime":"2026-10-05 10:00"}'
          ']}';
      final list = ZhihuishuService.parseWorkListJson(body, courseName: 'c');
      expect(list, isNull);
    });

    test('全部条目都无截止字段：返回 null（不可信结果），不是权威空列表', () {
      // 若返回 [] 会被当「确认没有作业」+ complete 清掉该课程旧条目——
      // 字段名没对上（未抓包校准）时必须走 failedCount 而不是清库
      final body =
          '{"code":0,"data":['
          '{"workId":"1","workName":"甲"},'
          '{"workId":"2","workName":"乙"}'
          ']}';
      expect(ZhihuishuService.parseWorkListJson(body, courseName: 'c'), isNull);
    });

    test('时长语义的小数值不落进 1970（limitTime=5400 秒不是时刻）', () {
      final body =
          '{"code":0,"data":['
          '{"workId":"1","workName":"只有时长","limitTime":5400}'
          ']}';
      expect(ZhihuishuService.parseWorkListJson(body, courseName: 'c'), isNull);
    });

    test('同 id 条目去重（重复条目会重复排提醒）', () {
      final body =
          '{"code":0,"data":['
          '{"workId":"9","workName":"a","endTime":"2026-10-05 10:00"},'
          '{"workId":"9","workName":"a 副本","endTime":"2026-10-06 10:00"}'
          ']}';
      final list = ZhihuishuService.parseWorkListJson(body, courseName: 'c');
      final items = list!;
      expect(items, hasLength(1));
      expect(items[0].title, 'a');
    });

    test('code!=0 返回 null（候选端点链据此换下一个）', () {
      expect(
        ZhihuishuService.parseWorkListJson(
          '{"code":401,"message":"未登录"}',
          courseName: 'c',
        ),
        isNull,
      );
    });

    test('非 JSON 返回 null', () {
      expect(
        ZhihuishuService.parseWorkListJson(
          '<html>login</html>',
          courseName: 'c',
        ),
        isNull,
      );
    });

    test('数组元素混入非对象视为形状陌生返回 null', () {
      expect(
        ZhihuishuService.parseWorkListJson(
          '{"code":0,"data":["oops"]}',
          courseName: 'c',
        ),
        isNull,
      );
    });
  });

  group('parseCourseListJson', () {
    test('课程列表混入无法识别的对象时不能作为完整课程列表', () {
      final body =
          '{"code":0,"data":{"list":['
          '{"courseName":"高等数学","courseId":"10001"},'
          '{"name":"张三","id":"T1"}'
          ']}}';
      expect(ZhihuishuService.parseCourseListJson(body), isNull);
    });

    test('code!=0 或非 JSON 返回 null（翻页据此置 listFailed，绝不当短页）', () {
      // 拒绝必须与「信封成功但没课」（空列表）区分：多页课表第 2 页被拒
      // 时若当短页处理，complete 误真、后续页课程的旧条目会被整批清掉
      expect(ZhihuishuService.parseCourseListJson('{"code":1}'), isNull);
      expect(ZhihuishuService.parseCourseListJson('oops'), isNull);
    });

    test('envelopeOk：code 数字 0 与字符串 "0" 都算成功信封', () {
      expect(ZhihuishuService.envelopeOk('{"code":0}'), isTrue);
      expect(ZhihuishuService.envelopeOk('{"code":"0"}'), isTrue);
      expect(ZhihuishuService.envelopeOk('{"code":1}'), isFalse);
      expect(ZhihuishuService.envelopeOk('not json'), isFalse);
    });

    test('真机信封：code=200 + result.courseOpenDtos（含 courseOpenId）', () {
      // 2026-10-04 真机日志实证的成功信封形态；courseOpenDtos 为 null
      // （无课）也必须解析成空列表而非失败
      final ok =
          '{"result":{"totalCount":0,"courseOpenDtos":null},'
          '"code":200,"message":null,"errMsg":null}';
      expect(ZhihuishuService.envelopeOk(ok), isTrue);
      expect(ZhihuishuService.parseCourseListJson(ok), isEmpty);

      final withCourse =
          '{"result":{"totalCount":1,"courseOpenDtos":['
          '{"courseName":"高等数学","courseOpenId":"100861"}]},"code":200}';
      final courses = ZhihuishuService.parseCourseListJson(withCourse)!;
      expect(courses, hasLength(1));
      expect(courses[0].name, '高等数学');
      expect(courses[0].courseId, '100861');
    });
  });

  group('候选端点锁定', () {
    test('endpointTryOrder：未命中按原序，命中后命中下标优先', () {
      expect(ZhihuishuService.endpointTryOrder(null), [0, 1, 2, 3, 4, 5]);
      expect(ZhihuishuService.endpointTryOrder(2), [2, 0, 1, 3, 4, 5]);
      expect(ZhihuishuService.endpointTryOrder(99), [0, 1, 2, 3, 4, 5]);
    });

    test('候选端点含校内课（school）网关变体：学分课作业通常在校内通道', () {
      expect(ZhihuishuService.homeworkEndpoints.length, 6);
      expect(
        ZhihuishuService.homeworkEndpoints.any((u) => u.contains('/school/')),
        isTrue,
      );
    });
  });

  group('签名拒收识别', () {
    test('aes 异常字样（大小写不敏感）与拦截器名 checkSecretStr 都判拒收', () {
      expect(
        ZhihuishuService.signatureRejectedBody(
          '{"code":400,"message":"aes加密参数异常"}',
        ),
        isTrue,
        reason: '真机日志实证的拒收字样',
      );
      expect(
        ZhihuishuService.signatureRejectedBody(
          '{"code":400,"message":"AES解密异常"}',
        ),
        isTrue,
      );
      expect(
        ZhihuishuService.signatureRejectedBody('checkSecretStr: fail'),
        isTrue,
      );
    });

    test('正常信封与普通业务错误不误判为签名拒收', () {
      expect(
        ZhihuishuService.signatureRejectedBody('{"code":0,"data":[]}'),
        isFalse,
      );
      expect(
        ZhihuishuService.signatureRejectedBody('{"code":401,"message":"未登录"}'),
        isFalse,
        reason: '会话失效是另一类，抓包前保守走「过期」口径',
      );
    });
  });

  group('secretStr 加密', () {
    test('三把密钥各自加密后都可同密钥解回（CBC/PKCS7/base64 形态）', () {
      const plain =
          '{"pageIndex":"1","pageSize":"1",'
          '"date":"2026-10-03T15:31:35.000Z"}';
      for (var ki = 0; ki < 3; ki++) {
        final cipher = ZhihuishuService.encryptSecret(plain, ki);
        expect(cipher, isNot(contains(plain)), reason: '不能是明文直出');
        expect(
          ZhihuishuService.decryptSecret(cipher, ki),
          plain,
          reason: '密钥 $ki 加密后必须能解回原文',
        );
      }
    });

    test('不同密钥加密同一明文产出不同密文；越界下标被钳回不炸', () {
      const plain = '{"pageIndex":"1"}';
      final a = ZhihuishuService.encryptSecret(plain, 0);
      final b = ZhihuishuService.encryptSecret(plain, 1);
      expect(a, isNot(b));
      expect(
        ZhihuishuService.decryptSecret(
          ZhihuishuService.encryptSecret(plain, 99),
          2,
        ),
        plain,
      );
    });
  });
}
