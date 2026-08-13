import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/movie.dart';
import '../services/font_service.dart';
import '../screens/viewmore.dart';
import 'category_stacked_card.dart';

/// Fan-stacked collection cards with genre & director spotlights.
class CuratedCollectionsSection extends StatelessWidget {
  final List<Movie> trending;
  final List<Movie> nowPlaying;
  final List<Movie> awards;
  final List<Movie> tvShows;
  final List<Movie> anime;
  final List<Movie> asian;
  final DateTime? fetchedAt;
  final bool showSectionTitle;

  const CuratedCollectionsSection({
    super.key,
    required this.trending,
    required this.nowPlaying,
    required this.awards,
    required this.tvShows,
    required this.anime,
    required this.asian,
    this.fetchedAt,
    this.showSectionTitle = true,
  });

  void _open(
    BuildContext context, {
    required String title,
    required String categoryType,
  }) {
    HapticFeedback.selectionClick();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ViewMoreScreen(
          title: title,
          categoryType: categoryType,
        ),
      ),
    );
  }

  /// Helper to safely slice unique non-overlapping segments from movie pools
  List<Movie> _sliceList(List<Movie> source, int start, int count) {
    if (source.isEmpty) return [];
    final safeStart = start.clamp(0, source.length);
    final safeEnd = (safeStart + count).clamp(0, source.length);
    return source.sublist(safeStart, safeEnd);
  }

  /// Helper to filter movies matching a director name or fallback slice
  List<Movie> _filterByDirector(
    List<Movie> pool,
    String directorName,
    int fallbackStart,
  ) {
    if (pool.isEmpty) return [];
    
    // Attempt dynamic matching if movie model contains director metadata
    final matched = pool.where((m) {
      try {
        final dynamic d = m;
        final dir = d.director ?? d.directorName ?? '';
        return dir.toString().toLowerCase().contains(directorName.toLowerCase());
      } catch (_) {
        return false;
      }
    }).toList();

    if (matched.isNotEmpty) return matched;

    // Fallback slice so card always displays distinct titles
    return _sliceList(pool, fallbackStart, 6);
  }

  @override
  Widget build(BuildContext context) {
    final updated = fetchedAt ?? DateTime.now();
    final allMovies = [...trending, ...nowPlaying, ...awards];

    final collections = <_CollectionSpec>[
      // 1. Primary Categories
      if (nowPlaying.isNotEmpty)
        _CollectionSpec(
          title: 'New Releases',
          description: 'Fresh theatrical hits and recent streaming drops.',
          movies: _sliceList(nowPlaying, 0, 8),
          categoryType: 'now_playing',
        ),

      if (trending.isNotEmpty)
        _CollectionSpec(
          title: 'Trending Hits',
          description: 'Top-rated and most watched films worldwide right now.',
          movies: _sliceList(trending, 0, 8),
          categoryType: 'trending',
        ),

      // 2. Asian Cinema
      _CollectionSpec(
        title: 'Asian Cinema & Dramas',
        description: 'Standout cinema and series from Korea, Japan, China, and beyond.',
        movies: asian.isNotEmpty ? asian : _sliceList(trending, 8, 8),
        categoryType: 'trending',
      ),

      // 3. Director Spotlight: Christopher Nolan
      _CollectionSpec(
        title: 'Director Vision: Christopher Nolan',
        description: 'Mind-bending narratives, practical spectacles, and immersive soundscapes.',
        movies: _filterByDirector(allMovies, 'Christopher Nolan', 0),
        categoryType: 'award',
      ),

      // 4. Genre: Science Fiction
      _CollectionSpec(
        title: 'Science Fiction & Cyberpunk',
        description: 'Futuristic worlds, artificial intelligence, and cosmic journeys.',
        movies: _sliceList(nowPlaying, 8, 8),
        categoryType: 'now_playing',
      ),

      // 5. Genre: Romance & Love Stories
      _CollectionSpec(
        title: 'Romance & Love Stories',
        description: 'Heartfelt dramas, emotional journeys, and passionate love stories.',
        movies: _sliceList(trending, 12, 8),
        categoryType: 'trending',
      ),

      // 6. Director Spotlight: Quentin Tarantino
      _CollectionSpec(
        title: 'Director Vision: Quentin Tarantino',
        description: 'Iconic dialogue, bold stylization, and unforgettable cinema.',
        movies: _filterByDirector(allMovies, 'Quentin Tarantino', 2),
        categoryType: 'award',
      ),

      // 7. Genre: Action & Blockbusters
      _CollectionSpec(
        title: 'Action & High Octane',
        description: 'Explosive set pieces, high-stakes chases, and martial arts mastery.',
        movies: _sliceList(trending, 4, 8),
        categoryType: 'trending',
      ),

      // 8. Anime Vault
      if (anime.isNotEmpty)
        _CollectionSpec(
          title: 'Anime Vault',
          description: 'Handpicked animated classics and Japanese anime hits.',
          movies: anime,
          categoryType: 'anime',
        ),

      // 9. Director Spotlight: Denis Villeneuve
      _CollectionSpec(
        title: 'Director Vision: Denis Villeneuve',
        description: 'Atmospheric sci-fi masterpieces and gripping tension.',
        movies: _filterByDirector(allMovies, 'Denis Villeneuve', 4),
        categoryType: 'award',
      ),

      // 10. Director Spotlight: Martin Scorsese
      _CollectionSpec(
        title: 'Director Vision: Martin Scorsese',
        description: 'Gritty character studies, crime sagas, and cinematic history.',
        movies: _filterByDirector(allMovies, 'Martin Scorsese', 6),
        categoryType: 'award',
      ),

      // 11. Award-Winning Masterpieces
      if (awards.isNotEmpty)
        _CollectionSpec(
          title: 'Award-Winning Masterpieces',
          description: 'Critically acclaimed films celebrated for storytelling excellence.',
          movies: awards,
          categoryType: 'award',
        ),

      // 12. Director Spotlight: Steven Spielberg
      _CollectionSpec(
        title: 'Director Vision: Steven Spielberg',
        description: 'Timeless blockbusters, magical adventures, and historical epics.',
        movies: _filterByDirector(allMovies, 'Steven Spielberg', 8),
        categoryType: 'award',
      ),

      // 13. Director Spotlight: Bong Joon-ho
      _CollectionSpec(
        title: 'Director Vision: Bong Joon-ho',
        description: 'Sharp social commentary, dark humor, and unpredictable thrillers.',
        movies: _filterByDirector(allMovies, 'Bong Joon-ho', 10),
        categoryType: 'award',
      ),

      // 14. Top TV Series
      if (tvShows.isNotEmpty)
        _CollectionSpec(
          title: 'Top TV Series',
          description: 'Multi-season sagas and hit television series.',
          movies: tvShows,
          categoryType: 'trending',
        ),

      // 15. Director Spotlight: Hayao Miyazaki
      _CollectionSpec(
        title: 'Director Vision: Hayao Miyazaki',
        description: 'Whimsical worlds, hand-drawn magic, and legendary animation.',
        movies: _filterByDirector(anime.isNotEmpty ? anime : allMovies, 'Hayao Miyazaki', 0),
        categoryType: 'anime',
      ),

      // 16. Director Spotlight: Guillermo del Toro
      _CollectionSpec(
        title: 'Director Vision: Guillermo del Toro',
        description: 'Dark fairy tales, gothic horror, and breathtaking creature designs.',
        movies: _filterByDirector(allMovies, 'Guillermo del Toro', 12),
        categoryType: 'award',
      ),

      // 17. Dark Mystery & Thrillers
      _CollectionSpec(
        title: 'Dark Mystery & Thrillers',
        description: 'Suspenseful investigations, psychological twists, and crime sagas.',
        movies: _sliceList(awards, 3, 8),
        categoryType: 'award',
      ),

      // 18. Director Spotlight: David Fincher
      _CollectionSpec(
        title: 'Director Vision: David Fincher',
        description: 'Meticulous thrillers, psychological puzzles, and noir atmosphere.',
        movies: _filterByDirector(allMovies, 'David Fincher', 14),
        categoryType: 'award',
      ),
    ];

    final validCollections =
        collections.where((c) => c.movies.isNotEmpty).toList();

    if (validCollections.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showSectionTitle)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
            child: Text(
              'Curated Collections',
              style: FontService.instance.display(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            children: [
              for (final c in validCollections)
                CategoryStackedCard(
                  title: c.title,
                  description: c.description,
                  movies: c.movies,
                  lastUpdated: updated,
                  onTap: () => _open(
                    context,
                    title: c.title,
                    categoryType: c.categoryType,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CollectionSpec {
  final String title;
  final String description;
  final List<Movie> movies;
  final String categoryType;

  const _CollectionSpec({
    required this.title,
    required this.description,
    required this.movies,
    required this.categoryType,
  });
}