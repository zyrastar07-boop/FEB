import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/movie.dart';

/// Local library: Watchlist, Watched, Liked, My List.
/// Persisted with SharedPreferences. Used by DetailScreen + Library.
class UserLibraryService extends ChangeNotifier {
  static final UserLibraryService instance = UserLibraryService._();
  UserLibraryService._() {
    hydrate();
  }

  static const _kWatchlist = 'mela_lib_watchlist_v1';
  static const _kWatched = 'mela_lib_watched_v1';
  static const _kLiked = 'mela_lib_liked_v1';
  static const _kMyList = 'mela_lib_mylist_v1';

  final List<Movie> _watchlist = [];
  final List<Movie> _watched = [];
  final List<Movie> _liked = [];
  final List<Movie> _myList = [];

  bool _hydrated = false;

  List<Movie> get watchlist => List.unmodifiable(_watchlist);
  List<Movie> get watched => List.unmodifiable(_watched);
  List<Movie> get liked => List.unmodifiable(_liked);
  List<Movie> get myList => List.unmodifiable(_myList);

  int get watchlistCount => _watchlist.length;
  int get watchedCount => _watched.length;
  int get likedCount => _liked.length;
  int get myListCount => _myList.length;

  String _key(Movie m) {
    final type = (m.mediaType.isNotEmpty ? m.mediaType : 'movie').toLowerCase();
    return '$type:${m.id}';
  }

  bool _contains(List<Movie> list, Movie m) {
    final k = _key(m);
    return list.any((e) => _key(e) == k);
  }

  int _indexOf(List<Movie> list, Movie m) {
    final k = _key(m);
    return list.indexWhere((e) => _key(e) == k);
  }

  // ---- Query helpers used by DetailScreen ----

  bool isInWatchlistMovie(Movie m) => _contains(_watchlist, m);
  bool isWatchedMovie(Movie m) => _contains(_watched, m);
  bool isLikedMovie(Movie m) => _contains(_liked, m);
  bool isInMyListMovie(Movie m) => _contains(_myList, m);

  // Aliases some screens may call
  bool isInWatchlist(Movie m) => isInWatchlistMovie(m);
  bool isWatched(Movie m) => isWatchedMovie(m);

  /// Called from main.dart — same as hydrate().
  Future<void> init() => hydrate();

  Future<void> hydrate() async {
    if (_hydrated) return;
    _hydrated = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      _watchlist
        ..clear()
        ..addAll(_decode(prefs.getString(_kWatchlist)));
      _watched
        ..clear()
        ..addAll(_decode(prefs.getString(_kWatched)));
      _liked
        ..clear()
        ..addAll(_decode(prefs.getString(_kLiked)));
      _myList
        ..clear()
        ..addAll(_decode(prefs.getString(_kMyList)));
      notifyListeners();
    } catch (e) {
      debugPrint('[UserLibraryService] hydrate failed: $e');
    }
  }

  List<Movie> _decode(String? raw) {
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List;
      final out = <Movie>[];
      for (final e in list) {
        try {
          final map = e is Map<String, dynamic>
              ? e
              : Map<String, dynamic>.from(e as Map);
          try {
            out.add(Movie.fromJson(map));
          } catch (_) {
            // Fallback if Movie.fromJson is unavailable or schema differs
            out.add(Movie(
              id: (map['id'] as num?)?.toInt() ?? 0,
              title: (map['title'] ?? map['name'] ?? '') as String,
              posterPath: (map['poster_path'] ?? map['posterPath'] ?? '') as String?,
              backdropPath:
                  (map['backdrop_path'] ?? map['backdropPath'] ?? '') as String?,
              overview: (map['overview'] ?? '') as String?,
              voteAverage: (map['vote_average'] as num?)?.toDouble() ?? 0,
              releaseDate:
                  (map['release_date'] ?? map['first_air_date'] ?? '') as String,
              mediaType: (map['media_type'] ?? map['mediaType'] ?? 'movie') as String,
            ));
          }
        } catch (_) {}
      }
      return out.where((m) => m.id != 0).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _persist(String key, List<Movie> list) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = jsonEncode(list.map((m) {
        try {
          final dynamic d = m;
          if (d.toJson is Function) return d.toJson();
        } catch (_) {}
        return {
          'id': m.id,
          'title': m.title,
          'poster_path': m.posterPath,
          'backdrop_path': m.backdropPath,
          'overview': m.overview,
          'vote_average': m.voteAverage,
          'release_date': m.releaseDate,
          'media_type': m.mediaType,
        };
      }).toList());
      await prefs.setString(key, encoded);
    } catch (e) {
      debugPrint('[UserLibraryService] persist failed: $e');
    }
  }

  /// Returns true if now in the list, false if removed.
  Future<bool> _toggle(List<Movie> list, String storageKey, Movie m) async {
    await hydrate();
    final i = _indexOf(list, m);
    if (i >= 0) {
      list.removeAt(i);
      await _persist(storageKey, list);
      notifyListeners();
      return false;
    }
    list.insert(0, m);
    await _persist(storageKey, list);
    notifyListeners();
    return true;
  }

  Future<bool> toggleWatchlist(Movie m) =>
      _toggle(_watchlist, _kWatchlist, m);

  Future<bool> toggleWatched(Movie m) => _toggle(_watched, _kWatched, m);

  Future<bool> toggleLiked(Movie m) => _toggle(_liked, _kLiked, m);

  Future<bool> toggleMyList(Movie m) => _toggle(_myList, _kMyList, m);

  Future<void> removeFromWatchlist(int id) async {
    await hydrate();
    _watchlist.removeWhere((m) => m.id == id);
    await _persist(_kWatchlist, _watchlist);
    notifyListeners();
  }

  Future<void> removeFromWatched(int id) async {
    await hydrate();
    _watched.removeWhere((m) => m.id == id);
    await _persist(_kWatched, _watched);
    notifyListeners();
  }

  Future<void> removeFromLiked(int id) async {
    await hydrate();
    _liked.removeWhere((m) => m.id == id);
    await _persist(_kLiked, _liked);
    notifyListeners();
  }

  Future<void> removeFromMyList(int id) async {
    await hydrate();
    _myList.removeWhere((m) => m.id == id);
    await _persist(_kMyList, _myList);
    notifyListeners();
  }
}