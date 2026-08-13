import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

class AuthService {
  // Singleton pattern
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  static const String _googleWebClientId =
      '341624343876-5qpngd647trkoephibjfp1md4q42llss.apps.googleusercontent.com';

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    serverClientId: _googleWebClientId,
  );

  /// Current Firebase User
  User? get currentUser => _auth.currentUser;

  /// Auth state change listener stream
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  /// Sign In with Google
  Future<UserCredential?> signInWithGoogle() async {
    try {
      // Trigger the Google Authentication flow
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        // User canceled the sign-in
        return null;
      }

      // Obtain the auth details from the request
      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;

      // Create a new credential
      final OAuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      // Sign in to Firebase with the Google user credential
      return await _auth.signInWithCredential(credential);
    } on FirebaseAuthException catch (e) {
      debugPrint('Firebase Auth Error (Google Sign-In): ${e.message}');
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
    } on FirebaseAuthException catch (e) {
      debugPrint('Firebase Auth Error (Apple Sign-In): ${e.message}');
      rethrow;
    } catch (e) {
      debugPrint('Unexpected error during Apple Sign-In: $e');
      rethrow;
    }
  }

  /// Anonymous / Guest Sign-In
  Future<UserCredential?> signInAnonymously() async {
    try {
      return await _auth.signInAnonymously();
    } on FirebaseAuthException catch (e) {
      debugPrint('Firebase Auth Error (Guest Sign-In): ${e.message}');
      rethrow;
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
    try {
      return await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
    } on FirebaseAuthException catch (e) {
      debugPrint('Firebase Auth Error (Email Login): ${e.message}');
      rethrow;
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
    try {
      final UserCredential userCredential =
          await _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );

      // Update user display name
      final String displayName = '${firstName.trim()} ${lastName.trim()}'.trim();
      if (displayName.isNotEmpty && userCredential.user != null) {
        await userCredential.user!.updateDisplayName(displayName);
        await userCredential.user!.reload();
      }

      return userCredential;
    } on FirebaseAuthException catch (e) {
      debugPrint('Firebase Auth Error (Email Sign-Up): ${e.message}');
      rethrow;
    } catch (e) {
      debugPrint('Unexpected error during Email Sign-Up: $e');
      rethrow;
    }
  }

  /// Password Reset Email
  Future<void> sendPasswordResetEmail(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email.trim());
    } on FirebaseAuthException catch (e) {
      debugPrint('Firebase Auth Error (Password Reset): ${e.message}');
      rethrow;
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
    }
  }
}
