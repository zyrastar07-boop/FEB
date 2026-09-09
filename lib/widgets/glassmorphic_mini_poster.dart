import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/font_service.dart';

import '../design/tokens.dart';

const _gold = AppDesignTokens.gold;

/// Toy Story–style poster: rounded art, title under image, gold "Added",
/// ★ rating + year pills. Optional side action dots.
class GlassmorphicMiniPoster extends StatelessWidget {
  final String imageUrl;
  final String title;
  final double? rating;
  final String? year;
  final String? badge;
  final bool showAdded;
  final bool showSideActions;
  final VoidCallback? onTap;
  final VoidCallback? onPlay;
  final VoidCallback? onBookmark;
  final VoidCallback? onWatch;
  final VoidCallback? onDownload;
  final double? width;
  final int memCacheWidth;
  final int memCacheHeight;

  const GlassmorphicMiniPoster({
    super.key,
    required this.imageUrl,
    required this.title,
    this.rating,
    this.year,
    this.badge,
    this.showAdded = false,
    this.showSideActions = false,
    this.onTap,
    this.onPlay,
    this.onBookmark,
    this.onWatch,
    this.onDownload,
    this.width,
    this.memCacheWidth = 320,
    this.memCacheHeight = 480,
  });

  String get _resolvedUrl {
    final u = imageUrl.trim();
    if (u.isEmpty || u.contains('null')) return '';
    if (u.startsWith('http')) return u;
    if (u.startsWith('/')) return 'https://image.tmdb.org/t/p/w500$u';
    return u;
  }

  @override
  Widget build(BuildContext context) {
    final url = _resolvedUrl;

    return RepaintBoundary(
      child: GestureDetector(
        onTap: onTap,
        child: SizedBox(
          width: width,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(18),
                        child: url.isNotEmpty
                            ? CachedNetworkImage(
                                imageUrl: url,
                                fit: BoxFit.cover,
                                alignment: Alignment.topCenter,
                                memCacheWidth: memCacheWidth,
                                memCacheHeight: memCacheHeight,
                                placeholder: (_, _) => _ph(),
                                errorWidget: (_, _, _) => _ph(),
                              )
                            : _ph(),
                      ),
                    ),
                    Positioned.fill(
                      child: IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.18),
                              width: 1.1,
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (badge != null && badge!.isNotEmpty)
                      Positioned(
                        top: 8,
                        left: 8,
                        child: Align(
                          alignment: Alignment.topLeft,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(999),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: _gold.withValues(alpha: 0.92),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                badge!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.black,
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    if (showSideActions)
                      Positioned(
                        top: 12,
                        right: 10,
                        child: Column(
                          children: [
                            _dot(Icons.play_arrow_rounded, onPlay ?? onTap),
                            const SizedBox(height: 8),
                            _dot(Icons.bookmark_border_rounded, onBookmark),
                            const SizedBox(height: 8),
                            _dot(Icons.remove_red_eye_outlined, onWatch),
                            const SizedBox(height: 8),
                            _dot(Icons.download_rounded, onDownload),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: FontService.instance.style(
                  color: Colors.white,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (showAdded) ...[
                const SizedBox(height: 2),
                const Text(
                  'Added',
                  style: TextStyle(
                    color: _gold,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                children: [
                  if (rating != null && rating! > 0)
                    _pill(
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.star_rounded,
                              color: _gold, size: 12),
                          const SizedBox(width: 3),
                          Text(
                            rating!.toStringAsFixed(1),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (year != null && year!.isNotEmpty) _pill(Text(year!)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _dot(IconData icon, VoidCallback? onPressed) {
    return GestureDetector(
      onTap: onPressed,
      child: ClipOval(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.black.withValues(alpha: 0.45),
              border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
            ),
            child: Icon(icon, color: Colors.white, size: 16),
          ),
        ),
      ),
    );
  }

  Widget _pill(Widget child) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        ),
        child: DefaultTextStyle(
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 11.5,
            fontWeight: FontWeight.w500,
          ),
          child: child,
        ),
      ),
    );
  }

  Widget _ph() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1E1E22), Color(0xFF0E0E12)],
        ),
      ),
      child: const Center(
        child: Icon(Icons.movie_rounded, color: Colors.white24, size: 36),
      ),
    );
  }
}