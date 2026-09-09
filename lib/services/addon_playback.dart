// Add-on playback resolver.
//
// The player and the download picker address content by *TMDB* ids, while
// Stremio add-ons address content by their own string ids (commonly IMDb
// "tt…" ids, sometimes "tmdb:<id>" or the bare TMDB id). This service
// translates between the two worlds:
//
//   1. enrich TMDB ids → IMDb id (best-effort, via the TMDB proxy)
//   2. probe candidate content-ids against every installed add-on that
//      offers a `stream` resource for the content type
//   3. aggregate + de-duplicate the resulting streams, preserving the
//      order in which the candidates matched
//
// SPDX-License-Identifier: GPL-3.0
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_config.dart';
import 'addon_catalog.dart';
import 'addon_content_models.dart';
import 'addon_models.dart';

/// One playable result matched against the content.
class AddonPlaybackSource {
  final AddonManifest manifest;
  final AddonStream stream;
  final String requestedId;

  const AddonPlaybackSource({
    required this.manifest,
    required this.stream,
    required this.requestedId,
  });

  String get addonName => manifest.name;

  /// Row title for pickers (quality comes from the stream label/description).
  String get title => stream.label;

  String? get description => stream.description;

  /// Whether this source is a torrent/magnet entry that needs
  /// a streaming server or debrid to resolve.
  bool get isTorrentStream => stream.isTorrent;
}

/// The transport `type` an add-on expects for a TMDB media type.
String addonTypeForMediaType(String mediaType) =>
    mediaType.toLowerCase() == 'tv' ? 'series' : 'movie';

/// Builds the candidate stream ids probed against add-ons, best match first.
///
/// Episodes are addressed as `<base>:<season>:<episode>`; the bare show id is
/// appended last as a fallback for add-ons that answer at series level.
List<String> buildAddonContentIdCandidates({
  String? tmdbId,
  String? imdbId,
  required bool isSeries,
  int? season,
  int? episode,
}) {
  final bases = <String>[];
  final imdb = imdbId?.trim();
  if (imdb != null && imdb.isNotEmpty) bases.add(imdb);
  final tmdb = tmdbId?.trim();
  if (tmdb != null && tmdb.isNotEmpty) {
    bases
      ..add('tmdb:$tmdb')
      ..add(tmdb);
  }
  final unique = <String>[];
  for (final base in bases) {
    if (base.isEmpty || unique.contains(base)) continue;
    unique.add(base);
  }

  final hasEpisode = isSeries && season != null && episode != null;
  final candidates = <String>[
    for (final base in unique)
      if (hasEpisode) episodeStreamId(base, season, episode) else base,
    // Show-level fallback for series (only when an episode was requested).
    if (hasEpisode) ...unique,
  ];
  final result = <String>[];
  for (final candidate in candidates) {
    if (!result.contains(candidate)) result.add(candidate);
  }
  return result;
}

/// Best-effort TMDB → IMDb lookup through the app's TMDB proxy. Returns null
/// when unavailable (offline, unknown id, proxy differences, …).
Future<String?> resolveImdbIdForTmdb({
  required String tmdbId,
  required String mediaType,
  http.Client? client,
}) async {
  final path = mediaType.toLowerCase() == 'tv'
      ? '/tmdb/tv/$tmdbId/external_ids'
      : '/tmdb/movie/$tmdbId/external_ids';
  try {
    final httpClient = client ?? http.Client();
    try {
      final response = await httpClient
          .get(Uri.parse('${ApiConfig.proxyBaseUrl}$path'))
          .timeout(const Duration(seconds: 5));
      if (response.statusCode != 200) return null;
      final decoded = _decodeJson(response.body);
      final imdb = decoded?['imdb_id'];
      if (imdb is String && imdb.isNotEmpty) return imdb;
      return null;
    } finally {
      if (client == null) httpClient.close();
    }
  } catch (_) {
    return null;
  }
}

/// Queries every installed add-on that can stream [mediaType] content and
/// returns the matched, de-duplicated sources ordered by candidate quality.
///
/// Set [skipImdbEnrichment] to avoid the TMDB proxy call when an IMDb id is
/// already known or explicitly unwanted.
Future<List<AddonPlaybackSource>> resolveAddonStreamsForContent({
  required List<AddonManifest> manifests,
  String? tmdbId,
  String? imdbId,
  required String mediaType,
  int? season,
  int? episode,
  bool skipImdbEnrichment = false,
  AddonDocumentFetcher? fetcher,
}) async {
  final type = addonTypeForMediaType(mediaType);
  final applicable = manifests
      .where((m) => addonOffersStreams(m, type))
      .toList(growable: false);
  if (applicable.isEmpty) return const [];

  final isSeries = type == 'series';

  var effectiveImdb = imdbId?.trim();
  if ((effectiveImdb == null || effectiveImdb.isEmpty) &&
      tmdbId != null &&
      tmdbId.isNotEmpty &&
      !skipImdbEnrichment) {
    try {
      effectiveImdb =
          await resolveImdbIdForTmdb(tmdbId: tmdbId, mediaType: mediaType);
    } catch (_) {
      effectiveImdb = null;
    }
  }

  final candidates = buildAddonContentIdCandidates(
    tmdbId: tmdbId,
    imdbId: effectiveImdb,
    isSeries: isSeries,
    season: isSeries ? season : null,
    episode: isSeries ? episode : null,
  );
  if (candidates.isEmpty) return const [];

  final results = <AddonPlaybackSource>[];
  final seen = <String>{};
  for (final candidateId in candidates) {
    await Future.wait(applicable.map((manifest) async {
      List<AddonStream> streams;
      try {
        streams = await fetchAddonStreams(
          manifest: manifest,
          type: type,
          id: candidateId,
          fetcher: fetcher,
        );
      } catch (_) {
        return;
      }
      for (final stream in streams) {
        final direct = stream.playableDirectUrl;
        final external = stream.openExternalUrl;
        // De-duplicate across add-ons and candidates: the same master/url
        // surfacing from several add-ons is still one source to the user.
        final key = direct ??
            external ??
            stream.infoHash ??
            '${manifest.transportUrl}|${stream.label}';
        if (!seen.add(key)) continue;
        results.add(AddonPlaybackSource(
          manifest: manifest,
          stream: stream,
          requestedId: candidateId,
        ));
      }
    }));
  }
  return results;
}

/// Pick the strongest stream for auto-play: first playable direct URL wins,
/// then streaming-server-resolved torrent URL, then external URL.
///
/// When [streamingServerBase] is non-null, torrent sources are resolved
/// through the Stremio streaming server (e.g. http://127.0.0.1:11470).
AddonPlaybackSource? bestPlayableSource(
  List<AddonPlaybackSource> sources, {
  String? streamingServerBase,
}) {
  for (final source in sources) {
    final url = source.stream.playableDirectUrl;
    if (url != null && url.isNotEmpty) return source;
  }
  if (streamingServerBase != null && streamingServerBase.isNotEmpty) {
    for (final source in sources) {
      if (!source.isTorrentStream) continue;
      final url = source.stream.streamingServerUrl(streamingServerBase);
      if (url != null && url.isNotEmpty) return source;
    }
  }
  return null;
}

Map<String, dynamic>? _decodeJson(String body) {
  try {
    final decoded = jsonDecode(body);
    return decoded is Map<String, dynamic> ? decoded : null;
  } catch (_) {
    return null;
  }
}
