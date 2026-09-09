import 'package:hive/hive.dart';
import '../models/movie.dart';

class ContinueWatchingService {
  static const String _boxName = 'continue_watching_store';

  /// Opens the Hive box safely
  static Future<Box> _openBox() async {
    if (Hive.isBoxOpen(_boxName)) {
      return Hive.box(_boxName);
    }
    return await Hive.openBox(_boxName);
  }

  /// Generates a deduplication key (per-movie or per-show)
  static String _getKey(int movieId, String mediaType) {
    return mediaType == 'tv' ? 'tv-$movieId' : 'movie-$movieId';
  }

  /// Retrieves all continue-watching entries sorted by recent activity (`updatedAt`)
  static Future<List<Map<String, dynamic>>> getEntries() async {
    final box = await _openBox();
    final List<Map<String, dynamic>> entries = [];

    for (var key in box.keys) {
      final data = box.get(key);
      if (data != null) {
        entries.add(Map<String, dynamic>.from(data));
      }
    }

    entries.sort((a, b) => (b['updatedAt'] as int).compareTo(a['updatedAt'] as int));
    return entries;
  }

  /// Upsert logic matching the progress rules (position < 30s or ratio > 95% is discarded)
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

    // Discard if position < 30 seconds or watched past 95%
    if (position < 30 || ratio > 0.95) {
      if (box.containsKey(key)) {
        await box.delete(key);
      }
      return;
    }

    final entryMap = {
      'movie': {
        'id': movie.id,
        'title': movie.title,
        'posterPath': movie.posterPath,
        'backdropPath': movie.backdropPath,
        'overview': movie.overview,
        'voteAverage': movie.voteAverage,
        'releaseDate': movie.releaseDate,
      },
      'position': position,
      'duration': duration,
      'season': season,
      'episode': episode,
      'mediaType': mediaType,
      'updatedAt': DateTime.now().millisecondsSinceEpoch,
    };

    await box.put(key, entryMap);

    // Enforce maximum cap of 20 items
    final entries = await getEntries();
    if (entries.length > 20) {
      for (int i = 20; i < entries.length; i++) {
        final oldKey = _getKey(entries[i]['movie']['id'], entries[i]['mediaType'] ?? 'movie');
        await box.delete(oldKey);
      }
    }
  }

  /// Instantly re-points a show to a new season/episode with progress reset to 0 (for autoplay/next episode)
  static Future<void> advanceEpisode(Movie movie, int season, int episode, String mediaType) async {
    final box = await _openBox();
    final key = _getKey(movie.id, mediaType);

    final entryMap = {
      'movie': {
        'id': movie.id,
        'title': movie.title,
        'posterPath': movie.posterPath,
        'backdropPath': movie.backdropPath,
        'overview': movie.overview,
        'voteAverage': movie.voteAverage,
        'releaseDate': movie.releaseDate,
      },
      'position': 0,
      'duration': 0,
      'season': season,
      'episode': episode,
      'mediaType': mediaType,
      'updatedAt': DateTime.now().millisecondsSinceEpoch,
    };

    await box.put(key, entryMap);
  }

  /// Removes a specific entry from continue watching
  static Future<void> remove(int movieId, String mediaType) async {
    final box = await _openBox();
    final key = _getKey(movieId, mediaType);
    if (box.containsKey(key)) {
      await box.delete(key);
    }
  }

  /// Retrieves progress for a single movie/show
  static Future<Map<String, dynamic>?> getProgress(int movieId, String mediaType) async {
    final box = await _openBox();
    final key = _getKey(movieId, mediaType);
    final data = box.get(key);
    return data != null ? Map<String, dynamic>.from(data) : null;
  }
}