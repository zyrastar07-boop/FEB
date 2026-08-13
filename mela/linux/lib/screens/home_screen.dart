import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/movie.dart';
import '../services/tmdb_service.dart';
import '../services/tmdb_details_service.dart';
import '../services/continue_watching_service.dart';
import '../services/font_service.dart';
import '../widgets/liquid_glass.dart';
import '../widgets/floating_nav_bar.dart';
import '../widgets/available_downloads_sheet.dart';
import 'detail_screen.dart';
import 'viewmore.dart';
import 'search_screen.dart';
import 'library_screen.dart';
import 'profile_screen.dart';

const _gold = Color(0xFFFFB800);
const _bg = Color(0xFF0A0A0A);

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  int _currentPage = 0;
  int _currentNavIndex = 0;

  bool _isLoading = true;
  bool _hasError = false;
  String? _errorMessage;

  List<Movie> _continueWatching = [];
  Map<int, Map<String, dynamic>> _continueProgress = {};

  final List<Movie> _trendingMovies = [];
  final List<Movie> _scifiMovies = [];
  final List<Movie> _romanticMovies = [];
  final List<Movie> _actionMovies = [];
  final List<Movie> _classicMovies = [];
  final List<Movie> _nowPlayingMovies = [];
  final List<Movie> _animeMovies = [];

  final Map<int, String> _heroLogos = {};

  final TmdbService _tmdbService = TmdbService();
  final TmdbDetailsService _detailsService = TmdbDetailsService();
  late AnimationController _fadeController;

  // Best of providers (dropdown style like reference)
  final List<Map<String, dynamic>> _providers = [
    {'name': 'Netflix', 'provider_id': 8},
    {'name': 'HBO Max', 'provider_id': 1899},
    {'name': 'Prime Video', 'provider_id': 119},
    {'name': 'Apple TV+', 'provider_id': 350},
    {'name': 'Disney+/Hulu', 'provider_id': 337},
    {'name': 'Paramount+', 'provider_id': 531},
    {'name': 'Peacock', 'provider_id': 386},
    {'name': 'Crunchyroll', 'provider_id': 283},
    {'name': 'MGM+', 'provider_id': 34},
    {'name': 'A24', 'provider_id': 410},
    {'name': 'Studio Ghibli', 'provider_id': 0},
  ];
  String _selectedProviderName = 'Best of';

  final List<String> _contentTypes = ['All', 'Movies', 'TV Shows', 'Anime', 'Asian'];
  String _selectedContentType = 'All';

  final List<String> _trendingTags = [
    'Trending',
    'New Releases',
    'Award Winners',
    'Cult Classics',
    'Must Watch',
  ];
  String _selectedTag = 'Trending';

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _loadContinueWatching();
    _fetchInitialData();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  Future<void> _loadContinueWatching() async {
    try {
      // Movies list from Hive box (typed Movie objects)
      final box = Hive.isBoxOpen('continue_watching')
          ? Hive.box<Movie>('continue_watching')
          : await Hive.openBox<Movie>('continue_watching');
      final movies = box.values.toList().reversed.toList();

      // Progress bars from ContinueWatchingService (position/duration)
      final progress = <int, Map<String, dynamic>>{};
      try {
        final entries = await ContinueWatchingService.getEntries();
        for (final e in entries) {
          final m = e['movie'];
          if (m is Map && m['id'] != null) {
            progress[m['id'] as int] = e;
          }
        }
      } catch (_) {}

      if (!mounted) return;
      setState(() {
        _continueWatching = movies;
        _continueProgress = progress;
      });
    } catch (e) {
      debugPrint('Error loading continue watching: $e');
    }
  }

  Future<void> _fetchInitialData() async {
    setState(() {
      _isLoading = true;
      _hasError = false;
      _errorMessage = null;
    });

    try {
      final results = await Future.wait([
        _tmdbService.getTrendingMovies(),
        _tmdbService.getSciFiMovies(),
        _tmdbService.getActionMovies(),
        _tmdbService.getRomanticMovies(),
        _tmdbService.getClassicMovies(),
        _tmdbService.getNowPlayingMovies(),
        _tmdbService.getAnimationMovies(),
      ]);

      if (!mounted) return;

      // Deduplicate across rows so the same title is not repeated
      final seen = <int>{};

      List<Movie> unique(List<Movie> src, {int take = 16}) {
        final out = <Movie>[];
        for (final m in src) {
          if (seen.add(m.id)) out.add(m);
          if (out.length >= take) break;
        }
        return out;
      }

      setState(() {
        _trendingMovies
          ..clear()
          ..addAll(unique(results[0], take: 18));
        _scifiMovies
          ..clear()
          ..addAll(unique(results[1], take: 14));
        _actionMovies
          ..clear()
          ..addAll(unique(results[2], take: 14));
        _romanticMovies
          ..clear()
          ..addAll(unique(results[3], take: 14));
        _classicMovies
          ..clear()
          ..addAll(unique(results[4], take: 14));
        _nowPlayingMovies
          ..clear()
          ..addAll(unique(results[5], take: 14));
        _animeMovies
          ..clear()
          ..addAll(unique(results[6], take: 14));
        _isLoading = false;
        _hasError = false;
      });

      _fadeController.forward(from: 0.0);
      _fetchHeroLogos(_trendingMovies.take(5).toList());
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = error.toString();
        _isLoading = false;
        _hasError = true;
      });
    }
  }

  Future<void> _fetchHeroLogos(List<Movie> movies) async {
    for (final movie in movies) {
      try {
        final logo = await _detailsService.getMovieLogo(movie.id);
        if (logo != null && mounted) {
          setState(() => _heroLogos[movie.id] = logo);
        }
      } catch (_) {}
    }
  }

  void _onProviderSelected(Map<String, dynamic> provider) {
    HapticFeedback.selectionClick();
    setState(() {
      _selectedProviderName = provider['name'] as String;
    });
    final id = provider['provider_id'] as int;
    if (id == 0) {
      // Studio Ghibli – open animation category
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ViewMoreScreen(
            title: provider['name'] as String,
            categoryType: 'animation',
          ),
        ),
      );
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ViewMoreScreen(
          title: provider['name'] as String,
          providerId: id,
        ),
      ),
    );
  }

  Future<void> _openDetail(Movie movie) async {
    try {
      final box = Hive.isBoxOpen('continue_watching')
          ? Hive.box<Movie>('continue_watching')
          : await Hive.openBox<Movie>('continue_watching');
      await box.put(movie.id, movie);
    } catch (e) {
      debugPrint('Error saving to continue watching: $e');
    }

    if (!mounted) return;
    Navigator.push(
      context,
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 380),
        pageBuilder: (_, _, _) => DetailScreen(movie: movie),
        transitionsBuilder: (_, animation, _, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    ).then((_) => _loadContinueWatching());
  }

  void _onNavTapped(int index) {
    HapticFeedback.selectionClick();
    setState(() => _currentNavIndex = index);
    if (index == 0) return;

    Widget screen;
    if (index == 1) {
      screen = const SearchScreen();
    } else if (index == 2) {
      screen = const LibraryScreen();
    } else {
      screen = const ProfileScreen();
    }

    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => screen),
    ).then((_) {
      if (!mounted) return;
      setState(() => _currentNavIndex = 0);
      _loadContinueWatching();
    });
  }

  bool _isReleased(Movie m) {
    if (m.releaseDate.isEmpty) return true;
    try {
      final d = DateTime.parse(m.releaseDate);
      return !d.isAfter(DateTime.now());
    } catch (_) {
      return true;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      backgroundColor: _bg,
      body: RefreshIndicator(
        color: _gold,
        backgroundColor: const Color(0xFF1E1E1E),
        onRefresh: () async {
          await _loadContinueWatching();
          await _fetchInitialData();
        },
        child: _hasError
            ? _buildOfflineState()
            : SingleChildScrollView(
                physics: const BouncingScrollPhysics(
                  parent: AlwaysScrollableScrollPhysics(),
                ),
                child: _isLoading
                    ? _buildSkeletonLoadingState()
                    : _buildLoadedContent(),
              ),
      ),
      bottomNavigationBar: FloatingNavBar(
        currentIndex: _currentNavIndex,
        onTap: _onNavTapped,
      ),
    );
  }

  // ── Offline / error ───────────────────────────────────────────────────
  Widget _buildOfflineState() {
    return SafeArea(
      child: Column(
        children: [
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Text(
                  'Phono',
                  style: FontService.instance.display(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  'Film',
                  style: FontService.instance.display(
                    color: _gold,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _buildContentTypeChips(),
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      "Couldn't reach PhonoFilm.",
                      textAlign: TextAlign.center,
                      style: FontService.instance.display(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Check your connection and try again.',
                      textAlign: TextAlign.center,
                      style: FontService.instance.label(
                        color: Colors.white54,
                        fontSize: 13.5,
                      ),
                    ),
                    const SizedBox(height: 22),
                    GestureDetector(
                      onTap: () {
                        HapticFeedback.mediumImpact();
                        _fetchInitialData();
                      },
                      child: Container(
                        width: double.infinity,
                        height: 48,
                        decoration: BoxDecoration(
                          color: _gold,
                          borderRadius: BorderRadius.circular(24),
                        ),
                        alignment: Alignment.center,
                        child: const Text(
                          'Retry',
                          style: TextStyle(
                            color: Colors.black,
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadedContent() {
    return FadeTransition(
      opacity: _fadeController,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeroHeader(context),
          const SizedBox(height: 14),
          _buildContentTypeChips(),
          const SizedBox(height: 14),
          _buildBestOfRow(),
          const SizedBox(height: 14),
          _buildTrendingTags(),
          const SizedBox(height: 18),

          if (_continueWatching.isNotEmpty) ...[
            _buildSectionHeader('Continue Watching', null),
            const SizedBox(height: 12),
            _buildContinueWatchingList(),
            const SizedBox(height: 24),
          ],

          // Featured row driven by Trending / New Releases / Award tags
          _buildSectionHeader(_featuredTitle, _featuredCategory),
          const SizedBox(height: 12),
          _buildMovieList(_featuredMovies, isLarge: true),
          const SizedBox(height: 24),

          // Only show other rows when not already featured
          if (_selectedTag != 'New Releases') ...[
            _buildSectionHeader('New Releases', 'now_playing'),
            const SizedBox(height: 12),
            _buildMovieList(_nowPlayingMovies, isLarge: false),
            const SizedBox(height: 24),
          ],

          if (_selectedTag != 'Cult Classics' &&
              _selectedTag != 'Award Winners') ...[
            _buildSectionHeader('Classic Films', 'classics'),
            const SizedBox(height: 12),
            _buildMovieList(_classicMovies, isLarge: false),
            const SizedBox(height: 24),
          ],

          _buildSectionHeader('Action Packed', 'action'),
          const SizedBox(height: 12),
          _buildMovieList(_actionMovies, isLarge: false),
          const SizedBox(height: 24),

          _buildSectionHeader('Science Fiction', 'scifi'),
          const SizedBox(height: 12),
          _buildMovieList(_scifiMovies, isLarge: false),
          const SizedBox(height: 24),

          _buildSectionHeader('Anime & Animation', 'anime'),
          const SizedBox(height: 12),
          _buildMovieList(_animeMovies, isLarge: false),
          const SizedBox(height: 24),

          _buildSectionHeader('Romantic Escapes', 'romance'),
          const SizedBox(height: 12),
          _buildMovieList(_romanticMovies, isLarge: false),
          const SizedBox(height: 110),
        ],
      ),
    );
  }

  Widget _buildSkeletonLoadingState() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Tall hero skeleton
        Container(
          height: MediaQuery.of(context).size.height * 0.72,
          color: const Color(0xFF121212),
          child: const Center(
            child: CircularProgressIndicator(color: _gold, strokeWidth: 2.5),
          ),
        ),
        const SizedBox(height: 16),
        // Chip skeletons
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: List.generate(
              4,
              (i) => Container(
                margin: const EdgeInsets.only(right: 8),
                width: 72,
                height: 32,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 24),
        ...List.generate(
          3,
          (_) => Padding(
            padding: const EdgeInsets.only(bottom: 20, left: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 120,
                  height: 16,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 180,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: 4,
                    itemBuilder: (_, _) => Container(
                      width: 120,
                      margin: const EdgeInsets.only(right: 12),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ── Hero – taller, full poster/backdrop ───────────────────────────────
  Widget _buildHeroHeader(BuildContext context) {
    final heroList = _trendingMovies.take(5).toList();
    if (heroList.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      // Taller hero so the poster/backdrop is fully visible
      height: MediaQuery.of(context).size.height * 0.72,
      child: PageView.builder(
        itemCount: heroList.length,
        onPageChanged: (index) => setState(() => _currentPage = index),
        itemBuilder: (context, index) {
          final movie = heroList[index];
          final logoUrl = _heroLogos[movie.id];
          final released = _isReleased(movie);

          return GestureDetector(
            onTap: () => _openDetail(movie),
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Prefer backdrop; fall back to poster – top aligned so face isn't cut
                Image.network(
                  movie.backdropUrl ?? movie.posterUrl,
                  fit: BoxFit.cover,
                  alignment: Alignment.topCenter,
                  errorBuilder: (_, _, _) =>
                      Container(color: Colors.grey[900]),
                ),
                Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.transparent,
                        Colors.black38,
                        Color(0xFF0A0A0A),
                      ],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      stops: [0.30, 0.60, 1.0],
                    ),
                  ),
                ),
                Positioned(
                  left: 20,
                  right: 20,
                  bottom: 28,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        height: 78,
                        child: logoUrl != null
                            ? Image.network(
                                logoUrl,
                                fit: BoxFit.contain,
                                alignment: Alignment.center,
                                errorBuilder: (_, _, _) =>
                                    _heroTitle(movie.title),
                              )
                            : _heroTitle(movie.title),
                      ),
                      const SizedBox(height: 8),
                      // Rating + year pills
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _pill(
                            '★ ${movie.voteAverage.toStringAsFixed(1)}',
                            gold: true,
                          ),
                          const SizedBox(width: 8),
                          _pill(movie.releaseYear),
                          if (!released) ...[
                            const SizedBox(width: 8),
                            _pill('Coming Soon'),
                          ],
                        ],
                      ),
                      const SizedBox(height: 14),
                      LiquidGlassContainer(
                        borderRadius: 28,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 32,
                          vertical: 11,
                        ),
                        backgroundColor: _gold.withValues(alpha: 0.18),
                        borderColor: _gold,
                        child: Text(
                          'View Details',
                          style: FontService.instance.style(
                            color: _gold,
                            fontWeight: FontWeight.bold,
                            fontSize: 13.5,
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(
                          heroList.length,
                          (idx) => AnimatedContainer(
                            duration: const Duration(milliseconds: 280),
                            margin: const EdgeInsets.symmetric(horizontal: 3),
                            height: 5,
                            width: _currentPage == idx ? 20 : 5,
                            decoration: BoxDecoration(
                              color: _currentPage == idx
                                  ? _gold
                                  : Colors.white30,
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _pill(String text, {bool gold = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: gold
            ? _gold.withValues(alpha: 0.18)
            : Colors.white.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: gold
              ? _gold.withValues(alpha: 0.5)
              : Colors.white.withValues(alpha: 0.14),
        ),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: gold ? _gold : Colors.white70,
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _heroTitle(String title) {
    return Text(
      title.toUpperCase(),
      textAlign: TextAlign.center,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: FontService.instance.display(
        color: Colors.white,
        fontSize: 26,
        fontWeight: FontWeight.w900,
        letterSpacing: 1.1,
      ),
    );
  }

  // ── Content type chips ────────────────────────────────────────────────
  Widget _buildContentTypeChips() {
    return SizedBox(
      height: 36,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: _contentTypes.length,
        itemBuilder: (context, index) {
          final type = _contentTypes[index];
          final selected = _selectedContentType == type;
          return GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() => _selectedContentType = type);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.only(right: 8),
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: selected ? _gold : Colors.white.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: selected
                      ? _gold
                      : Colors.white.withValues(alpha: 0.12),
                ),
              ),
              child: Text(
                type,
                style: FontService.instance.label(
                  color: selected ? Colors.black : Colors.white70,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.3,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ── Best of dropdown – real system menu so it sits on top & is tappable ─
  Widget _buildBestOfRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          Text(
            'Best of',
            style: FontService.instance.label(
              color: Colors.white54,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(width: 6),
          const Icon(Icons.chevron_right_rounded,
              color: Colors.white38, size: 16),
          const SizedBox(width: 8),
          // PopupMenuButton renders above all content and is fully clickable
          PopupMenuButton<Map<String, dynamic>>(
            onSelected: _onProviderSelected,
            color: const Color(0xFF1A1A1A),
            elevation: 12,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
            ),
            offset: const Offset(0, 40),
            itemBuilder: (context) {
              return _providers.map((p) {
                final name = p['name'] as String;
                final selected = _selectedProviderName == name;
                return PopupMenuItem<Map<String, dynamic>>(
                  value: p,
                  child: Text(
                    name,
                    style: TextStyle(
                      color: selected ? _gold : Colors.white,
                      fontSize: 13.5,
                      fontWeight:
                          selected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                );
              }).toList();
            },
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.12),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _selectedProviderName,
                    style: FontService.instance.label(
                      color: Colors.white,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Icon(
                    Icons.keyboard_arrow_down_rounded,
                    color: Colors.white70,
                    size: 16,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Movies shown in the featured row under the tags (changes with tag)
  List<Movie> get _featuredMovies {
    switch (_selectedTag) {
      case 'New Releases':
        return _nowPlayingMovies.isNotEmpty
            ? _nowPlayingMovies
            : _trendingMovies;
      case 'Award Winners':
      case 'Cult Classics':
        return _classicMovies.isNotEmpty ? _classicMovies : _trendingMovies;
      case 'Must Watch':
        return _actionMovies.isNotEmpty ? _actionMovies : _trendingMovies;
      case 'Trending':
      default:
        return _trendingMovies;
    }
  }

  String get _featuredTitle {
    switch (_selectedTag) {
      case 'New Releases':
        return 'New Releases';
      case 'Award Winners':
        return 'Award Winners';
      case 'Cult Classics':
        return 'Cult Classics';
      case 'Must Watch':
        return 'Must Watch';
      default:
        return 'Trending Now';
    }
  }

  String? get _featuredCategory {
    switch (_selectedTag) {
      case 'New Releases':
        return 'now_playing';
      case 'Award Winners':
      case 'Cult Classics':
        return 'classics';
      case 'Must Watch':
        return 'action';
      default:
        return 'trending';
    }
  }

  // ── Trending tags – functional filters ────────────────────────────────
  Widget _buildTrendingTags() {
    return SizedBox(
      height: 34,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: _trendingTags.length,
        itemBuilder: (context, index) {
          final tag = _trendingTags[index];
          final selected = _selectedTag == tag;
          return GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() => _selectedTag = tag);
            },
            child: Container(
              margin: const EdgeInsets.only(right: 8),
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: selected
                    ? _gold.withValues(alpha: 0.18)
                    : Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: selected
                      ? _gold.withValues(alpha: 0.6)
                      : Colors.white.withValues(alpha: 0.08),
                ),
              ),
              child: Text(
                tag,
                style: FontService.instance.label(
                  color: selected ? _gold : Colors.white60,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.3,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ── Continue watching with progress ───────────────────────────────────
  Widget _buildContinueWatchingList() {
    return SizedBox(
      height: 230,
      child: ListView.builder(
        physics: const BouncingScrollPhysics(),
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: _continueWatching.length,
        itemBuilder: (context, index) {
          final movie = _continueWatching[index];
          final prog = _continueProgress[movie.id];
          double ratio = 0;
          if (prog != null) {
            final pos = (prog['position'] as num?)?.toDouble() ?? 0;
            final dur = (prog['duration'] as num?)?.toDouble() ?? 0;
            if (dur > 0) ratio = (pos / dur).clamp(0.0, 1.0);
          }

          return GestureDetector(
            onTap: () => _openDetail(movie),
            child: Container(
              width: 140,
              margin: const EdgeInsets.only(right: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.network(
                            movie.posterUrl,
                            fit: BoxFit.cover,
                            alignment: Alignment.topCenter,
                            errorBuilder: (_, _, _) =>
                                Container(color: Colors.grey[900]),
                          ),
                          // Progress bar
                          if (ratio > 0)
                            Positioned(
                              left: 0,
                              right: 0,
                              bottom: 0,
                              child: LinearProgressIndicator(
                                value: ratio,
                                minHeight: 3.5,
                                backgroundColor:
                                    Colors.white.withValues(alpha: 0.15),
                                color: _gold,
                              ),
                            ),
                          Positioned(
                            top: 6,
                            right: 6,
                            child: GestureDetector(
                              onTap: () {
                                HapticFeedback.mediumImpact();
                                AvailableDownloadsSheet.show(
                                  context,
                                  movieTitle: movie.title,
                                  tmdbId: movie.id.toString(),
                                  posterUrl: movie.posterUrl,
                                );
                              },
                              child: Container(
                                width: 28,
                                height: 28,
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.65),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: _gold.withValues(alpha: 0.7),
                                  ),
                                ),
                                child: const Icon(
                                  Icons.download_rounded,
                                  color: _gold,
                                  size: 15,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  // Title in pill shape
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      movie.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: FontService.instance.style(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ── Movie lists – wider posters ───────────────────────────────────────
  Widget _buildMovieList(List<Movie> movies, {required bool isLarge}) {
    if (movies.isEmpty) {
      return const SizedBox(
        height: 100,
        child: Center(
          child: Text(
            'Nothing found for this category.',
            style: TextStyle(color: Colors.white54),
          ),
        ),
      );
    }

    final height = isLarge ? 270.0 : 230.0;
    final cardWidth = isLarge ? 160.0 : 140.0;

    return SizedBox(
      height: height,
      child: ListView.builder(
        physics: const BouncingScrollPhysics(),
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: movies.length,
        itemBuilder: (context, index) {
          final movie = movies[index];
          final released = _isReleased(movie);

          return GestureDetector(
            onTap: () => _openDetail(movie),
            child: Container(
              width: cardWidth,
              margin: const EdgeInsets.only(right: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
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
                            left: 0,
                            right: 0,
                            bottom: 0,
                            child: Container(
                              height: 48,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Colors.transparent,
                                    Colors.black.withValues(alpha: 0.7),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          // Rating + year
                          Positioned(
                            left: 6,
                            bottom: 6,
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color:
                                        Colors.black.withValues(alpha: 0.65),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.star_rounded,
                                          color: _gold, size: 11),
                                      const SizedBox(width: 2),
                                      Text(
                                        movie.voteAverage.toStringAsFixed(1),
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 10,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color:
                                        Colors.black.withValues(alpha: 0.65),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    movie.releaseYear,
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 10,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // Coming soon badge instead of play for unreleased
                          if (!released)
                            Positioned(
                              top: 6,
                              left: 6,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 7, vertical: 3),
                                decoration: BoxDecoration(
                                  color: _gold.withValues(alpha: 0.9),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Text(
                                  'Soon',
                                  style: TextStyle(
                                    color: Colors.black,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  // Title in soft pill
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.07),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      movie.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: FontService.instance.style(
                        color: Colors.white,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSectionHeader(String title, String? categoryType) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: FontService.instance.display(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (categoryType != null)
            GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ViewMoreScreen(
                      title: title,
                      categoryType: categoryType,
                    ),
                  ),
                );
              },
              child: LiquidGlassContainer(
                borderRadius: 20,
                padding: const EdgeInsets.all(6),
                child: const Icon(
                  Icons.chevron_right_rounded,
                  color: _gold,
                  size: 18,
                ),
              ),
            ),
        ],
      ),
    );
  }
}