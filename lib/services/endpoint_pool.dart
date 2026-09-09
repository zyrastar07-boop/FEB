import 'dart:math';

/// Load-balancing pool of base-URL endpoints.
///
/// Distributes requests across multiple mirrors in round-robin order while
/// tracking health: an endpoint that fails [cooldownThreshold] times in a row
/// is quarantined for [cooldown], then automatically re-enters rotation.
/// This gives the app resilience when the primary Cloudflare Worker is down
/// or rate-limited — calls transparently fall over to the next healthy mirror.
class EndpointPool {
  EndpointPool({
    required List<String> endpoints,
    this.cooldownThreshold = 2,
    this.cooldown = const Duration(minutes: 2),
    Random? random,
  })  : _endpoints = List.of(endpoints),
        _random = random ?? Random() {
    if (_endpoints.isEmpty) {
      throw ArgumentError('EndpointPool requires at least one endpoint');
    }
    _healthy = List<bool>.filled(_endpoints.length, true);
    _consecutiveFailures = List<int>.filled(_endpoints.length, 0);
    _cooldownUntil = List<DateTime?>.filled(_endpoints.length, null);
    _cursor = _random.nextInt(_endpoints.length);
  }

  final List<String> _endpoints;
  final int cooldownThreshold;
  final Duration cooldown;
  final Random _random;

  late List<bool> _healthy;
  late List<int> _consecutiveFailures;
  late List<DateTime?> _cooldownUntil;
  late int _cursor;

  int _lastIssued = -1;

  /// All configured endpoints (mirrors + primary).
  List<String> get endpoints => List.unmodifiable(_endpoints);

  /// Number of endpoints currently considered healthy (not cooling down).
  int get healthyCount => _healthy.where((h) => h).length;

  /// Picks the next endpoint to use, round-robin over healthy nodes.
  ///
  /// If every node is cooling down, the one closest to recovery wins so
  /// requests still have somewhere to go instead of hard-failing.
  String next() {
    _refreshCooldowns();

    // Find all healthy indices, start scanning from the cursor.
    final n = _endpoints.length;
    final healthyIndices = <int>[];
    for (var i = 0; i < n; i++) {
      if (_healthy[i]) healthyIndices.add(i);
    }

    if (healthyIndices.isNotEmpty) {
      // Advance cursor to the first healthy index at/after current position.
      int chosen = -1;
      for (final idx in healthyIndices) {
        if (idx >= _cursor) {
          chosen = idx;
          break;
        }
      }
      if (chosen == -1) chosen = healthyIndices.first;
      _cursor = (chosen + 1) % n;
      _lastIssued = chosen;
      return _endpoints[chosen];
    }

    // Everything cooling down — use the one that recovers soonest.
    int best = 0;
    DateTime? bestUntil = _cooldownUntil[0];
    for (var i = 1; i < n; i++) {
      final until = _cooldownUntil[i];
      if (until != null && (bestUntil == null || until.isBefore(bestUntil))) {
        best = i;
        bestUntil = until;
      }
    }
    _cursor = (best + 1) % n;
    _lastIssued = best;
    return _endpoints[best];
  }

  /// Reports success for the most recently issued endpoint.
  void reportSuccess() {
    if (_lastIssued >= 0 && _lastIssued < _endpoints.length) {
      reportSuccessFor(_endpoints[_lastIssued]);
    }
  }

  /// Reports failure for the most recently issued endpoint.
  void reportFailure() {
    if (_lastIssued >= 0 && _lastIssued < _endpoints.length) {
      reportFailureFor(_endpoints[_lastIssued]);
    }
  }

  /// Report a successful request against [endpoint] — resets its failure
  /// streak so a recovering mirror is trusted again.
  void reportSuccessFor(String endpoint) {
    final i = _endpoints.indexOf(endpoint);
    if (i == -1) return;
    _consecutiveFailures[i] = 0;
    _cooldownUntil[i] = null;
    _healthy[i] = true;
  }

  /// Report a failed request against [endpoint]. After [cooldownThreshold]
  /// consecutive failures the endpoint is quarantined for [cooldown].
  void reportFailureFor(String endpoint) {
    final i = _endpoints.indexOf(endpoint);
    if (i == -1) return;
    _consecutiveFailures[i] += 1;
    if (_consecutiveFailures[i] >= cooldownThreshold) {
      _healthy[i] = false;
      _cooldownUntil[i] = DateTime.now().add(cooldown);
    }
  }

  /// Manually re-enable every endpoint (e.g. after connectivity restored).
  void reset() {
    for (var i = 0; i < _endpoints.length; i++) {
      _healthy[i] = true;
      _consecutiveFailures[i] = 0;
      _cooldownUntil[i] = null;
    }
  }

  void _refreshCooldowns() {
    final now = DateTime.now();
    for (var i = 0; i < _endpoints.length; i++) {
      final until = _cooldownUntil[i];
      if (until != null && !until.isAfter(now)) {
        _healthy[i] = true;
        _consecutiveFailures[i] = 0;
        _cooldownUntil[i] = null;
      }
    }
  }
}