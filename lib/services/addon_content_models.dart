// Add-on content models + content-id strategy.
//
// Content comes from installed Stremio add-ons, whose ids are *strings*
// (e.g. IMDb-style "tt1234567", or addon-defined keys) unlike the app's
// TMDB-backed `Movie` model (numeric ids). To keep the two worlds apart
// without polluting `Movie`/Hive, add-on content is modeled here as
// [AddonCatalogItem] / [AddonMeta] / [AddonStream].
//
// Content-id conventions (Stremio protocol):
//   - a movie is addressed by its bare id:            `tt1234567`
//   - an episode is addressed as `<id>:<season>:<ep>` `tt1234567:1:2`
//   - resource URLs are `/{resource}/{type}/{id}.json`
//   - `type` is whatever the addon manifest declares ("movie" | "series",
//     occasionally "tv"/"anime" — preserved verbatim for transport and
//     normalized only for display / player routing via [normalizeContentType]).
library;

import 'dart:convert';

// ── Content-id helpers ───────────────────────────────────────────────────────

/// Canonical display type used for player routing and UI.
String normalizeContentType(String raw) {
  switch (raw.trim().toLowerCase()) {
    case 'tv':
    case 'show':
    case 'tvshow':
    case 'anime':
      return 'series';
    default:
      return raw.trim().toLowerCase();
  }
}

/// Stream-request id for one episode: `<contentId>:<season>:<episode>`.
String episodeStreamId(String contentId, int season, int episode) =>
    '$contentId:$season:$episode';

/// Splits `tt1234:1:2` → (contentId, 1, 2). Handles bare movie ids.
({String contentId, int? season, int? episode})? parseEpisodeStreamId(
  String id,
) {
  final parts = id.split(':');
  if (parts.length < 3) {
    return (contentId: id, season: null, episode: null);
  }
  final season = int.tryParse(parts[parts.length - 2]);
  final episode = int.tryParse(parts[parts.length - 1]);
  return (
    contentId: parts.take(parts.length - 2).join(':'),
    season: season,
    episode: episode,
  );
}

// ── Models ───────────────────────────────────────────────────────────────────

/// A single row from an addon catalog (Stremio "meta preview").
class AddonCatalogItem {
  final String id;
  final String type; // raw addon type: "movie" | "series" | …
  final String name;
  final String? poster;
  final String? background;
  final String? logo;
  final String? description;
  final String? releaseInfo; // year or range, e.g. "2023"
  final String? imdbRating;
  final List<String> genres;

  const AddonCatalogItem({
    required this.id,
    required this.type,
    required this.name,
    this.poster,
    this.background,
    this.logo,
    this.description,
    this.releaseInfo,
    this.imdbRating,
    this.genres = const [],
  });

  bool get isSeries => normalizeContentType(type) == 'series';

  factory AddonCatalogItem.fromJson(Map<String, dynamic> json) =>
      AddonCatalogItem(
        id: _string(json, 'id'),
        type: _stringOr(json, 'type', 'movie'),
        name: _stringOr(json, 'name', 'Untitled'),
        poster: _nullableString(json, 'poster'),
        background: _nullableString(json, 'background') ??
            _nullableString(json, 'backdrop'),
        logo: _nullableString(json, 'logo'),
        description: _nullableString(json, 'description'),
        releaseInfo: _nullableString(json, 'releaseInfo'),
        imdbRating: _nullableString(json, 'imdbRating'),
        genres: _stringList(json, 'genres'),
      );
}

/// Full meta document (`meta` resource). For series this carries the episode
/// list under [videos] (season/episode/thumbnail/released).
class AddonMeta {
  final String id;
  final String type;
  final String name;
  final String? poster;
  final String? background;
  final String? logo;
  final String? description;
  final String? releaseInfo;
  final String? imdbRating;
  final List<String> genres;
  final List<String> director;
  final List<AddonCastMember> cast;
  final String? runtime;
  final String? country;
  final List<AddonVideo> videos;

  const AddonMeta({
    required this.id,
    required this.type,
    required this.name,
    this.poster,
    this.background,
    this.logo,
    this.description,
    this.releaseInfo,
    this.imdbRating,
    this.genres = const [],
    this.director = const [],
    this.cast = const [],
    this.runtime,
    this.country,
    this.videos = const [],
  });

  bool get isSeries => normalizeContentType(type) == 'series';

