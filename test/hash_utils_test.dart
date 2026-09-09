import 'package:flutter_test/flutter_test.dart';

import 'package:feb/services/hash_utils.dart';

void main() {
  group('HashUtils', () {
    test('sha256Hex is 64 lowercase hex chars and deterministic', () {
      final a = HashUtils.sha256Hex('hello world');
      expect(a, hasLength(64));
      expect(a, matches(RegExp(r'^[0-9a-f]{64}$')));
      expect(HashUtils.sha256Hex('hello world'), a);
      expect(HashUtils.sha256Hex('Hello World'), isNot(a));
    });

    test('sha256Hex matches the well-known NIST vector', () {
      // NIST FIPS-180 test vector for SHA-256 of "abc".
      expect(
        HashUtils.sha256Hex('abc'),
        'ba7816bf8f01cfea414140de5dae2223'
        'b00361a396177a9cb410ff61f20015ad',
      );
    });

    test('checksumOf is canonical regardless of map key order', () {
      const payloadA = {'b': 2, 'a': [1, 2, {'x': true}]};
      const payloadB = {'a': [1, 2, {'x': true}], 'b': 2};
      expect(HashUtils.checksumOf(payloadA), HashUtils.checksumOf(payloadB));
      // A genuinely different payload hashes differently.
      expect(
        HashUtils.checksumOf(payloadA),
        isNot(HashUtils.checksumOf({'a': 1})),
      );
    });

    test('hashToken normalizes case/whitespace before hashing', () {
      expect(HashUtils.hashToken('ABC-123'), HashUtils.hashToken('abc-123'));
      expect(HashUtils.hashToken('  xyz  '), HashUtils.hashToken('XYZ'));
      // Raw value must never leak into the hash.
      expect(HashUtils.hashToken('secret-code'), isNot(contains('secret')));
    });

    test('verifyToken matches hashToken output and rejects wrong tokens', () {
      const token = 'WATCH-PARTY-7Q2';
      final hash = HashUtils.hashToken(token);
      expect(HashUtils.verifyToken(token, hash), isTrue);
      expect(HashUtils.verifyToken('watch-party-7q2', hash), isTrue);
      expect(HashUtils.verifyToken('WRONG', hash), isFalse);
    });

    test('verifyToken handles malformed expected hashes gracefully', () {
      expect(HashUtils.verifyToken('abc', 'not-a-hex-hash!'), isFalse);
      expect(HashUtils.verifyToken('abc', ''), isFalse);
      expect(HashUtils.verifyToken('abc', 'abc'), isFalse); // wrong length
    });
  });
}