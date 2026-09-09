// home_media_rail.dart
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../models/movie.dart';
import '../utils/adaptive.dart';
import 'poster_card.dart';

class HomeMediaRail extends StatelessWidget {
  const HomeMediaRail({
    super.key,
    required this.movies,
    required this.onOpen,
    this.categoryLabel,
    this.isReleased,
    this.formatReleaseDate,
    this.isTvMap,
    this.onLongPress,
  });

  final List<Movie> movies;
  final ValueChanged<Movie> onOpen;
  final String? categoryLabel;
  final bool Function(Movie)? isReleased;
  final String Function(String)? formatReleaseDate;
  final Map<int, bool>? isTvMap;
  final ValueChanged<Movie>? onLongPress;

  @override
  Widget build(BuildContext context) {
    if (movies.isEmpty) return const SizedBox.shrink();
    final pad = Adaptive.pagePadding(context);
    final cardW = Adaptive.cardWidth(context);
    const spacing = 12.0;
    return SizedBox(
      height: cardW * 1.5 + 58,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        scrollCacheExtent: ScrollCacheExtent.pixels(600.0),
        addAutomaticKeepAlives: false,
        itemExtent: cardW + spacing,
        padding: EdgeInsets.only(left: pad.left, right: pad.right),
        itemCount: movies.length,
        itemBuilder: (context, index) {
          final movie = movies[index];
          final released = isReleased?.call(movie) ?? true;
          final isTv =
              (isTvMap?[movie.id] == true) || movie.mediaType == 'tv';
          final badge = (!released && formatReleaseDate != null)
              ? 'Soon: ${formatReleaseDate!(movie.releaseDate)}'
              : null;
          return Padding(
            padding: const EdgeInsets.only(right: spacing),
            child: PosterCard(
              movie: movie,
              width: cardW,
              heroTagPrefix: 'rail-${categoryLabel ?? 'home'}',
              showMetadata: true,
              isTv: isTv,
              releaseBadge: badge,
              onTap: () => onOpen(movie),
              onLongPress:
                  onLongPress == null ? null : () => onLongPress!(movie),
            ),
          );
        },
      ),
    );
  }
}