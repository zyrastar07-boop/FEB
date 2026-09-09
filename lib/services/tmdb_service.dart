import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/movie.dart';
import 'api_config.dart';
import 'compression_client.dart';
import 'proxy_http_client.dart';

class TmdbService {
  // Reusable client for connection pooling and faster response times.
  // Wrapped in ProxyHttpClient so the load balancer learns which mirror is
  // healthy from real request outcomes; wrapped in CompressionClient so
  // every response negotiates gzip explicitly.
  final http.Client _client =
      ProxyHttpClient(CompressionClient(http.Client()));

  // Cache for TMDB API configuration (image base URL and supported sizes)
  Map<String, dynamic>? _cachedConfig;

  /// Fetches TMDB API configuration (including secure base URLs and image poster sizes).
  Future<Map<String, dynamic>> getConfiguration() async {
    if (_cachedConfig != null) return _cachedConfig!;
    try {
      final response = await _client.get(_uri('/configuration'));
      if (response.statusCode == 200) {
        _cachedConfig = json.decode(response.body);
        return _cachedConfig!;
      }
    } catch (_) {}
    return {};
  }

  /// Generates a 1080p high-definition image URL for posters and backdrops.
  /// Defaults to [original] resolution or high-res [w780] for crisp quality.
  Future<String> getHighQualityImageUrl(String? imagePath, {bool useOriginal = true}) async {
    if (imagePath == null || imagePath.isEmpty) return '';
    
    String baseUrl = 'https://image.tmdb.org/t/p/';
    String size = useOriginal ? 'original' : 'w780';

    try {
      final config = await getConfiguration();
      final images = config['images'] as Map<String, dynamic>?;
      if (images != null) {
        final secureBase = images['secure_base_url'] as String?;
        if (secureBase != null && secureBase.isNotEmpty) {
          baseUrl = secureBase;
        }
      }
    } catch (_) {}

    return '$baseUrl$size$imagePath';
  }

  /// Smart release & delay validator.
  /// Checks full Year, Month, and Day.
  ///
  /// - Future dates (unreleased): Hidden.
  /// - New releases within the delay window (default 3 days): Hidden.
  /// - Passed delay window: Visible.
  static bool _isReleased(Movie m, {int delayDays = 3}) {
    if (m.releaseDate.isEmpty) return true;
    try {
      final release = DateTime.parse(m.releaseDate);
      final today = DateTime.now();

      // Normalize to exact Year, Month, and Day
      final releaseDateOnly = DateTime(release.year, release.month, release.day);
      final todayDateOnly = DateTime(today.year, today.month, today.day);

      // Add the delay buffer (e.g., 21 days = 3 weeks) to the release date
      final availableDate = releaseDateOnly.add(Duration(days: delayDays));

      // Show ONLY if today is on or after the available date
      return !todayDateOnly.isBefore(availableDate);
    } catch (_) {
      return true; // Fallback so malformed dates don't crash
    }
  }

  /// Content safety gate used by every list mapper.
  ///
  /// - Always rejects TMDB `adult: true`.
  /// - Unconditionally rejects R, NC-17, TV-MA, and all explicit equivalents.
  static bool isSafeContent({
    required bool adult,
    String? rating,
    bool blockMature = true,
  }) {
    if (adult) return false;
    if (rating == null || rating.trim().isEmpty) return true;

    final r = rating.toUpperCase().trim();

    // Block mature / adult / unrated explicit labels (MPA + TV + common intl).
    // Kids-safe: G, PG, PG-13, TV-Y, TV-Y7, TV-G, TV-PG, TV-14.
    final blocked = {
      'R', 'NC-17', 'NC17', 'X', 'XX', 'XXX', 'AO',
      'NR', 'N/R', 'NOT RATED', 'NOTRATED', 'UNRATED', 'UR',
      'TV-MA', 'TVMA', 'MA', 'MA15+', 'MA18', 'M18',
      '18', '18+', '18A', 'R18', 'R18+', 'R-18',
      '16+', '17+', '21', '21+',
      'ADULT', 'PORN',
    };
    if (blocked.contains(r)) return false;
    if (r.startsWith('TV-MA') || r.startsWith('NC-17') || r.startsWith('R18')) {
      return false;
    }
    if (r.contains('PORN') || r.contains('ADULT ONLY')) return false;
    return true;
  }

