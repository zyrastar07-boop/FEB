import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/cast_member.dart';
import '../models/movie.dart';
import 'api_config.dart';

/// TMDB details via Cloudflare Worker — no client-side API key.
class TmdbDetailsService {
  final http.Client _client = http.Client();

  Uri _uri(String path, {Map<String, String>? query}) {
    final base = ApiConfig.tmdb(path);
    if (query == null || query.isEmpty) return Uri.parse(base);
    final u = Uri.parse(base);
    return u.replace(queryParameters: {...u.queryParameters, ...query});
  }

  Future<List<CastMember>> getCast(int tmdbId, {bool isTv = false}) async {
    try {
      final type = isTv ? 'tv' : 'movie';
      final response = await _client.get(_uri('/$type/$tmdbId/credits'));

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

  /// Returns director or creator info: {name, id, profile_path} or null.
  Future<Map<String, dynamic>?> getDirector(int tmdbId,
      {bool isTv = false}) async {
    try {
      final type = isTv ? 'tv' : 'movie';

      if (isTv) {
        final detailsRes = await _client.get(_uri('/tv/$tmdbId'));
        if (detailsRes.statusCode == 200) {
          final details = json.decode(detailsRes.body);
          final createdBy = details['created_by'] as List?;
          if (createdBy != null && createdBy.isNotEmpty) {
            final creator = createdBy.first as Map<String, dynamic>;
            return {
              'name': creator['name'] as String?,
              'id': creator['id'] as int?,
              'profile_path': creator['profile_path'] as String?,
            };
          }
        }
      }

      final response = await _client.get(_uri('/$type/$tmdbId/credits'));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List crew = data['crew'] ?? [];
        Map? pick;
        for (final c in crew) {
          final job = (c['job'] as String?)?.toLowerCase() ?? '';
          if (job == 'director') {
            pick = c as Map;
            break;
          }
        }
        if (pick == null && isTv) {
          for (final c in crew) {
            final job = (c['job'] as String?)?.toLowerCase() ?? '';
            if (job.contains('creator') ||
                job.contains('executive producer') ||
                job.contains('director')) {
              pick = c as Map;
              break;
            }
          }
        }
        if (pick == null) return null;
        return {
          'name': pick['name'] as String?,
          'id': pick['id'] as int?,
          'profile_path': pick['profile_path'] as String?,
        };
      }
    } catch (_) {}
    return null;
  }

  Future<String?> getTrailerKey(int tmdbId, {bool isTv = false}) async {
    try {
      final type = isTv ? 'tv' : 'movie';
      final response = await _client.get(_uri('/$type/$tmdbId/videos'));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List results = data['results'] ?? [];
        if (results.isEmpty) return null;

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

  Future<List<Movie>> getSimilarMovies(int tmdbId, {bool isTv = false}) async {
    try {
      final type = isTv ? 'tv' : 'movie';
      final responses = await Future.wait([
        _client.get(_uri('/$type/$tmdbId/recommendations')),
        _client.get(_uri('/$type/$tmdbId/similar')),
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
          final map = Map<String, dynamic>.from(json as Map);
          if (isTv || map['name'] != null) {
            map['title'] = map['title'] ?? map['name'] ?? '';
            map['release_date'] =
                map['release_date'] ?? map['first_air_date'] ?? '';
          }
          map['media_type'] = isTv ? 'tv' : (map['media_type'] ?? 'movie');
          final m = Movie.fromJson(map);
          if (seen.add(m.id)) movies.add(m);
        } catch (_) {}
      }
      return movies;
    } catch (_) {}
    return [];
  }

  /// Fetches a textless (clean) poster when available.
  /// Prefers posters where `iso_639_1 == null` so transparent title logos
  /// don't double up with printed titles on the artwork.
  Future<String?> getTextlessPoster(int tmdbId, {bool isTv = false}) async {
    try {
      final type = isTv ? 'tv' : 'movie';
      final response = await _client.get(
        _uri('/$type/$tmdbId/images', query: {
          'include_image_language': 'null,en',
        }),
      );

      if (response.statusCode != 200) return null;

      final data = json.decode(response.body);
      final List posters = data['posters'] ?? [];
      if (posters.isEmpty) return null;

      // 1) Prefer fully textless (null language)
      Map<String, dynamic>? selected;
      for (final p in posters.cast<Map<String, dynamic>>()) {
        final lang = p['iso_639_1'];
        final path = p['file_path'] as String?;
        if ((lang == null || lang == '') &&
            path != null &&
            path.isNotEmpty) {
          selected = p;
          break;
        }
      }

      // 2) Fallback: English poster
      if (selected == null) {
        for (final p in posters.cast<Map<String, dynamic>>()) {
          if (p['iso_639_1'] == 'en' &&
              (p['file_path'] as String?)?.isNotEmpty == true) {
            selected = p;
            break;
          }
        }
      }

      // 3) Any poster
      selected ??= posters.cast<Map<String, dynamic>>().firstWhere(
            (p) => (p['file_path'] as String?)?.isNotEmpty == true,
            orElse: () => <String, dynamic>{},
          );

      final filePath = selected['file_path'] as String?;
      if (filePath != null && filePath.isNotEmpty) {
        return 'https://image.tmdb.org/t/p/w780$filePath';
      }
    } catch (_) {}
    return null;
  }

  Future<String?> getMovieLogo(int tmdbId, {bool isTv = false}) async {
    try {
      final type = isTv ? 'tv' : 'movie';
      // Prefer null (textless context) then English, then other languages.
      final response = await _client.get(
        _uri('/$type/$tmdbId/images', query: {
          'include_image_language': 'null,en,fr,es,de,it,ja,ko,zh,pt,hi,ar',
        }),
      );

      if (response.statusCode != 200) return null;

      final data = json.decode(response.body);
      final List logos = data['logos'] ?? [];
      if (logos.isEmpty) return null;

      // Prefer: English → language-less → first available with a path.
      Map<String, dynamic>? selectedLogo;
      for (final l in logos.cast<Map<String, dynamic>>()) {
        if (l['iso_639_1'] == 'en' &&
            (l['file_path'] as String?)?.isNotEmpty == true) {
          selectedLogo = l;
          break;
        }
      }
      if (selectedLogo == null) {
        for (final l in logos.cast<Map<String, dynamic>>()) {
          final lang = l['iso_639_1'];
          if ((lang == null || lang == '') &&
              (l['file_path'] as String?)?.isNotEmpty == true) {
            selectedLogo = l;
            break;
          }
        }
      }
      selectedLogo ??= logos.cast<Map<String, dynamic>>().firstWhere(
            (l) => (l['file_path'] as String?)?.isNotEmpty == true,
            orElse: () => <String, dynamic>{},
          );

      final filePath = selectedLogo['file_path'] as String?;
      if (filePath != null && filePath.isNotEmpty) {
        return 'https://image.tmdb.org/t/p/w500$filePath';
      }
    } catch (_) {}
    return null;
  }

  Future<Map<String, dynamic>> getActorDetails(int actorId) async {
    CastMember? actorInfo;
    List<Movie> movies = [];

    try {
      final responses = await Future.wait([
        _client.get(_uri('/person/$actorId')),
        _client.get(_uri('/person/$actorId/combined_credits')),
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
                final map = Map<String, dynamic>.from(json as Map);
                if (map['title'] == null && map['name'] != null) {
                  map['title'] = map['name'];
                  map['release_date'] = map['first_air_date'];
                }
                map['media_type'] = map['media_type'] ?? 'movie';
                return Movie.fromJson(map);
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

  Future<Map<String, dynamic>?> getMovieDetails(int tmdbId,
      {bool isTv = false}) async {
    try {
      final type = isTv ? 'tv' : 'movie';
      final response = await _client.get(
        _uri('/$type/$tmdbId', query: {
          'append_to_response': 'release_dates,content_ratings,credits',
        }),
      );
      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        if (isTv) {
          data['title'] = data['title'] ?? data['name'] ?? '';
          data['release_date'] =
              data['release_date'] ?? data['first_air_date'] ?? '';
        }
        return data;
      }
    } catch (_) {}
    return null;
  }

  Future<List<Map<String, dynamic>>> getSeasonEpisodes(
      int tmdbId, int seasonNumber) async {
    try {
      final response =
          await _client.get(_uri('/tv/$tmdbId/season/$seasonNumber'));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List episodes = data['episodes'] ?? [];
        return episodes
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      }
    } catch (_) {}
    return [];
  }

  String? extractParentalRating(Map<String, dynamic>? details,
      {bool isTv = false}) {
    if (details == null) return null;
    try {
      if (isTv) {
        final ratings = details['content_ratings']?['results'] as List?;
        if (ratings != null) {
          for (final r in ratings) {
            if (r['iso_3166_1'] == 'US') {
              final rating = r['rating'] as String?;
              if (rating != null && rating.isNotEmpty) return rating;
            }
          }
          if (ratings.isNotEmpty) {
            final rating = ratings.first['rating'] as String?;
            if (rating != null && rating.isNotEmpty) return rating;
          }
        }
      } else {
        final releases = details['release_dates']?['results'] as List?;
        if (releases != null) {
          for (final country in releases) {
            if (country['iso_3166_1'] == 'US') {
              final dates = country['release_dates'] as List? ?? [];
              for (final d in dates) {
                final cert = d['certification'] as String?;
                if (cert != null && cert.isNotEmpty) return cert;
              }
            }
          }
        }
      }
    } catch (_) {}
    return null;
  }

  String formatRuntime(Map<String, dynamic>? details, {bool isTv = false}) {
    if (details == null) return '';
    try {
      if (isTv) {
        final runtimes = details['episode_run_time'] as List?;
        if (runtimes != null && runtimes.isNotEmpty) {
          final mins = runtimes.first as int;
          return '${mins}m / ep';
        }
        final seasons = details['number_of_seasons'];
        if (seasons != null && seasons > 0) {
          return '$seasons season${seasons == 1 ? '' : 's'}';
        }
      } else {
        final mins = details['runtime'] as int?;
        if (mins != null && mins > 0) {
          final h = mins ~/ 60;
          final m = mins % 60;
          if (h > 0) return '${h}h ${m}m';
          return '${m}m';
        }
      }
    } catch (_) {}
    return '';
  }

  String formatGenres(Map<String, dynamic>? details) {
    if (details == null) return '';
    try {
      final genres = details['genres'] as List?;
      if (genres == null || genres.isEmpty) return '';
      return genres
          .map((g) => g['name'] as String? ?? '')
          .where((n) => n.isNotEmpty)
          .join(', ');
    } catch (_) {}
    return '';
  }

  String formatCountries(Map<String, dynamic>? details) {
    if (details == null) return '';
    try {
      final countries = details['production_countries'] as List?;
      if (countries == null || countries.isEmpty) return '';
      return countries
          .map((c) => c['name'] as String? ?? '')
          .where((n) => n.isNotEmpty)
          .join(', ');
    } catch (_) {}
    return '';
  }
}