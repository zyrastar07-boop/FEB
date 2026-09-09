// Debrid instant resolution: turn a torrent add-on stream into a direct
// HTTPS link served by a configured debrid provider.
//
// Ported from NuvioMobile (GPL-3.0):
//   features/debrid/DebridMagnetBuilder.kt
//   features/debrid/DebridApiClients.kt
//   features/debrid/DebridFileSelectors.kt
//   features/debrid/DirectDebridResolver.kt
//
// Resolution tries each configured provider in preference order and returns
// the first instant link found. Only *cached* torrents resolve instantly —
// providers refuse to queue a real transfer here by design (that is what
// "instant playback" means).
//
// SPDX-License-Identifier: GPL-3.0
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import 'addon_content_models.dart';
import 'debrid_models.dart';
import 'debrid_settings.dart';

/// Outcome of an instant-resolve attempt.
class DebridResolveResult {
  final bool success;
  final String? url;
  final String? filename;
  final int? videoSize;
  final DebridProvider? provider;
  final DebridResolveFailure? failure;

  const DebridResolveResult._({
    this.success = false,
    this.url,
    this.filename,
    this.videoSize,
    this.provider,
    this.failure,
  });

  factory DebridResolveResult.success({
    required String url,
    required DebridProvider provider,
    String? filename,
    int? videoSize,
  }) =>
      DebridResolveResult._(
        success: true,
        url: url,
        filename: filename,
        videoSize: videoSize,
        provider: provider,
      );

  const DebridResolveResult.failure(DebridResolveFailure failure)
      : this._(failure: failure);

  /// Short human-readable reason, for snackbars / inline status.
  String get failureMessage => switch (failure) {
        DebridResolveFailure.notConfigured =>
          'No debrid account is connected. Add one in Settings → Debrid.',
        DebridResolveFailure.missingApiKey =>
          'Add your ${provider?.displayName ?? 'debrid'} API key in Settings → Debrid.',
        DebridResolveFailure.notCached =>
          'Not instantly cached on ${provider?.displayName ?? 'the debrid service'} yet.',
        DebridResolveFailure.noVideoFile =>
          'No playable video file was found on the debrid service.',
        DebridResolveFailure.unsupported =>
          'This stream has no torrent hash/magnet to resolve.',
        DebridResolveFailure.error =>
          'Debrid resolution failed. Please try again.',
        null => '',
      };
}

enum DebridResolveFailure {
  notConfigured,
  missingApiKey,
  notCached,
  noVideoFile,
  unsupported,
  error,
}

/// Builds a magnet URI for a torrent add-on stream (Nuvio's
/// `DebridMagnetBuilder`). Prefers an explicit magnet; otherwise synthesises
/// one from the info-hash + filename + tracker list.
String? magnetFromAddonStream(AddonStream stream) {
  for (final candidate in [stream.url, stream.externalUrl]) {
    final raw = candidate?.trim() ?? '';
    if (raw.toLowerCase().startsWith('magnet:')) return raw;
  }
  final hash = stream.infoHash?.trim();
  if (hash == null || hash.isEmpty) return null;

  final buffer = StringBuffer('magnet:?xt=urn:btih:$hash');
  final filename = stream.filename?.trim();
  if (filename != null && filename.isNotEmpty) {
    buffer.write('&dn=${Uri.encodeQueryComponent(filename)}');
  }
  for (final source in stream.sources) {
    final tracker = _trackerUrl(source);
    if (tracker == null) continue;
    buffer.write('&tr=${Uri.encodeQueryComponent(tracker)}');
  }
  return buffer.toString();
}

String? _trackerUrl(String source) {
  final value = source.trim();
  if (value.isEmpty || value.toLowerCase().startsWith('dht:')) return null;
  return value
      .replaceFirst(RegExp(r'^tracker:', caseSensitive: false), '')
      .trim();
}

