import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../design/motion.dart';
import '../services/font_service.dart';
import '../widgets/focusable_scale.dart';
import '../utils/adaptive.dart';

import '../design/tokens.dart';

const _gold = AppDesignTokens.gold;

class StackedListCard extends StatelessWidget {
  final String title;
  final String description;
  final List<String> posterUrls;
  final DateTime? lastEdited;
  final int contentCount;
  final int watchedCount;
  final VoidCallback? onTap;
  final bool pinned;
  const StackedListCard({
    super.key,
    required this.title,
    this.description = '',
    this.posterUrls = const [],
    this.lastEdited,
    this.contentCount = 0,
    this.watchedCount = 0,
    this.onTap,
    this.pinned = false,
  });

  @override
  Widget build(BuildContext context) {
    final progress =
        contentCount > 0 ? (watchedCount / contentCount).clamp(0.0, 1.0) : 0.0;
    final percent = (progress * 100).round();
    final isMobile = Adaptive.of(context) == ScreenType.mobile;
    final pad = isMobile ? 16.0 : 20.0;
    return FocusableScale(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      scale: 1.02,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            margin: const EdgeInsets.only(bottom: 14),
            decoration: BoxDecoration(
              color: const Color(0xFF141414),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: pinned
                    ? _gold.withValues(alpha: 0.35)
                    : Colors.white.withValues(alpha: 0.07),
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RepaintBoundary(child: _PosterFan(urls: posterUrls)),
                Padding(
                  padding: EdgeInsets.fromLTRB(pad, 14, pad, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (pinned)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Row(
                            children: [
                              Icon(Icons.push_pin_rounded,
                                  size: 12, color: _gold.withValues(alpha: 0.9)),
                              const SizedBox(width: 4),
                              Text(
                                'PINNED',
                                style: FontService.instance.label(
                                  color: _gold,
                                  fontSize: 10,
                                  letterSpacing: 0.8,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: FontService.instance.display(
                          color: Colors.white,
                          fontSize: isMobile ? 17 : 19,
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
                        _metaLine(),
                        style: const TextStyle(color: Colors.white38, fontSize: 12),
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
                            '$watchedCount/$contentCount watched',
                            style:
                                const TextStyle(color: Colors.white54, fontSize: 11),
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
      ),
    );
  }

  String _metaLine() {
    final date = lastEdited != null
        ? 'Last Edited: ${_formatDate(lastEdited!)}'
        : 'Last Edited: —';
    return '$date · $contentCount Content${contentCount == 1 ? '' : 's'}';
  }

  String _formatDate(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[d.month - 1]} ${d.day}, ${d.year}';
  }
}

class _PosterFan extends StatelessWidget {
  final List<String> urls;
  const _PosterFan({required this.urls});

  @override
  Widget build(BuildContext context) {
    final display = urls.take(5).toList(growable: false);
    if (display.isEmpty) {
      return Container(
        height: 120,
        width: double.infinity,
        color: Colors.white.withValues(alpha: 0.04),
        child: const Center(
          child: Icon(Icons.collections_bookmark_outlined,
              color: Colors.white24, size: 36),
        ),
      );
    }
    final isMobile = Adaptive.of(context) == ScreenType.mobile;
    final fanHeight = isMobile ? 132.0 : 160.0;
    final offsetStep = isMobile ? 52.0 : 64.0;
    return SizedBox(
      height: fanHeight,
      width: double.infinity,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.white10, Colors.transparent],
                ),
              ),
            ),
          ),
          ...List.generate(display.length, (i) {
            final center = (display.length - 1) / 2.0;
            return Positioned(
              left: 0,
              right: 0,
              top: 16,
              child: Center(
                child: RepaintBoundary(
                  child: Transform.translate(
                    offset: Offset((i - center) * offsetStep, i * 2.0),
                    child: Transform.rotate(
                      angle: (i - center) * 0.08,
                      child: Transform.scale(
                        scale: 1.0 - (i * 0.02),
                        child: _PosterThumb(url: display[i]),
                      ),
                    ),
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _PosterThumb extends StatelessWidget {
  final String url;
  const _PosterThumb({required this.url});

  @override
  Widget build(BuildContext context) {
    final isMobile = Adaptive.of(context) == ScreenType.mobile;
    return Container(
      width: isMobile ? 72.0 : 88.0,
      height: isMobile ? 104.0 : 126.0,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.45),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      clipBehavior: Clip.antiAlias,
      child: CachedNetworkImage(
        imageUrl: url,
        fit: BoxFit.cover,
        memCacheWidth: 220,         fadeInDuration: AppMotion.scaled(context, AppMotion.fast),

        placeholder: (_, _) => Container(color: Colors.grey[850]),
        errorWidget: (_, _, _) => Container(
          color: Colors.grey[850],
          child: const Icon(Icons.movie, color: Colors.white24, size: 22),
        ),
      ),
    );
  }
}
