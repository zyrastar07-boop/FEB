import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/movie.dart';
import '../services/tmdb_service.dart';
import '../services/font_service.dart';
import 'detail_screen.dart';

const _gold = Color(0xFFFFB800);
const _bg = Color(0xFF0A0A0A);

class ViewMoreScreen extends StatefulWidget {
  final String title;
  final String? categoryType;
  final int? providerId;

  const ViewMoreScreen({
    super.key,
    required this.title,
    this.categoryType,
    this.providerId,
  });

  @override
  State<ViewMoreScreen> createState() => _ViewMoreScreenState();
}

class _ViewMoreScreenState extends State<ViewMoreScreen>
    with SingleTickerProviderStateMixin {
  final TmdbService _tmdbService = TmdbService();
  final ScrollController _scrollController = ScrollController();

  final List<Movie> _items = [];
  int _page = 1;
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;

  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _loadMovies();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 240 &&
        !_isLoadingMore &&
        _hasMore) {
      _loadMoreMovies();
    }
  }

  Future<void> _loadMovies() async {
    setState(() {
      _isLoading = true;
      _page = 1;
      _hasMore = true;
    });

    try {
      final category = widget.providerId != null
          ? 'provider'
          : (widget.categoryType ?? 'trending');
      final results = await _tmdbService.getMoviesByCategory(
        categoryType: category,
        page: 1,
        providerId: widget.providerId,
      );

      if (!mounted) return;
      setState(() {
        _items
          ..clear()
          ..addAll(results);
        _isLoading = false;
        if (results.isEmpty) _hasMore = false;
      });
      _fadeCtrl.forward(from: 0);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _hasMore = false;
      });
      _fadeCtrl.forward(from: 0);
    }
  }

  Future<void> _loadMoreMovies() async {
    if (_isLoadingMore || !_hasMore) return;

    setState(() => _isLoadingMore = true);

    try {
      final nextPage = _page + 1;
      final category = widget.providerId != null
          ? 'provider'
          : (widget.categoryType ?? 'trending');
      final results = await _tmdbService.getMoviesByCategory(
        categoryType: category,
        page: nextPage,
        providerId: widget.providerId,
      );

      if (!mounted) return;
      setState(() {
        _page = nextPage;
        _isLoadingMore = false;
        if (results.isEmpty) {
          _hasMore = false;
        } else {
          _items.addAll(results);
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoadingMore = false;
        _hasMore = false;
      });
    }
  }

  void _openDetail(Movie movie) {
    HapticFeedback.selectionClick();
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
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final crossAxisCount = screenWidth > 600 ? 4 : 3;

    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Column(
          children: [
            // Custom header
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 16, 12),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      Navigator.pop(context);
                    },
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withValues(alpha: 0.08),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.12),
                        ),
                      ),
                      child: const Icon(Icons.arrow_back_rounded,
                          color: Colors.white, size: 20),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      widget.title,
                      style: FontService.instance.display(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  if (!_isLoading && _items.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: _gold.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${_items.length}${_hasMore ? '+' : ''}',
                        style: FontService.instance.label(
                          color: _gold,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                ],
              ),
            ),

            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: _gold,
                        strokeWidth: 2.5,
                      ),
                    )
                  : _items.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.movie_filter_outlined,
                                  size: 48,
                                  color: Colors.white.withValues(alpha: 0.25)),
                              const SizedBox(height: 12),
                              Text(
                                'Nothing to show',
                                style: FontService.instance.display(
                                  color: Colors.white54,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        )
                      : FadeTransition(
                          opacity: _fadeAnim,
                          child: RefreshIndicator(
                            color: _gold,
                            backgroundColor: const Color(0xFF1E1E1E),
                            onRefresh: _loadMovies,
                            child: GridView.builder(
                              controller: _scrollController,
                              physics: const BouncingScrollPhysics(
                                parent: AlwaysScrollableScrollPhysics(),
                              ),
                              padding: const EdgeInsets.fromLTRB(14, 4, 14, 24),
                              gridDelegate:
                                  SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: crossAxisCount,
                                childAspectRatio: 0.62,
                                crossAxisSpacing: 12,
                                mainAxisSpacing: 14,
                              ),
                              itemCount:
                                  _items.length + (_hasMore ? 1 : 0),
                              itemBuilder: (context, index) {
                                if (index == _items.length) {
                                  return const Center(
                                    child: Padding(
                                      padding: EdgeInsets.all(16),
                                      child: SizedBox(
                                        width: 24,
                                        height: 24,
                                        child: CircularProgressIndicator(
                                          color: _gold,
                                          strokeWidth: 2.2,
                                        ),
                                      ),
                                    ),
                                  );
                                }

                                final movie = _items[index];
                                return TweenAnimationBuilder<double>(
                                  tween: Tween(begin: 0.0, end: 1.0),
                                  duration: Duration(
                                      milliseconds:
                                          280 + (index % 9) * 40),
                                  curve: Curves.easeOutCubic,
                                  builder: (context, value, child) {
                                    return Opacity(
                                      opacity: value,
                                      child: Transform.translate(
                                        offset:
                                            Offset(0, 16 * (1 - value)),
                                        child: child,
                                      ),
                                    );
                                  },
                                  child: GestureDetector(
                                    onTap: () => _openDetail(movie),
                                    child: _buildPosterCard(movie),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPosterCard(Movie movie) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.network(
                  movie.posterUrl,
                  fit: BoxFit.cover,
                  alignment: Alignment.topCenter,
                  errorBuilder: (_, _, _) => Container(
                    color: Colors.grey[900],
                    child: const Icon(Icons.movie_rounded,
                        color: Colors.white24),
                  ),
                ),
                Positioned(
                  left: 5,
                  bottom: 5,
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.7),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.star_rounded,
                                color: _gold, size: 10),
                            const SizedBox(width: 2),
                            Text(
                              movie.voteAverage.toStringAsFixed(1),
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 10),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.7),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          movie.releaseYear,
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 10),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 5),
        Text(
          movie.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: FontService.instance.style(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}