import 'movie.dart';

/// A user-created collection of movies / TV titles.
class UserList {
  final String id;
  final String name;
  final String description;
  final List<Movie> items;
  final DateTime createdAt;
  final DateTime updatedAt;

  const UserList({
    required this.id,
    required this.name,
    this.description = '',
    this.items = const [],
    required this.createdAt,
    required this.updatedAt,
  });

  int get contentCount => items.length;

  int get watchedCount {
    // Prefer explicit watched flags if present on Movie; otherwise 0.
    try {
      return items.where((m) {
        final dynamic d = m;
        if (d.isWatched is bool) return d.isWatched as bool;
        return false;
      }).length;
    } catch (_) {
      return 0;
    }
  }

  double get progressPercent {
    if (items.isEmpty) return 0;
    return (watchedCount / items.length).clamp(0.0, 1.0) * 100;
  }

  List<String> get posterUrls {
    final urls = <String>[];
    for (final m in items) {
      if (urls.length >= 5) break;
      final url = _posterOf(m);
      if (url.isNotEmpty) urls.add(url);
    }
    return urls;
  }

  static String _posterOf(Movie m) {
    try {
      final dynamic d = m;
      if (d.posterUrl is String && (d.posterUrl as String).isNotEmpty) {
        return d.posterUrl as String;
      }
      final path = d.posterPath;
      if (path is String && path.isNotEmpty) {
        if (path.startsWith('http')) return path;
        return 'https://image.tmdb.org/t/p/w342$path';
      }
    } catch (_) {}
    return '';
  }

  UserList copyWith({
    String? name,
    String? description,
    List<Movie>? items,
    DateTime? updatedAt,
  }) {
    return UserList(
      id: id,
      name: name ?? this.name,
      description: description ?? this.description,
      items: items ?? this.items,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'items': items.map((m) {
          try {
            final dynamic d = m;
            if (d.toJson is Function) return d.toJson();
          } catch (_) {}
          return {
            'id': m.id,
            'title': m.title,
            'poster_path': m.posterPath,
            'overview': m.overview,
            'vote_average': m.voteAverage,
            'release_date': m.releaseDate,
            'media_type': m.mediaType,
          };
        }).toList(),
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory UserList.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'] as List? ?? [];
    final items = <Movie>[];
    for (final e in rawItems) {
      try {
        if (e is Map<String, dynamic>) {
          items.add(Movie.fromJson(e));
        } else if (e is Map) {
          items.add(Movie.fromJson(Map<String, dynamic>.from(e)));
        }
      } catch (_) {}
    }
    return UserList(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'Untitled',
      description: json['description'] as String? ?? '',
      items: items,
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}