// OpenSubtitles.com REST client — subtitle search + download for FEB.
//
// Pure Dart (no Rust/FFI). Search endpoints work without credentials;
// **downloads require an API key** (free tier: 200 downloads/day) set via
// [OpenSubtitlesService.apiKey] or the `opensubtitles_api_key` Hive box /
// 'opensubtitles_api_key' SharedPreferences key.
//
// Caching:
// - Search results: TTL'd in-memory (repeat searches <10ms) + Hive-backed
//   so results survive restarts.
// - Downloaded files: written through [SubtitleCacheHelper] (same directory
//   the wyzie subtitles already use, so the player finds them unchanged).
//
// Rate limiting: a 300ms gap is enforced between any two API calls —
// OpenSubtitles throttles bursts and 402s otherwise.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:http/http.dart' as http;

import 'subtitle_cache_helper.dart';
import 'wyzie_subtitle_service.dart';

const String _osBase = 'https://api.opensubtitles.com/api/v1';
const String _osDefaultUserAgent = 'MelaFilm v1.0.0';

class OpenSubtitlesException implements Exception {
  final String message;
  final int? statusCode;
  OpenSubtitlesException(this.message, {this.statusCode});
  @override
  String toString() => 'OpenSubtitlesException($statusCode): $message';
}

class _TtlEntry<T> {
  final T value;
  final DateTime storedAt;
  const _TtlEntry(this.value, this.storedAt);
  bool isFresh(Duration ttl) => DateTime.now().difference(storedAt) <= ttl;
}

/// One OpenSubtitles search hit, normalised into the app's subtitle model
/// ([WyzieSubtitleTrack]) so the existing subtitle UI consumes it unchanged.
/// Extra OpenSubtitles-specific fields are kept for ranking/display.
class OpenSubtitlesResult {
  final WyzieSubtitleTrack track;
  final int fileId;
  final double? rating;
  final int? downloads;
  final int? featureYear;

  const OpenSubtitlesResult({
    required this.track,
    required this.fileId,
    this.rating,
    this.downloads,
    this.featureYear,
  });

  /// Ranking heuristic: rating first, then download count (both proxies for
  /// sync quality / popularity on OpenSubtitles).
  double get score => (rating ?? 0) * 100 + min(downloads ?? 0, 10000) / 100.0;
}

/// Client for api.opensubtitles.com.
///
/// Usage:
/// ```dart
/// final os = OpenSubtitlesService();
/// await os.initialize();
/// os.setApiKey('<your key>'); // required for downloads
/// final results = await os.searchByImdbId('tt0468567');
/// final path = await os.downloadSubtitle(results.first);
/// ```
class OpenSubtitlesService {
  factory OpenSubtitlesService() => _instance;
  OpenSubtitlesService._();
  static final OpenSubtitlesService _instance = OpenSubtitlesService._();

  final http.Client _client = http.Client();
  static const Duration _minRequestGap = Duration(milliseconds: 300);
  static const Duration _searchTtl = Duration(minutes: 30);
  DateTime _lastRequestAt = DateTime.fromMillisecondsSinceEpoch(0);

  final Map<String, _TtlEntry<List<OpenSubtitlesResult>>> _memoryCache = {};
  Box<String>? _cacheBox;
  bool _initialized = false;

  /// API key — required for the download endpoint. Searches work without it.
  String _apiKey = '';

  /// Daily download accounting (best-effort local counter; the server has
  /// the authoritative number).
  int _downloadsToday = 0;
  DateTime _downloadCounterDay = DateTime.now();

  bool get isDownloadAvailable => _apiKey.isNotEmpty;
  int get downloadsToday => _downloadsToday;

  /// Open the Hive cache box and load any persisted API key / counters.
  Future<void> initialize() async {
    if (_initialized) return;
    try {
      _cacheBox = await Hive.openBox<String>('opensubtitles_cache');
      _apiKey = _cacheBox?.get('api_key') ?? '';
      final dayRaw = _cacheBox?.get('download_day');
      if (dayRaw != null) {
        final day = DateTime.tryParse(dayRaw);
        if (day != null && _sameUtcDay(day, DateTime.now())) {
          _downloadsToday = int.tryParse(_cacheBox!.get('dl_count') ?? '0') ?? 0;
          _downloadCounterDay = day;
        }
      }
    } catch (e) {
      debugPrint('OpenSubtitles init (cache unavailable): $e');
    }
    _initialized = true;
  }