/// Resolves [stream] to an instant playable link using the configured
/// debrid accounts. Callers must have loaded [DebridSettings].
Future<DebridResolveResult> resolveAddonStreamTorrent({
  required AddonStream stream,
  int? season,
  int? episode,
  http.Client? client,
  DebridSettings? settings,
}) async {
  final effective = settings ?? DebridSettings.instance;
  await effective.ensureLoaded();
  if (!effective.enabled) {
    return const DebridResolveResult.failure(
        DebridResolveFailure.notConfigured);
  }
  final services = effective.configuredServices;
  if (services.isEmpty) {
    return const DebridResolveResult.failure(
        DebridResolveFailure.notConfigured);
  }

  final magnet = magnetFromAddonStream(stream);
  if (magnet == null) {
    return const DebridResolveResult.failure(
        DebridResolveFailure.unsupported);
  }

  DebridResolveFailure? firstFailure;
  for (final credential in services) {
    final result = switch (credential.provider.id) {
      DebridProviders.torboxId => await _resolveTorbox(
          apiKey: credential.apiKey,
          magnet: magnet,
          fileIdx: stream.fileIdx,
          filename: stream.filename,
          season: season,
          episode: episode,
          client: client,
        ),
      DebridProviders.premiumizeId => await _resolvePremiumize(
          apiKey: credential.apiKey,
          magnet: magnet,
          filename: stream.filename,
          season: season,
          episode: episode,
          client: client,
        ),
      _ => const DebridResolveResult.failure(DebridResolveFailure.error),
    };
    if (result.success) return result;
    // Keep the first provider's failure as the most useful signal (providers
    // are tried in preference order). Reporting success here would be wrong:
    // there is no local P2P daemon detection or configuration, so an
    // uncached/erroring torrent must surface its real failure (e.g.
    // notCached) instead of a dead 127.0.0.1 stream URL.
    firstFailure ??= result.failure ?? DebridResolveFailure.error;
  }
  return DebridResolveResult.failure(
      firstFailure ?? DebridResolveFailure.error);
}

// ── Torbox ──────────────────────────────────────────────────────────────────

const _torboxBase = 'https://api.torbox.app';

