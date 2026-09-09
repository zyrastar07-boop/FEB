import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../design/tokens.dart';
import '../models/movie.dart';
import '../services/continue_watching_service.dart';

/// Continue Watching card — landscape still + bottom progress + time-left pill.
/// Matches a clean streaming-app pattern: image first, title under the card,
/// dismiss on the image, no download chrome.
class ContinueWatchingCard extends StatelessWidget {
  final Movie movie;
  final String mediaType;
  final int position;
  final int duration;
  final int? season;
  final int? episode;
  final double cardWidth;
  final VoidCallback onTap;
  final VoidCallback? onRemoved;

  const ContinueWatchingCard({
    super.key,
    required this.movie,
    required this.mediaType,
    required this.position,
    required this.duration,
    this.season,
    this.episode,
    required this.cardWidth,
    required this.onTap,
    this.onRemoved,
  });

  double get _progress {
    if (duration <= 0) return 0;
    return (position / duration).clamp(0.0, 1.0);
  }

  /// Prefer a wide still; fall back to poster.
  String get _imageUrl {
    final backdrop = (movie.backdropPath ?? '').toString().trim();
    if (backdrop.isNotEmpty && backdrop != 'null') {
      if (backdrop.startsWith('http')) return backdrop;
      final path = backdrop.startsWith('/') ? backdrop : '/$backdrop';
      return 'https://image.tmdb.org/t/p/w780$path';
    }
    final u = movie.posterUrl.trim();
    if (u.isNotEmpty && !u.contains('null')) return u;
    final p = (movie.posterPath ?? '').toString().trim();
    if (p.isEmpty || p == 'null') return '';
    if (p.startsWith('http')) return p;
    if (p.startsWith('/')) return 'https://image.tmdb.org/t/p/w500$p';
    return p;
  }

  String get _timeLeftLabel {
    if (duration <= 0) return '';
    final remaining = (duration - position).clamp(0, duration);
    if (remaining <= 0) return 'Done';
    final minutes = (remaining / 60).ceil();
    if (minutes < 60) return '${minutes}m left';
    final hours = minutes ~/ 60;
    final mins = minutes % 60;
    if (mins == 0) return '${hours}h left';
    return '${hours}h ${mins}m left';
  }

  String? get _episodeChip {
    if (mediaType != 'tv' || season == null || episode == null) return null;
    return 'S${season.toString().padLeft(2, '0')}E${episode.toString().padLeft(2, '0')}';
  }

  Future<void> _remove() async {
    HapticFeedback.mediumImpact();
    await ContinueWatchingService.remove(movie.id, mediaType);
    onRemoved?.call();
  }

  @override
  Widget build(BuildContext context) {
    final imageH = cardWidth * 0.56; // ~16:9 landscape
    final url = _imageUrl;
    final left = _timeLeftLabel;
    final ep = _episodeChip;

    return SizedBox(
      width: cardWidth,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Artwork
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              onLongPress: onRemoved == null ? null : _remove,
              borderRadius: BorderRadius.circular(16),
              splashColor: AppDesignTokens.gold.withValues(alpha: 0.12),
              highlightColor: AppDesignTokens.gold.withValues(alpha: 0.06),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: SizedBox(
                  width: cardWidth,
                  height: imageH,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      url.isNotEmpty
                          ? CachedNetworkImage(
                              imageUrl: url,
                              fit: BoxFit.cover,
                              alignment: Alignment.center,
                              memCacheWidth: 640,
                              memCacheHeight: 360,
                              fadeInDuration:
                                  const Duration(milliseconds: 180),
                              placeholder: (_, _) => _placeholder(),
                              errorWidget: (_, _, _) => _placeholder(),
                            )
                          : _placeholder(),

                      // Soft bottom scrim so progress + pill stay readable
                      const Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        height: 48,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Color(0x00000000),
                                Color(0x99000000),
                              ],
                            ),
                          ),
                        ),
                      ),

                      // Dismiss
                      if (onRemoved != null)
                        Positioned(
                          top: 8,
                          right: 8,
                          child: Semantics(
                            button: true,
                            label: 'Remove from Continue Watching',
                            child: Material(
                              color: Colors.black.withValues(alpha: 0.55),
                              shape: const CircleBorder(),
                              child: InkWell(
                                customBorder: const CircleBorder(),
                                onTap: _remove,
                                child: const SizedBox(
                                  width: 28,
                                  height: 28,
                                  child: Icon(
                                    Icons.close_rounded,
                                    color: Colors.white,
                                    size: 16,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),

                      // Episode chip (top-left) when TV
                      if (ep != null)
                        Positioned(
                          top: 8,
                          left: 8,
                          child: _chip(
                            ep,
                            background: Colors.black.withValues(alpha: 0.7),
                          ),
                        ),

                      // Time left
                      if (left.isNotEmpty)
                        Positioned(
                          right: 8,
                          bottom: 12,
                          child: _chip(
                            left,
                            background: Colors.black.withValues(alpha: 0.72),
                          ),
                        ),

                      // Progress — full-bleed edge under the card, like the reference
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: SizedBox(
                          height: 3.5,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              const ColoredBox(color: Color(0x33FFFFFF)),
                              FractionallySizedBox(
                                alignment: Alignment.centerLeft,
                                widthFactor: _progress,
                                child: const ColoredBox(
                                  color: Color(0xFFE50914), // streaming red edge
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Title under the card
          const SizedBox(height: 10),
          Text(
            movie.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w600,
              height: 1.2,
              letterSpacing: -0.1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(String text, {required Color background}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            height: 1.1,
          ),
        ),
      ),
    );
  }

  Widget _placeholder() {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2A2A30), Color(0xFF121216)],
        ),
      ),
      child: Center(
        child: Icon(Icons.movie_rounded, color: Colors.white30, size: 36),
      ),
    );
  }
}
