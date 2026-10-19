import 'dart:async';
import 'dart:convert';
import 'dart:io';

typedef SyntheticHandler = FutureOr<SyntheticResponse> Function(
  String method,
  Uri uri,
  String body,
);

class SyntheticResponse {
  final String body;
  final int status;
  final Map<String, String> headers;
  SyntheticResponse(this.body, [this.status = 200, this.headers = const {}]);
}

/// Replaces the socket boundary only: all production URL, request, parsing and
/// completeness logic still runs, with no connection to a real account/server.
class SyntheticHttp extends HttpOverrides {
  SyntheticHandler handler = (_, _, _) =>
      throw StateError('Unexpected request');
  @override
  HttpClient createHttpClient(SecurityContext? context) => _Client(this);
}

class _Client implements HttpClient {
  _Client(this.owner);
  final SyntheticHttp owner;
  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async =>
      _Request(owner, method, url);
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _Headers implements HttpHeaders {
  _Headers([Map<String, String> values = const {}]) : values = {...values};
  final Map<String, String> values;
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {
    values[name] = '$value';
  }

  @override
  void forEach(void Function(String, List<String>) action) {
    values.forEach((key, value) => action(key, [value]));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _Request implements HttpClientRequest {
  _Request(this.owner, this.method, this.uri);
  final SyntheticHttp owner;
  @override
  final String method;
  @override
  final Uri uri;
  final List<int> bytes = [];
  @override
  final HttpHeaders headers = _Headers();
  @override
  Future<void> addStream(Stream<List<int>> stream) async {
    await for (final chunk in stream) {
      bytes.addAll(chunk);
    }
  }

  @override
  Future<HttpClientResponse> close() async =>
      _Response(await owner.handler(method, uri, utf8.decode(bytes)));
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _Response extends Stream<List<int>> implements HttpClientResponse {
  _Response(this.response);
  final SyntheticResponse response;
  @override
  int get statusCode => response.status;
  @override
  int get contentLength => utf8.encode(response.body).length;
  @override
  HttpHeaders get headers => _Headers(response.headers);
  @override
  bool get isRedirect => statusCode >= 300 && statusCode < 400;
  @override
  List<RedirectInfo> get redirects => [];
  @override
  bool get persistentConnection => true;
  @override
  String get reasonPhrase => 'Synthetic';
  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => Stream.value(utf8.encode(response.body)).listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