Future<DebridResolveResult> _resolveTorbox({
  required String apiKey,
  required String magnet,
  int? fileIdx,
  String? filename,
  int? season,
  int? episode,
  http.Client? client,
}) async {
  final key = apiKey.trim();
  if (key.isEmpty) {
    return const DebridResolveResult.failure(
        DebridResolveFailure.missingApiKey);
  }

  final httpClient = client ?? http.Client();
  try {
    // 1. Ask Torbox to attach the torrent — but only if it is already
    //    cached. The provider returns success=false for cache misses, which
    //    is exactly the "not cached" signal we surface.
    final boundary = 'NuvioDebrid${magnet.hashCode.toUInt32Safe()}';
    final createResponse = await httpClient
        .post(
          Uri.parse('$_torboxBase/v1/api/torrents/createtorrent'),
          headers: {
            'Authorization': 'Bearer $key',
            'Content-Type': 'multipart/form-data; boundary=$boundary',
            'Accept': 'application/json',
          },
          body: _multipartBody(boundary, {
            'magnet': magnet,
            'add_only_if_cached': 'true',
            'allow_zip': 'false',
          }),
        )
        .timeout(const Duration(seconds: 30));
    final createEnvelope = _decodeEnvelope(createResponse.body);
    final status = createResponse.statusCode;
    if (status == 401 || status == 403) {
      return const DebridResolveResult.failure(
          DebridResolveFailure.missingApiKey);
    }
    final createData = createEnvelope?['data'];
    final torrentId = _torboxIdFromCreate(createData);
    if (createEnvelope?['success'] != true || torrentId == null) {
      if (status == 409) {
        return const DebridResolveResult.failure(
            DebridResolveFailure.notCached);
      }
      return const DebridResolveResult.failure(
          DebridResolveFailure.notCached);
    }

    // 2. Read back the torrent's file list.
    final infoResponse = await httpClient
        .get(
          Uri.parse(
              '$_torboxBase/v1/api/torrents/mylist?id=$torrentId&bypass_cache=true'),
          headers: {
            'Authorization': 'Bearer $key',
            'Accept': 'application/json',
          },
        )
        .timeout(const Duration(seconds: 30));
    final infoData =
        _decodeEnvelope(infoResponse.body)?['data'] as Map<String, dynamic>?;
    final rawFiles = infoData?['files'];
    final files = <TorboxFile>[];
    if (rawFiles is List) {
      for (final raw in rawFiles) {
        if (raw is! Map<String, dynamic>) continue;
        final id = _asInt(raw['id']);
        final name = (raw['name'] ?? raw['short_name'] ?? '').toString();
        final mime = (raw['mime'] ?? '').toString().toLowerCase();
        final size = _asInt(raw['size']);
        if (name.trim().isEmpty) continue;
        files.add(TorboxFile(
          id: id,
          name: name.trim(),
          mime: mime,
          size: size,
        ));
      }
    }
    final file = selectDebridVideoFile(
      files: files,
      fileIdx: fileIdx,
      filenameHint: filename,
      season: season,
      episode: episode,
      displayName: (f) => f.name,
      isPlayable: (f) => f.isPlayableVideo,
      sizeOf: (f) => f.size,
      idOf: (f) => f.id,
    );
    if (file == null) {
      return const DebridResolveResult.failure(
          DebridResolveFailure.noVideoFile);
    }

    // 3. Ask for the direct streaming link of the chosen file.
    final linkUri = Uri.parse('$_torboxBase/v1/api/torrents/requestdl')
        .replace(queryParameters: {
      'token': key,
      'torrent_id': torrentId.toString(),
      if (file.id != null) 'file_id': file.id.toString(),
      'zip_link': 'false',
      'redirect': 'false',
      'append_name': 'false',
    });
    final linkResponse = await httpClient
        .get(linkUri, headers: {
          'Authorization': 'Bearer $key',
          'Accept': 'application/json',
        })
        .timeout(const Duration(seconds: 30));
    final linkBody = _decodeEnvelope(linkResponse.body);
    if (linkBody?['success'] != true) {
      if (linkResponse.statusCode == 401 || linkResponse.statusCode == 403) {
        return const DebridResolveResult.failure(
            DebridResolveFailure.missingApiKey);
      }
      return const DebridResolveResult.failure(DebridResolveFailure.error);
    }
    final url = linkBody?['data']?.toString().trim() ?? '';
    if (url.isEmpty) {
      return const DebridResolveResult.failure(DebridResolveFailure.error);
    }
    return DebridResolveResult.success(
      url: url,
      provider: DebridProviders.torbox,
      filename: file.name,
      videoSize: file.size,
    );
  } catch (_) {
    return const DebridResolveResult.failure(DebridResolveFailure.error);
  } finally {
    if (client == null) httpClient.close();
  }
}

class TorboxFile {
  final int? id;
  final String name;
  final String mime;
  final int? size;

  const TorboxFile({
    required this.id,
    required this.name,
    required this.mime,
    required this.size,
  });

  bool get isPlayableVideo {
    if (mime.startsWith('video/')) return true;
    return hasVideoExtension(name);
  }
}

int? _torboxIdFromCreate(Object? data) {
  if (data is! Map<String, dynamic>) return null;
  final direct = _asInt(data['torrent_id']);
  if (direct != null) return direct;
  final nested = data['data'];
  if (nested is Map<String, dynamic>) {
    final nestedId = _asInt(nested['torrent_id']);
    if (nestedId != null) return nestedId;
  }
  return _asInt(data['id']);
}

// ── Premiumize ─────────────────────────────────────────────────────────────

const _premiumizeBase = 'https://www.premiumize.me';

