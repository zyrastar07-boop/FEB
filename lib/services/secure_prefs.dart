import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:pointycastle/export.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// AES-256-GCM encryption helper for sensitive values persisted via
/// [SharedPreferences].
///
/// Sensitive fields (subscription transaction IDs, payment provider, watch
/// party codes, etc.) are encrypted at rest with a key derived from a
/// per-install random salt + an app-scoped secret, so a raw prefs dump no
/// longer leaks them in plaintext.
///
/// Security note: the derived key lives in memory and the app secret is
/// compiled into the binary, so this protects against casual inspection /
/// backups / logs — not against a determined attacker with the APK. For
/// hardware-backed security, keys would need to live in the platform
/// keystore (flutter_secure_storage), which is out of scope here.
class SecurePrefs {
  SecurePrefs._();

  /// App-scoped secret mixed into the key derivation. Not a user secret —
  /// it only ensures two different apps/forks derive different keys from
  /// the same salt.
  static const String _appSecret = 'mela.secure.v1';

  /// Key under which the per-install random salt is persisted.
  static const String _saltKey = 'mela_sec_salt_v1';

  /// Cached derived key (32 bytes, AES-256).
  static Uint8List? _cachedKey;

  /// Prefix marking an encrypted value (vs legacy plaintext).
  static const String _prefix = 'enc:';

  static const int _nonceLength = 12;
  static const int _macLength = 16; // 128-bit GCM tag

  /// Resets the cached derived key so the next operation re-reads the salt
  /// from prefs. Test-only hook.
  @visibleForTesting
  static void resetForTest() {
    _cachedKey = null;
  }

  /// Returns the 32-byte derived key, generating + persisting the per-install
  /// salt on first use.
  static Future<Uint8List> _key() async {
    if (_cachedKey != null) return _cachedKey!;

    final prefs = await SharedPreferences.getInstance();
    var salt = prefs.getString(_saltKey);
    if (salt == null || salt.isEmpty) {
      final rng = Random.secure();
      final bytes = Uint8List(16);
      for (var i = 0; i < 16; i++) {
        bytes[i] = rng.nextInt(256);
      }
      salt = base64UrlEncode(bytes);
      try {
        await prefs.setString(_saltKey, salt);
      } catch (_) {
        // Salt persistence is best-effort; deriving from memory still works
        // for this session.
      }
    }

    // key = SHA-256(appSecret || ":" || salt)
    // Implemented with package:crypto (same digest as the previous
    // pointycastle SHA256Digest, so existing encrypted values stay valid).
    final out = Uint8List.fromList(
        sha256.convert(utf8.encode('$_appSecret:$salt')).bytes);

    _cachedKey = out;
    return _cachedKey!;
  }

  /// Encrypts [plaintext] → "enc:" + base64(nonce || ciphertext || tag).
  /// Returns null on failure (caller treats as write-failure).
  static Future<String?> encryptString(String plaintext) async {
    try {
      final key = await _key();
      final rng = Random.secure();
      final nonce = Uint8List(_nonceLength);
      for (var i = 0; i < _nonceLength; i++) {
        nonce[i] = rng.nextInt(256);
      }

      final plain = Uint8List.fromList(utf8.encode(plaintext));
      final params = AEADParameters(
        KeyParameter(key),
        _macLength * 8,
        nonce,
        Uint8List(0), // no AAD
      );
      final cipher = GCMBlockCipher(AESEngine())
        ..init(true, params);

      // process() emits the ciphertext and appends the 128-bit GCM tag.
      final out = cipher.process(plain);

      final payload = Uint8List(_nonceLength + out.length)
        ..setRange(0, _nonceLength, nonce)
        ..setRange(_nonceLength, _nonceLength + out.length, out);

      return '$_prefix${base64UrlEncode(payload)}';
    } catch (e) {
      debugPrint('SecurePrefs.encryptString failed: $e');
      return null;
    }
  }

  /// Decrypts a value previously produced by [encryptString]. Returns null if
  /// the value is not in encrypted format (legacy plaintext, or corrupt).
  static Future<String?> decryptString(String? value) async {
    if (value == null || !value.startsWith(_prefix)) return null;
    try {
      final key = await _key();
      final payload = base64Url.decode(value.substring(_prefix.length));
      if (payload.length <= _nonceLength + _macLength) return null;

      final nonce = Uint8List.sublistView(payload, 0, _nonceLength);
      final ciphertext =
          Uint8List.sublistView(payload, _nonceLength, payload.length);

      final params = AEADParameters(
        KeyParameter(key),
        _macLength * 8,
        nonce,
        Uint8List(0),
      );
      final cipher = GCMBlockCipher(AESEngine())
        ..init(false, params);

      // process() authenticates the tag and emits the plaintext.
      final plain = cipher.process(ciphertext);
      return utf8.decode(plain, allowMalformed: true);
    } catch (e) {
      debugPrint('SecurePrefs.decryptString failed: $e');
      return null;
    }
  }

  /// Reads a possibly-encrypted string from prefs. Returns the decrypted
  /// value, or the raw legacy value if it was stored unencrypted.
  static Future<String?> readString(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);
    if (raw == null) return null;
    final decrypted = await decryptString(raw);
    return decrypted ?? raw;
  }

  /// Writes [value] to prefs encrypted at rest.
  static Future<void> writeString(String key, String value) async {
    final prefs = await SharedPreferences.getInstance();
    final encrypted = await encryptString(value);
    if (encrypted != null) {
      await prefs.setString(key, encrypted);
    } else {
      // Fall back to plaintext write so we never lose user data.
      await prefs.setString(key, value);
    }
  }
}