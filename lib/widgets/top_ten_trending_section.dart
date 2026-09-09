import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../design/tokens.dart';
import '../models/movie.dart';
import '../services/font_service.dart';
import '../widgets/striped_rank_number.dart';
import '../widgets/app_card.dart';
import '../widgets/app_chip.dart';
import '../utils/adaptive.dart';

enum TopTenMediaFilter { all, movie, tvShow, anime }
enum TopTenTimeframe { day, week, month }

class TopTenTrendingSection extends StatefulWidget {
  const TopTenTrendingSection({
    super.key,
    required this.trendingMovies,
    required this.tvShows,
    required this.animeMovies,
    required this.isTvMap,
    required this.onOpenDetail,
  });
  final List<Movie> trendingMovies;
  final List<Movie> tvShows;
  final List<Movie> animeMovies;
  final Map<int, bool> isTvMap;
  final void Function(Movie movie) onOpenDetail;
  @override
  State<TopTenTrendingSection> createState() => _TopTenTrendingSectionState();
}

class _TopTenTrendingSectionState extends State<TopTenTrendingSection> {
  TopTenMediaFilter _mediaFilter = TopTenMediaFilter.movie;
  TopTenTimeframe _timeframe = TopTenTimeframe.day;
  List<Movie> _items = const <Movie>[];
  int _sig = -1;

  static const _mediaLabels = <TopTenMediaFilter, String>{
    TopTenMediaFilter.all: 'All',
    TopTenMediaFilter.movie: 'Movie',
    TopTenMediaFilter.tvShow: 'TV Show',
    TopTenMediaFilter.anime: 'Anime',
  };
  static const _mediaIcons = <TopTenMediaFilter, IconData>{
    TopTenMediaFilter.all: Icons.grid_view_rounded,
    TopTenMediaFilter.movie: Icons.movie_rounded,
    TopTenMediaFilter.tvShow: Icons.tv_rounded,
    TopTenMediaFilter.anime: Icons.sentiment_satisfied_alt_rounded,
  };

  @override
  void initState() {
    super.initState();
    _syncItems(force: true);
  }

  @override
  void didUpdateWidget(covariant TopTenTrendingSection old) {
    super.didUpdateWidget(old);
    _syncItems();
  }

  // Cheap change detection: parent mutates lists in place, so identity
  // checks fail — use a length/head-id signature instead.
  int _signature() {
    final t = widget.trendingMovies, v = widget.tvShows, a = widget.animeMovies;
    return Object.hash(
      t.length, v.length, a.length,
      t.isEmpty ? 0 : t.first.id,
      v.isEmpty ? 0 : v.first.id,
      a.isEmpty ? 0 : a.first.id,
    );
  }

