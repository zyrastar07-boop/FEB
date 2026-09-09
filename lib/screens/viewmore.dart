import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/movie.dart';
import '../services/tmdb_service.dart';
import '../services/font_service.dart';
import '../services/recommendation_service.dart';
import '../design/tokens.dart';
import '../utils/adaptive.dart';
import '../widgets/poster_card.dart';
import 'detail_screen.dart';

/// Full-list screen for a home rail.
///
/// Prefer [seedMovies] when opening from a curated home section so the grid
/// matches what the user saw on Home. [categoryType] is used to load more of
/// the same kind. [forceTv] keeps TV sections on series only.
class ViewMoreScreen extends StatefulWidget {
  const ViewMoreScreen({
    super.key,
    required this.title,
    this.categoryType = 'trending',
    this.seedMovies = const [],
    this.forceTv = false,
  });

  final String title;
  final String categoryType;
  final List<Movie> seedMovies;
  final bool forceTv;

  @override
  State<ViewMoreScreen> createState() => _ViewMoreScreenState();
}

class _ViewMoreScreenState extends State<ViewMoreScreen> {
  final TmdbService _tmdb = TmdbService();
  final List<Movie> _movies = [];
  final Set<int> _seen = {};
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasError = false;
  bool _hasMore = true;
  int _page = 1;

