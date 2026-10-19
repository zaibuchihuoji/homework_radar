import 'dart:async';
import 'dart:convert';
import 'dart:io';

class LoopbackRequest {
  LoopbackRequest(this.method, this.uri, this.body, this.headers);
  final String method;
  final Uri uri;
  final String body;
  final Map<String, String> headers;
}

class LoopbackResponse {
  LoopbackResponse(this.body, [this.status = 200, this.headers = const {}]);
  final String body;
  final int status;
  final Map<String, String> headers;
}

/// Executes the actual Dart HttpClient redirect implementation. The connection
/// factory routes every destination to our own loopback server, without DNS or
/// any socket connection to the URL's real host.
class LoopbackHttp extends HttpOverrides {
  late HttpServer _server;
  final _clients = <HttpClient>[];
  final requests = <LoopbackRequest>[];
  FutureOr<LoopbackResponse> Function(LoopbackRequest) handler =
      (_) => LoopbackResponse('Unexpected request', 500);

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server.listen((request) async {
      final headers = <String, String>{};
      request.headers.forEach((key, values) => headers[key] = values.join(','));
      final captured = LoopbackRequest(
        request.method,
        Uri.parse('http://${request.headers.value('host')}${request.uri}'),
        await utf8.decoder.bind(request).join(),
        headers,
      );
      requests.add(captured);
      final response = await handler(captured);
      request.response
        ..statusCode = response.status
        ..persistentConnection = false;
      response.headers.forEach(request.response.headers.set);
      request.response.write(response.body);
      await request.response.close();
    });
  }

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    client.findProxy = (_) => 'DIRECT';
    client.connectionFactory = (_, _, _) =>
        Socket.startConnect(InternetAddress.loopbackIPv4, _server.port);
    _clients.add(client);
    return client;
  }

  Future<void> close() async {
    for (final client in _clients) {
      client.close(force: true);
    }
    await _server.close(force: true);
  }
}
