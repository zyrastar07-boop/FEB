import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'api_config.dart';
import 'compression_client.dart';
import 'subtitle_cache_helper.dart';

/// One subtitle track from wyzie-subs / sub.wyzie.io.
class WyzieSubtitleTrack {
  final String id;
  final String url;
  final String languageCode;
  final String displayLanguage;
  final String format; // srt | vtt | ass …
  final String? source;
  final String? fileName;
  final bool isHearingImpaired;

  const WyzieSubtitleTrack({
    required this.id,
    required this.url,
    required this.languageCode,
    required this.displayLanguage,
    required this.format,
    this.source,
    this.fileName,
    this.isHearingImpaired = false,
  });

  factory WyzieSubtitleTrack.fromJson(Map<String, dynamic> json) {
    final lang = (json['language'] ?? json['lang'] ?? '').toString();
    final display = (json['display'] ??
            json['displayLanguage'] ??
            json['languageName'] ??
            lang)
        .toString();
    final format = (json['format'] ?? json['encoding'] ?? 'srt')
        .toString()
        .toLowerCase()
        .replaceAll('.', '');
    final url = (json['url'] ?? json['link'] ?? json['file'] ?? '').toString();
    final id = (json['id'] ?? url).toString();

    return WyzieSubtitleTrack(
      id: id,
      url: url,
      languageCode: lang.length == 2 ? lang.toLowerCase() : lang,
      displayLanguage: display.isEmpty ? lang : display,
      format: format.isEmpty ? 'srt' : format,
      source: json['source']?.toString(),
      fileName: json['fileName']?.toString() ?? json['filename']?.toString(),
      isHearingImpaired: json['isHearingImpaired'] == true ||
          json['hearingImpaired'] == true ||
          (display.toLowerCase().contains('hi') &&
              display.toLowerCase().contains('hearing')),
    );
  }

  bool get isSrt => format.contains('srt');
  bool get isVtt => format.contains('vtt');
}

class WyzieSubtitleException implements Exception {
  final String message;
  final int? statusCode;
  WyzieSubtitleException(this.message, {this.statusCode});
  @override
  String toString() => 'WyzieSubtitleException($statusCode): $message';
}

class _TtlEntry<T> {
  final T value;
  final DateTime storedAt;
  const _TtlEntry(this.value, this.storedAt);

  bool isFresh(Duration ttl) => DateTime.now().difference(storedAt) <= ttl;
}

/// Client for Wyzie Subs.
///
/// Wyzie now requires a free API key on every request
/// (`&key=…` — claim at https://store.wyzie.io/redeem).
///
/// This service prefers your existing Cloudflare proxy (key injected
/// server-side, same pattern as [WyzieService] / ApiConfig) and only
/// falls back to direct `sub.wyzie.io` when [apiKey] is set.
///
/// - 12s HTTP timeout
/// - Never throws into the UI (empty list / null body)
/// - UTF-8 body decoding for accents / CJK
/// - Process-lifetime in-memory cache (10 min) for search + downloads
class WyzieSubtitleService {
  WyzieSubtitleService({
    /// Cloudflare / worker base that injects the key (no trailing slash).
    /// Defaults to the load-balanced ApiConfig proxy so mirror failover
    /// applies here too.
    String? proxyBaseUrl,
    this.directBaseUrl = 'https://sub.wyzie.io',
    /// Optional free/pro key for direct calls. Prefer the proxy instead.
    this.apiKey,
    this.timeout = const Duration(seconds: 12),
    http.Client? client,
  })  : proxyBaseUrl = proxyBaseUrl ?? ApiConfig.proxyBaseUrl,
        _client = client ?? CompressionClient(http.Client());
    /// Direct Wyzie host — only used when [apiKey] is non-empty.
  final String proxyBaseUrl;
  final String directBaseUrl;
  final String? apiKey;
  final Duration timeout;
  final http.Client _client;

  /// Last human-readable search failure (401 / 429 / network).
  /// Cleared on a successful non-empty search.
  String? lastError;

  /// Shared across all service instances in this process.
  static const Duration cacheTtl = Duration(minutes: 10);
  static final Map<String, _TtlEntry<List<WyzieSubtitleTrack>>> _searchCache =
      {};
  static final Map<String, _TtlEntry<String>> _bodyCache = {};

