import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/cast_member.dart';
import '../models/movie.dart';
import '../services/tmdb_details_service.dart';
import '../services/font_service.dart';
import 'detail_screen.dart';

const _gold = Color(0xFFFFB800);
const _bg = Color(0xFF0A0A0A);

class ActorDetailScreen extends StatefulWidget {
  final int actorId;

  const ActorDetailScreen({super.key, required this.actorId});

  @override
  State<ActorDetailScreen> createState() => _ActorDetailScreenState();
}

class _ActorDetailScreenState extends State<ActorDetailScreen>
    with TickerProviderStateMixin {
  final TmdbDetailsService _service = TmdbDetailsService();
  bool _isLoading = true;
  CastMember? _actor;
  List<Movie> _movies = [];

  late AnimationController _fadeCtrl;
  late AnimationController _slideCtrl;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _slideCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 750),
    );
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.06),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _slideCtrl, curve: Curves.easeOutCubic));
    _fetchData();
  }

  Future<void> _fetchData() async {
    try {
      final result = await _service.getActorDetails(widget.actorId);
      if (mounted) {
        setState(() {
          _actor = result['actor'] as CastMember?;
          _movies = (result['movies'] as List<Movie>?) ?? [];
          _isLoading = false;
        });
        _fadeCtrl.forward();
        _slideCtrl.forward();
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoading = false);
        _fadeCtrl.forward();
        _slideCtrl.forward();
      }
    }
  }

  void _openMovie(Movie movie) {
    HapticFeedback.lightImpact();
    Navigator.push(
      context,
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 380),
        pageBuilder: (_, _, _) => DetailScreen(movie: movie),
        transitionsBuilder: (_, animation, _, child) {
          return FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0.04, 0),
                end: Offset.zero,
              ).animate(CurvedAnimation(
                parent: animation,
                curve: Curves.easeOutCubic,
              )),
              child: child,
            ),
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    _slideCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(
                color: _gold,
                strokeWidth: 2.5,
              ),
            )
          : FadeTransition(
              opacity: _fadeAnim,
              child: CustomScrollView(
                physics: const BouncingScrollPhysics(),
                slivers: [
                  // Collapsing header
                  SliverAppBar(
                    expandedHeight: 360,
                    pinned: true,
                    backgroundColor: _bg,
                    leading: Padding(
                      padding: const EdgeInsets.all(8),
                      child: GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.black.withValues(alpha: 0.5),
                            border: Border.all(color: Colors.white24),
                          ),
                          child: const Icon(Icons.arrow_back_rounded,
                              color: Colors.white, size: 20),
                        ),
                      ),
                    ),
                    flexibleSpace: FlexibleSpaceBar(
                      background: _buildHeaderPhoto(),
                    ),
                  ),

                  // Content
                  SliverToBoxAdapter(
                    child: SlideTransition(
                      position: _slideAnim,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Name
                            Text(
                              _actor?.name ?? 'Unknown',
                              style: FontService.instance.display(
                                color: Colors.white,
                                fontSize: 28,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.2,
                                height: 1.15,
                              ),
                            ),
                            const SizedBox(height: 12),

                            // Chips
                            Wrap(
                              spacing: 8,
                              runSpacing: 6,
                              children: [
                                if (_actor?.birthday != null &&
                                    _actor!.birthday!.isNotEmpty)
                                  _chip(_actor!.birthday!),
                                _chip('ACTOR', gold: true),
                                if (_movies.isNotEmpty)
                                  _chip('${_movies.length} titles'),
                              ],
                            ),
                            const SizedBox(height: 20),

                            // Biography
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.05),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.08),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'BIOGRAPHY',
                                    style: FontService.instance.label(
                                      color: Colors.white38,
                                      fontSize: 11,
                                      letterSpacing: 1.0,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    (_actor?.biography != null &&
                                            _actor!.biography!.isNotEmpty)
                                        ? _actor!.biography!
                                        : 'No biography available.',
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 13.5,
                                      height: 1.55,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 28),

                            // Known For
                            Text(
                              'Known For',
                              style: FontService.instance.display(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 14),

                            if (_movies.isEmpty)
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 30),
                                child: Center(
                                  child: Text(
                                    'No titles found',
                                    style: FontService.instance.label(
                                      color: Colors.white38,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              )
                            else
                              ..._movies.asMap().entries.map((entry) {
                                final i = entry.key;
                                final movie = entry.value;
                                return TweenAnimationBuilder<double>(
                                  tween: Tween(begin: 0.0, end: 1.0),
                                  duration: Duration(
                                      milliseconds: 300 + (i % 8) * 45),
                                  curve: Curves.easeOutCubic,
                                  builder: (context, value, child) {
                                    return Opacity(
                                      opacity: value,
                                      child: Transform.translate(
                                        offset:
                                            Offset(0, 12 * (1 - value)),
                                        child: child,
                                      ),
                                    );
                                  },
                                  child: _movieTile(movie),
                                );
                              }),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildHeaderPhoto() {
    final hasPhoto = _actor?.profilePath != null;

    return Stack(
      fit: StackFit.expand,
      children: [
        if (hasPhoto)
          Image.network(
            'https://image.tmdb.org/t/p/w780${_actor!.profilePath}',
            fit: BoxFit.cover,
            alignment: const Alignment(0, -0.25),
            errorBuilder: (_, _, _) =>
                Container(color: const Color(0xFF1A1A1A)),
          )
        else
          Container(color: const Color(0xFF1A1A1A)),

        // Soft multi-stop gradient
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withValues(alpha: 0.35),
                Colors.transparent,
                Colors.transparent,
                _bg.withValues(alpha: 0.4),
                _bg.withValues(alpha: 0.85),
                _bg,
              ],
              stops: const [0.0, 0.2, 0.45, 0.65, 0.85, 1.0],
            ),
          ),
        ),
      ],
    );
  }

  Widget _movieTile(Movie movie) {
    return GestureDetector(
      onTap: () => _openMovie(movie),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.07),
          ),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                movie.posterUrl,
                width: 50,
                height: 74,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Container(
                  width: 50,
                  height: 74,
                  color: Colors.grey[850],
                  child: const Icon(Icons.broken_image,
                      color: Colors.white38, size: 18),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    movie.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: FontService.instance.style(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    movie.releaseDate.isNotEmpty
                        ? movie.releaseDate.split('-').first
                        : '',
                    style: FontService.instance.label(
                      color: Colors.white54,
                      fontSize: 11.5,
                    ),
                  ),
                  if (movie.voteAverage > 0) ...[
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        const Icon(Icons.star_rounded,
                            color: _gold, size: 13),
                        const SizedBox(width: 3),
                        Text(
                          movie.voteAverage.toStringAsFixed(1),
                          style: const TextStyle(
                            color: _gold,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: _gold,
              size: 22,
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(String label, {bool gold = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: gold
            ? _gold.withValues(alpha: 0.15)
            : Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: gold ? _gold.withValues(alpha: 0.5) : Colors.white24,
        ),
      ),
      child: Text(
        label,
        style: FontService.instance.label(
          color: gold ? _gold : Colors.white70,
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}