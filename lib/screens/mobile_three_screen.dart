import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../design/tokens.dart';
import '../models/movie.dart';
import '../services/tmdb_service.dart';
import '../widgets/morphing_search_dock.dart';
import 'detail_screen.dart';

/// Demo host for the Mobile 3 morphing-search-dock.
/// A scrollable list of curated content + the dock pinned at the bottom.
class MobileThreeScreen extends StatefulWidget {
  const MobileThreeScreen({super.key});

  @override
  State<MobileThreeScreen> createState() => _MobileThreeScreenState();
}

class _MobileThreeScreenState extends State<MobileThreeScreen> {
  final TmdbService _tmdb = TmdbService();
  final List<Movie> _curated = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadCurated();
  }

  Future<void> _loadCurated() async {
    try {
      final list = await _tmdb.getTrendingMovies();
      if (!mounted) return;
      setState(() {
        _curated
          ..clear()
          ..addAll(list.take(12));
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppDesignTokens.backgroundCanvas,
      extendBody: true,
      body: Stack(children: [
        Positioned.fill(
          child: SafeArea(
            bottom: false,
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppDesignTokens.gold,
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 200),
                    itemCount: _curated.length,
                    itemBuilder: (context, i) {
                      final m = _curated[i];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
child: _ResultTile(
                            movie: m,
                            onTap: () {
                              HapticFeedback.selectionClick();
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) =>
                                      DetailScreen(movie: m, isTv: false),
                                ),
                              );
                            },
                          ),
                      );
                    },
                  ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: MorphingSearchDock<Movie>(
            onQuery: (q) async {
              final list = await _tmdb.searchMovies(q);
              return list;
            },
            queryHint: 'Search movies, shows, people…',
            resultBuilder: (context, q, results) {
              return ListView.builder(
                padding: const EdgeInsets.symmetric(
                  vertical: 8,
                  horizontal: 8,
                ),
                itemCount: results.length,
                itemBuilder: (context, i) {
                  final m = results[i];
                  return _ResultTile(
                    movie: m,
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              DetailScreen(movie: m, isTv: false),
                        ),
                      );
                    },
                  );
                },
              );
            },
          ),
        ),
      ]),
    );
  }
}

class _ResultTile extends StatelessWidget {
  const _ResultTile({required this.movie, required this.onTap});
  final Movie movie;
  final VoidCallback onTap;

  String _poster() {
    final p = movie.posterPath;
    if (p == null || p.isEmpty) return '';
    if (p.startsWith('http')) return p;
    return 'https://image.tmdb.org/t/p/w154$p';
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: AppDesignTokens.radiusLg,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: AppDesignTokens.radiusMd,
                child: SizedBox(
                  width: 44,
                  height: 64,
                  child: _poster().isEmpty
                      ? Container(
                          color: AppDesignTokens.borderCork,
                          child: const Icon(
                            Icons.movie_outlined,
                            size: 18,
                            color: AppDesignTokens.gold,
                          ),
                        )
                      : CachedNetworkImage(
                          imageUrl: _poster(),
                          fit: BoxFit.cover,
                          errorWidget: (c, _, _) => Container(
                            color: AppDesignTokens.borderCork,
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      movie.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppDesignTokens.titleMedium(),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      [
                        if (movie.releaseDate.isNotEmpty)
                          movie.releaseDate.split('-').first,
                        if (movie.mediaType.isNotEmpty)
                          movie.mediaType.toUpperCase(),
                      ].join(' · '),
                      style: AppDesignTokens.labelSmall(
                        color: AppDesignTokens.textCream.withValues(alpha: 0.55),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.north_east_rounded,
                size: 16,
                color: AppDesignTokens.gold.withValues(alpha: 0.65),
              ),
            ],
          ),
        ),
      ),
    );
  }
}