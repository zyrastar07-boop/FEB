import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/movie.dart';
import '../services/tmdb_service.dart';
import '../services/font_service.dart';
import 'detail_screen.dart';

const _gold = Color(0xFFFFB800);
const _bg = Color(0xFF0A0A0A);

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _searchController = TextEditingController();
  final TmdbService _tmdbService = TmdbService();
  final FocusNode _searchFocus = FocusNode();
  Timer? _debounce;

  List<Movie> _searchResults = [];
  List<Movie> _allResults = [];
  bool _isSearching = false;
  bool _isLoadingKeywords = true;
  bool _isLoadingTrending = true;
  List<String> _dynamicSearchKeywords = [];
  List<Movie> _trendingNow = [];
  List<Movie> _popularMovies = [];

  final List<String> _filterOptions = ['All', 'Movies', 'Series', 'Anime'];
  String _selectedFilter = 'All';

  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;

  final List<Map<String, dynamic>> _categories = [
    {'label': 'Trending', 'icon': Icons.local_fire_department_rounded},
    {'label': 'Top Rated', 'icon': Icons.star_rounded},
    {'label': 'New', 'icon': Icons.new_releases_rounded},
    {'label': 'Action', 'icon': Icons.flash_on_rounded},
    {'label': 'Sci-Fi', 'icon': Icons.rocket_launch_rounded},
    {'label': 'Drama', 'icon': Icons.theater_comedy_rounded},
    {'label': 'Comedy', 'icon': Icons.sentiment_very_satisfied_rounded},
    {'label': 'Horror', 'icon': Icons.nightlight_round},
  ];

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    );
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _fadeCtrl.forward();
    _loadDynamicKeywords();
    _loadTrendingAndPopular();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    _debounce?.cancel();
    _fadeCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadDynamicKeywords() async {
    setState(() => _isLoadingKeywords = true);
    try {
      final trending = await _tmdbService.getTrendingMovies();
      final titles = trending
          .map((m) => m.title)
          .where((t) => t.trim().isNotEmpty)
          .toList();
      titles.shuffle(Random());
      if (mounted) {
        setState(() {
          _dynamicSearchKeywords = titles.take(10).toList();
          _isLoadingKeywords = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _dynamicSearchKeywords = [
            'Blade Runner', 'Inception', 'Interstellar', 'Dune',
            'The Matrix', 'Arrival', 'Ex Machina', 'Ghost in the Shell',
          ];
          _isLoadingKeywords = false;
        });
      }
    }
  }

  Future<void> _loadTrendingAndPopular() async {
    setState(() => _isLoadingTrending = true);
    try {
      final trending = await _tmdbService.getTrendingMovies();
      if (mounted) {
        setState(() {
          _trendingNow = trending.take(12).toList();
          _popularMovies = trending.skip(4).take(12).toList();
          _isLoadingTrending = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingTrending = false);
    }
  }

  void _onSearchChanged(String query) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      if (query.trim().isNotEmpty) {
        _performSearch(query);
      } else {
        setState(() {
          _searchResults.clear();
          _allResults.clear();
          _isSearching = false;
        });
      }
    });
  }

  Future<void> _performSearch(String query) async {
    setState(() => _isSearching = true);
    try {
      final results = await _tmdbService.searchMovies(query);
      if (!mounted) return;
      setState(() {
        _allResults = results;
        _searchResults = _applyFilter(results);
        _isSearching = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _isSearching = false;
          _searchResults = [];
          _allResults = [];
        });
      }
    }
  }

  List<Movie> _applyFilter(List<Movie> source) {
    if (_selectedFilter == 'All') return List.from(source);
    if (_selectedFilter == 'Movies') {
      return source.where((m) {
        final t = m.title.toLowerCase();
        return !t.contains('season') && !t.contains('episode');
      }).toList();
    }
    if (_selectedFilter == 'Series') {
      return source.where((m) {
        final t = m.title.toLowerCase();
        return t.contains('season') || t.contains('episode') || t.contains('series') || true;
      }).toList();
    }
    return source.where((m) {
      final t = m.title.toLowerCase();
      return t.contains('anime') || t.contains('studio') || t.contains('ghibli') || true;
    }).toList();
  }

  void _onFilterChanged(String? value) {
    if (value == null) return;
    HapticFeedback.selectionClick();
    setState(() {
      _selectedFilter = value;
      if (_allResults.isNotEmpty) {
        _searchResults = _applyFilter(_allResults);
      }
    });
  }

  void _onKeywordTapped(String keyword) {
    HapticFeedback.selectionClick();
    _searchController.text = keyword;
    _searchFocus.requestFocus();
    _performSearch(keyword);
  }

  void _onCategoryTapped(String label) {
    HapticFeedback.selectionClick();
    _searchController.text = label;
    _performSearch(label);
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() {
      _searchResults.clear();
      _allResults.clear();
      _isSearching = false;
    });
  }


  void _openDetail(Movie movie) {
    HapticFeedback.lightImpact();
    Navigator.push(
      context,
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 340),
        pageBuilder: (_, _, _) => DetailScreen(movie: movie),
        transitionsBuilder: (_, animation, _, child) {
          return FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0.03, 0),
                end: Offset.zero,
              ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
              child: child,
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasQuery = _searchController.text.trim().isNotEmpty;

    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeAnim,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Text(
                      'Search',
                      style: FontService.instance.display(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Spacer(),
                    _buildFilterPill(),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () {
                        HapticFeedback.lightImpact();
                        Navigator.pop(context);
                      },
                      child: Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.08),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                        ),
                        child: const Icon(Icons.close_rounded, color: Colors.white, size: 16),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Container(
                  height: 46,
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1A1A).withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Row(
                    children: [
                      Icon(Icons.search_rounded, color: Colors.white.withValues(alpha: 0.4), size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: _searchController,
                          focusNode: _searchFocus,
                          onChanged: _onSearchChanged,
                          style: const TextStyle(color: Colors.white, fontSize: 15),
                          cursorColor: _gold,
                          decoration: InputDecoration(
                            hintText: 'Movies, series, anime…',
                            hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 14.5),
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                      ),
                      if (_searchController.text.isNotEmpty)
                        GestureDetector(
                          onTap: _clearSearch,
                          child: Icon(Icons.close_rounded, color: Colors.white.withValues(alpha: 0.5), size: 18),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: _isSearching
                    ? const Center(child: CircularProgressIndicator(color: _gold, strokeWidth: 2.5))
                    : hasQuery && _searchResults.isNotEmpty
                        ? _buildResultsGrid()
                        : hasQuery && _searchResults.isEmpty
                            ? _buildEmptyResults()
                            : _buildDiscovery(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFilterPill() {
    return Container(
      height: 32,
      padding: const EdgeInsets.only(left: 12, right: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _selectedFilter,
          dropdownColor: const Color(0xFF1E1E1E),
          borderRadius: BorderRadius.circular(12),
          icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white70, size: 16),
          style: FontService.instance.label(
            color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w600, letterSpacing: 0.2,
          ),
          items: _filterOptions.map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
          onChanged: _onFilterChanged,
        ),
      ),
    );
  }

  Widget _buildDiscovery() {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Browse by category',
              style: FontService.instance.label(color: Colors.white54, fontSize: 12, letterSpacing: 0.6)),
          const SizedBox(height: 10),
          SizedBox(
            height: 38,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _categories.length,
              itemBuilder: (context, index) {
                final cat = _categories[index];
                return TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.0, end: 1.0),
                  duration: Duration(milliseconds: 280 + index * 40),
                  curve: Curves.easeOutCubic,
                  builder: (context, value, child) {
                    return Opacity(
                      opacity: value,
                      child: Transform.translate(offset: Offset(12 * (1 - value), 0), child: child),
                    );
                  },
                  child: GestureDetector(
                    onTap: () => _onCategoryTapped(cat['label'] as String),
                    child: Container(
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.07),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                      ),
                      child: Row(
                        children: [
                          Icon(cat['icon'] as IconData, color: _gold, size: 15),
                          const SizedBox(width: 6),
                          Text(cat['label'] as String,
                              style: FontService.instance.label(
                                  color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w500, letterSpacing: 0.2)),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 22),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            decoration: BoxDecoration(
              color: const Color(0xFF161616).withValues(alpha: 0.95),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Everyone searching',
                    style: FontService.instance.label(
                        color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: 0.3)),
                const SizedBox(height: 12),
                if (_isLoadingKeywords)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: _gold, strokeWidth: 2))),
                  )
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _dynamicSearchKeywords.asMap().entries.map((e) {
                      final i = e.key;
                      final keyword = e.value;
                      return TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0.0, end: 1.0),
                        duration: Duration(milliseconds: 250 + i * 35),
                        curve: Curves.easeOutCubic,
                        builder: (context, value, child) {
                          return Opacity(opacity: value, child: Transform.scale(scale: 0.85 + 0.15 * value, child: child));
                        },
                        child: GestureDetector(
                          onTap: () => _onKeywordTapped(keyword),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.07),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: Colors.white.withValues(alpha: 0.09)),
                            ),
                            child: Text(keyword, style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w500)),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Text('Trending now', style: FontService.instance.display(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          if (_isLoadingTrending)
            const SizedBox(height: 160, child: Center(child: CircularProgressIndicator(color: _gold, strokeWidth: 2)))
          else
            SizedBox(
              height: 200,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                itemCount: _trendingNow.length,
                itemBuilder: (context, index) {
                  final movie = _trendingNow[index];
                  return TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0.0, end: 1.0),
                    duration: Duration(milliseconds: 300 + index * 40),
                    curve: Curves.easeOutCubic,
                    builder: (context, value, child) {
                      return Opacity(opacity: value, child: Transform.translate(offset: Offset(18 * (1 - value), 0), child: child));
                    },
                    child: GestureDetector(
                      onTap: () => _openDetail(movie),
                      child: Container(
                        width: 118,
                        margin: const EdgeInsets.only(right: 10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    Image.network(movie.posterUrl, fit: BoxFit.cover, alignment: Alignment.topCenter,
                                        errorBuilder: (_, _, _) => Container(color: Colors.grey[900])),
                                    Positioned(
                                      left: 5, bottom: 5,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                        decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.7), borderRadius: BorderRadius.circular(6)),
                                        child: Row(children: [
                                          const Icon(Icons.star_rounded, color: _gold, size: 10),
                                          const SizedBox(width: 2),
                                          Text(movie.voteAverage.toStringAsFixed(1), style: const TextStyle(color: Colors.white, fontSize: 10)),
                                        ]),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(movie.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                                style: FontService.instance.style(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          const SizedBox(height: 24),
          Text('Popular right now', style: FontService.instance.display(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3, childAspectRatio: 0.62, crossAxisSpacing: 10, mainAxisSpacing: 12,
            ),
            itemCount: _popularMovies.length.clamp(0, 9),
            itemBuilder: (context, index) {
              final movie = _popularMovies[index];
              return TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.0, end: 1.0),
                duration: Duration(milliseconds: 280 + (index % 6) * 45),
                curve: Curves.easeOutCubic,
                builder: (context, value, child) {
                  return Opacity(opacity: value, child: Transform.translate(offset: Offset(0, 14 * (1 - value)), child: child));
                },
                child: GestureDetector(
                  onTap: () => _openDetail(movie),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.network(movie.posterUrl, fit: BoxFit.cover, width: double.infinity, alignment: Alignment.topCenter,
                              errorBuilder: (_, _, _) => Container(color: Colors.grey[900])),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(movie.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: FontService.instance.style(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w500)),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyResults() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.search_off_rounded, color: Colors.white.withValues(alpha: 0.25), size: 48),
          const SizedBox(height: 12),
          Text('No results found', style: FontService.instance.display(color: Colors.white54, fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Text('Try a different title or category', style: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 13)),
        ],
      ),
    );
  }

  Widget _buildResultsGrid() {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 30),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2, childAspectRatio: 0.64, crossAxisSpacing: 12, mainAxisSpacing: 14,
      ),
      itemCount: _searchResults.length,
      itemBuilder: (context, index) {
        final movie = _searchResults[index];
        return TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.0, end: 1.0),
          duration: Duration(milliseconds: 260 + (index % 8) * 35),
          curve: Curves.easeOutCubic,
          builder: (context, value, child) {
            return Opacity(opacity: value, child: Transform.translate(offset: Offset(0, 16 * (1 - value)), child: child));
          },
          child: GestureDetector(
            onTap: () => _openDetail(movie),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.network(movie.posterUrl, fit: BoxFit.cover, alignment: Alignment.topCenter,
                            errorBuilder: (_, _, _) => Container(color: Colors.grey[900])),
                        Positioned(
                          left: 6, bottom: 6,
                          child: Row(children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.7), borderRadius: BorderRadius.circular(7)),
                              child: Row(children: [
                                const Icon(Icons.star_rounded, color: _gold, size: 11),
                                const SizedBox(width: 2),
                                Text(movie.voteAverage.toStringAsFixed(1),
                                    style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
                              ]),
                            ),
                            const SizedBox(width: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.7), borderRadius: BorderRadius.circular(7)),
                              child: Text(movie.releaseYear, style: const TextStyle(color: Colors.white70, fontSize: 11)),
                            ),
                          ]),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(movie.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: FontService.instance.style(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        );
      },
    );
  }
}