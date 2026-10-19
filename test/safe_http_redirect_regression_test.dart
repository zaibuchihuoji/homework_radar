import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:homework_radar/services/safe_http.dart';

import 'support/loopback_http.dart';

void main() {
  final network = LoopbackHttp();
  setUpAll(() async {
    await network.start();
    HttpOverrides.global = network;
  });
  setUp(() => network.requests.clear());
  tearDownAll(() async {
    await network.close();
    HttpOverrides.global = null;
  });

  for (final method in ['get', 'form', 'json']) {
    for (final destination in [
      'http://localhost/landing',
      'http://127.0.0.1/landing',
      'http://outside.invalid/landing',
    ]) {
      test('$method rejects redirect to $destination before requesting it', () async {
        network.handler = (request) => request.uri.path == '/start'
            ? LoopbackResponse('', method == 'get' ? 302 : 303,
                {'location': destination})
            : LoopbackResponse('forbidden landing was requested');
        final response = switch (method) {
          'get' => await SafeHttp.get('http://www.icourse163.org/start'),
          'form' => await SafeHttp.postForm('http://www.icourse163.org/start',
              body: {'synthetic_secret': 'form-value'}),
          _ => await SafeHttp.postJson('http://www.icourse163.org/start',
              body: '{"synthetic_secret":"json-value"}'),
        };
        expect(response, isNull);
        expect(network.requests.map((request) => request.uri.host),
            ['www.icourse163.org']);
      });
    }
  }

  test('every hop is checked, including a relative then forbidden redirect', () async {
    network.handler = (request) => switch (request.uri.path) {
      '/start' => LoopbackResponse('', 302, {'location': '/next'}),
      '/next' => LoopbackResponse('', 302,
          {'location': 'http://localhost/landing'}),
      _ => LoopbackResponse('forbidden'),
    };
    expect(await SafeHttp.get('http://www.icourse163.org/start'), isNull);
    expect(network.requests.map((request) => request.uri.path), ['/start', '/next']);
  });

  test('same-origin relative redirect retains session headers', () async {
    network.handler = (request) => request.uri.path == '/start'
        ? LoopbackResponse('', 302, {'location': '/next'})
        : LoopbackResponse('ok');
    final response = await SafeHttp.get('http://www.icourse163.org/start',
        headers: {'Cookie': 'synthetic=session', 'X-CSRFToken': 'synthetic-csrf'});
    expect(response!.body, 'ok');
    expect(network.requests.last.headers['cookie'], 'synthetic=session');
    expect(network.requests.last.headers['x-csrftoken'], 'synthetic-csrf');
  });

  test('allowed cross-origin redirect drops custom credentials and referrer', () async {
    network.handler = (request) => request.uri.path == '/start'
        ? LoopbackResponse('', 302,
            {'location': 'http://www.chaoxing.com/landing'})
        : LoopbackResponse('ok');
    final response = await SafeHttp.get('http://www.icourse163.org/start', headers: {
      'Cookie': 'synthetic=session',
      'Authorization': 'Bearer synthetic',
      'X-CSRFToken': 'synthetic-csrf',
      'Referer': 'http://www.icourse163.org/private?synthetic=value',
    });
    expect(response!.body, 'ok');
    final forwarded = network.requests.last.headers;
    expect(forwarded['cookie'], isNull);
    expect(forwarded['authorization'], isNull);
    expect(forwarded['x-csrftoken'], isNull);
    expect(forwarded['referer'], isNull);
  });

  for (final method in ['form', 'json']) {
    test('$method cross-origin 303 sends GET without the sensitive body', () async {
      network.handler = (request) => request.uri.path == '/start'
          ? LoopbackResponse('', 303,
              {'location': 'http://www.chaoxing.com/landing'})
          : LoopbackResponse('ok');
      final response = method == 'form'
          ? await SafeHttp.postForm('http://www.icourse163.org/start',
              body: {'synthetic_secret': 'value'})
          : await SafeHttp.postJson('http://www.icourse163.org/start',
              body: '{"synthetic_secret":"value"}');
      expect(response!.body, 'ok');
      expect(network.requests.last.method, 'GET');
      expect(network.requests.last.body, isEmpty);
    });

    test('$method 307 does not replay a sensitive POST body', () async {
      network.handler = (_) => LoopbackResponse('', 307,
          {'location': 'http://www.chaoxing.com/landing'});
      final response = method == 'form'
          ? await SafeHttp.postForm('http://www.icourse163.org/start',
              body: {'synthetic_secret': 'value'})
          : await SafeHttp.postJson('http://www.icourse163.org/start',
              body: '{"synthetic_secret":"value"}');
      expect(response!.statusCode, 307);
      expect(network.requests, hasLength(1));
    });
  }

  test('followRedirects false returns the redirect without following it', () async {
    network.handler = (_) => LoopbackResponse('', 302,
        {'location': 'http://localhost/landing'});
    final response = await SafeHttp.get('http://www.icourse163.org/start',
        followRedirects: false);
    expect(response!.statusCode, 302);
    expect(network.requests, hasLength(1));
  });

  test('redirect loops terminate within the limit', () async {
    network.handler = (_) => LoopbackResponse('', 302, {'location': '/start'});
    expect(await SafeHttp.get('http://www.icourse163.org/start'), isNull);
    expect(network.requests.length, lessThanOrEqualTo(6));
  });
}
