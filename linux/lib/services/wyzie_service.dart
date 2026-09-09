import 'dart:convert';
import 'package:http/http.dart' as http;

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
      : id = json['id'],
        url = json['url'],
        flagUrl = json['flagUrl'],
        format = json['format'],
        encoding = json['encoding'],
        display = json['display'],
        language = json['language'],
        media = json['media'],
        isHearingImpaired = json['isHearingImpaired'],
        source = json['source'],
        fileName = json['fileName'];
}

class WyzieError implements Exception {
  final String message;
  WyzieError(this.message);
  @override
  String toString() => 'WyzieError: $message';
}

class WyzieService {
  final String baseUrl;
  final String apiKey;
  final Duration timeout;

  WyzieService({
    required this.baseUrl,
    required this.apiKey,
    this.timeout = const Duration(seconds: 10),
  });

  Future<List<WyzieSubtitle>> searchSubtitles({
    required int tmdbId,
    int? season,
    int? episode,
    String? language,
    String format = 'srt',
  }) async {
    if (apiKey.isEmpty) {
      throw WyzieError('Missing Wyzie API key.');
    }

    final queryParams = {
      'id': tmdbId.toString(),
      'key': apiKey,
      'format': format,
      'language': ?language,
      if (season != null && episode != null) ...{
        'season': season.toString(),
        'episode': episode.toString(),
      },
    };

    final uri = Uri.parse('$baseUrl/search').replace(queryParameters: queryParams);

    try {
      final response = await http
          .get(uri, headers: {'Accept': 'application/json'})
          .timeout(timeout);

      if (response.statusCode != 200) {
        throw WyzieError('Wyzie request failed (${response.statusCode})');
      }

      final data = jsonDecode(response.body);
      if (data is List) {
        return data.map((item) => WyzieSubtitle.fromJson(item)).toList();
      } else if (data is Map<String, dynamic> && data.containsKey('url')) {
        return [WyzieSubtitle.fromJson(data)];
      }
      return [];
    } catch (err) {
      if (err is WyzieError) rethrow;
      throw WyzieError('Failed to fetch subtitles.');
    }
  }

  Future<String> fetchSubtitleText(String url) async {
    final response = await http.get(Uri.parse(url));
    if (response.statusCode != 200) {
      throw WyzieError('Failed to download subtitle (${response.statusCode})');
    }
    return response.body;
  }
}