  bool get _isTvCategory {
    if (widget.forceTv) return true;
    final c = widget.categoryType.toLowerCase();
    return c == 'tv' || c == 'anime' || c.contains('series');
  }

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    // Start with the exact curated rail the user tapped.
    if (widget.seedMovies.isNotEmpty) {
      for (final m in widget.seedMovies) {
        if (_seen.add(m.id)) _movies.add(_normalize(m));
      }
      if (mounted) {
        setState(() {
          _loading = false;
          _hasError = false;
        });
      }
      // Quietly expand in the background so the grid isn't short.
      _loadPage(reset: false);
      return;
    }
    await _loadPage(reset: true);
  }

  Movie _normalize(Movie m) {
    // Prefer the original instance. Detail opens with isTv from forceTv /
    // mediaType, so we avoid reconstructing Movie (field sets vary by app version).
    return m;
  }

  Future<void> _loadPage({required bool reset}) async {
    if (reset) {
      if (!mounted) return;
      setState(() {
        _loading = true;
        _hasError = false;
        _page = 1;
        _hasMore = true;
        _movies.clear();
        _seen.clear();
      });
    } else {
      if (_loadingMore || !_hasMore) return;
      if (!mounted) return;
      setState(() => _loadingMore = true);
    }

    try {
      final page = reset ? 1 : _page;
      final raw = await _fetchCategory(page);
      final filtered = <Movie>[];
      for (final m in raw) {
        if (!RecommendationService.instance.isFamilySafe(m)) continue;
        final item = _normalize(m);
        // Keep TV rails on TV only.
        if (_isTvCategory && item.mediaType != 'tv') continue;
        if (!_isTvCategory &&
            item.mediaType == 'tv' &&
            widget.categoryType != 'trending') {
          // Mixed trending can keep TV; pure movie categories drop series.
          continue;
        }
        if (_seen.add(item.id)) filtered.add(item);
      }

      if (!mounted) return;
      setState(() {
        _movies.addAll(filtered);
        _page = page + 1;
        _hasMore = raw.isNotEmpty && filtered.isNotEmpty;
        _loading = false;
        _loadingMore = false;
        _hasError = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadingMore = false;
        if (_movies.isEmpty) _hasError = true;
      });
    }
  }

  Future<List<Movie>> _fetchCategory(int page) async {
    final type = widget.categoryType.toLowerCase();
    // Prefer methods that exist on TmdbService; fall back gracefully.
    try {
      switch (type) {
        case 'trending':
          return await _tmdb.getTrendingMovies();
        case 'action':
          return await _tmdb.getActionMovies();
        case 'scifi':
          return await _tmdb.getSciFiMovies();
        case 'classics':
          return await _tmdb.getClassicMovies();
        case 'now_playing':
          return await _tmdb.getNowPlayingMovies();
        case 'award':
          return await _tmdb.getMoviesByCategory(categoryType: 'award');
        case 'tv':
          return await _tmdb.getTrendingTvShows();
        case 'anime':
          try {
            final tv = await _tmdb.getAnimeTvShows();
            if (tv.isNotEmpty) return tv;
          } catch (_) {}
          return await _tmdb.getAnimationMovies();
        case 'romance':
          return await _tmdb.getMoviesByCategory(categoryType: 'romance');
        default:
          return await _tmdb.getMoviesByCategory(categoryType: type);
      }
    } catch (_) {
      // Last resort — never throw out of the screen.
      try {
        return await _tmdb.getTrendingMovies();
      } catch (_) {
        return const [];
      }
    }
  }

  Future<void> _openDetail(Movie movie) async {
    HapticFeedback.selectionClick();
    final isTv = _isTvCategory || movie.mediaType == 'tv';
    // Single route — one system back / gesture pop returns here, not Home.
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DetailScreen(movie: movie, isTv: isTv),
      ),
    );
  }

  void _popOnce() {
    HapticFeedback.selectionClick();
    final nav = Navigator.of(context);
    if (nav.canPop()) {
      nav.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final pad = Adaptive.pagePadding(context);
    final cardW = Adaptive.cardWidth(context);
    final cols = MediaQuery.sizeOf(context).width >= 900
        ? 6
        : MediaQuery.sizeOf(context).width >= 700
            ? 5
            : MediaQuery.sizeOf(context).width >= 520
                ? 4
                : 3;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0A0A),
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          tooltip: 'Back',
          onPressed: _popOnce,
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
        ),
        title: Text(
          widget.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: FontService.instance.display(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: [
          if (_isTvCategory)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Center(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppDesignTokens.gold.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: AppDesignTokens.gold.withValues(alpha: 0.35),
                    ),
                  ),
                  child: const Text(
                    'Series',
                    style: TextStyle(
                      color: AppDesignTokens.gold,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      body: _loading && _movies.isEmpty
          ? const Center(
              child: CircularProgressIndicator(
                color: AppDesignTokens.gold,
                strokeWidth: 2.4,
              ),
            )
          : _hasError && _movies.isEmpty
              ? _ErrorState(onRetry: () => _loadPage(reset: true))
              : RefreshIndicator(
                  color: AppDesignTokens.gold,
                  backgroundColor: const Color(0xFF141414),
                  onRefresh: () => _loadPage(reset: true),
                  child: NotificationListener<ScrollNotification>(
                    onNotification: (n) {
                      if (n.metrics.pixels >=
                          n.metrics.maxScrollExtent - 420) {
                        _loadPage(reset: false);
                      }
                      return false;
                    },
                    child: CustomScrollView(
                      physics: const AlwaysScrollableScrollPhysics(
                        parent: BouncingScrollPhysics(),
                      ),
                      slivers: [
                        if (_movies.isEmpty)
                          const SliverFillRemaining(
                            hasScrollBody: false,
                            child: Center(
                              child: Text(
                                'Nothing here yet',
                                style: TextStyle(
                                  color: Colors.white54,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          )
                        else
                          SliverPadding(
                            padding: EdgeInsets.fromLTRB(
                              pad.left,
                              8,
                              pad.right,
                              28,
                            ),
                            sliver: SliverGrid(
                              gridDelegate:
                                  SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: cols,
                                crossAxisSpacing: 12,
                                mainAxisSpacing: 16,
                                childAspectRatio: 0.55,
                              ),
                              delegate: SliverChildBuilderDelegate(
                                (context, index) {
                                  final movie = _movies[index];
                                  return PosterCard(
                                    movie: movie,
                                    width: cardW,
                                    heroTagPrefix:
                                        'viewmore-${widget.categoryType}',
                                    showMetadata: true,
                                    isTv: _isTvCategory ||
                                        movie.mediaType == 'tv',
                                    onTap: () => _openDetail(movie),
                                  );
                                },
                                childCount: _movies.length,
                              ),
                            ),
                          ),
                        if (_loadingMore)
                          const SliverToBoxAdapter(
                            child: Padding(
                              padding: EdgeInsets.only(bottom: 28, top: 8),
                              child: Center(
                                child: SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    color: AppDesignTokens.gold,
                                    strokeWidth: 2.2,
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off_rounded, color: Colors.white38, size: 40),
            const SizedBox(height: 12),
            const Text(
              'Couldn’t load this list',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: onRetry,
              child: const Text(
                'Retry',
                style: TextStyle(
                  color: AppDesignTokens.gold,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
