import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/movie.dart';
import '../services/font_service.dart';
import '../widgets/app_button.dart';
import '../widgets/curated_collections_section.dart';
import '../design/tokens.dart';
import '../utils/adaptive.dart';

/// Full-screen developer-curated collections.
/// Fully responsive + Android TV / D-pad ready.
class DevPicksScreen extends StatelessWidget {
  final List<Movie> trending;
  final List<Movie> nowPlaying;
  final List<Movie> awards;
  final List<Movie> tvShows;
  final List<Movie> anime;
  final DateTime? fetchedAt;

  const DevPicksScreen({
    super.key,
    required this.trending,
    required this.nowPlaying,
    required this.awards,
    required this.tvShows,
    required this.anime,
    this.fetchedAt,
  });

  @override
  Widget build(BuildContext context) {
    final padding = Adaptive.pagePadding(context);

    return Scaffold(
      backgroundColor: AppDesignTokens.bg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(8, 8, padding.right, 0),
              child: Row(
                children: [
                  AppButton(
                    variant: AppButtonVariant.ghost,
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      Navigator.pop(context);
                    },
                    padding: EdgeInsets.zero,
                    borderRadius: AppDesignTokens.radiusFull,
                    semanticLabel: 'Back',
                    child: const Padding(
                      padding: EdgeInsets.all(8),
                      child: Icon(Icons.arrow_back_ios_new_rounded,
                          color: Colors.white70, size: 20),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      'From the Dev',
                      style: FontService.instance.display(
                        color: Colors.white,
                        fontSize: Adaptive.of(context) == ScreenType.mobile
                            ? 22
                            : 26,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                padding.left,
                2,
                padding.right,
                8,
              ),
              child: Text(
                'Hand-picked by the developer',
                style: FontService.instance.label(
                  color: Colors.white54,
                  fontSize: 12.5,
                ),
              ),
            ),
            const Divider(color: Colors.white10, height: 1),
            Expanded(
              child: FocusTraversalGroup(
                policy: OrderedTraversalPolicy(),
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.only(top: 12, bottom: 40),
                  child: CuratedCollectionsSection(
                    trending: trending,
                    nowPlaying: nowPlaying,
                    awards: awards,
                    tvShows: tvShows,
                    anime: anime,
                    fetchedAt: fetchedAt,
                    showSectionTitle: false,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
