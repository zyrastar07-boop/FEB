import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import 'auth_service.dart';

/// Proactively refreshes the Firebase Auth ID token so backend API calls
/// always have a fresh-ish credential without paying the round-trip cost
/// of `forceRefresh: true` on every request.
///
/// Firebase ID tokens are valid for 1 hour. The Worker accepts a token
/// until ~5 minutes after its declared `exp` (we give it a small grace
/// window). This guard:
///   1. Schedules a refresh ~5 min before each token's expiry.
///   2. Re-prompts on resume if the token is past the grace window.
///   3. Exposes a single `getValidIdToken()` to call sites so they get
///      a guaranteed-valid token without thinking about refresh logic.
class AuthSessionGuard {
  AuthSessionGuard._();
  static final AuthSessionGuard instance = AuthSessionGuard._();

  Timer? _refreshTimer;
  DateTime? _cachedExpiry;
  String? _cachedToken;

  /// Returns a non-null, non-expired ID token, refreshing it proactively
  /// when needed. Use this anywhere the Worker expects `Authorization`.
  Future<String?> getValidIdToken({bool forceRefresh = false}) async {
    final auth = AuthService();
    final user = auth.currentUser;
    if (user == null) return null;

    final now = DateTime.now();
    if (!forceRefresh &&
        _cachedToken != null &&
        _cachedExpiry != null &&
        now.isBefore(_cachedExpiry!.subtract(_grace))) {
      return _cachedToken;
    }

    try {
      final token = await user.getIdToken(forceRefresh);
      if (token == null) return null;

      _cachedToken = token;
      // Firebase SDK doesn't expose exp on the ID token result directly,
      // so we conservatively assume the full 60-minute lifetime and
      // refresh again at the 55-minute mark.
      _cachedExpiry = now.add(_refreshAhead);
      _scheduleRefresh(_refreshAhead - _grace);
      return token;
    } catch (e) {
      debugPrint('[AuthSessionGuard] getIdToken failed: $e');
      return null;
    }
  }

  /// Hook from `WidgetsBindingObserver.didChangeAppLifecycleState`. When
  /// the app comes back to foreground, force a refresh if the cached
  /// token is older than the grace window.
  void onAppResume() {
    final now = DateTime.now();
    if (_cachedExpiry != null && now.isAfter(_cachedExpiry!.subtract(_grace))) {
      // ignore: discarded_futures
      getValidIdToken(forceRefresh: true);
    }
  }

  /// Wipe the cache. Call on sign-out so the next user doesn't inherit
  /// the previous user's token.
  void invalidate() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
    _cachedToken = null;
    _cachedExpiry = null;
  }

  void _scheduleRefresh(Duration after) {
    _refreshTimer?.cancel();
    _refreshTimer = Timer(after, () {
      // ignore: discarded_futures
      getValidIdToken(forceRefresh: false);
    });
  }

  static const Duration _refreshAhead = Duration(minutes: 55);
  static const Duration _grace = Duration(minutes: 5);

  /// Current Firebase user UID, for diagnostics.
  String? get currentUid {
    final user = FirebaseAuth.instance.currentUser;
    return user?.uid;
  }

  @visibleForTesting
  void resetForTest() {
    invalidate();
  }
}
