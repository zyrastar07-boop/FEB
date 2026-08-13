import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/movie.dart';

class TmdbService {
  static const String _apiKey = '7070e2fe1f83238edc3ada49acb2cb25';
  static const String _baseUrl = 'https://api.themoviedb.org/3';

  // Reusable client for connection pooling and faster response times
  final http.Client _client = http.Client();

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
    return getMoviesByCategory(categoryType: 'upcoming', page: page);
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
  }) async {
    String endpoint;
    String queryParams = '&page=$page';

    switch (categoryType) {
      case 'trending':
        endpoint = '/trending/tv/day';
        break;
      case 'anime':
        endpoint = '/discover/tv';
        // Animation genre + Japanese origin for anime
        queryParams +=
            '&with_genres=16&with_origin_country=JP&sort_by=popularity.desc';
        break;
      case 'top_rated':
        endpoint = '/tv/top_rated';
        break;
      case 'popular':
        endpoint = '/tv/popular';
        break;
      case 'asian':
        endpoint = '/discover/tv';
        queryParams +=
            '&with_origin_country=KR|JP|CN|TH|TW&sort_by=popularity.desc';
        break;
      case 'action':
        endpoint = '/discover/tv';
        queryParams += '&with_genres=10759&sort_by=popularity.desc';
        break;
      case 'scifi':
        endpoint = '/discover/tv';
        queryParams += '&with_genres=10765&sort_by=popularity.desc';
        break;
      case 'drama':
        endpoint = '/discover/tv';
        queryParams += '&with_genres=18&sort_by=popularity.desc';
        break;
      case 'comedy':
        endpoint = '/discover/tv';
        queryParams += '&with_genres=35&sort_by=popularity.desc';
        break;
      case 'horror':
        endpoint = '/discover/tv';
        queryParams += '&with_genres=9648&sort_by=popularity.desc';
        break;
      default:
        endpoint = '/trending/tv/day';
    }

    try {
      final response = await _client.get(
        Uri.parse('$_baseUrl$endpoint?api_key=$_apiKey$queryParams'),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List results = data['results'] ?? [];
        return results.map((json) {
          final map = Map<String, dynamic>.from(json as Map);
          if (map['title'] == null && map['name'] != null) {
            map['title'] = map['name'];
          }
          if (map['release_date'] == null && map['first_air_date'] != null) {
            map['release_date'] = map['first_air_date'];
          }
          // Tag as TV so downstream screens can use the correct endpoints
          map['media_type'] = 'tv';
          return Movie.fromJson(map);
        }).toList();
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
  }) async {
    String endpoint;
    String queryParams = '&page=$page';

    if (providerId != null) {
      queryParams += '&with_watch_providers=$providerId&watch_region=US';
    }

    switch (categoryType) {
      case 'trending':
        if (providerId != null) {
          endpoint = '/discover/movie';
          queryParams += '&sort_by=popularity.desc';
        } else {
          endpoint = '/trending/movie/day';
        }
        break;
      case 'action':
        endpoint = '/discover/movie';
        queryParams += '&with_genres=28&sort_by=popularity.desc';
        break;
      case 'scifi':
        endpoint = '/discover/movie';
        queryParams += '&with_genres=878&sort_by=popularity.desc';
        break;
      case 'romance':
        endpoint = '/discover/movie';
        queryParams += '&with_genres=10749&sort_by=popularity.desc';
        break;
      case 'horror':
        endpoint = '/discover/movie';
        queryParams += '&with_genres=27&sort_by=popularity.desc';
        break;
      case 'animation':
      case 'anime':
        endpoint = '/discover/movie';
        queryParams += '&with_genres=16&sort_by=popularity.desc';
        break;
      case 'drama':
        endpoint = '/discover/movie';
        queryParams += '&with_genres=18&sort_by=popularity.desc';
        break;
      case 'comedy':
        endpoint = '/discover/movie';
        queryParams += '&with_genres=35&sort_by=popularity.desc';
        break;
      case 'classics':
        endpoint = '/discover/movie';
        queryParams +=
            '&primary_release_date.lte=1999-12-31&sort_by=vote_average.desc&vote_count.gte=1000';
        break;
      case 'provider':
        endpoint = '/discover/movie';
        queryParams += '&sort_by=popularity.desc';
        break;
      case 'now_playing':
        endpoint = '/movie/now_playing';
        break;
      case 'top_rated':
        endpoint = '/movie/top_rated';
        break;
      case 'upcoming':
        endpoint = '/movie/upcoming';
        break;
      case 'award':
        // High-rated films with solid vote counts as a proxy for award-leaning titles
        endpoint = '/discover/movie';
        queryParams +=
            '&sort_by=vote_average.desc&vote_count.gte=2000&vote_average.gte=7.5';
        break;
      default:
        endpoint = '/trending/movie/day';
    }

    try {
      final response = await _client.get(
        Uri.parse('$_baseUrl$endpoint?api_key=$_apiKey$queryParams'),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List results = data['results'] ?? [];
        return results.map((json) {
          final map = Map<String, dynamic>.from(json as Map);
          map['media_type'] = 'movie';
          return Movie.fromJson(map);
        }).toList();
      } else {
        throw Exception('Failed to load content for $categoryType');
      }
    } catch (_) {
      return [];
    }
  }

  /// Multi search that preserves media_type on each result so filters work.
  Future<List<Movie>> searchMovies(String query, {int page = 1}) async {
    final encoded = Uri.encodeQueryComponent(query);
    final multiUrl =
        '$_baseUrl/search/multi?api_key=$_apiKey&query=$encoded&page=$page&include_adult=false';

    try {
      final response = await _client.get(Uri.parse(multiUrl));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List results = data['results'] ?? [];
        final movies = <Movie>[];
        for (final item in results) {
          final mediaType = item['media_type'] as String?;
          if (mediaType == 'movie' || mediaType == 'tv') {
            try {
              final map = Map<String, dynamic>.from(item as Map);
              if (mediaType == 'tv') {
                if (map['title'] == null && map['name'] != null) {
                  map['title'] = map['name'];
                }
                if (map['release_date'] == null &&
                    map['first_air_date'] != null) {
                  map['release_date'] = map['first_air_date'];
                }
              }
              map['media_type'] = mediaType;
              movies.add(Movie.fromJson(map));
            } catch (_) {}
          }
        }
        if (movies.isNotEmpty) return movies;
      }
    } catch (_) {}
    return [];
  }

  /// Discover titles directed by a specific person (crew job = Director).
  Future<List<Movie>> getMoviesByDirector(int personId, {int page = 1}) async {
    try {
      final url = Uri.parse(
        '$_baseUrl/discover/movie?api_key=$_apiKey&with_crew=$personId&sort_by=popularity.desc&page=$page',
      );
      final response = await _client.get(url);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List results = data['results'] ?? [];
        return results.map((json) {
          final map = Map<String, dynamic>.from(json as Map);
          map['media_type'] = 'movie';
          return Movie.fromJson(map);
        }).toList();
      }
    } catch (_) {}
    return [];
  }

  /// Popular directors (people known for directing) for home “Directed by” row.
  Future<List<Map<String, dynamic>>> getPopularDirectors(
      {int page = 1}) async {
    try {
      // TMDB people popular endpoint; filter client-side for directors when possible
      final url = Uri.parse(
        '$_baseUrl/person/popular?api_key=$_apiKey&page=$page',
      );
      final response = await _client.get(url);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List results = data['results'] ?? [];
        final directors = <Map<String, dynamic>>[];
        for (final p in results) {
          final known = (p['known_for_department'] as String?) ?? '';
          // Prefer directing department; still include strong film people
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