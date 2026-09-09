import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/movie.dart';

class TmdbService {
  static const String _apiKey = '7070e2fe1f83238edc3ada49acb2cb25';
  static const String _baseUrl = 'https://api.themoviedb.org/3';

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

  /// Classic / older films (pre-2000, high rating)
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
      case 'classics':
        // Older highly-rated films (released before 2000)
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
      default:
        endpoint = '/trending/movie/day';
    }

    final response = await http.get(
      Uri.parse('$_baseUrl$endpoint?api_key=$_apiKey$queryParams'),
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      final List results = data['results'] ?? [];
      return results.map((json) => Movie.fromJson(json)).toList();
    } else {
      throw Exception('Failed to load movies for $categoryType');
    }
  }

  Future<List<Movie>> searchMovies(String query, {int page = 1}) async {
    final encoded = Uri.encodeQueryComponent(query);
    final multiUrl =
        '$_baseUrl/search/multi?api_key=$_apiKey&query=$encoded&page=$page&include_adult=false';
    final movieUrl =
        '$_baseUrl/search/movie?api_key=$_apiKey&query=$encoded&page=$page';

    try {
      final response = await http.get(Uri.parse(multiUrl));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List results = data['results'] ?? [];
        final movies = <Movie>[];
        for (final item in results) {
          final mediaType = item['media_type'] as String?;
          if (mediaType == 'movie' || mediaType == 'tv') {
            try {
              if (mediaType == 'tv' && item['title'] == null) {
                item['title'] = item['name'];
                item['release_date'] = item['first_air_date'];
              }
              movies.add(Movie.fromJson(item));
            } catch (_) {}
          }
        }
        if (movies.isNotEmpty) return movies;
      }
    } catch (_) {}

    final response = await http.get(Uri.parse(movieUrl));
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      final List results = data['results'] ?? [];
      return results.map((json) => Movie.fromJson(json)).toList();
    } else {
      throw Exception('Failed to search movies');
    }
  }
}