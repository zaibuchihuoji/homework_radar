// 教务配置：URL 规范化与旧版数据迁移。
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:homework_radar/services/jw_config.dart';
import 'package:homework_radar/services/secure_store.dart';
import 'package:homework_radar/services/storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    final secure = <String, String>{};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('homework_radar/platform'),
          (call) async {
            final args = (call.arguments as Map?) ?? {};
            final key = args['key'] as String?;
            switch (call.method) {
              case 'secureRead':
                return secure[key];
              case 'secureWrite':
                secure[key!] = args['value'] as String;
                return true;
              case 'secureDelete':
                secure.remove(key);
                return true;
              default:
                return null;
            }
          },
        );
  });
  test('normalizeUrl：补协议 / 去空白 / 拒绝非法域名', () {
    // 无协议输入默认按 https（抓取页打不开会自动回落 http）
    expect(
      JwStore.normalizeUrl(' jw.zzuli.edu.cn '),
      'https://jw.zzuli.edu.cn',
    );
    expect(
      JwStore.normalizeUrl('https://jiaowu.xxx.edu.cn/home'),
      'https://jiaowu.xxx.edu.cn/home',
    );
    expect(
      JwStore.normalizeUrl('http://jw.zzuli.edu.cn'),
      'http://jw.zzuli.edu.cn',
    );
    expect(JwStore.normalizeUrl('不是网址'), isNull);
    expect(JwStore.normalizeUrl(''), isNull);
    expect(JwStore.normalizeUrl('no-dot'), isNull);
  });

  test('save/load 往返', () async {
    SharedPreferences.setMockInitialValues({});
    await Storage.init();
    const cfg = JwConfig(name: '测试大学', url: 'http://jw.test.edu.cn/');
    await JwStore.save(cfg);
    final loaded = JwStore.load();
    expect(loaded?.name, '测试大学');
    expect(loaded?.url, 'http://jw.test.edu.cn/');
    expect(loaded?.host, 'jw.test.edu.cn');
  });

  test('迁移：老用户只有 zf_cookie 时默认郑州轻工业大学', () async {
    SharedPreferences.setMockInitialValues({});
    await Storage.init();
    // Cookie 已迁入安全存储；测试环境没有原生通道，直接写缓存
    await SecureStore.write('zf_cookie', 'a=b');
    final cfg = JwStore.load();
    expect(cfg, isNotNull);
    expect(cfg!.name, '郑州轻工业大学');
    expect(cfg.url, 'http://jiaowu.zzuli.edu.cn');
  });

  test('全新用户：无配置返回 null', () async {
    SharedPreferences.setMockInitialValues({});
    await Storage.init();
    // SecureStore 缓存是进程级的，清掉前一个测试种下的凭据
    await SecureStore.delete('zf_cookie');
    expect(JwStore.load(), isNull);
    expect(JwStore.hasConfig, isFalse);
  });

  test('显式删除过的配置不复活（即便教务 Cookie 还在）', () async {
    SharedPreferences.setMockInitialValues({});
    await Storage.init();
    await SecureStore.write('zf_cookie', 'a=b');
    await JwStore.save(
      const JwConfig(name: '测试大学', url: 'http://jw.test.edu.cn/'),
    );
    await JwStore.clear();
    // 此前删除后 load() 一看 zf_cookie 非空就把配置弹回默认学校，删除形同虚设
    expect(JwStore.load(), isNull);
    expect(JwStore.hasConfig, isFalse);
  });

  test('损坏的配置 JSON 不致命', () async {
    SharedPreferences.setMockInitialValues({'jw_config': '{oops'});
    await Storage.init();
    await SecureStore.write('zf_cookie', 'a=b');
    final cfg = JwStore.load();
    // 配置损坏 → 落回迁移默认
    expect(cfg?.url, 'http://jiaowu.zzuli.edu.cn');
  });
}
