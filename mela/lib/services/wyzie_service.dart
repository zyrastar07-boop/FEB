import 'dart:convert';
import 'package:http/http.dart' as http;
import 'api_config.dart';

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
      'language': ?isoLang,
      if (season != null && episode != null) ...{
        'season': season.toString(),
        'episode': episode.toString(),
      },
    };

    try {
      final response = await http
          .get(
            Uri.parse(ApiConfig.wyzieSearch(params)),
            headers: {'Accept': 'application/json'},
          )
          .timeout(timeout);

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
      throw WyzieError('Failed to fetch subtitles: $err');
    }
  }

  Future<String> fetchSubtitleText(String url) async {
    // Download through the Worker so the client never hits Wyzie with a key.
    final response = await http
        .get(
          Uri.parse(ApiConfig.wyzieFetch(url)),
          headers: {'Accept': '*/*'},
        )
        .timeout(timeout);
    if (response.statusCode != 200) {
      throw WyzieError('Failed to download subtitle (${response.statusCode})');
    }
    var body = response.body;
    if (body.isNotEmpty && body.codeUnitAt(0) == 0xFEFF) {
      body = body.substring(1);
    }
    return body;
  }
}