  /// Convenience: adult flag from raw JSON + optional rating string.
  static bool _rawIsSafe(Map<String, dynamic> json, {String? rating}) {
    final adult = json['adult'] == true;
    return isSafeContent(adult: adult, rating: rating);
  }

  Uri _uri(String path, {Map<String, String>? query}) {
    final base = ApiConfig.tmdb(path);
    final queryParams = <String, String>{
      'include_adult': 'false',
    };
    if (query != null) {
      queryParams.addAll(query);
    }
    final u = Uri.parse(base);
    return u.replace(queryParameters: {...u.queryParameters, ...queryParams});
  }

  Future<List<Movie>> getTrendingMovies({int page = 1, int? providerId}) async {
    return getMoviesByCategory(
      categoryType: 'trending',
      page: page,
      providerId: providerId,
    );
  }

  Future<List<Movie>> getNowPlayingMovies({int page = 1}) async {
    return getMoviesByCategory(categoryType: 'now_playing', page: page);
  }

  Future<List<Movie>> getTopRatedMovies({int page = 1}) async {
    return getMoviesByCategory(categoryType: 'top_rated', page: page);
  }

  Future<List<Movie>> getUpcomingMovies({int page = 1}) async {
    return getMoviesByCategory(
      categoryType: 'upcoming',
      page: page,
      hideUnreleased: false, // Explicitly keep upcoming movies list available
    );
  }

  Future<List<Movie>> getClassicMovies({int page = 1}) async {
    return getMoviesByCategory(categoryType: 'classics', page: page);
  }

  Future<List<Movie>> getSciFiMovies({int page = 1, int? providerId}) async {
    return getMoviesByCategory(
      categoryType: 'scifi',
      page: page,
      providerId: providerId,
    );
  }

  Future<List<Movie>> getActionMovies({int page = 1, int? providerId}) async {
    return getMoviesByCategory(
      categoryType: 'action',
      page: page,
      providerId: providerId,
    );
  }

  Future<List<Movie>> getRomanticMovies({int page = 1, int? providerId}) async {
    return getMoviesByCategory(
      categoryType: 'romance',
      page: page,
      providerId: providerId,
    );
  }

  Future<List<Movie>> getHorrorMovies({int page = 1}) async {
    return getMoviesByCategory(categoryType: 'horror', page: page);
  }

  Future<List<Movie>> getAnimationMovies({int page = 1}) async {
    return getMoviesByCategory(categoryType: 'animation', page: page);
  }

  Future<List<Movie>> getDramaMovies({int page = 1}) async {
    return getMoviesByCategory(categoryType: 'drama', page: page);
  }

  Future<List<Movie>> getComedyMovies({int page = 1}) async {
    return getMoviesByCategory(categoryType: 'comedy', page: page);
  }

  // --- TV Series & Anime Series Endpoints ---
  Future<List<Movie>> getTrendingTvShows({int page = 1}) async {
    return getTvShowsByCategory(categoryType: 'trending', page: page);
  }

  Future<List<Movie>> getAnimeTvShows({int page = 1}) async {
    return getTvShowsByCategory(categoryType: 'anime', page: page);
  }

  Future<List<Movie>> getTopRatedTvShows({int page = 1}) async {
    return getTvShowsByCategory(categoryType: 'top_rated', page: page);
  }

  Future<List<Movie>> getPopularTvShows({int page = 1}) async {
    return getTvShowsByCategory(categoryType: 'popular', page: page);
  }

  Future<List<Movie>> getAsianTvShows({int page = 1}) async {
    return getTvShowsByCategory(categoryType: 'asian', page: page);
  }

