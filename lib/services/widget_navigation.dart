import 'dart:async';

class WidgetDestination {
  const WidgetDestination(this.tab, [this.homeworkId]);
  final int tab;
  final String? homeworkId;

  static WidgetDestination? parse(Uri? uri) {
    if (uri == null ||
        uri.scheme != 'homework-radar' ||
        uri.host != 'widget' ||
        (uri.queryParametersAll['id']?.length ?? 0) > 1) {
      return null;
    }
    if (uri.path == '/timetable') return const WidgetDestination(1);
    if (uri.path != '/homework') return null;
    final id = uri.queryParameters['id'];
    return WidgetDestination(0, id == null || id.isEmpty ? null : id);
  }
}

/// Keep clicks arriving during the splash, and never let a delayed initial
/// intent overwrite a newer tap. This channel only navigates; it never writes data.
class WidgetNavigation {
  WidgetNavigation({required this.onDestination});
  final void Function(WidgetDestination) onDestination;
  StreamSubscription<Uri?>? _subscription;
  WidgetDestination? _pending;
  bool _ready = false, _disposed = false;
  int _events = 0;

  Future<void> bind(Future<Uri?> initial, Stream<Uri?> clicks) async {
    final before = _events;
    _subscription = clicks.listen((uri) {
      _events++;
      _accept(uri);
    }, onError: (Object _) {});
    try {
      final uri = await initial;
      if (!_disposed && _events == before) _accept(uri);
    } catch (_) {
      // Unsupported platforms and unavailable widget plugins still open normally.
    }
  }

  void _accept(Uri? uri) {
    if (_disposed) return;
    final destination = WidgetDestination.parse(uri);
    if (destination == null) return;
    _pending = destination;
    _flush();
  }

  void setReady() {
    _ready = true;
    _flush();
  }

  void _flush() {
    if (!_ready || _disposed) return;
    final destination = _pending;
    _pending = null;
    if (destination != null) onDestination(destination);
  }

  Future<void> dispose() async {
    _disposed = true;
    _pending = null;
    await _subscription?.cancel();
  }
}