  /// Map display names → ISO 639-1 (safe for API language filters).
  static String toIsoLanguage(String language) {
    const map = <String, String>{
      'english': 'en',
      'spanish': 'es',
      'french': 'fr',
      'german': 'de',
      'arabic': 'ar',
      'italian': 'it',
      'portuguese': 'pt',
      'russian': 'ru',
      'japanese': 'ja',
      'korean': 'ko',
      'chinese': 'zh',
      'mandarin': 'zh',
      'hindi': 'hi',
      'turkish': 'tr',
      'dutch': 'nl',
      'polish': 'pl',
      'swedish': 'sv',
      'norwegian': 'no',
      'danish': 'da',
      'finnish': 'fi',
      'greek': 'el',
      'hebrew': 'he',
      'thai': 'th',
      'vietnamese': 'vi',
      'indonesian': 'id',
      'romanian': 'ro',
      'czech': 'cs',
      'hungarian': 'hu',
      'ukrainian': 'uk',
      'amharic': 'am',
      'off': 'off',
    };
    final key = language.trim().toLowerCase();
    if (key.length == 2) return key;
    return map[key] ?? key;
  }

  /// Search tracks by TMDB id and/or IMDb id (`tt…`).
  ///
  /// Returns an empty list on network/HTTP errors (does not throw).
  /// Fresh results are cached for [cacheTtl].
  Future<List<WyzieSubtitleTrack>> search({
    String? tmdbId,
    String? imdbId,
    int? season,
    int? episode,
    String? language,
    /// Empty = all formats (more hits). Pass `srt` to narrow.
    String format = '',
  }) async {
    lastError = null;
    final id = _resolveId(tmdbId: tmdbId, imdbId: imdbId);
    if (id == null) {
      lastError = 'No valid TMDB or IMDb ID.';
      debugPrint('WyzieSubtitleService: no valid id');
      return const [];
    }

    final params = <String, String>{
      'id': id,
      if (format.isNotEmpty) 'format': format,
    };

    final iso = language == null || language.isEmpty
        ? null
        : toIsoLanguage(language);
    if (iso != null && iso.isNotEmpty && iso != 'off') {
      params['language'] = iso;
    }
    if (season != null && season > 0) params['season'] = season.toString();
    if (episode != null && episode > 0) params['episode'] = episode.toString();

    final cacheKey = params.entries.map((e) => '${e.key}=${e.value}').join('&');
    final cached = _searchCache[cacheKey];
    if (cached != null && cached.isFresh(cacheTtl)) {
      debugPrint('WyzieSubtitleService search cache hit: $cacheKey');
      return List<WyzieSubtitleTrack>.from(cached.value);
    }

    // 1) Proxy first (key injected server-side — preferred).
    final proxyCandidates = <Uri>[
      Uri.parse('$proxyBaseUrl/search')
          .replace(queryParameters: params),
      Uri.parse('$proxyBaseUrl/wyzie/search')
          .replace(queryParameters: params),
      Uri.parse('$proxyBaseUrl/subtitles/search')
          .replace(queryParameters: params),
    ];

    for (final uri in proxyCandidates) {
      final tracks = await _getTracks(uri, cacheKey: cacheKey, cached: cached);
      if (tracks != null) {
        if (tracks.isNotEmpty) lastError = null;
        return tracks;
      }
    }

    // 2) Direct Wyzie only when a free/pro key is configured.
    final key = apiKey?.trim();
    if (key != null && key.isNotEmpty) {
      final directParams = Map<String, String>.from(params)..['key'] = key;
      final uri = Uri.parse('$directBaseUrl/search')
          .replace(queryParameters: directParams);
      final tracks = await _getTracks(uri, cacheKey: cacheKey, cached: cached);
      if (tracks != null) {
        if (tracks.isNotEmpty) lastError = null;
        return tracks;
      }
    } else if (lastError == null || lastError!.isEmpty) {
      lastError =
          'Wyzie needs a free API key (or a working proxy). '
          'Claim one at store.wyzie.io/redeem, or keep using your Cloudflare worker.';
    }

    if (cached != null) {
      debugPrint('WyzieSubtitleService: serving stale search cache');
      return List<WyzieSubtitleTrack>.from(cached.value);
    }
    return const [];
  }

