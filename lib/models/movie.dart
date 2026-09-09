import 'package:hive/hive.dart';
import '../utils/tmdb_image_helper.dart';

// Required for code generation
part 'movie.g.dart';

@HiveType(typeId: 0)
class Movie extends HiveObject {
  @HiveField(0)
  final int id;

  @HiveField(1)
  final String title;

  @HiveField(2)
  final String? posterPath;

  @HiveField(3)
  final String? backdropPath;

  @HiveField(4)
  final String? overview;

  @HiveField(5)
  final double voteAverage;

  @HiveField(6)
  final String releaseDate;

  @HiveField(7)
  final String mediaType;

  Movie({
    required this.id,
    required this.title,
    this.posterPath,
    this.backdropPath,
    this.overview,
    required this.voteAverage,
    required this.releaseDate,
    this.mediaType = 'movie',
  });

  factory Movie.fromJson(Map<String, dynamic> json) {
    return Movie(
      id: json['id'] ?? 0,
      title: json['title'] ?? json['name'] ?? 'Untitled',
      posterPath: json['poster_path'],
      backdropPath: json['backdrop_path'],
      overview: json['overview'] as String?,
      voteAverage: (json['vote_average'] as num?)?.toDouble() ?? 0.0,
      releaseDate: json['release_date'] ?? json['first_air_date'] ?? '',
      mediaType: json['media_type'] ?? 'movie',
    );
  }

  String get posterUrl => posterPath != null
      ? TmdbImageHelper.getUrl(posterPath!, TmdbImageSize.w500)
      : 'https://via.placeholder.com/500x750?text=No+Poster';

  String? get backdropUrl => backdropPath != null
      ? TmdbImageHelper.getUrl(backdropPath!, TmdbImageSize.w780)
      : null;

  String get releaseYear =>
      releaseDate.length >= 4 ? releaseDate.substring(0, 4) : 'N/A';
}
