import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/movie.dart';
import '../services/tmdb_service.dart';
import '../services/tmdb_details_service.dart';
import '../services/font_service.dart';
import '../widgets/glassmorphic_mini_poster.dart';
import '../utils/adaptive.dart';
import 'detail_screen.dart';

import '../design/tokens.dart';

const _gold = AppDesignTokens.gold;
const _bg = AppDesignTokens.backgroundCanvas;

enum PersonCreditKind { actor, director }

/// Filmography by TMDB **person id** using existing worker-backed services.
class PersonCreditsScreen extends StatefulWidget {
  final int personId;
  final String name;
  final PersonCreditKind kind;

  const PersonCreditsScreen({
    super.key,
    required this.personId,
    required this.name,
    this.kind = PersonCreditKind.actor,
  });

  @override
  State<PersonCreditsScreen> createState() => _PersonCreditsScreenState();
}

class _PersonCreditsScreenState extends State<PersonCreditsScreen> {
  final _tmdb = TmdbService();
  final _details = TmdbDetailsService();
  List<Movie> _items = [];
  bool _loading = true;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = false;
    });
    try {
      List<Movie> results;
      if (widget.kind == PersonCreditKind.director) {
        results = await _tmdb.getMoviesByDirector(widget.personId);
      } else {
        final data = await _details.getActorDetails(widget.personId);
        results = (data['movies'] as List<Movie>?) ?? const [];
      }
      if (!mounted) return;
      setState(() {
        _items = results;
        _loading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = true;
        });
      }
    }
  }

  void _open(Movie m) {
    HapticFeedback.lightImpact();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DetailScreen(
          movie: m,
          isTv: m.mediaType == 'tv',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pad = Adaptive.pagePadding(context);
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        title: Text(
          widget.name,
          style: FontService.instance.display(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: _gold, strokeWidth: 2),
            )
          : _error
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.cloud_off_rounded,
                        size: 48,
                        color: Colors.white.withValues(alpha: 0.30),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Could not load credits',
                        style: TextStyle(color: Colors.white54, fontSize: 14),
                      ),
                      const SizedBox(height: 12),
                      TextButton.icon(
                        onPressed: _load,
                        icon: const Icon(Icons.refresh_rounded,
                            color: _gold, size: 18),
                        label: const Text(
                          'Retry',
                          style: TextStyle(color: _gold),
                        ),
                      ),
                    ],
                  ),
                )
              : _items.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.movie_filter_outlined,
                            size: 48,
                            color: Colors.white.withValues(alpha: 0.25),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'No credits available',
                            style: FontService.instance.style(
                              color: Colors.white54,
                              fontSize: 15,
                            ),
                          ),
                        ],
                      ),
                    )
                  : GridView.builder(
                      padding:
                          EdgeInsets.fromLTRB(pad.left, 8, pad.right, 28),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        mainAxisSpacing: 14,
                        crossAxisSpacing: 10,
                        childAspectRatio: 0.52,
                      ),
                      itemCount: _items.length,
                      itemBuilder: (context, i) {
                        final m = _items[i];
                        return GlassmorphicMiniPoster(
                          imageUrl: m.posterUrl,
                          title: m.title,
                          rating: m.voteAverage,
                          year: m.releaseYear,
                          onTap: () => _open(m),
                        );
                      },
                    ),
    );
  }
}