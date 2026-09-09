import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/cast_member.dart';
import '../models/movie.dart';

class TmdbDetailsService {
  final String apiKey = '7070e2fe1f83238edc3ada49acb2cb25';
  final String baseUrl = 'https://api.themoviedb.org/3';

  Future<List<CastMember>> getCast(int tmdbId, {bool isTv = false}) async {
    try {
      final type = isTv ? 'tv' : 'movie';
      final url =
          Uri.parse('$baseUrl/$type/$tmdbId/credits?api_key=$apiKey');
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List castList = data['cast'] ?? [];
        return castList
            .map((json) => CastMember.fromJson(json))
            .toList()
            .cast<CastMember>();
      }
    } catch (_) {}
    return [];
  }

  /// Prefer official Trailer, then Teaser, then any YouTube clip
  Future<String?> getTrailerKey(int tmdbId, {bool isTv = false}) async {
    try {
      final type = isTv ? 'tv' : 'movie';
      final url =
          Uri.parse('$baseUrl/$type/$tmdbId/videos?api_key=$apiKey');
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List results = data['results'] ?? [];
        if (results.isEmpty) return null;

        // Prefer official English trailers
        Map? pick(String typeName) {
          try {
            return results.firstWhere(
              (v) =>
                  v['site'] == 'YouTube' &&
                  v['type'] == typeName &&
                  (v['official'] == true || v['iso_639_1'] == 'en'),
            ) as Map?;
          } catch (_) {
            try {
              return results.firstWhere(
                (v) => v['site'] == 'YouTube' && v['type'] == typeName,
              ) as Map?;
            } catch (_) {
              return null;
            }
          }
        }

        final trailer = pick('Trailer') ?? pick('Teaser') ?? pick('Clip');
        if (trailer != null) return trailer['key'] as String?;

        final anyYt = results.cast<Map>().firstWhere(
              (v) => v['site'] == 'YouTube',
              orElse: () => {},
            );
        return anyYt.isEmpty ? null : anyYt['key'] as String?;
      }
    } catch (_) {}
    return null;
  }

  Future<List<Movie>> getSimilarMovies(int tmdbId) async {
    try {
      // Try recommendations first (usually better), then similar
      final recUrl = Uri.parse(
          '$baseUrl/movie/$tmdbId/recommendations?api_key=$apiKey');
      final simUrl =
          Uri.parse('$baseUrl/movie/$tmdbId/similar?api_key=$apiKey');

      final responses = await Future.wait([
        http.get(recUrl),
        http.get(simUrl),
      ]);

      final List combined = [];
      for (final res in responses) {
        if (res.statusCode == 200) {
          final data = json.decode(res.body);
          combined.addAll(data['results'] ?? []);
        }
      }

      final seen = <int>{};
      final movies = <Movie>[];
      for (final json in combined) {
        try {
          final m = Movie.fromJson(json);
          if (seen.add(m.id)) movies.add(m);
        } catch (_) {}
      }
      return movies;
    } catch (_) {}
    return [];
  }

  Future<String?> getMovieLogo(int tmdbId, {bool isTv = false}) async {
    try {
      final type = isTv ? 'tv' : 'movie';
      final url = Uri.parse(
        '$baseUrl/$type/$tmdbId/images?api_key=$apiKey&include_image_language=en,null',
      );
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List logos = data['logos'] ?? [];
        if (logos.isEmpty) return null;

        final enLogo = logos.cast<Map<String, dynamic>>().firstWhere(
              (l) => l['iso_639_1'] == 'en',
              orElse: () => logos.first as Map<String, dynamic>,
            );

        final filePath = enLogo['file_path'] as String?;
        if (filePath != null && filePath.isNotEmpty) {
          return 'https://image.tmdb.org/t/p/w500$filePath';
        }
      }
    } catch (_) {}
    return null;
  }

  Future<Map<String, dynamic>> getActorDetails(int actorId) async {
    CastMember? actorInfo;
    List<Movie> movies = [];

    try {
      final personUrl =
          Uri.parse('$baseUrl/person/$actorId?api_key=$apiKey');
      final creditsUrl = Uri.parse(
          '$baseUrl/person/$actorId/combined_credits?api_key=$apiKey');

      final responses = await Future.wait([
        http.get(personUrl),
        http.get(creditsUrl),
      ]);

      final personRes = responses[0];
      final creditsRes = responses[1];

      if (personRes.statusCode == 200) {
        actorInfo = CastMember.fromJson(json.decode(personRes.body));
      }

      if (creditsRes.statusCode == 200) {
        final data = json.decode(creditsRes.body);
        final List cast = data['cast'] ?? [];

        final mapped = cast
            .map((json) {
              try {
                return Movie.fromJson(json);
              } catch (_) {
                return null;
              }
            })
            .whereType<Movie>()
            .toList();

        final seen = <int>{};
        movies = mapped.where((m) => seen.add(m.id)).toList();
        movies.sort((a, b) => b.voteAverage.compareTo(a.voteAverage));
      }
    } catch (_) {}

    return {
      'actor': actorInfo,
      'movies': movies,
    };
  }

  /// Runtime + genres from full movie details (optional enrichment)
  Future<Map<String, dynamic>?> getMovieDetails(int tmdbId) async {
    try {
      final url = Uri.parse('$baseUrl/movie/$tmdbId?api_key=$apiKey');
      final response = await http.get(url);
      if (response.statusCode == 200) {
        return json.decode(response.body) as Map<String, dynamic>;
      }
    } catch (_) {}
    return null;
  }
}