  Future<List<Movie>> getTvShowsByCategory({
    required String categoryType,
    int page = 1,
    bool hideUnreleased = true,
  }) async {
    String endpoint;
    final Map<String, String> queryParams = {'page': page.toString()};

    switch (categoryType) {
      case 'trending':
        endpoint = '/trending/tv/day';
        break;
      case 'anime':
        endpoint = '/discover/tv';
        queryParams['with_genres'] = '16';
        queryParams['with_origin_country'] = 'JP';
        queryParams['sort_by'] = 'popularity.desc';
        break;
      case 'top_rated':
        endpoint = '/tv/top_rated';
        break;
      case 'popular':
        endpoint = '/tv/popular';
        break;
      case 'asian':
        endpoint = '/discover/tv';
        queryParams['with_origin_country'] = 'KR|JP|CN|TH|TW';
        queryParams['sort_by'] = 'popularity.desc';
        break;
      case 'action':
        endpoint = '/discover/tv';
        queryParams['with_genres'] = '10759';
        queryParams['sort_by'] = 'popularity.desc';
        break;
      case 'scifi':
        endpoint = '/discover/tv';
        queryParams['with_genres'] = '10765';
        queryParams['sort_by'] = 'popularity.desc';
        break;
      case 'drama':
        endpoint = '/discover/tv';
        queryParams['with_genres'] = '18';
        queryParams['sort_by'] = 'popularity.desc';
        break;
      case 'comedy':
        endpoint = '/discover/tv';
        queryParams['with_genres'] = '35';
        queryParams['sort_by'] = 'popularity.desc';
        break;
      case 'horror':
        endpoint = '/discover/tv';
        queryParams['with_genres'] = '9648';
        queryParams['sort_by'] = 'popularity.desc';
        break;
      default:
        endpoint = '/trending/tv/day';
    }

    try {
      final response = await _client.get(_uri(endpoint, query: queryParams));

      if (response.statusCode == 200) {
        final body = response.body;
        // decode + map off the main isolate (compute falls back to inline
        // execution on web, where isolates are unavailable). await inside
        // the try so failures fall through to the catch → empty list.
        return await compute(
          _decodeMoviesFromBody,
          (body: body, isTv: true, hideUnreleased: hideUnreleased),
        );
      }
    } catch (_) {}
    return [];
  }

  Future<List<Movie>> getMoviesByProvider({
    required int providerId,
    int page = 1,
  }) {
    return getMoviesByCategory(
      categoryType: 'provider',
      page: page,
      providerId: providerId,
    );
  }

  Future<List<Movie>> getMoviesByCategory({
    required String categoryType,
    int page = 1,
    int? providerId,
    bool hideUnreleased = true,
  }) async {
    String endpoint;
    final Map<String, String> queryParams = {'page': page.toString()};

    if (providerId != null) {
      queryParams['with_watch_providers'] = providerId.toString();
      queryParams['watch_region'] = 'US';
    }

    switch (categoryType) {
      case 'trending':
        if (providerId != null) {
          endpoint = '/discover/movie';
          queryParams['sort_by'] = 'popularity.desc';
        } else {
          endpoint = '/trending/movie/day';
        }
        break;
      case 'action':
        endpoint = '/discover/movie';
        queryParams['with_genres'] = '28';
        queryParams['sort_by'] = 'popularity.desc';
        break;
      case 'scifi':
        endpoint = '/discover/movie';
        queryParams['with_genres'] = '878';
        queryParams['sort_by'] = 'popularity.desc';
        break;
      case 'romance':
        endpoint = '/discover/movie';
        queryParams['with_genres'] = '10749';
        queryParams['sort_by'] = 'popularity.desc';
        break;
      case 'horror':
        endpoint = '/discover/movie';
        queryParams['with_genres'] = '27';
        queryParams['sort_by'] = 'popularity.desc';
        break;
      case 'animation':
      case 'anime':
        endpoint = '/discover/movie';
        queryParams['with_genres'] = '16';
        queryParams['sort_by'] = 'popularity.desc';
        break;
      case 'drama':
        endpoint = '/discover/movie';
        queryParams['with_genres'] = '18';
        queryParams['sort_by'] = 'popularity.desc';
        break;
      case 'comedy':
        endpoint = '/discover/movie';
        queryParams['with_genres'] = '35';
        queryParams['sort_by'] = 'popularity.desc';
        break;
      case 'classics':
        endpoint = '/discover/movie';
        queryParams['primary_release_date.lte'] = '1999-12-31';
        queryParams['sort_by'] = 'vote_average.desc';
        queryParams['vote_count.gte'] = '1000';
        break;
      case 'provider':
        endpoint = '/discover/movie';
        queryParams['sort_by'] = 'popularity.desc';
        break;
      case 'now_playing':
        endpoint = '/movie/now_playing';
        break;
      case 'top_rated':
        endpoint = '/movie/top_rated';
        break;
      case 'upcoming':
        endpoint = '/movie/upcoming';
        hideUnreleased = false; // Keep upcoming movies list intact
        break;
      case 'award':
        endpoint = '/discover/movie';
        queryParams['sort_by'] = 'vote_average.desc';
        queryParams['vote_count.gte'] = '2000';
        queryParams['vote_average.gte'] = '7.5';
        break;
      default:
        endpoint = '/trending/movie/day';
    }

    try {
      final response = await _client.get(_uri(endpoint, query: queryParams));

      if (response.statusCode == 200) {
        final body = response.body;
        return await compute(
          _decodeMoviesFromBody,
          (body: body, isTv: false, hideUnreleased: hideUnreleased),
        );
      } else {
        throw Exception('Failed to load content for $categoryType');
      }
    } catch (_) {
      return [];
    }
  }

