import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/movie.dart';

/// Persists lightweight viewing events used by the analytics dashboard.
/// Existing libraries remain the source of truth for watched/watchlist counts;
/// this store only adds timestamps and user ratings needed for charts.
class WatchAnalyticsService extends ChangeNotifier {
  static final WatchAnalyticsService instance = WatchAnalyticsService._();
  WatchAnalyticsService._() { _load(); }

  static const _eventsKey = 'feb_watch_analytics_events_v1';
  static const _ratingsKey = 'feb_user_ratings_v1';

  final List<Map<String, dynamic>> _events = [];
  final Map<String, double> _ratings = {};
  bool _loaded = false;

  List<Map<String, dynamic>> get events => List.unmodifiable(_events);
  Map<String, double> get ratings => Map.unmodifiable(_ratings);

  Future<void> _load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final rawEvents = prefs.getString(_eventsKey);
      if (rawEvents != null && rawEvents.isNotEmpty) {
        final decoded = jsonDecode(rawEvents);
        if (decoded is List) {
          _events
            ..clear()
            ..addAll(decoded.whereType<Map>().map((e) => Map<String, dynamic>.from(e)));
        }
      }
      final rawRatings = prefs.getString(_ratingsKey);
      if (rawRatings != null && rawRatings.isNotEmpty) {
        final decoded = jsonDecode(rawRatings);
        if (decoded is Map) {
          _ratings
            ..clear()
            ..addEntries(decoded.entries.map((e) => MapEntry(e.key.toString(), (e.value as num).toDouble())));
        }
      }
      notifyListeners();
    } catch (_) {}
  }

  String keyFor(Movie movie) => '${movie.mediaType.isEmpty ? 'movie' : movie.mediaType}:${movie.id}';

  Future<void> recordWatched(Movie movie, {String source = 'watched'}) async {
    await _load();
    final now = DateTime.now();
    final key = keyFor(movie);
    _events.removeWhere((e) => e['key'] == key && e['type'] == 'watched');
    _events.insert(0, {
      'type': 'watched',
      'key': key,
      'id': movie.id,
      'title': movie.title,
      'mediaType': movie.mediaType,
      'releaseDate': movie.releaseDate,
      'timestamp': now.millisecondsSinceEpoch,
      'source': source,
    });
    if (_events.length > 500) _events.removeRange(500, _events.length);
    await _persistEvents();
    notifyListeners();
  }

  Future<void> recordWatchlistChange(Movie movie, bool added) async {
    await _load();
    _events.insert(0, {
      'type': added ? 'watchlist_add' : 'watchlist_remove',
      'key': keyFor(movie),
      'id': movie.id,
      'title': movie.title,
      'mediaType': movie.mediaType,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
    if (_events.length > 500) _events.removeRange(500, _events.length);
    await _persistEvents();
    notifyListeners();
  }

  Future<void> setRating(Movie movie, double rating) async {
    await _load();
    final value = rating.clamp(0.0, 5.0).toDouble();
    final key = keyFor(movie);
    if (value == 0) {
      _ratings.remove(key);
    } else {
      _ratings[key] = value;
    }
    await SharedPreferences.getInstance().then((prefs) => prefs.setString(_ratingsKey, jsonEncode(_ratings)));
    notifyListeners();
  }

  double ratingFor(Movie movie) => _ratings[keyFor(movie)] ?? 0;

  Future<void> clearAnalytics() async {
    _events.clear();
    _ratings.clear();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_eventsKey);
    await prefs.remove(_ratingsKey);
    notifyListeners();
  }

  Future<void> _persistEvents() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_eventsKey, jsonEncode(_events));
  }
}