  factory AddonMeta.fromJson(Map<String, dynamic> json) {
    final videosRaw = json['videos'];
    return AddonMeta(
      id: _string(json, 'id'),
      type: _stringOr(json, 'type', 'movie'),
      name: _stringOr(json, 'name', 'Untitled'),
      poster: _nullableString(json, 'poster'),
      background: _nullableString(json, 'background') ??
          _nullableString(json, 'backdrop'),
      logo: _nullableString(json, 'logo'),
      description: _nullableString(json, 'description'),
      releaseInfo: _nullableString(json, 'releaseInfo'),
      imdbRating: _nullableString(json, 'imdbRating'),
      genres: _stringList(json, 'genres'),
      director: _stringList(json, 'director'),
      cast: (json['cast'] is List)
          ? (json['cast'] as List)
              .whereType<Map<String, dynamic>>()
              .map(AddonCastMember.fromJson)
              .toList(growable: false)
          : const [],
      runtime: _nullableString(json, 'runtime'),
      country: _nullableString(json, 'country'),
      videos: videosRaw is List
          ? videosRaw
              .whereType<Map<String, dynamic>>()
              .map(AddonVideo.fromJson)
              .toList(growable: false)
          : const [],
    );
  }
}

class AddonCastMember {
  final String? name;
  final String? image;

  const AddonCastMember({this.name, this.image});

  factory AddonCastMember.fromJson(Map<String, dynamic> json) => AddonCastMember(
        name: _nullableString(json, 'name'),
        image: _nullableString(json, 'image'),
      );
}

class AddonVideo {
  final String? id;
  final String? title;
  final int? season;
  final int? episode;
  final String? overview;
  final String? released;
  final String? thumbnail;
  final bool? available;

  const AddonVideo({
    this.id,
    this.title,
    this.season,
    this.episode,
    this.overview,
    this.released,
    this.thumbnail,
    this.available,
  });

  String get displayCode {
    if (season == null && episode == null) return '';
    if (season == null) return 'E$episode';
    if (episode == null) return 'S$season';
    return 'S${season}E$episode';
  }

  factory AddonVideo.fromJson(Map<String, dynamic> json) => AddonVideo(
        id: _nullableString(json, 'id'),
        title: _nullableString(json, 'title'),
        season: _nullableInt(json, 'season'),
        episode: _nullableInt(json, 'episode'),
        overview: _nullableString(json, 'overview'),
        released: _nullableString(json, 'released'),
        thumbnail: _nullableString(json, 'thumbnail'),
        available: _nullableBool(json, 'available'),
      );
}

/// One entry in a `stream` resource response.
class AddonStream {
  final String? name;
  final String? title;
  final String? description;
  final String? url;
  final String? infoHash;
  final int? fileIdx;
  final String? externalUrl;
  final List<String> sources;
  final List<AddonSubtitle> subtitles;
  final bool notWebReady;
  final String? bingeGroup;
  final String? filename;
  final int? videoSize;
  final bool p2p;

  const AddonStream({
    this.name,
    this.title,
    this.description,
    this.url,
    this.infoHash,
    this.fileIdx,
    this.externalUrl,
    this.sources = const [],
    this.subtitles = const [],
    this.notWebReady = false,
    this.bingeGroup,
    this.filename,
    this.videoSize,
    this.p2p = false,
  });

  /// Display label (falls back to name → title → "Stream").
  String get label {
    final n = name?.trim();
    if (n != null && n.isNotEmpty) return n;
    final t = title?.trim();
    if (t != null && t.isNotEmpty) return t;
    return 'Stream';
  }

  /// A URL the player can consume directly (.m3u8/.mp4/.webm).
  String? get playableDirectUrl {
    final u = url?.trim();
    if (u == null || u.isEmpty) return null;
    final lower = u.toLowerCase();
    if (lower.startsWith('magnet:') ||
        lower.startsWith('torrent://') ||
        lower.startsWith('http') == false) {
      return null;
    }
    return u;
  }

  /// True when this entry must be opened in an external app/browser.
  bool get isExternalOnly =>
      (url == null || url!.isEmpty) &&
      externalUrl != null &&
      externalUrl!.isNotEmpty &&
      infoHash == null;

  String? get openExternalUrl {
    final u = externalUrl?.trim();
    if (u == null || u.isEmpty) return null;
    final lower = u.toLowerCase();
    if (lower.startsWith('magnet:') || lower.startsWith('torrent://')) {
      return null;
    }
    return u;
  }

  /// True for torrent entries (magnet / infohash) that need debrid or P2P.
  bool get isTorrent =>
      infoHash != null ||
      ((url?.toLowerCase().startsWith('magnet:') ?? false) ||
          (externalUrl?.toLowerCase().startsWith('magnet:') ?? false));

  /// Builds a streaming-server URL for torrent/magnet streams
  /// when [streamingServerBase] is configured (e.g. Stremio core at
  /// http://127.0.0.1:11470). Returns null for non-torrent streams.
  String? streamingServerUrl(String streamingServerBase) {
    final base = streamingServerBase.trim();
    if (base.isEmpty) return null;
    final hash = infoHash?.trim();
    if (hash == null || hash.isEmpty) return null;
    try {
      var url = Uri.parse(base);
      final segments = url.pathSegments.toList()..addAll([hash, fileIdx?.toString() ?? '-1']);
      url = url.replace(pathSegments: segments);
      final query = <String, String>{};
      for (final tr in sources) {
        if (tr.isNotEmpty) query['tr'] = tr;
      }
      if (query.isNotEmpty) {
        url = url.replace(queryParameters: query);
      }
      return url.toString();
    } catch (_) {
      return null;
    }
  }