  Future<List<Movie>> searchMovies(String query, {int page = 1}) async {
    try {
      final response = await _client.get(
        _uri('/search/multi', query: {
          'query': query,
          'page': page.toString(),
          'include_adult': 'false',
        }),
      );
      if (response.statusCode == 200) {
        final body = response.body;
        final movies = await compute(
          _decodeMoviesFromBody,
          (body: body, isTv: false, hideUnreleased: true),
        );
        if (movies.isNotEmpty) return movies;
      }
    } catch (_) {}
    return [];
  }

  Future<List<Movie>> getMoviesByDirector(int personId, {int page = 1}) async {
    try {
      final response = await _client.get(
        _uri('/discover/movie', query: {
          'with_crew': personId.toString(),
          'sort_by': 'popularity.desc',
          'page': page.toString(),
        }),
      );
      if (response.statusCode == 200) {
        final body = response.body;
        return await compute(
          _decodeMoviesFromBody,
          (body: body, isTv: false, hideUnreleased: true),
        );
      }
    } catch (_) {}
    return [];
  }

  Future<List<Map<String, dynamic>>> getPopularDirectors(
      {int page = 1}) async {
    try {
      final response = await _client.get(
        _uri('/person/popular', query: {
          'page': page.toString(),
        }),
      );
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List results = data['results'] ?? [];
        final directors = <Map<String, dynamic>>[];
        for (final p in results) {
          if (p['adult'] == true) continue;
          final known = (p['known_for_department'] as String?) ?? '';
          if (known.toLowerCase() == 'directing' ||
              known.toLowerCase() == 'acting') {
            directors.add({
              'id': p['id'],
              'name': p['name'],
              'profile_path': p['profile_path'],
              'known_for_department': known,
              'known_for': p['known_for'] ?? [],
            });
          }
          if (directors.length >= 12) break;
        }
        return directors;
      }
    } catch (_) {}
    return [];
  }
}

/// Payload for the off-main-isolate movie decoder.
typedef _DecodeMoviesRequest = ({String body, bool isTv, bool hideUnreleased});

/// Decodes a TMDB `results` payload and maps it to [Movie]s on a background
/// isolate (falls back to inline execution on web via [compute]).
///
/// Applies the same safety + release filters as the old inline mappers:
/// adult content is rejected, only `movie`/`tv` media types are kept, TV
/// rows get `name`→`title` / `first_air_date`→`release_date` fallbacks, and
/// unreleased rows are dropped when [hideUnreleased] is set.
List<Movie> _decodeMoviesFromBody(_DecodeMoviesRequest request) {
  final dynamic data = json.decode(request.body);
  final results = (data is Map ? data['results'] : null) as List? ?? const [];
  final movies = <Movie>[];

  for (final item in results) {
    if (item is! Map) continue;
    final map = Map<String, dynamic>.from(item);
    if (!TmdbService._rawIsSafe(map)) continue;

    final mediaType =
        request.isTv ? 'tv' : (map['media_type'] ?? 'movie');
    if (mediaType != 'movie' && mediaType != 'tv') continue;

    if (request.isTv || map['name'] != null) {
      map['title'] ??= map['name'] ?? '';
      map['release_date'] ??= map['first_air_date'] ?? '';
    }
    map['media_type'] = mediaType;

    try {
      final movie = Movie.fromJson(map);
      if (!request.hideUnreleased || TmdbService._isReleased(movie)) {
        movies.add(movie);
      }
    } catch (_) {
      // Skip a single malformed row instead of failing the whole page.
    }
  }
  return movies;
}