Future<DebridResolveResult> _resolvePremiumize({
  required String apiKey,
  required String magnet,
  String? filename,
  int? season,
  int? episode,
  http.Client? client,
}) async {
  final key = apiKey.trim();
  if (key.isEmpty) {
    return const DebridResolveResult.failure(
        DebridResolveFailure.missingApiKey);
  }

  final httpClient = client ?? http.Client();
  try {
    final response = await httpClient
        .post(
          Uri.parse('$_premiumizeBase/api/transfer/directdl'),
          headers: {
            'Authorization': 'Bearer $key',
            'Accept': 'application/json',
          },
          body: {'src': magnet},
        )
        .timeout(const Duration(seconds: 40));
    if (response.statusCode == 401 || response.statusCode == 403) {
      return const DebridResolveResult.failure(
          DebridResolveFailure.missingApiKey);
    }
    final rawDecoded = _decodeJson(response.body);
    final decoded = rawDecoded is Map<String, dynamic>
        ? rawDecoded
        : const <String, dynamic>{};
    final status = decoded['status']?.toString().toLowerCase();
    if (status != 'success') {
      // Premiumize reports cache misses as success with empty content only
      // when the magnet matches nothing usable; a plain failure means the
      // source isn't available to it.
      return const DebridResolveResult.failure(
          DebridResolveFailure.notCached);
    }
    final content = decoded['content'];
    final files = <PremiumizeFile>[];
    if (content is List) {
      for (final raw in content) {
        if (raw is! Map<String, dynamic>) continue;
        final path = (raw['path'] ?? '').toString();
        final link = (raw['stream_link'] ?? raw['link'] ?? '').toString();
        final size = _asInt(raw['size']);
        final display = path.isEmpty
            ? ''
            : path.split(RegExp(r'[/\\]')).lastWhere(
                (s) => s.isNotEmpty,
                orElse: () => path,
              );
        if (display.trim().isEmpty || link.trim().isEmpty) continue;
        files.add(PremiumizeFile(
          name: display.trim(),
          link: link.trim(),
          size: size,
        ));
      }
    }
    final file = selectDebridVideoFile(
      files: files,
      filenameHint: filename,
      season: season,
      episode: episode,
      displayName: (f) => f.name,
      isPlayable: (f) => hasVideoExtension(f.name),
      sizeOf: (f) => f.size,
    );
    if (file == null) {
      // Empty content list = the magnet is not in Premiumize's cache.
      if (files.isEmpty) {
        return const DebridResolveResult.failure(
            DebridResolveFailure.notCached);
      }
      return const DebridResolveResult.failure(
          DebridResolveFailure.noVideoFile);
    }
    return DebridResolveResult.success(
      url: file.link,
      provider: DebridProviders.premiumize,
      filename: file.name,
      videoSize: file.size,
    );
  } catch (_) {
    return const DebridResolveResult.failure(DebridResolveFailure.error);
  } finally {
    if (client == null) httpClient.close();
  }
}

class PremiumizeFile {
  final String name;
  final String link;
  final int? size;

  const PremiumizeFile({
    required this.name,
    required this.link,
    required this.size,
  });
}

// ── Shared video-file selection (port of Nuvio's selectors) ────────────────

/// Shared interface used by the provider file pickers.
typedef DebridCandidate = Object;

