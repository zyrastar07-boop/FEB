// lib/utils/tmdb_image_helper.dart

enum TmdbImageSize {
  original,
  w1280,
  w780,
  w500,
  w342,
  w300,
  w200,
  w185,
  w92,
}

class TmdbImageHelper {
  static const String _baseUrl = 'https://image.tmdb.org/t/p/';

  static String getUrl(String? path, TmdbImageSize size) {
    if (path == null || path.isEmpty) return '';
    final sizeString = size.toString().split('.').last;
    return '$_baseUrl$sizeString$path';
  }
}
