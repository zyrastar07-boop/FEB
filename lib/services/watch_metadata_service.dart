import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/movie.dart';
import 'api_config.dart';

class WatchMetadataSummary {
  final Map<String, int> directors;
  final Map<String, int> cast;
  final Map<String, int> genres;
  final Map<String, int> countries;
  final Map<String, int> languages;
  const WatchMetadataSummary({required this.directors, required this.cast, required this.genres, required this.countries, required this.languages});
}

/// Enriches local Movie records with TMDB detail metadata for analytics.
/// Results are cached per title so the dashboard becomes fast after first load.
class WatchMetadataService {
  static const _cacheKey = 'feb_watch_metadata_cache_v1';
  final http.Client _client = http.Client();

  Future<WatchMetadataSummary> summarize(List<Movie> movies) async {
    final cache = await _readCache();
    final results = <Map<String, dynamic>>[];
    for (final movie in movies.take(24)) {
      final key = '${movie.mediaType}:${movie.id}';
      final cached = cache[key];
      if (cached is Map) {
        results.add(Map<String, dynamic>.from(cached));
        continue;
      }
      final detail = await _fetch(movie);
      if (detail != null) { cache[key] = detail; results.add(detail); }
    }
    await _writeCache(cache);
    return _aggregate(results);
  }

  Future<Map<String, dynamic>?> _fetch(Movie movie) async {
    final type = movie.mediaType.toLowerCase() == 'tv' ? 'tv' : 'movie';
    try {
      final uri = Uri.parse(ApiConfig.tmdb('/$type/${movie.id}')).replace(queryParameters: {
        'include_adult': 'false',
        'append_to_response': 'credits',
      });
      final response = await _client.get(uri);
      if (response.statusCode != 200) { ApiConfig.reportProxyFailure(); return null; }
      ApiConfig.reportProxySuccess();
      final json = jsonDecode(response.body);
      if (json is! Map) return null;
      return _normalize(json, type == 'tv');
    } catch (_) { ApiConfig.reportProxyFailure(); return null; }
  }

  Map<String, dynamic> _normalize(Map raw, bool tv) {
    final genres = <String>[];
    for (final g in (raw['genres'] as List? ?? const [])) { if (g is Map && g['name'] != null) genres.add(g['name'].toString()); }
    final countries = <String>[];
    final countryList = tv ? (raw['origin_country'] as List? ?? const []) : (raw['production_countries'] as List? ?? const []);
    for (final c in countryList) { if (c is Map && c['name'] != null) countries.add(c['name'].toString()); else if (c is String) countries.add(c); }
    final languages = <String>[];
    for (final l in (raw['spoken_languages'] as List? ?? const [])) { if (l is Map && (l['english_name'] ?? l['name']) != null) languages.add((l['english_name'] ?? l['name']).toString()); }
    final directors = <String>[]; final cast = <String>[]; final credits = raw['credits'] as Map?;
    for (final c in (credits?['crew'] as List? ?? const [])) { if (c is Map && c['job']?.toString().toLowerCase() == 'director' && c['name'] != null) directors.add(c['name'].toString()); }
    for (final c in (credits?['cast'] as List? ?? const []).take(8)) { if (c is Map && c['name'] != null) cast.add(c['name'].toString()); }
    return {'genres': genres, 'countries': countries, 'languages': languages, 'directors': directors, 'cast': cast};
  }

  WatchMetadataSummary _aggregate(List<Map<String, dynamic>> results) {
    final directors = <String, int>{}; final cast = <String, int>{}; final genres = <String, int>{}; final countries = <String, int>{}; final languages = <String, int>{};
    void add(Map<String, int> out, dynamic raw) { for (final value in (raw as List? ?? const [])) { final name = value.toString(); if (name.isNotEmpty) out[name] = (out[name] ?? 0) + 1; } }
    for (final r in results) { add(directors, r['directors']); add(cast, r['cast']); add(genres, r['genres']); add(countries, r['countries']); add(languages, r['languages']); }
    return WatchMetadataSummary(directors: directors, cast: cast, genres: genres, countries: countries, languages: languages);
  }

  Future<Map<String, dynamic>> _readCache() async {
    try { final prefs = await SharedPreferences.getInstance(); final raw = prefs.getString(_cacheKey); if (raw == null) return {}; final decoded = jsonDecode(raw); return decoded is Map ? Map<String, dynamic>.from(decoded) : {}; } catch (_) { return {}; }
  }

  Future<void> _writeCache(Map<String, dynamic> cache) async {
    try { final prefs = await SharedPreferences.getInstance(); await prefs.setString(_cacheKey, jsonEncode(cache)); } catch (_) {}
  }
}
