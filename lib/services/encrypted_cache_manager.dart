import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path_provider/path_provider.dart';
import 'package:pointycastle/export.dart';

/// AES-256-CBC encrypted disk cache for streaming video chunks.
///
/// Design goals:
/// - Encrypted at rest — bytes on disk are opaque ciphertext
/// - Auto-purges when player exits or video completes
/// - Zero storage bloat — caller controls eviction
/// - Key derived from device-specific salt (never stored in plain text)
class EncryptedCacheManager {
  EncryptedCacheManager._();
  static final EncryptedCacheManager instance = EncryptedCacheManager._();

  static const _keyIterations = 100000;
  static const _saltLength = 32;
  static const _ivLength = 16;
  static const _aesKeyLength = 32;
  static const int _chunkMagic = 0xCAFEBABE;

  String? _cacheDirPath;
  Uint8List? _derivedKey;
  bool _disposed = false;

  Uint8List _deriveKey(Uint8List passphrase, Uint8List salt) {
    final params = Pbkdf2Parameters(salt, _keyIterations, _aesKeyLength);
    final pbkdf2 = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))
      ..init(params);
    return pbkdf2.process(passphrase);
  }

  Future<Uint8List> _getDevicePassphrase() async {
    try {
      final id = await _readDeviceId();
      final hash = sha256.convert(utf8.encode(id));
      return Uint8List.fromList(hash.bytes);
    } catch (_) {
      final fallback = sha256.convert(utf8.encode('mela_fallback_salt_v1'));
      return Uint8List.fromList(fallback.bytes);
    }
  }

  Future<String> _readDeviceId() async {
    final dir = await getApplicationSupportDirectory();
    final idFile = File('${dir.path}/.dk');
    if (await idFile.exists()) {
      return (await idFile.readAsString()).trim();
    }
    final id = '${DateTime.now().microsecondsSinceEpoch}_${_randHex(16)}';
    await idFile.writeAsString(id);
    return id;
  }

  String _randHex(int bytes) {
    final rnd = DateTime.now().microsecondsSinceEpoch;
    return sha256.convert([rnd]).toString().substring(0, bytes * 2);
  }

  Future<void> init() async {
    if (_derivedKey != null) return;
    final dir = await getApplicationSupportDirectory();
    final cacheDir = Directory('${dir.path}/wyzie_vcache');
    if (!await cacheDir.exists()) {
      await cacheDir.create(recursive: true);
    }
    _cacheDirPath = cacheDir.path;

    final saltFile = File('${dir.path}/.ks');
    Uint8List salt;
    if (await saltFile.exists()) {
      salt = Uint8List.fromList(await saltFile.readAsBytes());
    } else {
      final rng = FortunaRandom();
      final seed = Uint8List.fromList(
        List.generate(32, (i) => (DateTime.now().microsecondsSinceEpoch + i * 7) % 256),
      );
      rng.seed(KeyParameter(seed));
      salt = rng.nextBytes(_saltLength);
      await saltFile.writeAsBytes(salt);
    }

    final passphrase = await _getDevicePassphrase();
    _derivedKey = _deriveKey(passphrase, salt);
  }

  String? get cacheDir => _cacheDirPath;

  /// Test hook for [_sanitizeId].
  @visibleForTesting
  String sanitizeIdForTest(String id) => _sanitizeId(id);

  /// Strips everything outside [A-Za-z0-9_-] from remote-sourced IDs before
  /// they are used to build file paths. Defends against path traversal
  /// (`../`), separator injection (`/`, `\\`), and control bytes.
  String _sanitizeId(String id) {
    final cleaned = id.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    // A fully-masked ID (e.g. input was only dots) must never resolve to an
    // empty or wildcard-ish path component.
    return cleaned.isEmpty || cleaned == '_' ? 'invalid' : cleaned;
  }

  Future<void> write(String mediaId, String chunkId, Uint8List data) async {
    final key = _derivedKey;
    final dirPath = _cacheDirPath;
    if (key == null || dirPath == null || _disposed) return;

    final safeMediaId = _sanitizeId(mediaId);
    final safeChunkId = _sanitizeId(chunkId);
    final mediaDir = Directory('$dirPath/$safeMediaId');
    if (!await mediaDir.exists()) {
      await mediaDir.create(recursive: true);
    }

    final iv = _randomIv();
    final encrypted = _aesCbcEncrypt(data, key, iv);
    final mac = _hmacSha256(iv, encrypted, key);

    final header = ByteData(4 + _ivLength + 32);
    header.setUint32(0, _chunkMagic, Endian.big);
    for (int i = 0; i < _ivLength; i++) {
      header.setUint8(4 + i, iv[i]);
    }
    for (int i = 0; i < 32; i++) {
      header.setUint8(4 + _ivLength + i, mac[i]);
    }

    final file = File('${mediaDir.path}/$safeChunkId.enc');
    await file.writeAsBytes([...header.buffer.asUint8List(), ...encrypted]);
  }

  Future<Uint8List?> read(String mediaId, String chunkId) async {
    final key = _derivedKey;
    final dirPath = _cacheDirPath;
    if (key == null || dirPath == null || _disposed) return null;

    final safeMediaId = _sanitizeId(mediaId);
    final safeChunkId = _sanitizeId(chunkId);
    final file = File('$dirPath/$safeMediaId/$safeChunkId.enc');
    if (!await file.exists()) return null;

    try {
      final bytes = await file.readAsBytes();
      final minLen = 4 + _ivLength + 32;
      if (bytes.length < minLen) return null;

      final storedMagic = ByteData.sublistView(Uint8List.fromList(bytes))
          .getUint32(0, Endian.big);
      if (storedMagic != _chunkMagic) return null;

      final iv = bytes.sublist(4, 4 + _ivLength);
      final storedMac = bytes.sublist(4 + _ivLength, 4 + _ivLength + 32);
      final ciphertext = bytes.sublist(4 + _ivLength + 32);

      final computedMac = _hmacSha256(Uint8List.fromList(iv), Uint8List.fromList(ciphertext), key);
      if (!_constantTimeEquals(storedMac, computedMac)) return null;

      return _aesCbcDecrypt(Uint8List.fromList(ciphertext), key, Uint8List.fromList(iv));
    } catch (_) {
      return null;
    }
  }

  Future<void> purgeMedia(String mediaId) async {
    final dirPath = _cacheDirPath;
    if (dirPath == null) return;
    try {
      // Sanitize here too: the delete path must not be able to escape the
      // cache root even if a caller passes an unsanitized remote ID.
      final mediaDir = Directory('$dirPath/${_sanitizeId(mediaId)}');
      final canonicalRoot = Directory(dirPath).absolute.path;
      if (!mediaDir.absolute.path.startsWith(canonicalRoot)) return;
      if (await mediaDir.exists()) {
        await mediaDir.delete(recursive: true);
      }
    } catch (_) {}
  }

  Future<void> purgeAll() async {
    final dirPath = _cacheDirPath;
    if (dirPath == null) return;
    try {
      final dir = Directory(dirPath);
      if (await dir.exists()) {
        await dir.delete(recursive: true);
        await dir.create(recursive: true);
      }
    } catch (_) {}
  }

  Future<List<String>> get cachedMediaIds async {
    final dirPath = _cacheDirPath;
    if (dirPath == null) return [];
    final entries = <String>[];
    try {
      final dir = Directory(dirPath);
      if (await dir.exists()) {
        await for (final e in dir.list()) {
          if (e is Directory) {
            final name = e.path.split(Platform.pathSeparator).last;
            if (!name.startsWith('.')) entries.add(name);
          }
        }
      }
    } catch (_) {}
    return entries;
  }

  Uint8List _randomIv() {
    final rng = FortunaRandom();
    final seed = Uint8List.fromList(
      List.generate(32, (i) => (DateTime.now().microsecondsSinceEpoch * 31 + i * 17) % 256),
    );
    rng.seed(KeyParameter(seed));
    return rng.nextBytes(_ivLength);
  }

  Uint8List _hmacSha256(Uint8List iv, Uint8List ciphertext, Uint8List key) {
    final hmac = HMac(SHA256Digest(), 64);
    hmac.init(KeyParameter(key));
    hmac.update(iv, 0, iv.length);
    hmac.update(ciphertext, 0, ciphertext.length);
    return hmac.process(Uint8List(0));
  }

  Uint8List _aesCbcEncrypt(Uint8List plaintext, Uint8List key, Uint8List iv) {
    final padded = _pkcs7Pad(plaintext);
    final cipher = CBCBlockCipher(AESEngine())
      ..init(true, ParametersWithIV(KeyParameter(key), iv));
    final out = Uint8List(padded.length);
    for (var offset = 0; offset < padded.length; offset += 16) {
      cipher.processBlock(padded, offset, out, offset);
    }
    return out;
  }

  Uint8List _aesCbcDecrypt(Uint8List ciphertext, Uint8List key, Uint8List iv) {
    final cipher = CBCBlockCipher(AESEngine())
      ..init(false, ParametersWithIV(KeyParameter(key), iv));
    final out = Uint8List(ciphertext.length);
    for (var offset = 0; offset < ciphertext.length; offset += 16) {
      cipher.processBlock(ciphertext, offset, out, offset);
    }
    return Uint8List.fromList(_pkcs7Unpad(out));
  }

  Uint8List _pkcs7Pad(Uint8List data) {
    final padLen = 16 - (data.length % 16);
    final padded = Uint8List(data.length + padLen);
    padded.setRange(0, data.length, data);
    for (var i = data.length; i < padded.length; i++) {
      padded[i] = padLen;
    }
    return padded;
  }

  List<int> _pkcs7Unpad(Uint8List data) {
    if (data.isEmpty) return data;
    final padLen = data[data.length - 1];
    if (padLen < 1 || padLen > 16 || padLen > data.length) return data.toList();
    return data.sublist(0, data.length - padLen).toList();
  }

  bool _constantTimeEquals(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    var mismatch = 0;
    for (var i = 0; i < a.length; i++) {
      mismatch |= a[i] ^ b[i];
    }
    return mismatch == 0;
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await purgeAll();
    _derivedKey = null;
    _cacheDirPath = null;
  }
}
