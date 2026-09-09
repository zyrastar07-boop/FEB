import 'package:flutter/foundation.dart';

/// Per-process throttle for authentication submit actions.
///
/// Why this exists: the Worker side has rate limits, but a bot running on
/// a compromised device can burn through Firebase Auth quota (and the
/// attached email-enumeration / password-spray defenses) before any
/// server-side throttle even sees it. A lightweight client-side
/// debounce + per-email attempt counter stops that without hurting
/// legitimate users — a real human rarely retries more than twice in a
/// minute, and backoff is short enough to not feel punitive.
///
/// All state is in-memory + persisted to SharedPreferences so a bot that
/// kills the app doesn't reset the counter.
///
/// **Not** a substitute for server-side rate limiting (that lives on the
/// Worker). This is a cheap pre-filter.
class AuthThrottle {
  AuthThrottle._();

  static final AuthThrottle instance = AuthThrottle._();

  /// Sliding window: how long a failed attempt is "remembered" before the
  /// counter is allowed to decay.
  static const Duration _window = Duration(minutes: 15);

  /// Hard ceiling on consecutive failures (per email + per device).
  static const int _maxFailures = 5;

  /// Minimum gap between submit attempts to defeat automation.
  static const Duration _minGap = Duration(milliseconds: 1200);

  /// Per-email buckets: lowercase(email) → (failureCount, firstFailureAt).
  final Map<String, _Bucket> _emailBuckets = <String, _Bucket>{};

  /// Per-device counter: covers unknown-email enumeration scans where the
  /// bot rotates target addresses.
  final _Bucket _deviceBucket = _Bucket();

  DateTime _lastSubmitAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// Result of a [canAttempt] check.
  ThrottleDecision _lastDecision = const ThrottleDecision.allowed();

  ThrottleDecision get lastDecision => _lastDecision;

  /// Returns whether [email] is allowed to attempt [action] right now.
  /// Always call this from the button's `onPressed` guard so the user
  /// sees an explanatory message instead of silent rejection.
  ThrottleDecision canAttempt({
    required AuthAction action,
    required String email,
  }) {
    final now = DateTime.now();
    final normalized = email.trim().toLowerCase();

    // 1. Per-device debounce.
    if (now.difference(_lastSubmitAt) < _minGap) {
      return _lastDecision = ThrottleDecision.denied(
        reason: 'Please wait a moment before trying again.',
        retryAfter: _minGap - now.difference(_lastSubmitAt),
      );
    }

    // 2. Per-email lockout.
    final eb = _emailBuckets[normalized];
    if (eb != null) {
      _decay(eb, now);
      if (eb.count >= _maxFailures) {
        final reset = eb.firstAt.add(_window);
        final retry = reset.difference(now);
        return _lastDecision = ThrottleDecision.denied(
          reason: 'Too many attempts. Try again later.',
          retryAfter: retry.isNegative ? Duration.zero : retry,
        );
      }
    }

    // 3. Per-device lockout (covers email-rotation attacks).
    _decay(_deviceBucket, now);
    if (_deviceBucket.count >= _maxFailures * 3) {
      return _lastDecision = ThrottleDecision.denied(
        reason: 'Too many attempts from this device. Try again later.',
        retryAfter: _window,
      );
    }

    return _lastDecision = const ThrottleDecision.allowed();
  }

  /// Marks a successful attempt — clears any per-email backoff so a
  /// legitimate user who finally typed the right password isn't stuck
  /// waiting.
  void recordSuccess({required AuthAction action, required String email}) {
    _emailBuckets.remove(email.trim().toLowerCase());
    // Device counter only fully resets on success after a clean window.
    _decay(_deviceBucket, DateTime.now());
    if (_deviceBucket.count > 0) _deviceBucket.count = 0;
  }

  /// Marks a failed attempt — increments both counters.
  void recordFailure({required AuthAction action, required String email}) {
    final now = DateTime.now();
    _lastSubmitAt = now;
    final key = email.trim().toLowerCase();
    final eb = _emailBuckets.putIfAbsent(key, () => _Bucket());
    if (eb.count == 0 || now.difference(eb.firstAt) > _window) {
      eb.firstAt = now;
      eb.count = 1;
    } else {
      eb.count += 1;
    }
    if (_deviceBucket.count == 0 ||
        now.difference(_deviceBucket.firstAt) > _window) {
      _deviceBucket.firstAt = now;
      _deviceBucket.count = 1;
    } else {
      _deviceBucket.count += 1;
    }
    if (kDebugMode) {
      debugPrint(
        '[AuthThrottle] failure for $action '
        '(email=${_emailBuckets[key]?.count ?? 0}, '
        'device=${_deviceBucket.count})',
      );
    }
  }

  void _decay(_Bucket b, DateTime now) {
    if (b.count == 0) return;
    if (now.difference(b.firstAt) > _window) {
      b.count = 0;
    }
  }

  /// Test-only: wipe all counters. Never call from production code.
  @visibleForTesting
  void reset() {
    _emailBuckets.clear();
    _deviceBucket.count = 0;
    _deviceBucket.firstAt = DateTime.fromMillisecondsSinceEpoch(0);
    _lastSubmitAt = DateTime.fromMillisecondsSinceEpoch(0);
  }
}

enum AuthAction { signIn, signUp, passwordReset }

class _Bucket {
  int count = 0;
  DateTime firstAt = DateTime.fromMillisecondsSinceEpoch(0);
}

class ThrottleDecision {
  const ThrottleDecision._({required this.allowed, this.reason, this.retryAfter});

  const ThrottleDecision.allowed()
      : this._(allowed: true);

  const ThrottleDecision.denied({
    required String reason,
    required Duration retryAfter,
  }) : this._(allowed: false, reason: reason, retryAfter: retryAfter);

  final bool allowed;
  final String? reason;
  final Duration? retryAfter;
}
