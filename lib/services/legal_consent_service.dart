import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Tracks the user's one-time acceptance of the Terms of Service and
/// Privacy Policy.
///
/// The flag is stored locally (SharedPreferences). Until it is set, the
/// [LegalConsentGate] widget blocks app usage. This is an acceptance *record*
/// only — it is deliberately NOT a security boundary, so it is kept as a
/// plain boolean and never gated behind encryption (a user resetting the
/// flag should simply be prompted again).
class LegalConsentService {
  LegalConsentService._();
  static final LegalConsentService instance = LegalConsentService._();

  static const String _key = 'legal_consent_accepted_v1';

  /// Whether the user has accepted the ToS + Privacy Policy.
  Future<bool> hasAccepted() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_key) ?? false;
  }

  /// Records acceptance. Idempotent.
  Future<void> accept() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, true);
  }

  /// Test hook: clears the stored flag.
  @visibleForTesting
  static Future<void> resetForTest() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}