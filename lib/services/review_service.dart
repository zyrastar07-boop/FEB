import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

class UserReview {
  final String id;
  final String username;
  final DateTime date;
  final double rating;
  final String body;
  final bool containsSpoilers;
  final int upvotes;

  const UserReview({
    required this.id,
    required this.username,
    required this.date,
    required this.rating,
    required this.body,
    this.containsSpoilers = false,
    this.upvotes = 0,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'username': username,
        'date': date.toIso8601String(),
        'rating': rating,
        'body': body,
        'containsSpoilers': containsSpoilers,
        'upvotes': upvotes,
      };

  factory UserReview.fromMap(Map<String, dynamic> map) {
    return UserReview(
      id: map['id'] as String? ?? '',
      username: map['username'] as String? ?? 'you',
      date: DateTime.tryParse(map['date'] as String? ?? '') ?? DateTime.now(),
      rating: (map['rating'] as num?)?.toDouble() ?? 0,
      body: map['body'] as String? ?? '',
      containsSpoilers: map['containsSpoilers'] as bool? ?? false,
      upvotes: map['upvotes'] as int? ?? 0,
    );
  }
}

/// Persists per-title ratings and text reviews in Hive.
class ReviewService extends ChangeNotifier {
  ReviewService._();
  static final ReviewService instance = ReviewService._();

  static const String _boxName = 'user_reviews';

  Box? _box;
  bool _ready = false;

  Future<void> init() async {
    if (_ready) return;
    _box = Hive.isBoxOpen(_boxName)
        ? Hive.box(_boxName)
        : await Hive.openBox(_boxName);
    _ready = true;
    notifyListeners();
  }

  String _key(int tmdbId, String mediaType) => '$mediaType-$tmdbId';

  Map<String, dynamic> _entry(int tmdbId, String mediaType) {
    final raw = _box?.get(_key(tmdbId, mediaType));
    if (raw is Map) {
      return Map<String, dynamic>.from(raw);
    }
    return {'rating': 0.0, 'reviews': <Map<String, dynamic>>[]};
  }

  double getRating(int tmdbId, {String mediaType = 'movie'}) {
    return (_entry(tmdbId, mediaType)['rating'] as num?)?.toDouble() ?? 0.0;
  }

  List<UserReview> getReviews(int tmdbId, {String mediaType = 'movie'}) {
    final list = _entry(tmdbId, mediaType)['reviews'];
    if (list is! List) return const [];
    return list
        .whereType<Map>()
        .map((m) => UserReview.fromMap(Map<String, dynamic>.from(m)))
        .toList();
  }

  Future<void> setRating(
    int tmdbId,
    double rating, {
    String mediaType = 'movie',
  }) async {
    await init();
    final entry = _entry(tmdbId, mediaType);
    entry['rating'] = rating;
    await _box!.put(_key(tmdbId, mediaType), entry);
    notifyListeners();
  }

  Future<UserReview> addReview({
    required int tmdbId,
    required String body,
    required double rating,
    String mediaType = 'movie',
    String username = 'you',
    bool containsSpoilers = false,
  }) async {
    await init();
    final entry = _entry(tmdbId, mediaType);
    final review = UserReview(
      id: '${DateTime.now().millisecondsSinceEpoch}',
      username: username,
      date: DateTime.now(),
      rating: rating,
      body: body.trim(),
      containsSpoilers: containsSpoilers,
    );
    final reviews = List<Map<String, dynamic>>.from(
      (entry['reviews'] as List? ?? []).map(
        (e) => Map<String, dynamic>.from(e as Map),
      ),
    );
    reviews.insert(0, review.toMap());
    entry['reviews'] = reviews;
    if (rating > 0) entry['rating'] = rating;
    await _box!.put(_key(tmdbId, mediaType), entry);
    notifyListeners();
    return review;
  }

  Future<void> deleteReview(
    int tmdbId,
    String reviewId, {
    String mediaType = 'movie',
  }) async {
    await init();
    final entry = _entry(tmdbId, mediaType);
    final reviews = List<Map<String, dynamic>>.from(
      (entry['reviews'] as List? ?? []).map(
        (e) => Map<String, dynamic>.from(e as Map),
      ),
    )..removeWhere((r) => r['id'] == reviewId);
    entry['reviews'] = reviews;
    await _box!.put(_key(tmdbId, mediaType), entry);
    notifyListeners();
  }
}
