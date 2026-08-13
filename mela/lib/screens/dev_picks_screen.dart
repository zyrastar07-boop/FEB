import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/movie.dart';
import '../services/font_service.dart';
import '../widgets/curated_collections_section.dart';

const _gold = Color(0xFFFFB800);
const _bg = Color(0xFF0A0A0A);

/// Full-screen developer-curated collections.
/// Opened from the home "From the Dev" pill — not embedded on Home.
class DevPicksScreen extends StatelessWidget {
  final List<Movie> trending;
  final List<Movie> nowPlaying;
  final List<Movie> awards;
  final List<Movie> tvShows;
  final List<Movie> anime;
  final List<Movie> asian;
  final DateTime? fetchedAt;

  const DevPicksScreen({
    super.key,
    required this.trending,
    required this.nowPlaying,
    required this.awards,
    required this.tvShows,
    required this.anime,
    required this.asian,
    this.fetchedAt,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      Navigator.pop(context);
                    },
                    icon: const Icon(Icons.arrow_back_ios_new_rounded,
                        color: Colors.white70, size: 20),
                  ),
                  Expanded(
                    child: Text(
                      'From the Dev',
                      style: FontService.instance.display(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: _gold.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: _gold.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Text(
                      'DEVELOPER SUGGESTS',
                      style: FontService.instance.label(
                        color: _gold,
                        fontSize: 10,
                        letterSpacing: 1.0,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Hand-picked collections the developer thinks you should watch next — awards, series, anime, and more.',
                    style: FontService.instance.label(
                      color: Colors.white54,
                      fontSize: 13.5,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(color: Colors.white10, height: 1),
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.only(top: 12, bottom: 40),
                child: CuratedCollectionsSection(
                  trending: trending,
                  nowPlaying: nowPlaying,
                  awards: awards,
                  tvShows: tvShows,
                  anime: anime,
                  asian: asian,
                  fetchedAt: fetchedAt,
                  // Section header is redundant on this screen
                  showSectionTitle: false,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}