  /// Store or clear the API key (empty string clears).
  Future<void> setApiKey(String key) async {
    _apiKey = key.trim();
    try {
      final box = _cacheBox ??= await Hive.openBox<String>('opensubtitles_cache');
      await box.put('api_key', _apiKey);
    } catch (_) {}
  }

  static bool _sameUtcDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  // ── Public search API ─────────────────────────────────────────────────

  /// Search by IMDb id (`tt…`). Pass [season]/[episode] for TV.
  Future<List<OpenSubtitlesResult>> searchByImdbId({
    required String imdbId,
    String languageCode = 'en',
    int? season,
    int? episode,
  }) {
    final cacheKey = 'imdb:$imdbId:$languageCode:$season:$episode';
    return _search(cacheKey, {
      'imdb_id': imdbId.replaceAll(RegExp(r'[^0-9]'), ''),
      if (languageCode.isNotEmpty) 'languages': languageCode,
      if (season != null) 'season_number': '$season',
      if (episode != null) 'episode_number': '$episode',
    });
  }

  /// Free-text search (name/year). [type] is `movie` or `tv`.
  Future<List<OpenSubtitlesResult>> searchByQuery({
    required String query,
    String languageCode = 'en',
    int? yearFilter,
    String type = 'movie',
  }) {
    final cacheKey = 'q:$query:$languageCode:$yearFilter:$type';
    return _search(cacheKey, {
      'query': query,
      if (languageCode.isNotEmpty) 'languages': languageCode,
      if (yearFilter != null) 'year': '$yearFilter',
      if (type == 'tv') 'type': 'episode' else 'type': 'movie',
    });
  }

  Future<List<OpenSubtitlesResult>> _search(
    String cacheKey,
    Map<String, String> query,
  ) async {
    // 1. Fresh memory cache.
    final mem = _memoryCache[cacheKey];
    if (mem != null && mem.isFresh(_searchTtl)) return mem.value;

    // 2. Hive cache (stale-while-error: only used when network fails).
    List<OpenSubtitlesResult>? fallback;
    try {
      final raw = _cacheBox?.get(cacheKey);
      if (raw != null) {
        final entry = _TtlEntry(_decodeResults(raw), DateTime.now());
        fallback = entry.value;
      }
    } catch (_) {}

    try {
      await _throttle();
      final uri = Uri.parse('$_osBase/subtitles').replace(
        queryParameters: {...query, if (!query.containsKey('languages')) 'languages': 'en'},
      );
      final response = await _client
          .get(uri, headers: _headers())
          .timeout(const Duration(seconds: 12));
      if (response.statusCode == 429 || response.statusCode == 402) {
        throw OpenSubtitlesException(
          'Rate limited by OpenSubtitles',
          statusCode: response.statusCode,
        );
      }
      if (response.statusCode != 200) {
        throw OpenSubtitlesException(
          'Search failed (${response.statusCode})',
          statusCode: response.statusCode,
        );
      }
      final results = _parseSearchResponse(response.body);
      _memoryCache[cacheKey] = _TtlEntry(results, DateTime.now());
      try {
        _cacheBox?.put(cacheKey, jsonEncode({
          'ts': DateTime.now().millisecondsSinceEpoch,
          'results': results.map((r) => _encodeResult(r)).toList(),
        }));
      } catch (_) {}
      return results;
    } on OpenSubtitlesException {
      if (fallback != null) return fallback;
      rethrow;
    } catch (e) {
      if (fallback != null) return fallback;
      throw OpenSubtitlesException('Search error: $e');
    }
  }

  // ── Public download API ───────────────────────────────────────────────

