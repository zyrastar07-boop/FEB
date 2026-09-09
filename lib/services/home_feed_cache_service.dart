import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/movie.dart';

/// Disk-backed cache for Home screen feed rows (trending, action, tv, etc).
///
/// This is what makes the app feel instant on open: HomeScreen hydrates
/// synchronously from whatever was cached last time, paints immediately
/// with zero shimmer/spinner, then silently refreshes from the network
/// in the background and updates the UI + cache when the real data lands.
///
/// If there's no cache yet (first-ever launch) it behaves exactly like
/// before: shows the skeleton loader while the first fetch completes.
class HomeFeedCacheService {
  HomeFeedCacheService._();
  static final HomeFeedCacheService instance = HomeFeedCacheService._();

  static const _boxName = 'home_feed_cache';

  /// How long cached data is considered "fresh enough" to skip an
  /// immediate background refresh. Stale data is still shown instantly,
  /// just refreshed right away instead of after this window.
  static const freshWindow = Duration(minutes: 15);

  Box<Movie>? _box;
  Future<Box<Movie>>? _opening;

  Future<Box<Movie>> _openBox() {
    if (_box != null) return Future.value(_box);
    if (Hive.isBoxOpen(_boxName)) {
      _box = Hive.box<Movie>(_boxName);
      return Future.value(_box);
    }
    return _opening ??= Hive.openBox<Movie>(_boxName).then((b) {
      _box = b;
      _opening = null;
      return b;
    }).catchError((Object e, StackTrace st) {
      _opening = null;
      throw e;
    });
  }

  /// Persists [movies] under [key] (e.g. 'trending', 'action', 'tv').
  /// Fire-and-forget safe: swallow errors so a cache-write hiccup never
  /// takes down the home feed.
  Future<void> saveCategory(String key, List<Movie> movies) async {
    if (movies.isEmpty) return;
    try {
      final box = await _openBox();
      final prefs = await SharedPreferences.getInstance();

      // Clean out the previous entries for this key before writing new ones
      // so stale trailing items from a shorter previous list don't linger.
      // Both phases are single batched transactions (deleteAll / putAll) —
      // Hive applies each as one atomic write instead of N sequential ones.
      final oldIds = prefs.getStringList('home_cache_ids_$key') ?? const [];
      if (oldIds.isNotEmpty) {
        await box.deleteAll(oldIds);
      }

      final newIds = <String>[];
      final entries = <dynamic, Movie>{};
      for (var i = 0; i < movies.length; i++) {
        final cacheKey = '${key}_$i';
        entries[cacheKey] = movies[i];
        newIds.add(cacheKey);
      }
      await box.putAll(entries);

      await prefs.setStringList('home_cache_ids_$key', newIds);
      await prefs.setInt(
        'home_cache_ts_$key',
        DateTime.now().millisecondsSinceEpoch,
      );
    } catch (_) {
      // Cache is a nice-to-have; never let it throw into the caller.
    }
  }

  /// Returns the cached movies for [key], or an empty list if there's
  /// nothing cached yet.
  Future<List<Movie>> loadCategory(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final ids = prefs.getStringList('home_cache_ids_$key');
      if (ids == null || ids.isEmpty) return const [];
      final box = await _openBox();
      return ids.map((id) => box.get(id)).whereType<Movie>().toList();
    } catch (_) {
      return const [];
    }
  }

  /// Whether the cache for [key] is still within [freshWindow].
  Future<bool> isFresh(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final ts = prefs.getInt('home_cache_ts_$key');
      if (ts == null) return false;
      final age = DateTime.now().difference(
        DateTime.fromMillisecondsSinceEpoch(ts),
      );
      return age < freshWindow;
    } catch (_) {
      return false;
    }
  }
}