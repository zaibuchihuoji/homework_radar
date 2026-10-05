// SafeHttp.validate 白名单纯函数：整个请求安全模型的唯一闸门（#221）。
// 纯函数零依赖，直接穷举放行/拒绝两侧行为，防止后续改动悄悄打穿。
import 'package:flutter_test/flutter_test.dart';
import 'package:homework_radar/services/safe_http.dart';

void main() {
  group('validate 放行', () {
    test('三个平台域及其子域', () {
      expect(SafeHttp.validate('https://mooc1.chaoxing.com/x'), isNotNull);
      expect(SafeHttp.validate('http://passport2.chaoxing.com/login'), isNotNull);
      expect(SafeHttp.validate('https://www.icourse163.org/home.htm'), isNotNull);
      expect(SafeHttp.validate('https://www.zhihuishu.com/x'), isNotNull);
    });
    test('教务域允许 http（校内老系统约束，手输默认 https 另有回落）', () {
      expect(SafeHttp.validate('http://jiaowu.zzuli.edu.cn/'), isNotNull);
      expect(SafeHttp.validate('https://jw.zzuli.edu.cn/'), isNotNull);
    });
    test('裸域本身也放行（host == 后缀）', () {
      expect(SafeHttp.validate('https://chaoxing.com/'), isNotNull);
      expect(SafeHttp.validate('https://icourse163.org/'), isNotNull);
    });
  });

  group('validate 拒绝', () {
    test('非 http(s) 协议', () {
      expect(SafeHttp.validate('ftp://mooc1.chaoxing.com/x'), isNull);
      expect(SafeHttp.validate('javascript:alert(1)'), isNull);
      expect(SafeHttp.validate('file:///etc/passwd'), isNull);
    });

    test('保留主机名与本地/私有网段', () {
      expect(SafeHttp.validate('http://localhost/x'), isNull);
      expect(SafeHttp.validate('http://a.localhost/x'), isNull);
      expect(SafeHttp.validate('http://example.com/x'), isNull);
      expect(SafeHttp.validate('http://127.0.0.1/x'), isNull);
      expect(SafeHttp.validate('http://192.168.1.1/x'), isNull);
      expect(SafeHttp.validate('http://10.0.0.1/x'), isNull);
      expect(SafeHttp.validate('http://[::1]/x'), isNull);
    });

    test('伪装域（后缀拼接/前缀粘连）不越权放行', () {
      expect(SafeHttp.validate('https://chaoxing.com.evil.com/'), isNull,
          reason: 'allowedSuffix 必须按域边界匹配，不能 endsWith 裸串');
      expect(SafeHttp.validate('https://evichaoxing.com/'), isNull);
      expect(SafeHttp.validate('https://icourse163.org.cn/'), isNull,
          reason: '相近公共后缀不算白名单域');
      expect(SafeHttp.validate('https://zzuli.edu.cn.evil.com/'), isNull);
    });

    test('无法解析 / 空 host / IPv6 字面量', () {
      expect(SafeHttp.validate('not a url'), isNull);
      expect(SafeHttp.validate('https:///path'), isNull);
      expect(SafeHttp.validate(''), isNull);
    });
  });
}
