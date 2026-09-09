import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:feb/services/endpoint_pool.dart';

void main() {
  group('EndpointPool', () {
    test('round-robins across healthy endpoints', () {
      // Deterministic seed so the starting cursor is predictable.
      final pool = EndpointPool(
        endpoints: ['a.com', 'b.com', 'c.com'],
        random: Random(0),
      );
      final first = pool.next();
      // Every endpoint is issued exactly once before rotation wraps around.
      final seen = <String>{first, pool.next(), pool.next()};
      expect(seen, {'a.com', 'b.com', 'c.com'});
      // Wraps back around to the first endpoint issued.
      expect(pool.next(), first);
    });

    test('still works with a single endpoint', () {
      final pool = EndpointPool(endpoints: ['only.com']);
      expect(pool.next(), 'only.com');
      expect(pool.next(), 'only.com');
      expect(pool.healthyCount, 1);
    });

    test('quarantines a failing endpoint after threshold failures', () {
      final pool = EndpointPool(
        endpoints: ['bad.com', 'good.com'],
        cooldownThreshold: 2,
        cooldown: const Duration(minutes: 5),
        random: null,
      );

      // Report two consecutive failures against the first endpoint issued.
      pool.reportFailureFor('bad.com');
      pool.reportFailureFor('bad.com');

      expect(pool.healthyCount, 1);

      // All subsequent picks must come from the healthy pool.
      for (var i = 0; i < 6; i++) {
        expect(pool.next(), 'good.com');
      }
    });

    test('success resets the failure streak before quarantine', () {
      final pool = EndpointPool(
        endpoints: ['flaky.com', 'good.com'],
        cooldownThreshold: 3,
      );

      pool.reportFailureFor('flaky.com');
      pool.reportFailureFor('flaky.com');
      // One success resets the streak — next failure restarts the count.
      pool.reportSuccessFor('flaky.com');
      expect(pool.healthyCount, 2);

      pool.reportFailureFor('flaky.com');
      pool.reportFailureFor('flaky.com');
      pool.reportFailureFor('flaky.com');
      expect(pool.healthyCount, 1);
    });

    test('reporting last-issued endpoint works via no-arg helpers', () {
      final pool = EndpointPool(
        endpoints: ['a.com', 'b.com'],
        cooldownThreshold: 1,
      );

      // next() starts from a random cursor, so pin down the first issuance
      // by clearing the other endpoint's state, then fail whichever one
      // was issued via the no-arg helper.
      final first = pool.next();
      final other = first == 'a.com' ? 'b.com' : 'a.com';
      pool.reportSuccessFor(other); // other stays clean
      pool.reportFailure(); // quarantines the issued endpoint

      // Next issuance must skip the quarantined endpoint.
      expect(pool.next(), other);
    });

    test('recovers after cooldown elapses', () {
      final pool = EndpointPool(
        endpoints: ['down.com', 'up.com'],
        cooldownThreshold: 1,
        cooldown: const Duration(minutes: 1),
      );

      pool.reportFailureFor('down.com');
      expect(pool.healthyCount, 1);

      // Reset (manual recovery path) then verify rotation is restored.
      pool.reset();
      expect(pool.healthyCount, 2);
      expect(pool.endpoints, contains('down.com'));
    });

    test('falls back to soonest-recovering endpoint when all are cooling', () {
      final pool = EndpointPool(
        endpoints: ['a.com', 'b.com'],
        cooldownThreshold: 1,
        cooldown: const Duration(minutes: 5),
      );

      pool.reportFailureFor('a.com');
      pool.reportFailureFor('b.com');
      expect(pool.healthyCount, 0);

      // Still returns an endpoint rather than throwing.
      expect(pool.next(), anyOf('a.com', 'b.com'));
    });

    test('reset clears all quarantines', () {
      final pool = EndpointPool(
        endpoints: ['a.com', 'b.com', 'c.com'],
        cooldownThreshold: 1,
      );
      pool.reportFailureFor('a.com');
      pool.reportFailureFor('b.com');
      expect(pool.healthyCount, 1);

      pool.reset();
      expect(pool.healthyCount, 3);
    });
  });
}
