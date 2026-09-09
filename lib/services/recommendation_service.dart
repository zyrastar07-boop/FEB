import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/movie.dart';
import 'auth_service.dart';

/// TikTok-style recommendation engine with weighted genre affinity.
///
/// - like / notInterested persist per signed-in user (or guest)
/// - genre weights update on each interaction
/// - rankForYou / filterForHome for Home rails
/// - strong adult / NR filter
class RecommendationService extends ChangeNotifier {
  static final RecommendationService instance = RecommendationService._();
  RecommendationService._();

  static const _prefsKeyPrefix = 'rec_v2_';

  final Set<int> _likedIds = {};
  final Set<int> _notInterestedIds = {};
  /// genre key → affinity weight (positive = like, negative = avoid)
  final Map<String, double> _genreScores = {};
  final List<_Interaction> _recent = [];

  bool _loaded = false;

  Set<int> get likedIds => Set.unmodifiable(_likedIds);
  Set<int> get notInterestedIds => Set.unmodifiable(_notInterestedIds);
  Map<String, double> get genreScores => Map.unmodifiable(_genreScores);

  String get _storageKey {
    final uid = AuthService().currentUser?.uid;
    return '$_prefsKeyPrefix${uid ?? 'guest'}';
  }

  Future<void> ensureLoaded() async {
    if (_loaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKey);
      if (raw != null && raw.isNotEmpty) {
        final map = jsonDecode(raw) as Map<String, dynamic>;
        _likedIds
          ..clear()
          ..addAll(
              (map['liked'] as List? ?? []).map((e) => (e as num).toInt()));
        _notInterestedIds
          ..clear()
          ..addAll((map['ni'] as List? ?? []).map((e) => (e as num).toInt()));
        _genreScores
          ..clear()
          ..addAll(Map<String, double>.from(
            (map['genres'] as Map? ?? {}).map(
              (k, v) => MapEntry(k.toString(), (v as num).toDouble()),
            ),
          ));
      }
    } catch (e) {
      debugPrint('RecommendationService load: $e');
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _storageKey,
        jsonEncode({
          'liked': _likedIds.toList(),
          'ni': _notInterestedIds.toList(),
          'genres': _genreScores,
        }),
      );
    } catch (e) {
      debugPrint('RecommendationService persist: $e');
    }
  }

  Future<void> like(Movie movie) async {
    await ensureLoaded();
    _notInterestedIds.remove(movie.id);
    _likedIds.add(movie.id);
    _bumpGenres(movie, 2.0);
    _pushRecent(movie.id, liked: true);
    await _persist();
    notifyListeners();
  }

  /// Hide forever from personalized Home rails.
  Future<void> notInterested(Movie movie) async {
    await ensureLoaded();
    _likedIds.remove(movie.id);
    _notInterestedIds.add(movie.id);
    _bumpGenres(movie, -3.0);
    _pushRecent(movie.id, liked: false);
    await _persist();
    notifyListeners();
  }

  void _pushRecent(int id, {required bool liked}) {
    _recent.add(_Interaction(id, liked, DateTime.now()));
    while (_recent.length > 100) {
      _recent.removeAt(0);
    }
  }

  void _bumpGenres(Movie movie, double delta) {
    for (final g in _genresOf(movie)) {
      final next = ((_genreScores[g] ?? 0) + delta).clamp(-30.0, 30.0);
      _genreScores[g] = next;
    }
    // Soft decay of very old weak signals
    if (_genreScores.length > 40) {
      final keys = _genreScores.keys.toList();
      for (final k in keys) {
        final v = _genreScores[k]!;
        if (v.abs() < 0.4) _genreScores.remove(k);
      }
    }
  }

  List<String> _genresOf(Movie movie) {
    final out = <String>[];
    try {
      final dynamic m = movie;
      final ids = m.genreIds;
      if (ids is List) {
        for (final id in ids) {
          out.add('id:$id');
        }
      }
      final names = m.genres;
      if (names is List) {
        for (final n in names) {
          out.add(n.toString().toLowerCase().trim());
        }
      }
    } catch (_) {}
    final t = movie.title.toLowerCase();
    if (RegExp(r'\b(love|romance|wedding)\b').hasMatch(t)) out.add('romance');
    if (RegExp(r'\b(war|battle|soldier)\b').hasMatch(t)) out.add('action');
    if (RegExp(r'\b(space|alien|robot|future)\b').hasMatch(t)) out.add('scifi');
    return out.toSet().toList();
  }

  bool isHidden(int movieId) => _notInterestedIds.contains(movieId);
  bool isLiked(int movieId) => _likedIds.contains(movieId);

  // ── Adult / NR block ───────────────────────────────────────────────────

  static const _adultTerms = [
    'porn', 'porno', 'xxx', 'nsfw', 'hentai', 'erotica', 'erotic',
    'onlyfans', 'sex tape', 'hardcore', 'adult film', 'adult movie',
    'softcore', 'nude', 'nudity', 'sex scene', 'nc-17', 'unrated cut',
    'adults only', '18+', 'xxx ', 'leviticus',
    // NR / Not Rated and mature cert labels that may appear in titles/overviews
    ' not rated', 'not rated', '(nr)', '[nr]', ' tv-ma', 'tv-ma',
    'nc17', ' rated r', '(r)', 'unrated',
  ];

  bool isFamilySafe(Movie m) {
    try {
      final dynamic dm = m;
      if (dm.adult == true) return false;
      // Certification / parentalRating read dynamically (Movie may carry them
      // optionally); the loop below tries each accessor in turn.
      final cert = () {
        try {
          final c = dm.certification?.toString() ??
              dm.parentalRating?.toString() ??
              dm.contentRating?.toString() ??
              '';
          return c.toUpperCase().trim();
        } catch (_) {
          return '';
        }
      }();
      if (cert.isNotEmpty) {
        const blocked = {
          'R', 'NC-17', 'NC17', 'X', 'XX', 'XXX', 'AO',
          'NR', 'N/R', 'NOT RATED', 'NOTRATED', 'UNRATED', 'UR',
          'TV-MA', 'TVMA', 'MA', 'MA15+', 'MA18', 'M18',
          '18', '18+', '18A', 'R18', 'R18+', 'R-18',
          '16+', '17+', '21', '21+', 'ADULT',
        };
        if (blocked.contains(cert)) return false;
        if (cert.startsWith('TV-MA') || cert.startsWith('NC-17')) return false;
      }
    } catch (_) {}
    String overview = '';
    try {
      overview = (m as dynamic).overview?.toString() ?? '';
    } catch (_) {}
    final blob = ('${m.title} $overview').toLowerCase();
    for (final term in _adultTerms) {
      if (blob.contains(term)) return false;
    }
    return true;
  }

  /// Weighted score for ranking (higher = better match for this user).
  double score(Movie movie) {
    if (isHidden(movie.id)) return -1e9;
    if (!isFamilySafe(movie)) return -1e8;

    var s = 0.0;

    // Weighted genre affinity
    final genres = _genresOf(movie);
    for (final g in genres) {
      s += (_genreScores[g] ?? 0) * 1.35;
    }

    if (_likedIds.contains(movie.id)) s += 14;

    try {
      s += (movie.voteAverage.clamp(0, 10)) * 0.4;
    } catch (_) {}

    // Recency of similar likes
    final now = DateTime.now();
    for (final i in _recent.reversed.take(25)) {
      if (!i.liked) continue;
      final ageH = now.difference(i.at).inHours.clamp(1, 96);
      s += 1.1 / ageH;
    }

    return s;
  }

  List<Movie> rankForYou(List<Movie> candidates, {int take = 18}) {
    final filtered = candidates
        .where((m) => !isHidden(m.id) && isFamilySafe(m))
        .toList();
    filtered.sort((a, b) => score(b).compareTo(score(a)));
    return filtered.take(take).toList();
  }

  List<Movie> filterForHome(List<Movie> list) {
    return list
        .where((m) => !isHidden(m.id) && isFamilySafe(m))
        .toList();
  }
}

class _Interaction {
  final int id;
  final bool liked;
  final DateTime at;
  _Interaction(this.id, this.liked, this.at);
}