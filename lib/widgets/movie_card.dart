import 'package:flutter/material.dart';
import '../models/movie.dart';
import 'poster_card.dart';

/// MovieCard — thin compatibility wrapper around [PosterCard].
/// Existing call sites continue to work; new code should use PosterCard directly.
class MovieCard extends StatelessWidget {
  const MovieCard({
    super.key,
    required this.movie,
    this.isLarge = false,
    this.onTap,
    this.showQuickActions = true,
    this.heroTagNamespace = 'default',
  });

  final Movie movie;
  final bool isLarge;
  final VoidCallback? onTap;
  final bool showQuickActions;
  final String heroTagNamespace;

  @override
  Widget build(BuildContext context) {
    final size = isLarge ? PosterCardSize.large : PosterCardSize.medium;

    return PosterCard(
      key: Key('movie_card_$heroTagNamespace-${movie.mediaType}-${movie.id}'),
      movie: movie,
      size: size,
      onTap: onTap,
      showQuickActions: showQuickActions,
      showMetadata: !isLarge,
      heroTagPrefix: 'poster-$heroTagNamespace',
    );
  }
}