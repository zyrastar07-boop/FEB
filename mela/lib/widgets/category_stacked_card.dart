import 'package:flutter/material.dart';
import '../models/movie.dart';
import '../services/font_service.dart';
import '../services/user_library_service.dart';

const _gold = Color(0xFFFFB800);

/// Stacked poster collection card for curated home categories.
class CategoryStackedCard extends StatelessWidget {
  final String title;
  final String description;
  final List<Movie> movies;
  final DateTime? lastUpdated;
  final VoidCallback? onTap;

  const CategoryStackedCard({
    super.key,
    required this.title,
    required this.description,
    required this.movies,
    this.lastUpdated,
    this.onTap,
  });

  List<String> get _posters {
    final urls = <String>[];
    for (final m in movies) {
      final url = _posterUrl(m);
      if (url.isNotEmpty) urls.add(url);
    }
    return urls;
  }

  String _posterUrl(Movie m) {
    try {
      final dynamic d = m;
      if (d.posterUrl is String && (d.posterUrl as String).isNotEmpty) {
        return d.posterUrl as String;
      }
      final path = d.posterPath;
      if (path is String && path.isNotEmpty) {
        if (path.startsWith('http')) return path;
        return 'https://image.tmdb.org/t/p/w500$path';
      }
    } catch (_) {}
    return '';
  }

  int get _watchedCount {
    try {
      final lib = UserLibraryService.instance;
      return movies.where((m) {
        try {
          return (lib as dynamic).isWatchedMovie(m) == true;
        } catch (_) {
          return false;
        }
      }).length;
    } catch (_) {
      return 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = movies.length;
    final watched = _watchedCount.clamp(0, total);
    final progress = total > 0 ? watched / total : 0.0;
    final percent = (progress * 100).round();
    final updated = lastUpdated ?? DateTime.now();

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Container(
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            color: const Color(0xFF141414),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          clipBehavior: Clip.none,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Interactive Stacked Poster Carousel with layered card peaks
              _InteractiveStackedCarousel(urls: _posters),

              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: FontService.instance.display(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (description.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        description,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white60,
                          fontSize: 13,
                          height: 1.35,
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    Text(
                      'Last Updated: ${_fmt(updated)} · $total Title${total == 1 ? '' : 's'}',
                      style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: progress,
                              minHeight: 5,
                              backgroundColor: Colors.white12,
                              valueColor:
                                  const AlwaysStoppedAnimation<Color>(_gold),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          '$watched/$total watched',
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 11,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '$percent%',
                          style: const TextStyle(
                            color: _gold,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
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

  String _fmt(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[d.month - 1]} ${d.day}, ${d.year}';
  }
}

/// Interactive stack-layered card carousel showing full uncut posters + background stack tabs.
class _InteractiveStackedCarousel extends StatefulWidget {
  final List<String> urls;

  const _InteractiveStackedCarousel({required this.urls});

  @override
  State<_InteractiveStackedCarousel> createState() =>
      __InteractiveStackedCarouselState();
}

class __InteractiveStackedCarouselState
    extends State<_InteractiveStackedCarousel> {
  int _currentIndex = 0;
  double _dragOffset = 0.0;

  // Background accent colors for back cards (mimics reference illustration style)
  static const List<Color> _stackAccents = [
    Color(0xFFFF5252),
    Color(0xFF00E5FF),
    Color(0xFF7C4DFF),
    Color(0xFFFFD700),
  ];

  @override
  Widget build(BuildContext context) {
    if (widget.urls.isEmpty) {
      return Container(
        height: 240,
        width: double.infinity,
        color: Colors.white.withValues(alpha: 0.04),
        child: const Center(
          child: Icon(Icons.collections_outlined,
              color: Colors.white24, size: 36),
        ),
      );
    }

    final total = widget.urls.length;

    return Container(
      height: 320, // Increased height so the full vertical poster fits without cropping faces
      width: double.infinity,
      padding: const EdgeInsets.only(top: 24, left: 16, right: 16, bottom: 8),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: (details) {
          setState(() {
            _dragOffset += details.primaryDelta!;
          });
        },
        onHorizontalDragEnd: (details) {
          if (_dragOffset < -40) {
            setState(() {
              _currentIndex = (_currentIndex + 1) % total;
            });
          } else if (_dragOffset > 40) {
            setState(() {
              _currentIndex = (_currentIndex - 1 + total) % total;
            });
          }
          setState(() {
            _dragOffset = 0.0;
          });
        },
        child: Stack(
          alignment: Alignment.topCenter,
          clipBehavior: Clip.none,
          children: [
            // Render 3 stacked layers behind the main front poster (visible peaks at the top)
            for (int i = 3; i >= 1; i--) ...[
              _buildStackLayer(
                itemIndex: (_currentIndex + i) % total,
                stackLevel: i,
              ),
            ],
            // Render primary front poster card
            _buildStackLayer(
              itemIndex: _currentIndex,
              stackLevel: 0,
              dragTranslation: _dragOffset,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStackLayer({
    required int itemIndex,
    required int stackLevel,
    double dragTranslation = 0.0,
  }) {
    // Top positioning offset creates visible stacked steps at the top like the reference image
    final double topOffset = (3 - stackLevel) * 8.0; 
    final double horizontalMargin = (stackLevel * 10.0);
    final double opacity = (1.0 - (stackLevel * 0.12)).clamp(0.4, 1.0);
    final accentColor = _stackAccents[itemIndex % _stackAccents.length];

    return AnimatedPositioned(
      duration: dragTranslation == 0
          ? const Duration(milliseconds: 260)
          : Duration.zero,
      curve: Curves.easeOutCubic,
      top: topOffset,
      bottom: stackLevel * 6.0,
      left: horizontalMargin + (stackLevel == 0 ? dragTranslation : 0),
      right: horizontalMargin - (stackLevel == 0 ? dragTranslation : 0),
      child: Opacity(
        opacity: opacity,
        child: Container(
          decoration: BoxDecoration(
            color: stackLevel > 0 ? accentColor : const Color(0xFF1E1E1E),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.5),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
            border: Border.all(
              color: Colors.white.withValues(alpha: stackLevel == 0 ? 0.18 : 0.3),
              width: 1,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: stackLevel == 0
              ? Image.network(
                  widget.urls[itemIndex],
                  fit: BoxFit.cover,
                  alignment: Alignment.topCenter, // Keep actor faces framed in view
                  errorBuilder: (_, _, _) => Container(
                    color: const Color(0xFF222222),
                    child: const Center(
                      child: Icon(Icons.movie_outlined,
                          color: Colors.white24, size: 36),
                    ),
                  ),
                )
              : Stack(
                  children: [
                    // Preview image dimmed behind colored stack card banner
                    Positioned.fill(
                      child: Opacity(
                        opacity: 0.25,
                        child: Image.network(
                          widget.urls[itemIndex],
                          fit: BoxFit.cover,
                          alignment: Alignment.topCenter,
                          errorBuilder: (_, _, _) => const SizedBox(),
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