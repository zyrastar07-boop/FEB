import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Writes downloaded subtitle text (SRT / VTT / ASS) to a local temp file
/// and returns the absolute path.
///
/// Used so the player overlay and offline sidecar playback both load cues
/// from disk. Failures return `null` and never throw into the UI.
class SubtitleCacheHelper {
  SubtitleCacheHelper._();

  static const String _dirName = 'wyzie_subs';

  /// Directory that holds cached subtitle files for this install.
  static Future<Directory> cacheDirectory() async {
    final root = await getTemporaryDirectory();
    final dir = Directory('${root.path}/$_dirName');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Persist [body] as `<safeName>.<ext>` under the cache directory.
  ///
  /// [format] should be `srt` or `vtt` (dots are stripped).
  /// UTF-8 is forced so accents / CJK round-trip correctly.
  /// Returns the written absolute path, or null on any I/O error.
  static Future<String?> writeSubtitleFile({
    required String body,
    String format = 'srt',
    String? preferredName,
  }) async {
    var text = body;
    if (text.isEmpty) return null;
    if (text.codeUnitAt(0) == 0xFEFF) text = text.substring(1);
    if (text.trim().isEmpty) return null;

    try {
      final dir = await cacheDirectory();
      final ext = _normaliseExt(format, text);
      final base = _safeFileName(
        preferredName == null || preferredName.trim().isEmpty
            ? 'sub_${DateTime.now().millisecondsSinceEpoch}'
            : preferredName,
      );
      final path = '${dir.path}/$base.$ext';
      final file = File(path);
      await file.writeAsBytes(utf8.encode(text), flush: true);
      debugPrint(
        'SubtitleCacheHelper: wrote ${await file.length()} bytes → $path',
      );
      return path;
    } catch (e, st) {
      debugPrint('SubtitleCacheHelper write failed: $e\n$st');
      return null;
    }
  }

  /// Read UTF-8 subtitle text from [path] if the file exists.
  static Future<String?> readSubtitleFile(String path) async {
    final trimmed = path.trim();
    if (trimmed.isEmpty) return null;
    try {
      final file = File(trimmed);
      if (!await file.exists()) return null;
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) return null;
      final body = utf8.decode(bytes, allowMalformed: true);
      if (body.trim().isEmpty) return null;
      return body;
    } catch (e) {
      debugPrint('SubtitleCacheHelper read failed: $e');
      return null;
    }
  }

  /// True when [path] points at a non-empty local subtitle file.
  static Future<bool> exists(String? path) async {
    if (path == null || path.trim().isEmpty) return false;
    try {
      final file = File(path.trim());
      return await file.exists() && await file.length() > 0;
    } catch (_) {
      return false;
    }
  }

  static String _normaliseExt(String format, String body) {
    final f = format.toLowerCase().replaceAll('.', '').trim();
    if (f.contains('vtt')) return 'vtt';
    if (f.contains('ass') || f.contains('ssa')) return 'ass';
    if (body.trimLeft().toUpperCase().startsWith('WEBVTT')) return 'vtt';
    return 'srt';
  }

  static String _safeFileName(String raw) {
    var name = raw.trim();
    name = name.replaceAll('\\', '/').split('/').last;
    name = name.replaceAll(RegExp(r'\.[^.]+$'), '');
    name = name.replaceAll(RegExp(r'[^\w\-.]+'), '_');
    if (name.isEmpty) {
      name = 'sub_${DateTime.now().millisecondsSinceEpoch}';
    }
    if (name.length > 80) name = name.substring(0, 80);
    return name;
  }
}