  /// Download [result] to the local subtitle cache and return its path.
  /// Throws [OpenSubtitlesException] when no API key is set, the daily
  /// limit was reached locally, or the download fails.
  Future<String> downloadSubtitle(OpenSubtitlesResult result) async {
    if (_apiKey.isEmpty) {
      throw OpenSubtitlesException(
        'OpenSubtitles API key required for downloads (Settings → Subtitles).',
      );
    }
    _rolloverDayIfNeeded();
    if (_downloadsToday >= 200) {
      throw OpenSubtitlesException('Daily download limit reached (200).');
    }

    await _throttle();
    final response = await _client
        .post(
          Uri.parse('$_osBase/download'),
          headers: {..._headers(), 'Content-Type': 'application/json'},
          body: jsonEncode({'file_id': result.fileId, 'sub_format': 'srt'}),
        )
        .timeout(const Duration(seconds: 20));
    if (response.statusCode == 402 || response.statusCode == 429) {
      throw OpenSubtitlesException('Daily download limit reached on the server.',
          statusCode: response.statusCode);
    }
    if (response.statusCode != 200) {
      throw OpenSubtitlesException(
        'Download failed (${response.statusCode})',
        statusCode: response.statusCode,
      );
    }
    final decoded = jsonDecode(_decodeMaybeGzip(response.bodyBytes))
        as Map<String, dynamic>;
    final link = (decoded['link'] ?? '').toString();
    if (link.isEmpty) {
      throw OpenSubtitlesException('No download link returned.');
    }

    await _throttle();
    final fileResponse = await _client
        .get(Uri.parse(link), headers: {'User-Agent': _osDefaultUserAgent})
        .timeout(const Duration(seconds: 30));
    if (fileResponse.statusCode != 200) {
      throw OpenSubtitlesException(
        'Subtitle file fetch failed (${fileResponse.statusCode})',
        statusCode: fileResponse.statusCode,
      );
    }

    final body = _decodeMaybeGzip(fileResponse.bodyBytes);
    final safeName = 'os_${result.fileId}_${result.track.languageCode}';
    final path = await SubtitleCacheHelper.writeSubtitleFile(
      body: body,
      format: 'srt',
      preferredName: safeName,
    );
    if (path == null) {
      throw OpenSubtitlesException('Subtitle file was empty or unreadable.');
    }

    _downloadsToday++;
    try {
      _cacheBox?.put('download_day', _downloadCounterDay.toIso8601String());
      _cacheBox?.put('dl_count', '$_downloadsToday');
    } catch (_) {}
    return path;
  }

  /// One-call convenience: search by IMDb id and download the best result.
  /// Returns the local file path, or null when nothing was found/downloaded.
  Future<String?> autoDownloadBestSubtitle({
    required String imdbId,
    String languageCode = 'en',
    int? season,
    int? episode,
  }) async {
    final results = await searchByImdbId(
      imdbId: imdbId,
      languageCode: languageCode,
      season: season,
      episode: episode,
    );
    if (results.isEmpty || !isDownloadAvailable) return null;
    final best = results.reduce((a, b) => a.score >= b.score ? a : b);
    try {
      return await downloadSubtitle(best);
    } catch (e) {
      debugPrint('OpenSubtitles auto-download failed: $e');
      return null;
    }
  }

  // ── Internals ─────────────────────────────────────────────────────────

  Map<String, String> _headers() => {
        'Accept': 'application/json',
        'User-Agent': _osDefaultUserAgent,
        if (_apiKey.isNotEmpty) 'Api-Key': _apiKey,
      };

  Future<void> _throttle() async {
    final since = DateTime.now().difference(_lastRequestAt);
    if (since < _minRequestGap) {
      await Future<void>.delayed(_minRequestGap - since);
    }
    _lastRequestAt = DateTime.now();
  }

  void _rolloverDayIfNeeded() {
    final now = DateTime.now();
    if (!_sameUtcDay(_downloadCounterDay, now)) {
      _downloadCounterDay = now;
      _downloadsToday = 0;
    }
  }

  String _decodeMaybeGzip(List<int> bytes) {
    try {
      // magic 0x1f 0x8b → gzip payload (OpenSubtitles gzips file responses).
      if (bytes.length > 2 && bytes[0] == 0x1f && bytes[1] == 0x8b) {
        return utf8.decode(gzip.decode(bytes), allowMalformed: true);
      }
      return utf8.decode(bytes, allowMalformed: true);
    } catch (_) {
      return utf8.decode(bytes, allowMalformed: true);
    }
  }

