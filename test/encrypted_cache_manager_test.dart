import 'package:flutter_test/flutter_test.dart';

import 'package:feb/services/encrypted_cache_manager.dart';

void main() {
  group('EncryptedCacheManager id sanitization (path-traversal defense)', () {
    final mgr = EncryptedCacheManager.instance;

    test('plain alphanumeric ids pass through unchanged', () {
      expect(mgr.sanitizeIdForTest('tt0111161'), 'tt0111161');
      expect(mgr.sanitizeIdForTest('media_42-chunk_7'), 'media_42-chunk_7');
    });

    test('path traversal sequences are neutralized', () {
      // `..` and separators must not survive sanitization as a path.
      expect(mgr.sanitizeIdForTest('../../etc/passwd'), isNot(contains('..')));
      expect(mgr.sanitizeIdForTest('../../etc/passwd'), isNot(contains('/')));
      expect(mgr.sanitizeIdForTest(r'..\..\winnt'), isNot(contains('..')));
      expect(mgr.sanitizeIdForTest(r'..\..\winnt'), isNot(contains('\\')));
    });

    test('separators and dots are replaced with underscores', () {
      expect(mgr.sanitizeIdForTest('a/b/c'), 'a_b_c');
      expect(mgr.sanitizeIdForTest(r'a\b\c'), r'a_b_c');
      expect(mgr.sanitizeIdForTest('a..b'), 'a__b');
    });

    test('fully-masked ids fall back to a safe constant', () {
      expect(mgr.sanitizeIdForTest(''), 'invalid');
      expect(mgr.sanitizeIdForTest('...'), 'invalid');
      expect(mgr.sanitizeIdForTest('/'), 'invalid');
      expect(mgr.sanitizeIdForTest(r'\'), 'invalid');
    });

    test('control and non-ascii characters are stripped', () {
      final id = '${String.fromCharCodes([0x00, 0x1F, 0x7F])}ok';
      final out = mgr.sanitizeIdForTest(id);
      expect(out, matches(RegExp(r'^[A-Za-z0-9_-]+$')));
      expect(out, contains('ok'));
    });
  });
}
