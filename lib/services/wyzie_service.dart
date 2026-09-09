import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'api_config.dart';
import 'compression_client.dart';

class WyzieSubtitle {
  final String id;
  final String url;
  final String? flagUrl;
  final String format;
  final String? encoding;
  final String display;
  final String language;
  final String? media;
  final bool? isHearingImpaired;
  final String? source;
  final String? fileName;

  WyzieSubtitle.fromJson(Map<String, dynamic> json)
      : id = (json['id'] ?? '').toString(),
        url = (json['url'] ?? '').toString(),
        flagUrl = json['flagUrl']?.toString(),
        format = (json['format'] ?? 'srt').toString(),
        encoding = json['encoding']?.toString(),
        display = (json['display'] ?? '').toString(),
        language = (json['language'] ?? '').toString(),
        media = json['media']?.toString(),
        isHearingImpaired = json['isHearingImpaired'] as bool?,
        source = json['source']?.toString(),
        fileName = json['fileName']?.toString();
}

class WyzieError implements Exception {
  final String message;
  WyzieError(this.message);
  @override
  String toString() => 'WyzieError: $message';
}

/// Subtitles via Cloudflare Worker — Wyzie API key never ships in the APK.
class WyzieService {
  final Duration timeout;

  WyzieService({this.timeout = const Duration(seconds: 15)});

  static String toIsoLanguage(String language) {
    final map = <String, String>{
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
    };
    final key = language.trim().toLowerCase();
    if (key.length == 2) return key;
    return map[key] ?? key;
  }

  Future<List<WyzieSubtitle>> searchSubtitles({
    int? tmdbId,
    String? imdbId,
    int? season,
    int? episode,
    String? language,
    String format = 'srt',
  }) async {
    final hasTmdb = tmdbId != null && tmdbId > 0;
    final hasImdb = imdbId != null && imdbId.trim().isNotEmpty;
    if (!hasTmdb && !hasImdb) {
      throw WyzieError('Provide a valid TMDB or IMDb ID.');
    }

    final idValue = hasTmdb ? tmdbId.toString() : imdbId!.trim();
    final isoLang =
        language == null || language.isEmpty ? null : toIsoLanguage(language);

    final params = <String, String>{
      'id': idValue,
      'format': format,
      // Pull more providers so we are not stuck with only OpenSubtitles CDN links.
      'source': 'opensubtitles,subdl,podnapisi',
      if (isoLang != null && isoLang.isNotEmpty) 'language': isoLang,
      if (season != null && episode != null) ...{
        'season': season.toString(),
        'episode': episode.toString(),
      },
    };

    try {
      final client = CompressionClient(http.Client());
      final response = await client
          .get(
            Uri.parse(ApiConfig.wyzieSearch(params)),
            headers: {'Accept': 'application/json'},
          )
          .timeout(timeout);
      client.close();

      // Feed the load balancer: rate-limits/server errors = endpoint failure.
      if (response.statusCode >= 500 || response.statusCode == 429) {
        ApiConfig.reportProxyFailure();
      } else {
        ApiConfig.reportProxySuccess();
      }

      if (response.statusCode == 429) {
        throw WyzieError('Wyzie rate limit reached. Try again later.');
      }
      if (response.statusCode != 200) {
        throw WyzieError('Wyzie request failed (${response.statusCode})');
      }

      final data = jsonDecode(response.body);
      if (data is List) {
        return data
            .whereType<Map>()
            .map((item) =>
                WyzieSubtitle.fromJson(Map<String, dynamic>.from(item)))
            .where((s) => s.url.isNotEmpty)
            .toList();
      } else if (data is Map<String, dynamic> && data.containsKey('url')) {
        final sub = WyzieSubtitle.fromJson(data);
        return sub.url.isNotEmpty ? [sub] : <WyzieSubtitle>[];
      }
      return [];
    } catch (err) {
      if (err is WyzieError) rethrow;
      ApiConfig.reportProxyFailure();
      throw WyzieError('Failed to fetch subtitles: $err');
    }
  }