  /// Returns null on hard failure (caller may try next URL).
  /// Returns a (possibly empty) list on a successful HTTP JSON response.
  Future<List<WyzieSubtitleTrack>?> _getTracks(
    Uri uri, {
    required String cacheKey,
    required _TtlEntry<List<WyzieSubtitleTrack>>? cached,
  }) async {
    debugPrint('WyzieSubtitleService search: $uri');
    try {
      final response = await _client.get(
        uri,
        headers: const {
          'Accept': 'application/json',
          'User-Agent': 'FEB-Player/1.0',
        },
      ).timeout(timeout);

      final body = utf8.decode(response.bodyBytes, allowMalformed: true);

      if (response.statusCode == 429 || response.statusCode == 503) {
        ApiConfig.reportProxyFailure();
        lastError =
            'Wyzie daily limit reached. Resets at midnight UTC, or use another key.';
        debugPrint(
            'WyzieSubtitleService: rate-limited (${response.statusCode})');
        return null;
      }
      if (response.statusCode == 401 || response.statusCode == 403) {
        lastError =
            'Wyzie rejected the request (missing/invalid API key). '
            'Claim a free key at store.wyzie.io/redeem.';
        debugPrint(
            'WyzieSubtitleService: auth ${response.statusCode} — $body');
        return null;
      }
      if (response.statusCode >= 500) ApiConfig.reportProxyFailure();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        // Worker may wrap upstream errors as 502 with JSON body.
        final upstream = _parseUpstreamError(body);
        if (upstream != null) {
          lastError = upstream;
          debugPrint('WyzieSubtitleService: upstream error — $upstream');
          return null;
        }
        debugPrint('WyzieSubtitleService: HTTP ${response.statusCode}');
        lastError = 'Wyzie request failed (${response.statusCode}).';
        return null;
      }

      if (body.trim().isEmpty) return const [];

      final dynamic decoded = jsonDecode(body);

      // Worker / API error shapes even on 200.
      if (decoded is Map) {
        final code = decoded['code'];
        final err = decoded['error']?.toString();
        final msg = decoded['message']?.toString();
        if (code == 401 || code == 403) {
          lastError =
              'Wyzie API key required. Claim free at store.wyzie.io/redeem.';
          return null;
        }
        if (code == 429) {
          lastError =
              'Wyzie daily limit reached. Resets at midnight UTC.';
          return null;
        }
        if (err != null &&
            (err.toLowerCase().contains('wyzie') ||
                err.toLowerCase().contains('upstream'))) {
          lastError = msg ?? err;
          return null;
        }
      }

      final List<dynamic> list;
      if (decoded is List) {
        list = decoded;
      } else if (decoded is Map && decoded['data'] is List) {
        list = decoded['data'] as List;
      } else if (decoded is Map && decoded['subtitles'] is List) {
        list = decoded['subtitles'] as List;
      } else if (decoded is Map && decoded['url'] != null) {
        // Single-object response
        list = [decoded];
      } else {
        debugPrint('WyzieSubtitleService: unexpected JSON shape');
        return const [];
      }

      final tracks = <WyzieSubtitleTrack>[];
      for (final item in list) {
        if (item is! Map) continue;
        try {
          final track =
              WyzieSubtitleTrack.fromJson(Map<String, dynamic>.from(item));
          if (track.url.isEmpty) continue;
          tracks.add(track);
        } catch (e) {
          debugPrint('WyzieSubtitleService: skip bad item: $e');
        }
      }

      _searchCache[cacheKey] = _TtlEntry(
        List<WyzieSubtitleTrack>.from(tracks),
        DateTime.now(),
      );
      _pruneCache(_searchCache);
      ApiConfig.reportProxySuccess();
      return tracks;
    } catch (e, st) {
      ApiConfig.reportProxyFailure();
      debugPrint('WyzieSubtitleService search error ($uri): $e\n$st');
      lastError = 'Network error talking to Wyzie.';
      return null;
    }
  }

  String? _parseUpstreamError(String body) {
    try {
      final dynamic decoded = jsonDecode(body);
      if (decoded is! Map) return null;
      // {"error":"Wyzie upstream error","status":429,"body":"{...}"}
      final nested = decoded['body']?.toString();
      if (nested != null && nested.isNotEmpty) {
        try {
          final inner = jsonDecode(nested);
          if (inner is Map) {
            final code = inner['code'];
            final msg = inner['message']?.toString();
            if (code == 429) {
              return 'Wyzie daily limit reached. Resets at midnight UTC.';
            }
            if (code == 401 || code == 403) {
              return 'Wyzie API key required. Claim free at store.wyzie.io/redeem.';
            }
            if (msg != null && msg.isNotEmpty) return msg;
          }
        } catch (_) {}
      }
      final msg = decoded['message']?.toString() ?? decoded['error']?.toString();
      return msg;
    } catch (_) {
      return null;
    }
  }

  /// Download subtitle file body as UTF-8 text.
  /// Returns null on failure (never throws). Cached for [cacheTtl].
  Future<String?> downloadBody(String url) async {
    if (url.trim().isEmpty) return null;

    final cached = _bodyCache[url];
    if (cached != null && cached.isFresh(cacheTtl)) {
      debugPrint('WyzieSubtitleService body cache hit');
      return cached.value;
    }

    // Prefer proxy for sub.wyzie.io CDN paths so the key is not needed client-side.
    final targets = <String>[url];
    final lower = url.toLowerCase();
    if (lower.contains('sub.wyzie.io') || lower.contains('sub.wyzie.ru')) {
      final encoded = Uri.encodeComponent(url);
      targets.insert(0, '$proxyBaseUrl/wyzie/fetch?url=$encoded');
      targets.insert(0, '$proxyBaseUrl/fetch?url=$encoded');
    }

    for (final target in targets) {
      try {
        final response = await _client.get(
          Uri.parse(target),
          headers: const {
            'Accept': 'text/plain, text/vtt, application/x-subrip, */*',
            'User-Agent':
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
                    '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
            'Referer': 'https://sub.wyzie.io/',
            'Origin': 'https://sub.wyzie.io',
          },
        ).timeout(timeout);

        if (response.statusCode < 200 || response.statusCode >= 300) {
          debugPrint(
              'WyzieSubtitleService download HTTP ${response.statusCode} ($target)');
          continue;
        }

        final text = utf8.decode(response.bodyBytes, allowMalformed: true);
        if (!_looksLikeSubtitle(text)) continue;

        _bodyCache[url] = _TtlEntry(text, DateTime.now());
        _pruneCache(_bodyCache);
        return text;
      } catch (e) {
        debugPrint('WyzieSubtitleService download error ($target): $e');
      }
    }
    return cached?.value;
  }

  static bool _looksLikeSubtitle(String body) {
    if (body.trim().isEmpty) return false;
    final sample = body.length > 4000 ? body.substring(0, 4000) : body;
    return sample.contains('-->') ||
        sample.toUpperCase().contains('WEBVTT') ||
        RegExp(r'\d{2}:\d{2}:\d{2}').hasMatch(sample);
  }

  /// Download a track and persist it as a local SRT/VTT file.
  Future<({WyzieSubtitleTrack track, String body, String? localPath})?>
      downloadTrackToFile(WyzieSubtitleTrack track) async {
    final body = await downloadBody(track.url);
    if (body == null || body.trim().isEmpty) return null;

    final localPath = await SubtitleCacheHelper.writeSubtitleFile(
      body: body,
      format: track.format,
      preferredName: track.fileName ?? track.id,
    );
    return (track: track, body: body, localPath: localPath);
  }

  /// Search + download first usable track for [language] (or first track).
  Future<({WyzieSubtitleTrack track, String body, String? localPath})?>
      fetchPreferred({
    String? tmdbId,
    String? imdbId,
    int? season,
    int? episode,
    String? language,
  }) async {
    final tracks = await search(
      tmdbId: tmdbId,
      imdbId: imdbId,
      season: season,
      episode: episode,
      language: language,
    );
    if (tracks.isEmpty) return null;

    for (final track in tracks) {
      final saved = await downloadTrackToFile(track);
      if (saved != null) return saved;
    }
    return null;
  }

  String? _resolveId({String? tmdbId, String? imdbId}) {
    final imdb = imdbId?.trim();
    if (imdb != null && imdb.isNotEmpty) {
      if (imdb.startsWith('tt')) return imdb;
      if (RegExp(r'^\d+$').hasMatch(imdb)) return 'tt$imdb';
      return imdb;
    }
    final tmdb = tmdbId?.trim();
    if (tmdb != null && tmdb.isNotEmpty && tmdb != '0') return tmdb;
    return null;
  }

  static void _pruneCache<T>(Map<String, _TtlEntry<T>> cache) {
    if (cache.length < 48) return;
    final stale = <String>[];
    cache.forEach((k, v) {
      if (!v.isFresh(cacheTtl)) stale.add(k);
    });
    for (final k in stale) {
      cache.remove(k);
    }
  }

  static void clearMemoryCache() {
    _searchCache.clear();
    _bodyCache.clear();
  }

  void dispose() {
    _client.close();
  }
}