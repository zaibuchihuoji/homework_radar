import 'dart:async';
import 'dart:collection';

/// FIFO permits; a failed request always releases its slot.
class AsyncLimiter {
  AsyncLimiter(this.capacity) : assert(capacity > 0);
  final int capacity;
  int _active = 0;
  final _waiting = Queue<Completer<void>>();

  Future<T> run<T>(Future<T> Function() action) async {
    if (_active < capacity) {
      _active++;
    } else {
      final ready = Completer<void>();
      _waiting.add(ready);
      await ready.future;
    }
    try {
      return await action();
    } finally {
      if (_waiting.isEmpty) {
        _active--;
      } else {
        _waiting.removeFirst().complete();
      }
    }
  }
}
