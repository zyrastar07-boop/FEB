import '../models/movie.dart';

/// Centralized family-safe content gate for the Home feed.
///
/// The provider's `adult` flag is treated as authoritative when available.
/// The text pass is a fallback for items whose provider metadata is incomplete.
bool isFamilySafeMovie(Movie movie) {
  try {
    final dynamic raw = movie;
    if (raw.adult == true) return false;
  } catch (_) {
    // Continue with the textual safety check for model versions without
    // an `adult` property.
  }

  String overview = '';
  try {
    final dynamic raw = movie;
    overview = raw.overview?.toString() ?? '';
  } catch (_) {}

  final text = '${movie.title} $overview'.toLowerCase();

  const blockedTerms = <String>{
    'porn',
    'porno',
    'pornographic',
    'xxx',
    'nsfw',
    'hentai',
    'ecchi',
    'erotica',
    'erotic',
    'onlyfans',
    'sex tape',
    'sex film',
    'sex movie',
    'hardcore',
    'adult film',
    'adult movie',
    'adult content',
    'explicit sexual',
    'sexually explicit',
    'nudity',
    'nude scenes',
    'sexual content',
    'sexual exploitation',
    'fetish',
    'stripper',
  };

  for (final term in blockedTerms) {
    if (text.contains(term)) return false;
  }

  return true;
}
