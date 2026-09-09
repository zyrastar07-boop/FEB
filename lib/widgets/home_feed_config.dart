/// Curated home feed definition — expandable without rewriting HomeScreen.
/// Each section maps to a TMDB category key or a local list key filled at runtime.
class HomeFeedSection {
  final String id;
  final String title;
  final String? categoryType; // for ViewMoreScreen
  final String? listKey; // runtime bag: action, scifi, mood_mind, etc.
  final String? pillLabel; // shown on cards
  final bool markTv;

  const HomeFeedSection({
    required this.id,
    required this.title,
    this.categoryType,
    this.listKey,
    this.pillLabel,
    this.markTv = false,
  });
}

/// High-density discovery rails. Add more entries here to grow the feed.
/// (True 120+ unique API categories would thrash TMDB rate limits; this set
/// is curated for engagement and maps onto methods your TmdbService already has.)
const List<HomeFeedSection> kHomeFeedSections = [
  // Core
  HomeFeedSection(
    id: 'action',
    title: 'Action Packed',
    categoryType: 'action',
    listKey: 'action',
    pillLabel: 'Action',
  ),
  HomeFeedSection(
    id: 'scifi',
    title: 'Science Fiction',
    categoryType: 'scifi',
    listKey: 'scifi',
    pillLabel: 'Sci-Fi',
  ),
  HomeFeedSection(
    id: 'classics',
    title: 'Classic Films',
    categoryType: 'classics',
    listKey: 'classics',
    pillLabel: 'Classic',
  ),
  HomeFeedSection(
    id: 'romance',
    title: 'Romantic Escapes',
    categoryType: 'romance',
    listKey: 'romance',
    pillLabel: 'Romance',
  ),
  HomeFeedSection(
    id: 'now_playing',
    title: 'In Theaters',
    categoryType: 'now_playing',
    listKey: 'now_playing',
    pillLabel: 'Cinema',
  ),
  HomeFeedSection(
    id: 'award',
    title: 'Award Winners',
    categoryType: 'award',
    listKey: 'award',
    pillLabel: 'Award',
  ),
  HomeFeedSection(
    id: 'tv',
    title: 'TV Series',
    categoryType: 'tv',
    listKey: 'tv',
    pillLabel: 'Series',
    markTv: true,
  ),

  // Moods (reuse genre bags with emotional titles)
  HomeFeedSection(
    id: 'mood_mind',
    title: 'Mind-Benders',
    categoryType: 'scifi',
    listKey: 'scifi',
    pillLabel: 'Twist',
  ),
  HomeFeedSection(
    id: 'mood_heart',
    title: 'Heartwarming Escapes',
    categoryType: 'romance',
    listKey: 'romance',
    pillLabel: 'Warm',
  ),
  HomeFeedSection(
    id: 'mood_villain',
    title: 'Root for the Villain',
    categoryType: 'action',
    listKey: 'action',
    pillLabel: 'Dark',
  ),
  HomeFeedSection(
    id: 'mood_hook',
    title: 'Hooked from Ep 1',
    categoryType: 'tv',
    listKey: 'tv',
    pillLabel: 'Binge',
    markTv: true,
  ),
  HomeFeedSection(
    id: 'mood_endings',
    title: 'Perfect Endings',
    categoryType: 'award',
    listKey: 'award',
    pillLabel: 'Finale',
  ),
  HomeFeedSection(
    id: 'mood_plot',
    title: 'Plot Twists',
    categoryType: 'scifi',
    listKey: 'scifi',
    pillLabel: 'Surprise',
  ),

  // Extra discovery labels (same pools, different framing for scannability)
  HomeFeedSection(
    id: 'late_night',
    title: 'Late-Night Thrills',
    categoryType: 'action',
    listKey: 'action',
    pillLabel: 'Night',
  ),
  HomeFeedSection(
    id: 'weekend',
    title: 'Weekend Watchlist',
    categoryType: 'now_playing',
    listKey: 'now_playing',
    pillLabel: 'Weekend',
  ),
  HomeFeedSection(
    id: 'prestige',
    title: 'Prestige TV Energy',
    categoryType: 'tv',
    listKey: 'tv',
    pillLabel: 'Prestige',
    markTv: true,
  ),
];

/// Spotlight people for “Actors & Directors” chips (opens PersonCreditsScreen by id).
const List<Map<String, String>> kSpotlightPeople = [
  {'name': 'Christopher Nolan', 'kind': 'director', 'id': '525'},
  {'name': 'Denis Villeneuve', 'kind': 'director', 'id': '137427'},
  {'name': 'Greta Gerwig', 'kind': 'director', 'id': '45400'},
  {'name': 'Hayao Miyazaki', 'kind': 'director', 'id': '608'},
  {'name': 'Quentin Tarantino', 'kind': 'director', 'id': '138'},
  {'name': 'Timothée Chalamet', 'kind': 'actor', 'id': '1190668'},
  {'name': 'Florence Pugh', 'kind': 'actor', 'id': '1393134'},
  {'name': 'Cillian Murphy', 'kind': 'actor', 'id': '2037'},
  {'name': 'Zendaya', 'kind': 'actor', 'id': '505710'},
  {'name': 'Keanu Reeves', 'kind': 'actor', 'id': '6384'},
  {'name': 'Margot Robbie', 'kind': 'actor', 'id': '234352'},
  {'name': 'Ryan Gosling', 'kind': 'actor', 'id': '30614'},
];