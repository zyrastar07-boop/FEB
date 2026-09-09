import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/cast_member.dart';
import '../models/movie.dart';
import 'api_config.dart';
import 'compression_client.dart';
import 'proxy_http_client.dart';

/// TMDB details via Cloudflare Worker — no client-side API key.
class TmdbDetailsService {
  // Wrapped so request outcomes feed the load balancer (failover on 5xx/429);
  // wrapped in CompressionClient so responses negotiate gzip explicitly.
  final http.Client _client =
      ProxyHttpClient(CompressionClient(http.Client()));

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

  /// Content safety gate.
  ///
  /// - Always rejects TMDB `adult: true`.
  /// - Unconditionally rejects R, NC-17, TV-MA, and all explicit/mature equivalents.
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

  static bool isExplicitRating(String? rating, {bool blockMature = true}) {
    return !isSafeContent(adult: false, rating: rating, blockMature: blockMature);
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

  Future<List<CastMember>> getCast(int tmdbId, {bool isTv = false}) async {
    try {
      final type = isTv ? 'tv' : 'movie';
      final response = await _client.get(_uri('/$type/$tmdbId/credits'));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List castList = data['cast'] ?? [];
        return castList
            .where((json) => json['adult'] != true)
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
          if (c['adult'] == true) continue;
          final job = (c['job'] as String?)?.toLowerCase() ?? '';
          if (job == 'director') {
            pick = c as Map;
            break;
          }
        }
        if (pick == null && isTv) {
          for (final c in crew) {
            if (c['adult'] == true) continue;
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

      final bodies = <String>[];
      for (final res in responses) {
        if (res.statusCode == 200) bodies.add(res.body);
      }
      if (bodies.isEmpty) return [];

      // decode + map both payloads off the main isolate (await inside the
      // try so failures fall through to the catch → empty list).
      return await compute(
        _decodeSimilarMovies,
        (bodies: bodies, isTv: isTv),
      );
    } catch (_) {}
    return [];
  }

  /// Fetches a textless (clean) poster in maximum original 1080p/4K quality.
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

      if (selected == null) {
        for (final p in posters.cast<Map<String, dynamic>>()) {
          if (p['iso_639_1'] == 'en' &&
              (p['file_path'] as String?)?.isNotEmpty == true) {
            selected = p;
            break;
          }
        }
      }

      selected ??= posters.cast<Map<String, dynamic>>().firstWhere(
            (p) => (p['file_path'] as String?)?.isNotEmpty == true,
            orElse: () => <String, dynamic>{},
          );

      final filePath = selected['file_path'] as String?;
      if (filePath != null && filePath.isNotEmpty) {
        // Upgraded to 'original' for full HD / 1080p+ pristine quality
        return 'https://image.tmdb.org/t/p/original$filePath';
      }
    } catch (_) {}
    return null;
  }

  Future<String?> getMovieLogo(int tmdbId, {bool isTv = false}) async {
    try {
      final type = isTv ? 'tv' : 'movie';
      final response = await _client.get(
        _uri('/$type/$tmdbId/images', query: {
          'include_image_language': 'null,en,fr,es,de,it,ja,ko,zh,pt,hi,ar',
        }),
      );

      if (response.statusCode != 200) return null;

      final data = json.decode(response.body);
      final List logos = data['logos'] ?? [];
      if (logos.isEmpty) return null;

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
        // Upgraded to 'original' for maximum crispness
        return 'https://image.tmdb.org/t/p/original$filePath';
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
        final data = json.decode(personRes.body);
        if (data['adult'] != true) {
          actorInfo = CastMember.fromJson(data);
        }
      }

      if (creditsRes.statusCode == 200) {
        // decode + map the (potentially large) credit list off the main isolate.
        final mapped = await compute(_decodeActorCredits, creditsRes.body);

        final seen = <int>{};
        movies = mapped.where((m) => seen.add(m.id) && _isReleased(m)).toList();
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
        if (data['adult'] == true) return null;
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
            .where((map) => map['adult'] != true)
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

/// Payload for the off-main-isolate similar/recommendations decoder.
typedef _DecodeSimilarRequest = ({List<String> bodies, bool isTv});

/// Decodes recommendation + similar payloads and merges/dedupes them into
/// [Movie]s on a background isolate (inline on web via [compute]).
List<Movie> _decodeSimilarMovies(_DecodeSimilarRequest request) {
  final combined = <dynamic>[];
  for (final body in request.bodies) {
    final data = json.decode(body);
    if (data is Map && data['results'] is List) {
      combined.addAll(data['results'] as List);
    }
  }

  final seen = <int>{};
  final movies = <Movie>[];
  for (final json in combined) {
    try {
      final map = Map<String, dynamic>.from(json as Map);
      if (!TmdbDetailsService.isSafeContent(adult: map['adult'] == true)) {
        continue;
      }
      if (request.isTv || map['name'] != null) {
        map['title'] = map['title'] ?? map['name'] ?? '';
        map['release_date'] =
            map['release_date'] ?? map['first_air_date'] ?? '';
      }
      map['media_type'] =
          request.isTv ? 'tv' : (map['media_type'] ?? 'movie');
      final m = Movie.fromJson(map);
      if (seen.add(m.id) && TmdbDetailsService._isReleased(m)) {
        movies.add(m);
      }
    } catch (_) {}
  }
  return movies;
}

/// Decodes a `/person/{id}/combined_credits` cast list into [Movie]s on a
/// background isolate (inline on web via [compute]).
List<Movie> _decodeActorCredits(String body) {
  final data = json.decode(body);
  final cast = (data is Map ? data['cast'] : null) as List? ?? const [];
  final movies = <Movie>[];
  for (final json in cast) {
    try {
      final map = Map<String, dynamic>.from(json as Map);
      if (!TmdbDetailsService.isSafeContent(adult: map['adult'] == true)) {
        continue;
      }
      if (map['title'] == null && map['name'] != null) {
        map['title'] = map['name'];
        map['release_date'] = map['first_air_date'];
      }
      map['media_type'] = map['media_type'] ?? 'movie';
      movies.add(Movie.fromJson(map));
    } catch (_) {
      // Skip a single malformed credit instead of failing the whole list.
    }
  }
  return movies;
}