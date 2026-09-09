import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:feb/services/secure_prefs.dart';

void main() {
  setUp(() {
    // Fresh store per test. SecurePrefs caches its derived key statically,
    // so clear that too — otherwise the key (from a previous salt) would
    // mismatch the freshly-reset store's salt.
    SharedPreferences.setMockInitialValues(<String, Object>{});
    SecurePrefs.resetForTest();
  });

  group('SecurePrefs', () {
    test('encryptString produces non-plaintext, prefixed output', () async {
      const secret = 'txn_9f3ab21c';
      final encrypted = await SecurePrefs.encryptString(secret);
      expect(encrypted, isNotNull);
      expect(encrypted, startsWith('enc:'));
      expect(encrypted, isNot(contains(secret)));
      // Payload should look like base64url of nonce+ciphertext+tag.
      final body = encrypted!.substring(4);
      expect(body, isNot(contains('+'))); // base64Url, not standard base64
      expect(body, isNot(contains('/')));
    });

    test('round-trips encrypted value back to original plaintext', () async {
      const secret = 'party-code-X7Q2';
      final encrypted = await SecurePrefs.encryptString(secret);
      final decrypted = await SecurePrefs.decryptString(encrypted);
      expect(decrypted, secret);
    });

    test('writeString stores encrypted; readString returns plaintext', () async {
      const key = 'mela_sub_txId';
      const value = 'TXN-2026-8841';
      await SecurePrefs.writeString(key, value);

      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(key);
      // At rest it must be ciphertext, never the raw value.
      expect(raw, isNotNull);
      expect(raw, startsWith('enc:'));
      expect(raw, isNot(contains(value)));

      expect(await SecurePrefs.readString(key), value);
    });

    test('decryptString returns null for legacy plaintext values', () async {
      // Old unencrypted value must be handled gracefully.
      expect(await SecurePrefs.decryptString('legacy-plain'), isNull);
      expect(await SecurePrefs.decryptString(null), isNull);
      expect(await SecurePrefs.decryptString('enc:corrupt'), isNull);
    });

    test('readString falls back to raw value for legacy plaintext', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('legacy_key', 'old-value');
      expect(await SecurePrefs.readString('legacy_key'), 'old-value');
    });

    test('tampered ciphertext fails to decrypt (auth tag catches it)',
        () async {
      const secret = 'secret';
      final encrypted = await SecurePrefs.encryptString(secret);
      // Flip a character inside the payload body (not the prefix).
      final body = encrypted!.substring(4);
      final flipped = body.length > 8
          ? '${body.substring(0, body.length ~/ 2)}A${body.substring(body.length ~/ 2 + 1)}'
          : body;
      final decrypted = await SecurePrefs.decryptString('enc:$flipped');
      expect(decrypted, isNull);
    });
  });
}