  void _syncItems({bool force = false}) {
    final s = _signature();
    if (!force && s == _sig) return;
    _sig = s;
    List<Movie> source;
    switch (_mediaFilter) {
      case TopTenMediaFilter.all:
        final seen = <int>{};
        final mixed = <Movie>[];
        for (final m in [
          ...widget.trendingMovies,
          ...widget.tvShows,
          ...widget.animeMovies,
        ]) {
          if (seen.add(m.id)) mixed.add(m);
          if (mixed.length >= 14) break;
        }
        source = mixed;
        break;
      case TopTenMediaFilter.movie:
        source = widget.trendingMovies
            .where((m) => m.mediaType != 'tv' && widget.isTvMap[m.id] != true)
            .toList();
        if (source.isEmpty) source = widget.trendingMovies;
        break;
      case TopTenMediaFilter.tvShow:
        source = widget.tvShows;
        break;
      case TopTenMediaFilter.anime:
        source = widget.animeMovies;
        break;
    }
    final list = List<Movie>.from(source);
    switch (_timeframe) {
      case TopTenTimeframe.day:
        list.sort((a, b) => b.voteAverage.compareTo(a.voteAverage));
        break;
      case TopTenTimeframe.week:
        break;
      case TopTenTimeframe.month:
        list.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
        break;
    }
    _items = list.take(10).toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    if (_items.isEmpty) return const SizedBox.shrink();
    return RepaintBoundary(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildMediaTypePills(),
          const SizedBox(height: 14),
          _buildTimeframeHeader(),
          const SizedBox(height: 12),
          _buildCardList(),
        ],
      ),
    );
  }

  Widget _buildMediaTypePills() {
    return Padding(
      padding: Adaptive.pagePadding(context),
      child: SizedBox(
        height: 48,
        child: Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            borderRadius: AppDesignTokens.radiusFull,
            color: Colors.white.withValues(alpha: 0.05),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.12),
              width: 1.2,
            ),
          ),
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 2),
            itemCount: TopTenMediaFilter.values.length,
            separatorBuilder: (_, _) => const SizedBox(width: 6),
            itemBuilder: (context, index) {
              final filter = TopTenMediaFilter.values[index];
              return AppChip(
                label: _mediaLabels[filter]!,
                icon: Icon(_mediaIcons[filter], size: 15),
                variant: AppChipVariant.secondary,
                selected: _mediaFilter == filter,
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() {
                    _mediaFilter = filter;
                    _syncItems(force: true);
                  });
                },
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildTimeframeHeader() {
    return Padding(
      padding: Adaptive.pagePadding(context),
      child: Row(
        children: [
          Expanded(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    'Trending',
                    style: FontService.instance.display(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right_rounded,
                    color: Colors.white54, size: 20),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.07),
              borderRadius: AppDesignTokens.radiusFull,
              border:
                  Border.all(color: Colors.white.withValues(alpha: 0.10)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: TopTenTimeframe.values.map((tf) {
                final label = switch (tf) {
                  TopTenTimeframe.day => 'Day',
                  TopTenTimeframe.week => 'Week',
                  TopTenTimeframe.month => 'Month',
                };
                return AppChip(
                  label: label,
                  variant: AppChipVariant.ghost,
                  selected: _timeframe == tf,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() {
                      _timeframe = tf;
                      _syncItems(force: true);
                    });
                  },
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCardList() {
    final cardWidth = Adaptive.isLandscape(context)
        ? 340.0
        : MediaQuery.of(context).size.width * 0.78;
    const cardHeight = 168.0;
    return SizedBox(
      height: cardHeight + 8,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        scrollCacheExtent: ScrollCacheExtent.pixels(500.0),
        addAutomaticKeepAlives: false,
        padding: Adaptive.pagePadding(context),
        itemCount: _items.length,
        itemBuilder: (context, index) {
          final movie = _items[index];
          return RepaintBoundary(
            key: ValueKey<int>(movie.id),
            child: Padding(
              padding: const EdgeInsets.only(right: 14),
              child: _TopTenCard(
                movie: movie,
                rank: index + 1,
                width: cardWidth,
                height: cardHeight,
                onTap: () => widget.onOpenDetail(movie),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _TopTenCard extends StatelessWidget {
  const _TopTenCard({
    required this.movie,
    required this.rank,
    required this.width,
    required this.height,
    required this.onTap,
  });
  final Movie movie;
  final int rank;
  final double width;
  final double height;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final imageUrl = movie.backdropUrl ?? movie.posterUrl;
    return AppCard(
      onTap: onTap,
      elevation: AppCardElevation.medium,
      border: true,
      borderRadius: AppDesignTokens.radiusXl,
      borderColor: Colors.white.withValues(alpha: 0.12),
      padding: const EdgeInsets.all(3),
      clipBehavior: Clip.antiAlias,
      semanticLabel: movie.title,
      child: SizedBox(
        width: width,
        height: height,
        child: ClipRRect(
          borderRadius: const BorderRadius.all(Radius.circular(19)),
          child: Stack(
            fit: StackFit.expand,
            children: [
              CachedNetworkImage(
                imageUrl: imageUrl,
                fit: BoxFit.cover,
                alignment: Alignment.center,
                memCacheWidth:
                    (width * MediaQuery.of(context).devicePixelRatio).round(),
                placeholder: (_, _) => Container(color: const Color(0xFF1A1A1A)),
                errorWidget: (_, _, _) => Container(
                  color: const Color(0xFF1A1A1A),
                  child: const Icon(Icons.movie_rounded,
                      color: Colors.white24, size: 40),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: height * 0.55,
                child: const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black54,
                        Colors.black87,
                      ],
                      stops: [0.0, 0.45, 1.0],
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 10,
                bottom: 6,
                child: StripedRankNumber(
                  rank: rank,
                  fontSize: rank >= 10 ? 64 : 74,
                ),
              ),
              Positioned(
                left: rank >= 10 ? 78 : 62,
                right: 12,
                bottom: 14,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      movie.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppDesignTokens.titleMedium().copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        const Icon(Icons.star_rounded,
                            color: AppDesignTokens.gold, size: 13),
                        const SizedBox(width: 3),
                        Text(
                          movie.voteAverage.toStringAsFixed(1),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '·  ${movie.releaseYear}',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.75),
                            fontSize: 12.5,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}