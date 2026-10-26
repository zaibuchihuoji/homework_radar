import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:homework_radar/services/chaoxing_service.dart';
import 'package:homework_radar/services/xuetangx_service.dart';

import 'support/synthetic_http.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final network = SyntheticHttp();
  setUpAll(() => HttpOverrides.global = network);
  tearDownAll(() => HttpOverrides.global = null);

  for (final entry in [
    (200, '{"result": 1}', true),
    (200, '{\n  "result" : 1\n}', true),
    (200, '{"result":0}', false),
    (200, '<html>Service unavailable</html>', null),
    (200, '{"message":"unknown"}', null),
    (429, '{}', null),
    (503, '{}', null),
    (401, '{}', false),
    (403, '{}', false),
  ]) {
    test(
      'CX login result ${entry.$1} ${entry.$2} preserves auth/network distinction',
      () async {
        network.handler = (_, _, _) => SyntheticResponse(entry.$2, entry.$1);
        expect(
          await ChaoxingService(cookie: 'synthetic').checkLogin(),
          entry.$3,
        );
      },
    );
  }

  for (final status in [401, 503]) {
    test(
      'XT final session $status prevents authoritative cleanup after a healthy catalog',
      () async {
        var probes = 0;
        network.handler = (_, uri, _) {
          if (uri.queryParameters['status'] == '1' &&
              uri.queryParameters['page'] == '1' &&
              ++probes == 3) {
            return SyntheticResponse('unavailable', status);
          }
          return SyntheticResponse(
            jsonEncode({
              'success': true,
              'data': {'product_list': []},
            }),
          );
        };
        final service = XuetangxService(cookie: 'synthetic');
        await service.allHomework();
        expect(service.listFailed, isTrue);
        expect(
          service.lastSessionState,
          status == 401 ? XtSessionState.expired : XtSessionState.unknown,
        );
      },
    );
  }
}