  factory AddonStream.fromJson(Map<String, dynamic> json) {
    final hints = json['behaviorHints'];
    final Map<String, dynamic> hintMap =
        hints is Map<String, dynamic> ? hints : const {};
    final subsRaw = json['subtitles'];
    final rawSources = json['sources'];
    return AddonStream(
      name: _nullableString(json, 'name'),
      title: _nullableString(json, 'title'),
      description: _nullableString(json, 'description'),
      url: _nullableString(json, 'url'),
      infoHash: _nullableString(json, 'infoHash'),
      fileIdx: _nullableInt(json, 'fileIdx'),
      externalUrl: _nullableString(json, 'externalUrl'),
      sources: rawSources is List
          ? rawSources
              .whereType<String>()
              .map((s) => s.trim())
              .where((s) => s.isNotEmpty)
              .toList(growable: false)
          : const [],
      subtitles: subsRaw is List
          ? subsRaw
              .whereType<Map<String, dynamic>>()
              .map(AddonSubtitle.fromJson)
              .toList(growable: false)
          : const [],
      notWebReady: hintMap['notWebReady'] == true,
      bingeGroup: _nullableString(hintMap, 'bingeGroup'),
      filename: _nullableString(hintMap, 'filename'),
      videoSize: _nullableInt(hintMap, 'videoSize'),
      p2p: hintMap['p2p'] == true,
    );
  }
}

class AddonSubtitle {
  final String url;
  final String? lang;
  final String? name;
  final Map<String, String>? headers;

  const AddonSubtitle({
    required this.url,
    this.lang,
    this.name,
    this.headers,
  });

  factory AddonSubtitle.fromJson(Map<String, dynamic> json) {
    final rawHeaders = json['headers'];
    return AddonSubtitle(
      url: _string(json, 'url'),
      lang: _nullableString(json, 'lang') ?? _nullableString(json, 'language'),
      name: _nullableString(json, 'name'),
      headers: rawHeaders is Map
          ? rawHeaders.map(
              (k, v) => MapEntry(k.toString(), v?.toString() ?? ''))
          : null,
    );
  }
}

// ── Tolerant JSON helpers ────────────────────────────────────────────────────

Map<String, dynamic>? asJsonMap(Object? value) =>
    value is Map<String, dynamic> ? value : null;

List<AddonCatalogItem> parseCatalogItems(String payload) {
  final root = _decodeRoot(payload);
  if (root == null) return const [];
  final metas = root['metas'];
  if (metas is! List) return const [];
  return metas
      .whereType<Map<String, dynamic>>()
      .map(AddonCatalogItem.fromJson)
      .where((item) => item.id.isNotEmpty)
      .toList(growable: false);
}

AddonMeta? parseAddonMeta(String payload) {
  final root = _decodeRoot(payload);
  if (root == null) return null;
  final meta = asJsonMap(root['meta']);
  if (meta == null) return null;
  final parsed = AddonMeta.fromJson(meta);
  return parsed.id.isEmpty ? null : parsed;
}

List<AddonStream> parseAddonStreams(String payload) {
  final root = _decodeRoot(payload);
  if (root == null) return const [];
  final streams = root['streams'];
  if (streams is! List) return const [];
  return streams
      .whereType<Map<String, dynamic>>()
      .map(AddonStream.fromJson)
      .where((s) => (s.url?.isNotEmpty ?? false) ||
          (s.externalUrl?.isNotEmpty ?? false) ||
          s.infoHash != null)
      .toList(growable: false);
}

/// Decodes a resource body into a JSON object; malformed documents yield null
/// so callers degrade to an empty result instead of throwing.
Map<String, dynamic>? _decodeRoot(String payload) {
  try {
    return asJsonMap(jsonDecode(payload));
  } catch (_) {
    return null;
  }
}

String _string(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is String) return value;
  return '';
}

String _stringOr(Map<String, dynamic> json, String key, String fallback) {
  final value = json[key];
  if (value is String && value.trim().isNotEmpty) return value;
  return fallback;
}

String? _nullableString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is String) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
  return null;
}

List<String> _stringList(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! List) return const [];
  return value
      .whereType<String>()
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList(growable: false);
}

int? _nullableInt(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is int) return value;
  if (value is String) return int.tryParse(value);
  if (value is num) return value.toInt();
  return null;
}

bool? _nullableBool(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is bool) return value;
  return null;
}
