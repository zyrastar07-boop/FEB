// poster_card.dart
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../design/motion.dart';
import '../design/tokens.dart';
import '../models/movie.dart';
import '../utils/adaptive.dart';

enum PosterCardSize { small, medium, large }

class PosterCard extends StatelessWidget {
  const PosterCard({
    super.key,
    required this.movie,
    this.size = PosterCardSize.medium,
    this.heroTagPrefix = 'poster',
    this.onTap,
    this.onLongPress,
    this.onDownload,
    this.showQuickActions = false,
    this.showMetadata = false,
    this.width,
    this.isTv = false,
    this.releaseBadge,
  });

  final Movie movie;
  final PosterCardSize size;
  final String heroTagPrefix;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onDownload;
  final bool showQuickActions;
  final bool showMetadata;
  final double? width;
  final bool isTv;
  final String? releaseBadge;

  double _defaultWidth(BuildContext context) => switch (size) {
        PosterCardSize.small => 110,
        PosterCardSize.medium => Adaptive.cardWidth(context),
        PosterCardSize.large => Adaptive.cardWidth(context, large: true),
      };

  int _memWidth() => switch (size) {
        PosterCardSize.small => 220,
        PosterCardSize.medium => 340,
        PosterCardSize.large => 500,
      };

  @override
  Widget build(BuildContext context) {
    final w = width ?? _defaultWidth(context);
    final small = size == PosterCardSize.small;
    return RepaintBoundary(
      child: GestureDetector(
        onTap: onTap,
        onLongPress: onLongPress,
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          width: w,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Hero(
                tag: '$heroTagPrefix-${movie.mediaType}-${movie.id}',
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: AspectRatio(
                    aspectRatio: 2 / 3,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        CachedNetworkImage(
                          imageUrl: movie.posterUrl,
                          fit: BoxFit.cover,
                          memCacheWidth: _memWidth(),                           fadeInDuration: AppMotion.scaled(context, AppMotion.fast),

                          placeholder: (_, _) =>
                              Container(color: const Color(0xFF1A1A1A)),
                          errorWidget: (_, _, _) => Container(
                            color: const Color(0xFF1A1A1A),
                            child: const Icon(Icons.movie_rounded,
                                color: Colors.white24),
                          ),
                        ),
                        if (isTv || releaseBadge != null)
                          Positioned(
                            top: 8,
                            left: 8,
                            right: 8,
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Align(
                                  alignment: Alignment.topLeft,
                                  child: isTv
                                      ? _tag('TV',
                                          bg: Colors.black
                                              .withValues(alpha: 0.65),
                                          fg: Colors.white70)
                                      : const SizedBox.shrink(),
                                ),
                                Align(
                                  alignment: Alignment.topLeft,
                                  child: releaseBadge != null
                                      ? _tag(releaseBadge!,
                                          bg: AppDesignTokens.gold
                                              .withValues(alpha: 0.9),
                                          fg: Colors.black)
                                      : const SizedBox.shrink(),
                                ),
                              ],
                            ),
                          ),
                        if (showQuickActions)
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            child: Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Colors.transparent,
                                    Colors.black.withValues(alpha: 0.7),
                                  ],
                                ),
                              ),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 6),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  if (onDownload != null)
                                    _quickIcon(Icons.download_rounded,
                                        onDownload!),
                                  const SizedBox(width: 6),
                                  if (onTap != null)
                                    _quickIcon(Icons.play_arrow_rounded, onTap!),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                movie.title,
                maxLines: small ? 1 : 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: small ? 11 : 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (showMetadata) ...[
                const SizedBox(height: 3),
                Row(
                  children: [
                    const Icon(Icons.star_rounded,
                        color: AppDesignTokens.gold, size: 11),
                    const SizedBox(width: 3),
                    Text(
                      movie.voteAverage.toStringAsFixed(1),
                      style: const TextStyle(
                          color: Colors.white70, fontSize: 10.5),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      movie.releaseYear,
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.55),
                          fontSize: 10.5),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _tag(String label, {required Color bg, required Color fg}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
              color: fg, fontSize: 9.5, fontWeight: FontWeight.w800),
        ),
      ),
    );
  }

  Widget _quickIcon(IconData icon, VoidCallback onTap) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(999),
          child: Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.65),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Icon(icon, color: AppDesignTokens.gold, size: 16),
          ),
        ),
      ),
    );
  }
}
