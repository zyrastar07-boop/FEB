import 'package:hive/hive.dart';
import '../models/movie.dart';
import 'watch_analytics_service.dart';

class ContinueWatchingService {
  static const String _boxName = 'continue_watching_store';

  static Future<Box> _openBox() async {
    if (Hive.isBoxOpen(_boxName)) return Hive.box(_boxName);
    return await Hive.openBox(_boxName);
  }

  static String _getKey(int movieId, String mediaType) =>
      mediaType == 'tv' ? 'tv-$movieId' : 'movie-$movieId';

  static Future<List<Map<String, dynamic>>> getEntries() async {
    final box = await _openBox();
    final List<Map<String, dynamic>> entries = [];
    for (var key in box.keys) {
      final data = box.get(key);
      if (data != null) entries.add(Map<String, dynamic>.from(data));
    }
    entries.sort((a, b) {
      final ba = (b['updatedAt'] as num?)?.toInt() ?? 0;
      final aa = (a['updatedAt'] as num?)?.toInt() ?? 0;
      return ba.compareTo(aa);
    });
    return entries;
  }

  static Movie? movieFromEntry(Map<String, dynamic> e) {
    try {
      final rawMovie = e['movie'];
      if (rawMovie is! Map) return null;
      final m = Map<String, dynamic>.from(rawMovie);
      final id = (m['id'] as num?)?.toInt();
      if (id == null || id <= 0) return null;
      final title = (m['title'] ?? m['name'] ?? '').toString().trim();
      if (title.isEmpty || title == 'N/A' || title == 'Unknown') return null;
      final mediaType = (e['mediaType'] ?? m['mediaType'] ?? m['media_type'] ?? 'movie').toString().toLowerCase();
      final posterPath = (m['posterPath'] ?? m['poster_path'] ?? '').toString().trim();
      final backdropPath = (m['backdropPath'] ?? m['backdrop_path'] ?? '').toString().trim();
      final overview = (m['overview'] ?? '').toString();
      final voteAverage = (m['voteAverage'] as num?)?.toDouble() ?? (m['vote_average'] as num?)?.toDouble() ?? 0.0;
      final releaseDate = (m['releaseDate'] ?? m['release_date'] ?? m['first_air_date'] ?? '').toString();
      return Movie.fromJson({'id': id, 'title': title, 'name': title, 'poster_path': posterPath, 'backdrop_path': backdropPath, 'overview': overview, 'vote_average': voteAverage, 'release_date': releaseDate, 'first_air_date': releaseDate, 'media_type': mediaType});
    } catch (_) { return null; }
  }

  static Future<void> rehydrateMissingPosters() async {
    try {
      final box = await _openBox();
      final entries = await getEntries();
      if (entries.isEmpty) return;
      for (final e in entries) {
        final rawMovie = e['movie'];
        if (rawMovie is! Map) continue;
        final m = Map<String, dynamic>.from(rawMovie);
        final poster = (m['posterPath'] ?? m['poster_path'] ?? '').toString().trim();
        if (poster.isNotEmpty && poster != 'null') continue;
        final id = (m['id'] as num?)?.toInt();
        final mediaType = (e['mediaType'] as String?) ?? 'movie';
        if (id == null) continue;
        final key = _getKey(id, mediaType);
        if (box.containsKey(key)) { e['movie'] = m; await box.put(key, e); }
      }
    } catch (_) {}
  }

  static Future<void> upsert({
    required Movie movie,
    required int position,
    required int duration,
    int? season,
    int? episode,
    String mediaType = 'movie',
  }) async {
    final box = await _openBox();
    final ratio = duration > 0 ? position / duration : 0.0;
    final key = _getKey(movie.id, mediaType);

    if (duration > 0 && ratio > 0.95) {
      await WatchAnalyticsService.instance.recordWatched(movie, source: 'playback_complete');
      if (box.containsKey(key)) await box.delete(key);
      return;
    }
    if (position < 30) return;

    final entryMap = {
      'movie': {'id': movie.id, 'title': movie.title, 'posterPath': movie.posterPath, 'backdropPath': movie.backdropPath, 'overview': movie.overview, 'voteAverage': movie.voteAverage, 'releaseDate': movie.releaseDate},
      'position': position,
      'duration': duration,
      'season': season,
      'episode': episode,
      'mediaType': mediaType,
      'updatedAt': DateTime.now().millisecondsSinceEpoch,
    };
    await box.put(key, entryMap);

    final entries = await getEntries();
    if (entries.length > 20) {
      final stale = <dynamic>[];
      for (int i = 20; i < entries.length; i++) {
        final m = entries[i]['movie'];
        final id = m is Map ? (m['id'] as num?)?.toInt() : null;
        final mt = (entries[i]['mediaType'] as String?) ?? 'movie';
        if (id != null) stale.add(_getKey(id, mt));
      }
      if (stale.isNotEmpty) await box.deleteAll(stale);
    }
  }

  static Future<void> advanceEpisode(Movie movie, int season, int episode, String mediaType) async {
    final box = await _openBox();
    final key = _getKey(movie.id, mediaType);
    final entryMap = {
      'movie': {'id': movie.id, 'title': movie.title, 'posterPath': movie.posterPath, 'backdropPath': movie.backdropPath, 'overview': movie.overview, 'voteAverage': movie.voteAverage, 'releaseDate': movie.releaseDate},
      'position': 0,
      'duration': 0,
      'season': season,
      'episode': episode,
      'mediaType': mediaType,
      'updatedAt': DateTime.now().millisecondsSinceEpoch,
    };
    await box.put(key, entryMap);
  }

  static Future<void> remove(int movieId, String mediaType) async {
    final box = await _openBox();
    final key = _getKey(movieId, mediaType);
    if (box.containsKey(key)) await box.delete(key);
  }

  static Future<void> clearAll() async {
    final box = await _openBox();
    if (box.isEmpty) return;
    await box.deleteAll(box.keys.toList());
  }

  static Future<Map<String, dynamic>?> getProgress(int movieId, String mediaType) async {
    final box = await _openBox();
    final key = _getKey(movieId, mediaType);
    final data = box.get(key);
    return data != null ? Map<String, dynamic>.from(data) : null;
  }
}