  List<OpenSubtitlesResult> _parseSearchResponse(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) return const [];
      final data = decoded['data'];
      if (data is! List) return const [];
      return data
          .whereType<Map<String, dynamic>>()
          .map(_parseSearchHit)
          .whereType<OpenSubtitlesResult>()
          .toList(growable: false);
    } catch (e) {
      debugPrint('OpenSubtitles parse error: $e');
      return const [];
    }
  }

  OpenSubtitlesResult? _parseSearchHit(Map<String, dynamic> hit) {
    try {
      final attrs = hit['attributes'];
      if (attrs is! Map<String, dynamic>) return null;
      final files = attrs['files'];
      int fileId = 0;
      if (files is List && files.isNotEmpty) {
        final first = files.firstWhere(
          (f) => f is Map<String, dynamic> && f['file_id'] != null,
          orElse: () => null,
        );
        if (first is Map<String, dynamic>) {
          fileId = int.tryParse('${first['file_id']}') ?? 0;
        }
      }
      if (fileId == 0) return null;

      final lang = (attrs['language'] ?? 'en').toString();
      final release = (attrs['release'] ?? attrs['release_info'] ?? '')
          .toString();
      final featureDetails = attrs['feature_details'];
      final year = featureDetails is Map<String, dynamic>
          ? int.tryParse('${featureDetails['year']}')
          : null;

      final track = WyzieSubtitleTrack(
        id: 'os_$fileId',
        url: '', // downloads go through the /download endpoint, not a URL
        languageCode: lang.length <= 3 ? lang.toLowerCase() : 'en',
        displayLanguage: _displayLanguage(lang),
        format: 'srt',
        source: 'OpenSubtitles',
        fileName: release.isEmpty ? null : release,
        isHearingImpaired: attrs['hearing_impaired'] == true,
      );
      return OpenSubtitlesResult(
        track: track,
        fileId: fileId,
        rating: (attrs['ratings'] as num?)?.toDouble(),
        downloads: attrs['download_count'] as int?,
        featureYear: year,
      );
    } catch (_) {
      return null;
    }
  }

  String _encodeResult(OpenSubtitlesResult r) => jsonEncode({
        'fileId': r.fileId,
        'rating': r.rating,
        'downloads': r.downloads,
        'featureYear': r.featureYear,
        'track': {
          'id': r.track.id,
          'url': r.track.url,
          'languageCode': r.track.languageCode,
          'displayLanguage': r.track.displayLanguage,
          'format': r.track.format,
          'source': r.track.source,
          'fileName': r.track.fileName,
          'isHearingImpaired': r.track.isHearingImpaired,
        },
      });

  List<OpenSubtitlesResult> _decodeResults(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return const [];
      final list = decoded['results'];
      if (list is! List) return const [];
      return list
          .whereType<Map<String, dynamic>>()
          .map((r) {
            final trackJson = r['track'];
            if (trackJson is! Map<String, dynamic>) return null;
            final track = WyzieSubtitleTrack(
              id: trackJson['id']?.toString() ?? '',
              url: trackJson['url']?.toString() ?? '',
              languageCode: trackJson['languageCode']?.toString() ?? 'en',
              displayLanguage:
                  trackJson['displayLanguage']?.toString() ?? 'English',
              format: trackJson['format']?.toString() ?? 'srt',
              source: trackJson['source']?.toString(),
              fileName: trackJson['fileName']?.toString(),
              isHearingImpaired: trackJson['isHearingImpaired'] == true,
            );
            return OpenSubtitlesResult(
              track: track,
              fileId: int.tryParse('${r['fileId']}') ?? 0,
              rating: (r['rating'] as num?)?.toDouble(),
              downloads: r['downloads'] as int?,
              featureYear: r['featureYear'] as int?,
            );
          })
          .whereType<OpenSubtitlesResult>()
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  static String _displayLanguage(String code) {
    const names = {
      'en': 'English', 'es': 'Spanish', 'fr': 'French', 'de': 'German',
      'it': 'Italian', 'pt': 'Portuguese', 'ru': 'Russian', 'ar': 'Arabic',
      'hi': 'Hindi', 'ja': 'Japanese', 'ko': 'Korean', 'zh': 'Chinese',
      'tr': 'Turkish', 'nl': 'Dutch', 'pl': 'Polish', 'sv': 'Swedish',
      'id': 'Indonesian', 'vi': 'Vietnamese', 'th': 'Thai', 'he': 'Hebrew',
      'bn': 'Bengali', 'ta': 'Tamil', 'te': 'Telugu', 'ml': 'Malayalam',
    };
    return names[code.toLowerCase()] ?? code.toUpperCase();
  }

  /// Clear search caches (memory + Hive). Downloaded files stay on disk.
  Future<void> clearCache() async {
    _memoryCache.clear();
    try {
      await _cacheBox?.clear();
    } catch (_) {}
  }

  void dispose() {
    _client.close();
    _initialized = false;
  }
}
