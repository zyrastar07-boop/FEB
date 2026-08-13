import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/movie.dart';
import '../services/user_library_service.dart';
import 'available_downloads_sheet.dart';
import 'pressable.dart';

class MovieCard extends StatelessWidget {
  final Movie movie;
  final bool isLarge;
  final VoidCallback? onTap;
  final bool showQuickActions;

  const MovieCard({
    super.key,
    required this.movie,
    this.isLarge = false,
    this.onTap,
    this.showQuickActions = true,
  });

  String get _heroTag => 'poster-${movie.mediaType}-${movie.id}';

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: isLarge ? double.infinity : 130,
        margin: isLarge ? EdgeInsets.zero : const EdgeInsets.only(right: 12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Hero(
                tag: _heroTag,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16.0),
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: CachedNetworkImage(
                          imageUrl: movie.posterUrl,
                          fit: BoxFit.cover,
                          memCacheWidth: 300,
                          memCacheHeight: 450,
                          placeholder: (context, url) => Container(
                            color: Colors.grey[900],
                            child: const Center(
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.amber,
                              ),
                            ),
                          ),
                          errorWidget: (context, url, error) => Container(
                            color: Colors.grey[800],
                            child: const Icon(Icons.broken_image,
                                color: Colors.white54),
                          ),
                        ),
                      ),
                      Positioned.fill(
                        child: Container(
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Colors.black87,
                                Colors.transparent,
                                Colors.black87
                              ],
                              begin: Alignment.bottomCenter,
                              end: Alignment.topCenter,
                              stops: [0.0, 0.5, 1.0],
                            ),
                          ),
                        ),
                      ),
                      if (showQuickActions)
                        Positioned(
                          top: 8,
                          right: 8,
                          child: ListenableBuilder(
                            listenable: UserLibraryService.instance,
                            builder: (context, _) {
                              final lib = UserLibraryService.instance;
                              final bookmarked = lib.isInWatchlistMovie(movie);
                              final watched = lib.isWatchedMovie(movie);
                              return Column(
                                children: [
                                  _actionChip(
                                    bookmarked
                                        ? Icons.bookmark_rounded
                                        : Icons.bookmark_border,
                                    bookmarked,
                                    () async {
                                      HapticFeedback.selectionClick();
                                      await lib.toggleWatchlist(movie);
                                    },
                                  ),
                                  const SizedBox(height: 6),
                                  _actionChip(
                                    watched
                                        ? Icons.visibility_rounded
                                        : Icons.visibility_outlined,
                                    watched,
                                    () async {
                                      HapticFeedback.selectionClick();
                                      await lib.toggleWatched(movie);
                                    },
                                  ),
                                  const SizedBox(height: 6),
                                  _actionChip(
                                    Icons.download_outlined,
                                    false,
                                    () {
                                      HapticFeedback.mediumImpact();
                                      AvailableDownloadsSheet.show(
                                        context,
                                        movieTitle: movie.title,
                                        tmdbId: movie.id.toString(),
                                        posterUrl: movie.posterUrl,
                                        mediaType: movie.mediaType,
                                      );
                                    },
                                  ),
                                ],
                              );
                            },
                          ),
                        ),
                      if (isLarge)
                        Positioned(
                          left: 12,
                          bottom: 12,
                          right: 12,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                movie.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  const Icon(Icons.star,
                                      color: Colors.amber, size: 14),
                                  const SizedBox(width: 4),
                                  Text(
                                    '${movie.voteAverage.toStringAsFixed(1)} • ${movie.releaseYear}',
                                    style: const TextStyle(
                                        color: Colors.white70, fontSize: 12),
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
            if (!isLarge) ...[
              const SizedBox(height: 6),
              Text(
                movie.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  const Icon(Icons.star, color: Colors.amber, size: 12),
                  const SizedBox(width: 2),
                  Text(
                    '${movie.voteAverage.toStringAsFixed(1)} • ${movie.releaseYear}',
                    style: const TextStyle(color: Colors.grey, fontSize: 11),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _actionChip(IconData icon, bool active, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: active
              ? const Color(0xFFFFB800).withValues(alpha: 0.25)
              : Colors.black.withValues(alpha: 0.5),
          shape: BoxShape.circle,
          border: Border.all(
            color: active
                ? const Color(0xFFFFB800).withValues(alpha: 0.7)
                : Colors.transparent,
          ),
        ),
        child: Icon(
          icon,
          color: active ? const Color(0xFFFFB800) : Colors.white,
          size: 14,
        ),
      ),
    );
  }
}
