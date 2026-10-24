import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:homework_radar/services/async_limiter.dart';

void main() {
  test(
    'permits bound concurrency, preserve queued order and recover from errors',
    () async {
      final pool = AsyncLimiter(2);
      final gate = Completer<void>();
      final started = <int>[];
      var active = 0, maximum = 0;
      final jobs = [
        for (var i = 0; i < 6; i++)
          pool
              .run(() async {
                started.add(i);
                active++;
                if (active > maximum) maximum = active;
                try {
                  await gate.future;
                  if (i == 1) throw StateError('synthetic');
                  return i;
                } finally {
                  active--;
                }
              })
              .then<Object>((v) => v, onError: (Object e) => e),
      ];
      await Future<void>.delayed(Duration.zero);
      expect(started, [0, 1]);
      gate.complete();
      final results = await Future.wait(jobs);
      expect(started, [0, 1, 2, 3, 4, 5]);
      expect(maximum, 2);
      expect(results[1], isA<StateError>());
      expect(await pool.run(() async => 42), 42);
    },
  );
}
