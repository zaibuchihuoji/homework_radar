import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:homework_radar/services/chaoxing_service.dart';

import 'support/loopback_http.dart';

// Production still supplies its original HTTPS URLs to this client. Only the
// local test transport uses cleartext so the existing loopback HTTP server can
// inspect real HttpClient requests without certificates or external networking.
class _LoopbackTransport extends LoopbackHttp {
  final targets = <Uri>[];

  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      _PlaintextClient(super.createHttpClient(context), targets);
}

class _PlaintextClient implements HttpClient {
  _PlaintextClient(this.client, this.targets);
  final HttpClient client;
  final List<Uri> targets;

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) {
    targets.add(url);
    return client.openUrl(method, url.replace(scheme: 'http'));
  }

  @override
  set connectionTimeout(Duration? value) => client.connectionTimeout = value;

  @override
  void close({bool force = false}) => client.close(force: force);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final network = _LoopbackTransport();
  const cookie = 'UID=123; _uid=123; synthetic_session=cx-private';
  const courseUrl = 'https://mooc1.chaoxing.com/course';
  const workHtml =
      '<div class="ulDiv"><li><div class="titTxt">'
      '<a data="8">Synthetic task</a></div></li></div>';
  String courses(String href) =>
      '<li class="course"><a href="$href">'
      '<span class="course-name">Synthetic course</span></a></li>';
  String params({String? examUrl}) =>
      '<input id="courseid" value="1">'
      '<input id="clazzid" value="2"><input id="oldenc" value="old">'
      '<input id="enc" value="plain"><input id="t" value="123">'
      '${examUrl == null ? '' : '<li dataname="ks"><a data-url="$examUrl"></a></li>'}';

  setUpAll(() async {
    await network.start();
    HttpOverrides.global = network;
  });
  setUp(() {
    network.requests.clear();
    network.targets.clear();
  });
  tearDownAll(() async {
    await network.close();
    HttpOverrides.global = null;
  });

  for (final destination in [
    'https://github.com/landing',
    'https://www.icourse163.org/landing',
    'http://mooc1.chaoxing.com/landing',
  ]) {
    test(
      'course redirect cannot reattach CX credentials to $destination',
      () async {
        network.handler = (request) {
          if (request.uri.path.endsWith('/courses/list')) {
            return LoopbackResponse(courses(courseUrl));
          }
          if (request.uri.path == '/course') {
            return LoopbackResponse('', 302, {'location': destination});
          }
          return LoopbackResponse(params());
        };
        final service = ChaoxingService(cookie: cookie);
        await service.allHomework();
        expect(network.targets.where((u) => u.path == '/landing'), isEmpty);
        expect(service.failedCount, greaterThan(0));
        expect(network.requests.first.headers['cookie'], cookie);
      },
    );

    test(
      'course link cannot send CX credentials directly to $destination',
      () async {
        network.handler = (request) =>
            request.uri.path.endsWith('/courses/list')
            ? LoopbackResponse(courses(destination))
            : LoopbackResponse(params());
        final service = ChaoxingService(cookie: cookie);
        await service.allHomework();
        expect(network.targets.where((u) => u.path == '/landing'), isEmpty);
        expect(service.failedCount, greaterThan(0));
      },
    );

    test('exam data-url cannot send CX credentials to $destination', () async {
      network.handler = (request) {
        if (request.uri.path.endsWith('/courses/list')) {
          return LoopbackResponse(courses(courseUrl));
        }
        if (request.uri.path == '/course') {
          return LoopbackResponse(params(examUrl: destination));
        }
        if (request.uri.path.contains('getAllWork')) {
          return LoopbackResponse(workHtml);
        }
        return LoopbackResponse('<div class="bottomList"><ul></ul></div>');
      };
      final service = ChaoxingService(cookie: cookie);
      final items = await service.allHomework();
      expect(items.single.title, 'Synthetic task');
      expect(network.targets.where((u) => u.path == '/landing'), isEmpty);
      expect(service.failedCount, greaterThan(0));
    });
  }

  for (final destination in [
    '/landing',
    'https://mooc1.chaoxing.com/landing',
    'https://mooc2-ans.chaoxing.com/landing',
  ]) {
    test(
      'valid CX redirect $destination preserves the session and homework',
      () async {
        network.handler = (request) {
          if (request.uri.path.endsWith('/courses/list')) {
            return LoopbackResponse(courses(courseUrl));
          }
          if (request.uri.path == '/course') {
            return LoopbackResponse('', 302, {'location': destination});
          }
          if (request.uri.path == '/landing') return LoopbackResponse(params());
          if (request.uri.path.contains('getAllWork')) {
            return LoopbackResponse(workHtml);
          }
          return LoopbackResponse('<div class="bottomList"><ul></ul></div>');
        };
        final service = ChaoxingService(cookie: cookie);
        final items = await service.allHomework();
        expect(items.single.title, 'Synthetic task');
        expect(service.failedCount, 0);
        expect(
          network.requests
              .singleWhere((r) => r.uri.path == '/landing')
              .headers['cookie'],
          cookie,
        );
        expect(network.targets.every((u) => u.scheme == 'https'), isTrue);
      },
    );
  }
}
