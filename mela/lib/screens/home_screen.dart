import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/movie.dart';
import '../services/tmdb_service.dart';
import '../services/tmdb_details_service.dart';
import '../services/continue_watching_service.dart';
import '../services/font_service.dart';
import '../services/app_settings_service.dart';
import '../services/user_library_service.dart';
import '../widgets/liquid_glass.dart';
import '../widgets/floating_nav_bar.dart';
import '../widgets/available_downloads_sheet.dart';
import '../widgets/pressable.dart';
import '../widgets/provider_pill_selector.dart';
import '../widgets/update_banner_widget.dart';
import '../services/update_service.dart';
import 'detail_screen.dart';
import 'dev_picks_screen.dart';
import 'viewmore.dart';
import 'search_screen.dart';
import 'library_screen.dart';
import 'profile_screen.dart';
import 'iptv_channel_list_screen.dart';

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

  List<Movie> _continueWatching = [];
  Map<int, Map<String, dynamic>> _continueProgress = {};

  final List<Movie> _trendingMovies = [];
  final List<Movie> _scifiMovies = [];
  final List<Movie> _romanticMovies = [];
  final List<Movie> _actionMovies = [];
  final List<Movie> _classicMovies = [];
  final List<Movie> _nowPlayingMovies = [];
  final List<Movie> _animeMovies = [];
  final List<Movie> _tvShows = [];
  final List<Movie> _awardMovies = [];
  final List<Movie> _asianContent = [];
  final List<Map<String, dynamic>> _directors = [];

  final Map<int, String> _heroLogos = {};
  final Map<int, bool> _isTvMap = {};

  final TmdbService _tmdbService = TmdbService();
  final TmdbDetailsService _detailsService = TmdbDetailsService();
  late AnimationController _fadeController;

  DateTime? _fetchedAt;

  UpdateInfo? _updateInfo;
  bool _updateBannerDismissed = false;

  static Future<Box<Movie>>? _continueWatchingBoxFuture;

  static Future<Box<Movie>> _openContinueWatchingBox() {
    if (Hive.isBoxOpen('continue_watching')) {
      return Future.value(Hive.box<Movie>('continue_watching'));
    }
    return _continueWatchingBoxFuture ??=
        Hive.openBox<Movie>('continue_watching').whenComplete(() {
      _continueWatchingBoxFuture = null;
    });
  }

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
  String _selectedProviderName = 'Netflix';

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _loadContinueWatching();
    _fetchInitialData();
    _checkForUpdate();
  }

  Future<void> _checkForUpdate() async {
    final info = await UpdateService.checkForUpdate();
    if (!mounted || info == null) return;
    setState(() => _updateInfo = info);
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  Future<void> _loadContinueWatching() async {
    try {
      final box = await _openContinueWatchingBox();
      final movies = box.values.toList().reversed.toList();

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
    });

    try {
      final primary = await Future.wait([
        _tmdbService.getTrendingMovies(),
        _tmdbService.getActionMovies(),
        _tmdbService.getNowPlayingMovies(),
        _tmdbService.getTrendingTvShows(),
      ]);

      if (!mounted) return;

      final seen = <int>{};

      List<Movie> unique(List<Movie> src, {int take = 16, bool markTv = false}) {
        final out = <Movie>[];
        for (final m in src) {
          if (seen.add(m.id)) {
            out.add(m);
            if (markTv) _isTvMap[m.id] = true;
          }
          if (out.length >= take) break;
        }
        return out;
      }

      setState(() {
        _trendingMovies
          ..clear()
          ..addAll(unique(primary[0], take: 18));
        _actionMovies
          ..clear()
          ..addAll(unique(primary[1], take: 14));
        _nowPlayingMovies
          ..clear()
          ..addAll(unique(primary[2], take: 14));
        _tvShows
          ..clear()
          ..addAll(unique(primary[3], take: 16, markTv: true));
        _fetchedAt = DateTime.now();
        _isLoading = false;
        _hasError = false;
      });

      _fadeController.forward(from: 0.0);
      _fetchHeroLogos(_trendingMovies.take(5).toList());
      _fetchSecondaryCategories(seen, unique);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _hasError = true;
      });
    }
  }

  Future<void> _fetchSecondaryCategories(
    Set<int> seen,
    List<Movie> Function(List<Movie>, {int take, bool markTv}) unique,
  ) async {
    try {
      final secondary = await Future.wait([
        _tmdbService.getSciFiMovies(),
        _tmdbService.getRomanticMovies(),
        _tmdbService.getClassicMovies(),
        _tmdbService.getAnimationMovies(),
        _tmdbService.getAnimeTvShows(),
        _tmdbService.getMoviesByCategory(categoryType: 'award'),
        _tmdbService.getAsianTvShows(),
        _tmdbService.getPopularDirectors(),
      ]);

      if (!mounted) return;

      final animeTv = secondary[4] as List<Movie>;
      final animeSrc =
          animeTv.isNotEmpty ? animeTv : (secondary[3] as List<Movie>);

      setState(() {
        _scifiMovies
          ..clear()
          ..addAll(unique(secondary[0] as List<Movie>, take: 14));
        _romanticMovies
          ..clear()
          ..addAll(unique(secondary[1] as List<Movie>, take: 14));
        _classicMovies
          ..clear()
          ..addAll(unique(secondary[2] as List<Movie>, take: 14));
        _animeMovies
          ..clear()
          ..addAll(unique(animeSrc, take: 14, markTv: animeTv.isNotEmpty));
        _awardMovies
          ..clear()
          ..addAll(unique(secondary[5] as List<Movie>, take: 14));
        _asianContent
          ..clear()
          ..addAll(
              unique(secondary[6] as List<Movie>, take: 14, markTv: true));
        _directors
          ..clear()
          ..addAll(secondary[7] as List<Map<String, dynamic>>);
      });
    } catch (_) {}
  }

  Future<void> _fetchHeroLogos(List<Movie> movies) async {
    final futures = movies.map((movie) async {
      try {
        final isTv = _isTvMap[movie.id] == true || movie.mediaType == 'tv';
        final logo = await _detailsService.getMovieLogo(movie.id, isTv: isTv);
        return MapEntry(movie.id, logo);
      } catch (_) {
        return MapEntry(movie.id, null);
      }
    });

    final results = await Future.wait(futures);
    if (!mounted) return;

    setState(() {
      for (final entry in results) {
        if (entry.value != null) {
          _heroLogos[entry.key] = entry.value!;
        }
      }
    });
  }

  void _onProviderSelected(Map<String, dynamic> provider) {
    setState(() => _selectedProviderName = provider['name'] as String);
    final id = provider['provider_id'] as int;
    if (id == 0) {
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
      final box = await _openContinueWatchingBox();
      await box.put(movie.id, movie);
    } catch (e) {
      debugPrint('Error saving to continue watching: $e');
    }

    if (!mounted) return;
    final isTv = _isTvMap[movie.id] == true || movie.mediaType == 'tv';
    await Navigator.push(
      context,
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 380),
        pageBuilder: (_, _, _) => DetailScreen(movie: movie, isTv: isTv),
        transitionsBuilder: (_, animation, _, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );

    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final route = ModalRoute.of(context);
      if (route == null || route.isCurrent) {
        _loadContinueWatching();
      }
    });
  }

  List<Movie> _visibleMovies(List<Movie> movies) {
    if (!AppSettingsService.instance.hideWatchedFromHome) return movies;
    return movies
        .where((m) => !UserLibraryService.instance.isWatchedMovie(m))
        .toList();
  }

  void _onNavTapped(int index) {
    if (index < 0 || index > 4) return;
    if (_currentNavIndex == index) return;
    HapticFeedback.selectionClick();
    setState(() => _currentNavIndex = index);
    if (index == 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _loadContinueWatching();
      });
    }
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

  int _cacheWidthFor(BuildContext context, double logicalWidth) {
    final dpr = MediaQuery.of(context).devicePixelRatio;
    return (logicalWidth * dpr).round();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      resizeToAvoidBottomInset: false, // <-- Fixes keyboard shifting layout & nav bar
      body: Stack(
        children: [
          IndexedStack(
            index: _currentNavIndex,
            sizing: StackFit.expand,
            children: [
              _buildHomeTab(),
              const SearchScreen(),
              const IptvChannelListScreen(),
              const LibraryScreen(),
              const ProfileScreen(),
            ],
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: FloatingNavBar(
              currentIndex: _currentNavIndex,
              onTap: _onNavTapped,
            ),
          ),
          if (_updateInfo != null && !_updateBannerDismissed)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                bottom: false,
                child: UpdateBanner(
                  info: _updateInfo!,
                  onDismiss: () =>
                      setState(() => _updateBannerDismissed = true),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildHomeTab() {
    final bool isEmptyData = _trendingMovies.isEmpty &&
        _actionMovies.isEmpty &&
        _scifiMovies.isEmpty;

    return RefreshIndicator(
      color: _gold,
      backgroundColor: const Color(0xFF1E1E1E),
      onRefresh: () async {
        await _loadContinueWatching();
        await _fetchInitialData();
      },
      child: (_hasError || isEmptyData) && !_isLoading
          ? _buildOfflineState()
          : SingleChildScrollView(
              physics: const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics(),
              ),
              padding: const EdgeInsets.only(bottom: 120),
              child: _isLoading
                  ? _buildSkeletonLoadingState()
                  : _buildLoadedContent(),
            ),
    );
  }

  Widget _buildOfflineState() {
    return SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                "could not reach FEB server",
                textAlign: TextAlign.center,
                style: FontService.instance.display(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.2,
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'Check your connection and try again.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white60,
                  fontSize: 15,
                  fontFamily: 'Courier',
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 28),
              GestureDetector(
                onTap: () {
                  HapticFeedback.mediumImpact();
                  _fetchInitialData();
                },
                child: Container(
                  width: double.infinity,
                  height: 52,
                  decoration: BoxDecoration(
                    color: _gold.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(
                      color: _gold,
                      width: 1.5,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: const Text(
                    'Retry',
                    style: TextStyle(
                      color: _gold,
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
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
          const SizedBox(height: 18),
          ProviderPillSelector(
            selectedName: _selectedProviderName,
            providers: _providers,
            onSelected: _onProviderSelected,
            onDevPicksTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => DevPicksScreen(
                    trending: _trendingMovies,
                    nowPlaying: _nowPlayingMovies,
                    awards: _awardMovies,
                    tvShows: _tvShows,
                    anime: _animeMovies,
                    asian: _asianContent,
                    fetchedAt: _fetchedAt,
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 20),

          if (_continueWatching.isNotEmpty) ...[
            _buildSectionHeader('Continue Watching', null),
            const SizedBox(height: 12),
            _buildContinueWatchingList(),
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

          _buildSectionHeader('Classic Films', 'classics'),
          const SizedBox(height: 12),
          _buildMovieList(_classicMovies, isLarge: false),
          const SizedBox(height: 24),

          _buildSectionHeader('Romantic Escapes', 'romance'),
          const SizedBox(height: 12),
          _buildMovieList(_romanticMovies, isLarge: false),
          const SizedBox(height: 24),

          _buildSectionHeader('In Theaters', 'now_playing'),
          const SizedBox(height: 12),
          _buildMovieList(_nowPlayingMovies, isLarge: false),
          const SizedBox(height: 24),

          _buildSectionHeader('Award Winners', 'award'),
          const SizedBox(height: 12),
          _buildMovieList(_awardMovies, isLarge: false),
          const SizedBox(height: 24),

          _buildSectionHeader('Anime & Animation', 'anime'),
          const SizedBox(height: 12),
          _buildMovieList(_animeMovies, isLarge: false),
          const SizedBox(height: 24),

          _buildSectionHeader('TV Series', 'tv'),
          const SizedBox(height: 12),
          _buildMovieList(_tvShows, isLarge: false),
          const SizedBox(height: 24),

          _buildSectionHeader('Asian Cinema', 'asian'),
          const SizedBox(height: 12),
          _buildMovieList(_asianContent, isLarge: false),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildHeroHeader(BuildContext context) {
    final heroList = _trendingMovies.take(5).toList();
    if (heroList.isEmpty) return const SizedBox.shrink();

    final height = MediaQuery.of(context).size.height * 0.72;

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(32)),
      child: SizedBox(
        height: height,
        child: PageView.builder(
          itemCount: heroList.length,
          onPageChanged: (index) => setState(() => _currentPage = index),
          itemBuilder: (context, index) {
            final movie = heroList[index];
            final logoUrl = _heroLogos[movie.id];
            final released = _isReleased(movie);

            return Pressable(
              key: ValueKey('hero_card_${movie.mediaType}_${movie.id}'),
              onTap: () => _openDetail(movie),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CachedNetworkImage(
                    imageUrl: movie.backdropUrl ?? movie.posterUrl,
                    fit: BoxFit.cover,
                    alignment: Alignment.topCenter,
                    memCacheWidth: _cacheWidthFor(
                        context, MediaQuery.of(context).size.width),
                    placeholder: (_, _) =>
                        Container(color: const Color(0xFF121212)),
                    errorWidget: (_, _, _) =>
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
                              ? CachedNetworkImage(
                                  imageUrl: logoUrl,
                                  fit: BoxFit.contain,
                                  alignment: Alignment.center,
                                  memCacheHeight: 160,
                                  errorWidget: (_, _, _) =>
                                      _heroTitle(movie.title),
                                )
                              : _heroTitle(movie.title),
                        ),
                        const SizedBox(height: 8),
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
                              _pill('Coming Soon: ${movie.releaseDate}'),
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
                              margin:
                                  const EdgeInsets.symmetric(horizontal: 3),
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

  Widget _buildSkeletonLoadingState() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius:
              const BorderRadius.vertical(bottom: Radius.circular(32)),
          child: Container(
            height: MediaQuery.of(context).size.height * 0.72,
            color: const Color(0xFF121212),
            child: const Center(
              child:
                  CircularProgressIndicator(color: _gold, strokeWidth: 2.5),
            ),
          ),
        ),
        const SizedBox(height: 24),
        ...List.generate(
          3,
          (_) => Padding(
            padding: const EdgeInsets.only(bottom: 20, left: 20, right: 20),
            child: Container(
              height: 180,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(22),
              ),
            ),
          ),
        ),
      ],
    );
  }

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

          return Pressable(
            key: ValueKey('cw_card_${movie.mediaType}_${movie.id}'),
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
                          CachedNetworkImage(
                            imageUrl: movie.posterUrl,
                            fit: BoxFit.cover,
                            alignment: Alignment.topCenter,
                            memCacheWidth: 280,
                            placeholder: (_, _) =>
                                Container(color: const Color(0xFF1A1A1A)),
                            errorWidget: (_, _, _) =>
                                Container(color: Colors.grey[900]),
                          ),
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
                                  mediaType: (movie.mediaType == 'tv' ||
                                          _isTvMap[movie.id] == true)
                                      ? 'tv'
                                      : 'movie',
                                );
                              },
                              child: Container(
                                width: 28,
                                height: 28,
                                decoration: BoxDecoration(
                                  color:
                                      Colors.black.withValues(alpha: 0.65),
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
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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

  Widget _buildMovieList(List<Movie> movies, {required bool isLarge}) {
    final visible = _visibleMovies(movies);
    if (visible.isEmpty) {
      return const SizedBox.shrink();
    }

    final height = isLarge ? 270.0 : 230.0;
    final cardWidth = isLarge ? 160.0 : 140.0;

    return SizedBox(
      height: height,
      child: ListView.builder(
        physics: const BouncingScrollPhysics(),
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: visible.length,
        itemBuilder: (context, index) {
          final movie = visible[index];
          final released = _isReleased(movie);

          return Pressable(
            key: ValueKey('movie_card_${movie.mediaType}_${movie.id}'),
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
                          CachedNetworkImage(
                            imageUrl: movie.posterUrl,
                            fit: BoxFit.cover,
                            alignment: Alignment.topCenter,
                            memCacheWidth: 300,
                            placeholder: (_, _) =>
                                Container(color: const Color(0xFF1A1A1A)),
                            errorWidget: (_, _, _) => Container(
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
                                child: Text(
                                  'Soon: ${movie.releaseDate}',
                                  style: const TextStyle(
                                    color: Colors.black,
                                    fontSize: 9.5,
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
                  Container(
                    width: double.infinity,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
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