/// Picks the playable video file to stream, following Nuvio's selector
/// priority: filename hint match → episode markers (S01E02 / 1x02) → the
/// stream's advertised file index → the largest file.
///
/// [files] items are plain objects; [displayName], [isPlayable], [sizeOf],
/// [idOf] adapt each provider's file shape.
T? selectDebridVideoFile<T>({
  required List<T> files,
  int? fileIdx,
  String? filenameHint,
  int? season,
  int? episode,
  required String Function(T) displayName,
  required bool Function(T) isPlayable,
  required int? Function(T) sizeOf,
  int? Function(T)? idOf,
}) {
  if (files.isEmpty) return null;
  final playable = files.where(isPlayable).toList();
  if (playable.isEmpty) return null;

  // 1. An explicit file name from the add-on (best match when present).
  final hint = filenameHint?.trim();
  if (hint != null && hint.isNotEmpty) {
    final normalized = _normalizeName(hint);
    if (normalized.isNotEmpty) {
      for (final file in playable) {
        final name = _normalizeName(displayName(file));
        if (name.isNotEmpty &&
            (name.contains(normalized) || normalized.contains(name))) {
          return file;
        }
      }
    }
  }

  // 2. Episode markers (s01e02, 1x02) for series torrents.
  if (season != null && episode != null) {
    final patterns = _episodePatterns(season, episode);
    if (patterns.isNotEmpty) {
      for (final file in playable) {
        final name = displayName(file).toLowerCase();
        if (patterns.any(name.contains)) return file;
      }
    }
  }

  // 3. The add-on advertised a file index.
  final fileIdxGetter = idOf;
  if (fileIdx != null) {
    if (fileIdxGetter != null) {
      for (final file in playable) {
        if (fileIdxGetter(file) == fileIdx) return file;
      }
    }
    if (fileIdx >= 0 && fileIdx < playable.length) {
      return playable[fileIdx];
    }
    if (fileIdx - 1 >= 0 && fileIdx - 1 < playable.length) {
      return playable[fileIdx - 1];
    }
  }

  // 4. Largest playable file.
  return playable.reduce((best, file) {
    final bestSize = sizeOf(best) ?? 0;
    final fileSize = sizeOf(file) ?? 0;
    return fileSize > bestSize ? file : best;
  });
}

List<String> _episodePatterns(int season, int episode) {
  final s = season.toString().padLeft(2, '0');
  final e = episode.toString().padLeft(2, '0');
  return ['s${s}e$e', '${season}x$e', '${season}x$episode'];
}

String _normalizeName(String raw) {
  final fileName = raw
      .split(RegExp(r'[/\\]'))
      .lastWhere((s) => s.isNotEmpty, orElse: () => raw);
  final withoutExt = fileName.contains('.')
      ? fileName.substring(0, fileName.lastIndexOf('.'))
      : fileName;
  return withoutExt
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .trim();
}

bool hasVideoExtension(String name) {
  final lower = name.toLowerCase();
  const extensions = [
    '.mp4',
    '.mkv',
    '.webm',
    '.avi',
    '.mov',
    '.m4v',
    '.ts',
    '.m2ts',
    '.wmv',
    '.flv',
    '.mpg',
    '.mpeg',
  ];
  return extensions.any(lower.endsWith);
}

// ── JSON helpers ───────────────────────────────────────────────────────────

Map<String, dynamic>? _decodeEnvelope(String body) {
  final decoded = _decodeJson(body);
  if (decoded is! Map<String, dynamic>) return null;
  final data = decoded['data'];
  if (data is Map<String, dynamic>) {
    return Map<String, dynamic>.of(decoded)..['data'] = data;
  }
  return decoded;
}

Object? _decodeJson(String body) {
  if (body.trim().isEmpty) return null;
  try {
    return jsonDecode(body);
  } catch (_) {
    return null;
  }
}

int? _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value.trim());
  return null;
}

String _multipartBody(String boundary, Map<String, String> fields) {
  final buffer = StringBuffer();
  for (final entry in fields.entries) {
    buffer
      ..write('--$boundary\r\n')
      ..write('Content-Disposition: form-data; name="${entry.key}"\r\n\r\n')
      ..write(entry.value)
      ..write('\r\n');
  }
  buffer.write('--$boundary--\r\n');
  return buffer.toString();
}

extension on int {
  int toUInt32Safe() {
    // Deterministic non-negative seed for the multipart boundary.
    var value = this;
    if (value < 0) value = -value;
    return value & 0x7fffffff;
  }
}
