import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../utils/input_sanitizer.dart';
import 'auth_session_guard.dart';

class AuthService {
  // Singleton pattern
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  /// Google OAuth Web client ID. Read from build-time `--dart-define
  /// GOOGLE_WEB_CLIENT_ID=…` (see `.env.example`). The OAuth client ID is a
  /// public identifier (not a secret); the security boundary is the OAuth
  /// redirect-URI / package-hash allowlist configured in Google Cloud
  /// Console, not the obscurity of this string.
  static const String _googleWebClientId = String.fromEnvironment(
    'GOOGLE_WEB_CLIENT_ID',
    defaultValue:
        '341624343876-5qpngd647trkoephibjfp1md4q42llss.apps.googleusercontent.com',
  );

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    serverClientId: _googleWebClientId,
  );

  /// Current Firebase User
  User? get currentUser => _auth.currentUser;

  /// Wait for Firebase Auth to complete initial state check
  Future<User?> getCurrentUserSession() async {
    return await _auth.authStateChanges().first;
  }

  /// Auth state change listener stream
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  // ---------------------------------------------------------
  // NEW: Get the Firebase ID Token for Cloudflare Worker API Calls
  //
  // Delegates to AuthSessionGuard so the token is refreshed proactively
  // (no per-request `forceRefresh: true` round-trip), cached for the
  // ~55-min useful window, and invalidated on sign-out.
  // ---------------------------------------------------------
  Future<String?> getIdToken({bool forceRefresh = false}) {
    return AuthSessionGuard.instance.getValidIdToken(forceRefresh: forceRefresh);
  }

  /// Runs the full Google sign-in flow: account picker → OAuth tokens →
  /// Firebase credential exchange.
  Future<UserCredential?> _runGoogleSignInFlow() async {
    final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
    if (googleUser == null) return null;

    final GoogleSignInAuthentication googleAuth =
        await googleUser.authentication;

    final OAuthCredential credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );

    return await _auth.signInWithCredential(credential);
  }

  /// Sign In with Google
  Future<UserCredential?> signInWithGoogle() async {
    try {
      return await _runGoogleSignInFlow();
    } on PlatformException catch (e) {
      // GMS ApiException: 7 (network_error) is frequently transient — the
      // connection to Google's auth servers drops during the account-picker
      // round-trip. One short deferred retry resolves most occurrences.
      if (e.code == 'network_error') {
        debugPrint('Google Sign-In network_error — retrying once…');
        await Future<void>.delayed(const Duration(milliseconds: 800));
        try {
          return await _runGoogleSignInFlow();
        } on PlatformException catch (retry) {
          if (retry.code == 'network_error') {
            throw Exception(
              'No connection to Google servers. Check your internet '
              '(or emulator DNS) and try again.',
            );
          }
          debugPrint('Unexpected error during Google Sign-In retry: $retry');
          rethrow;
        }
      }
      debugPrint('Unexpected error during Google Sign-In: $e');
      rethrow;
    } catch (e) {
      debugPrint('Unexpected error during Google Sign-In: $e');
      rethrow;
    }
  }

  /// Sign In with Apple
  Future<UserCredential?> signInWithApple() async {
    try {
      final AuthorizationCredentialAppleID rawNonceCredential =
          await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
      );

      final OAuthProvider oauthProvider = OAuthProvider('apple.com');
      final AuthCredential credential = oauthProvider.credential(
        idToken: rawNonceCredential.identityToken,
        accessToken: rawNonceCredential.authorizationCode,
      );

      return await _auth.signInWithCredential(credential);
    } catch (e) {
      debugPrint('Unexpected error during Apple Sign-In: $e');
      rethrow;
    }
  }

  /// Anonymous / Guest Sign-In
  Future<UserCredential?> signInAnonymously() async {
    try {
      return await _auth.signInAnonymously();
    } catch (e) {
      debugPrint('Unexpected error during Guest Sign-In: $e');
      rethrow;
    }
  }

  /// Email & Password Login
  Future<UserCredential> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    final cleanedEmail = InputSanitizer.cleanEmail(email) ?? email.trim();
    try {
      return await _auth.signInWithEmailAndPassword(
        email: cleanedEmail,
        password: password,
      );
    } catch (e) {
      debugPrint('Unexpected error during Email Login: $e');
      rethrow;
    }
  }

  /// Email & Password Sign-Up
  Future<UserCredential> signUpWithEmailAndPassword({
    required String email,
    required String password,
    required String firstName,
    required String lastName,
  }) async {
    final cleanedEmail = InputSanitizer.cleanEmail(email) ?? email.trim();
    final cleanFirst =
        InputSanitizer.cleanText(firstName, maxLength: 32);
    final cleanLast =
        InputSanitizer.cleanText(lastName, maxLength: 32);

    try {
      final UserCredential userCredential =
          await _auth.createUserWithEmailAndPassword(
        email: cleanedEmail,
        password: password,
      );

      final String displayName = '$cleanFirst $cleanLast'.trim();
      // Firebase Auth's displayName limit is 64 chars; truncate defensively.
      final safeName = displayName.length > 64
          ? displayName.substring(0, 64).trim()
          : displayName;
      if (safeName.isNotEmpty && userCredential.user != null) {
        await userCredential.user!.updateDisplayName(safeName);
        await userCredential.user!.reload();
      }

      return userCredential;
    } catch (e) {
      debugPrint('Unexpected error during Email Sign-Up: $e');
      rethrow;
    }
  }

  /// Password Reset Email
  Future<void> sendPasswordResetEmail(String email) async {
    final cleanedEmail = InputSanitizer.cleanEmail(email) ?? email.trim();
    try {
      await _auth.sendPasswordResetEmail(email: cleanedEmail);
    } catch (e) {
      debugPrint('Unexpected error during Password Reset: $e');
      rethrow;
    }
  }

  /// Sign Out
  Future<void> signOut() async {
    try {
      if (await _googleSignIn.isSignedIn()) {
        await _googleSignIn.signOut();
      }
      await _auth.signOut();
    } catch (e) {
      debugPrint('Error signing out: $e');
      rethrow;
    } finally {
      // Make sure the cached ID token doesn't bleed into the next user.
      AuthSessionGuard.instance.invalidate();
    }
  }
}