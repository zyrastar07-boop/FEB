import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// One-way SHA-256 helpers.
///
/// Use these to avoid persisting plaintext versions of sensitive short
/// values (validation tokens, invite codes, entitlement IDs) when only an
/// equality/integrity check is needed, and to fingerprint cache payloads so
/// tampered/stale data can be detected.
///
/// Boundary note: hashing is *not* encryption. A value that must later be
/// transmitted in its raw form to a server still needs to be kept readable
/// (see [SecurePrefs] AES-256-GCM for that case). Hashing only helps when
/// the app compares or verifies values locally without needing the original.
class HashUtils {
  HashUtils._();

  /// SHA-256 of [input] as a lowercase hex string (64 chars).
  static String sha256Hex(String input) =>
      sha256.convert(utf8.encode(input)).toString();

  /// SHA-256 of raw bytes as a lowercase hex string.
  static String sha256HexBytes(List<int> bytes) =>
      sha256.convert(bytes).toString();

  /// SHA-256 digest of [input] as raw bytes (32 bytes).
  static Uint8List sha256Bytes(String input) =>
      Uint8List.fromList(sha256.convert(utf8.encode(input)).bytes);

  /// Stable checksum of a JSON-encodable value (canonical, key-ordered).
  ///
  /// Useful for detecting cache corruption / tampering: store the checksum
  /// next to a cached payload, then compare on load.
  static String checksumOf(Object jsonValue) =>
      sha256Hex(const JsonEncoder().convert(_canonicalize(jsonValue)));

  /// Hashes a short secret (code/token) for at-rest storage.
  /// The raw value is not recoverable from the hash.
  static String hashToken(String token) =>
      sha256Hex(token.trim().toUpperCase());

  /// Constant-time comparison of a raw [token] against a stored [expectedHash]
  /// produced by [hashToken]. Never short-circuits on prefix mismatches.
  static bool verifyToken(String token, String expectedHash) {
    final actual =
        sha256.convert(utf8.encode(token.trim().toUpperCase())).bytes;
    final expected = _hexToBytes(expectedHash);
    if (actual.length != expected.length) return false;
    var diff = 0;
    for (var i = 0; i < actual.length; i++) {
      diff |= actual[i] ^ expected[i];
    }
    return diff == 0;
  }

  /// Orders maps by key so equal payloads always checksum identically.
  static Object _canonicalize(Object value) {
    if (value is Map) {
      final src = value;
      final keys = src.keys.map((k) => k.toString()).toList()..sort();
      return {
        for (final k in keys) k: _canonicalize(src[k]),
      };
    }
    if (value is List) {
      return [for (final e in value) _canonicalize(e)];
    }
    return value;
  }

  static List<int> _hexToBytes(String hex) {
    final clean = hex.trim();
    if (clean.length.isOdd || !RegExp(r'^[0-9a-fA-F]*$').hasMatch(clean)) {
      return const [];
    }
    final out = <int>[];
    for (var i = 0; i < clean.length; i += 2) {
      out.add(int.parse(clean.substring(i, i + 2), radix: 16));
    }
    return out;
  }
}