  /// Downloads subtitle body — mirrors the working React Native client:
  /// bare `fetch(url)` against the track URL, with browser-like headers so
  /// Dart's default User-Agent is not sent (OpenSubtitles returns 401 for
  /// `Dart/...` agents).
  ///
  /// Routing:
  /// - OpenSubtitles / external CDNs → **direct only** (Worker uses CF IPs
  ///   that those CDNs often reject with 401/403/502).
  /// - sub.wyzie.io URLs → Worker first (API key stays server-side), then
  ///   direct as fallback.
  /// [subtitleId] is the Wyzie/OpenSubtitles file id from search results.
  /// When the CDN URL is blocked (common for dl.opensubtitles.org on mobile),
  /// we re-fetch via Wyzie's own CDN using that id + your Worker API key.
  Future<String> fetchSubtitleText(String url, {String? subtitleId}) async {
    final cleaned = url.trim();
    if (cleaned.isEmpty) {
      throw WyzieError('Subtitle URL is empty.');
    }

    final lower = cleaned.toLowerCase();
    final isOpenSubtitles = lower.contains('opensubtitles');
    final id = (subtitleId ?? '').trim();

    Future<String?> tryDirect(String target) async {
      final tLower = target.toLowerCase();
      final os = tLower.contains('opensubtitles');
      final headers = <String, String>{
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
            '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        'Accept': os
            ? 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8'
            : 'text/plain, text/vtt, application/x-subrip, */*',
        'Accept-Language': 'en-US,en;q=0.9',
      };
      if (os) {
        headers['Referer'] = 'https://www.opensubtitles.org/';
        headers['Origin'] = 'https://www.opensubtitles.org';
      } else if (tLower.contains('wyzie')) {
        headers['Referer'] = 'https://sub.wyzie.io/';
        headers['Origin'] = 'https://sub.wyzie.io';
      }

      debugPrint('Wyzie direct download: $target');
      final client = CompressionClient(http.Client());
      final direct =
          await client.get(Uri.parse(target), headers: headers).timeout(timeout);
      client.close();
      if (direct.statusCode == 200) {
        final body = _normalizeSubtitleBody(direct.body);
        if (_looksLikeSubtitle(body)) return body;
      } else {
        debugPrint('Wyzie direct status ${direct.statusCode}');
      }
      return null;
    }

    Future<String?> tryWorker(String target) async {
      try {
        final proxyUri = Uri.parse(ApiConfig.wyzieFetch(target));
        debugPrint('Wyzie fetch via worker: $proxyUri');
        final client = CompressionClient(http.Client());
        final response = await client
            .get(
              proxyUri,
              headers: {
                'Accept': 'text/plain, text/vtt, application/x-subrip, */*',
              },
            )
            .timeout(timeout);
        client.close();
        if (response.statusCode == 200) {
          final body = _normalizeSubtitleBody(response.body);
          if (_looksLikeSubtitle(body)) return body;
        } else {
          // Explicitly treat 502/503/504 as failures to trigger fallback
          debugPrint('Wyzie worker status ${response.statusCode}');
        }
      } catch (e) {
        debugPrint('Wyzie worker fetch failed: $e');
      }
      return null;
    }

    // Candidate URLs: original + Wyzie CDN mirrors built from file id.
    // Docs example: https://sub.wyzie.io/c/.../id/{id}?format=srt&encoding=UTF-8
    final targets = <String>[cleaned];
    if (id.isNotEmpty) {
      targets.addAll([
        'https://sub.wyzie.io/c/$id/id/$id?format=srt&encoding=UTF-8',
        'https://sub.wyzie.io/id/$id?format=srt&encoding=UTF-8',
      ]);
    }

    for (final target in targets) {
      final tLower = target.toLowerCase();
      final preferWorker =
          tLower.contains('sub.wyzie.io') || tLower.contains('sub.wyzie.ru');

      if (preferWorker) {
        final w = await tryWorker(target);
        if (w != null) return w;
        final d = await tryDirect(target);
        if (d != null) return d;
      } else {
        // OpenSubtitles: direct first; worker usually blocked by their CDN.
        final d = await tryDirect(target);
        if (d != null) return d;
        final w = await tryWorker(target);
        if (w != null) return w;
      }
    }

    throw WyzieError(
      isOpenSubtitles
          ? 'Failed to download subtitle (OpenSubtitles blocked; Wyzie mirror also failed)'
          : 'Failed to download subtitle',
    );
  }

  static String _normalizeSubtitleBody(String body) {
    if (body.isNotEmpty && body.codeUnitAt(0) == 0xFEFF) {
      return body.substring(1);
    }
    return body;
  }

  /// Heuristic: real SRT/VTT always contains a cue arrow or WEBVTT header.
  static bool _looksLikeSubtitle(String body) {
    if (body.trim().isEmpty) return false;
    final sample =
        body.length > 4000 ? body.substring(0, 4000) : body;
    return sample.contains('-->') ||
        sample.toUpperCase().contains('WEBVTT') ||
        RegExp(r'\d{2}:\d{2}:\d{2}').hasMatch(sample);
  }
}