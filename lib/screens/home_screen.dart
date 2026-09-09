import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/download_service.dart';
import '../models/movie.dart';
import '../services/tmdb_service.dart';
import '../services/tmdb_details_service.dart';
import '../services/continue_watching_service.dart';
import '../services/home_feed_cache_service.dart';
import '../services/font_service.dart';
import '../design/tokens.dart';
import '../design/motion.dart';
import '../widgets/adaptive_logo_title.dart';
import '../widgets/addons_rails.dart';
import '../widgets/floating_nav_bar.dart';
import '../widgets/update_banner_widget.dart';
import '../widgets/top_ten_trending_section.dart';
import '../widgets/continue_watching_card.dart';
import '../utils/adaptive.dart';
import '../widgets/home_media_rail.dart';
import '../widgets/home_feed_config.dart';
import '../widgets/app_card.dart';
import '../widgets/app_button.dart';
import '../widgets/section_header.dart';
import '../services/update_service.dart';
import '../services/recommendation_service.dart';
import '../services/watch_party_service.dart';
import '../widgets/watch_party_sheet.dart';
import 'detail_screen.dart';
import 'custom_player_screen.dart';
import 'dev_picks_screen.dart';
import 'viewmore.dart';
import 'search_screen.dart';
import 'library_screen.dart';
import 'profile_screen.dart';
import 'iptv_channel_list_screen.dart';
import 'person_credits_screen.dart';

const _bg = AppDesignTokens.backgroundCanvas;

bool heroIsReleased(Movie m) {
  if (m.releaseDate.isEmpty) return true;
  try {
    final d = DateTime.parse(m.releaseDate);
    final now = DateTime.now();
    return !DateTime(d.year, d.month, d.day)
        .isAfter(DateTime(now.year, now.month, now.day));
  } catch (_) {
    return true;
  }
}

String heroImageUrl(String? path, {String size = 'w500'}) {
  if (path == null || path.isEmpty) return '';
  if (path.startsWith('http')) return path;
  return 'https://image.tmdb.org/t/p/$size$path';
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with TickerProviderStateMixin {
  int _currentNavIndex = 0;
  bool _isLoading = true;
  bool _hasError = false;
  List<Movie> _continueWatching = [];
  Map<int, Map<String, dynamic>> _continueProgress = {};
  final List<Movie> _trendingMovies = [];
  final List<Movie> _scifiMovies = [];
  final List<Movie> _actionMovies = [];
  final List<Movie> _classicMovies = [];
  final List<Movie> _nowPlayingMovies = [];
  final List<Movie> _animeMovies = [];
  final List<Movie> _tvShows = [];
  final List<Movie> _awardMovies = [];
  final List<Map<String, dynamic>> _directors = [];
  final Map<int, String> _heroLogos = {};
  final Map<int, bool> _isTvMap = {};
  int _feedGeneration = 0;
  final Map<String, List<Movie>> _sectionShuffleCache = {};
  final Map<String, int> _sectionShuffleGeneration = {};
  final TmdbService _tmdbService = TmdbService();
  final TmdbDetailsService _detailsService = TmdbDetailsService();
  late AnimationController _fadeController;
  DateTime? _fetchedAt;
  UpdateInfo? _updateInfo;
  bool _updateBannerDismissed = false;
  final GlobalKey<_HeroCarouselState> _heroKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: AppMotion.slow,
    );
    _loadContinueWatching();
    _fetchInitialData();
    _checkForUpdate();
    RecommendationService.instance.ensureLoaded().then((_) {
      if (mounted) setState(() {});
    });
    RecommendationService.instance.addListener(_onRecChanged);

    // Scale the animation duration to the device's refresh rate once
    // the inherited widgets (MediaQuery) are available — initState
    // runs before that, so the call must happen after the first frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _rescaleAnimations();
    });
  }

  void _rescaleAnimations() {
    if (!mounted) return;
    _fadeController.duration = AppMotion.scaled(context, AppMotion.slow);
  }

  @override
  void dispose() {
    RecommendationService.instance.removeListener(_onRecChanged);
    _fadeController.dispose();
    super.dispose();
  }

  void _onRecChanged() {
    if (mounted) setState(() {});
  }

  // ── Data ───────────────────────────────────────────────────
  Future<void> _loadContinueWatching() async {
    try {
      await ContinueWatchingService.rehydrateMissingPosters();
      final entries = await ContinueWatchingService.getEntries();
      final movies = <Movie>[];
      final progress = <int, Map<String, dynamic>>{};
      for (final e in entries) {
        final movie = ContinueWatchingService.movieFromEntry(e);
        if (movie == null) continue;
        progress[movie.id] = e;
        movies.add(movie);
        if ((e['mediaType'] as String?) == 'tv') _isTvMap[movie.id] = true;
      }
      if (!mounted) return;
      setState(() {
        _continueWatching = movies;
        _continueProgress = progress;
      });
    } catch (e) {
      debugPrint('Error loading continue watching: $e');
    }
  }

  Future<void> _fetchInitialData({bool forceRefresh = false}) async {
    final cache = HomeFeedCacheService.instance;
    var hydratedFromCache = false;
    if (!forceRefresh) {
      try {
        final cached = await Future.wait([
          cache.loadCategory('trending'),
          cache.loadCategory('action'),
          cache.loadCategory('now_playing'),
          cache.loadCategory('tv'),
        ]);
        if (cached[0].isNotEmpty && mounted) {
          setState(() {
            _trendingMovies..clear()..addAll(cached[0]);
            _actionMovies..clear()..addAll(cached[1]);
            _nowPlayingMovies..clear()..addAll(cached[2]);
            _tvShows..clear()..addAll(cached[3]);
            for (final m in cached[3]) {
              _isTvMap[m.id] = true;
            }
            _isLoading = false;
            _hasError = false;
            _feedGeneration++;
          });
          hydratedFromCache = true;
          _fadeController.forward(from: 0.0);
          _fetchHeroLogos(_trendingMovies.take(5).toList());
          _hydrateSecondaryFromCache();
        }
      } catch (_) {}
    }
    if (!hydratedFromCache) {
      setState(() {
        _isLoading = true;
        _hasError = false;
      });
    }
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
          if (!RecommendationService.instance.isFamilySafe(m)) continue;
          if (seen.add(m.id)) {
            out.add(m);
            if (markTv) _isTvMap[m.id] = true;
          }
          if (out.length >= take) break;
        }
        return out;
      }

      final freshTrending = unique(primary[0], take: 18);
      final freshAction = unique(primary[1], take: 14);
      final freshNowPlaying = unique(primary[2], take: 14);
      final freshTv = unique(primary[3], take: 16, markTv: true);
      setState(() {
        _trendingMovies..clear()..addAll(freshTrending);
        _actionMovies..clear()..addAll(freshAction);
        _nowPlayingMovies..clear()..addAll(freshNowPlaying);
        _tvShows..clear()..addAll(freshTv);
        _fetchedAt = DateTime.now();
        _isLoading = false;
        _hasError = false;
        _feedGeneration++;
      });
      if (!hydratedFromCache) {
        _fadeController.forward(from: 0.0);
        _fetchHeroLogos(freshTrending.take(5).toList());
      }
      cache.saveCategory('trending', freshTrending);
      cache.saveCategory('action', freshAction);
      cache.saveCategory('now_playing', freshNowPlaying);
      cache.saveCategory('tv', freshTv);
      _fetchSecondaryCategories(seen, unique);
    } catch (error) {
      if (!mounted) return;
      if (!hydratedFromCache) {
        setState(() {
          _isLoading = false;
          _hasError = true;
        });
      }
    }
  }

  Future<void> _hydrateSecondaryFromCache() async {
    final cache = HomeFeedCacheService.instance;
    try {
      final cached = await Future.wait([
        cache.loadCategory('scifi'),
        cache.loadCategory('classics'),
        cache.loadCategory('anime'),
        cache.loadCategory('award'),
      ]);
      if (!mounted) return;
      setState(() {
        _scifiMovies..clear()..addAll(cached[0]);
        _classicMovies..clear()..addAll(cached[1]);
        _animeMovies..clear()..addAll(cached[2]);
        _awardMovies..clear()..addAll(cached[3]);
        _feedGeneration++;
      });
    } catch (_) {}
  }

  Future<void> _fetchSecondaryCategories(
    Set<int> seen,
    List<Movie> Function(List<Movie>, {int take, bool markTv}) unique,
  ) async {
    try {
      final secondary = await Future.wait([
        _tmdbService.getSciFiMovies(),
        _tmdbService.getClassicMovies(),
        _tmdbService.getAnimationMovies(),
        _tmdbService.getAnimeTvShows(),
        _tmdbService.getMoviesByCategory(categoryType: 'award'),
        _tmdbService.getPopularDirectors(),
      ]);
      if (!mounted) return;
      final animeTv = secondary[3] as List<Movie>;
      final animeSrc =
          animeTv.isNotEmpty ? animeTv : (secondary[2] as List<Movie>);
      final filteredDirectors =
          (secondary[5] as List<Map<String, dynamic>>).where((d) {
        final name = (d['name'] ?? '').toString().toLowerCase();
        if (name.contains('zendaya')) return false;
        final dept = (d['known_for_department'] ?? d['department'] ?? '')
            .toString()
            .toLowerCase();
        return dept != 'acting';
      }).toList();
      setState(() {
        _scifiMovies..clear()..addAll(unique(secondary[0] as List<Movie>, take: 14));
        _classicMovies..clear()..addAll(unique(secondary[1] as List<Movie>, take: 14));
        _animeMovies..clear()..addAll(unique(animeSrc, take: 14, markTv: animeTv.isNotEmpty));
        _awardMovies..clear()..addAll(unique(secondary[4] as List<Movie>, take: 14));
        _directors..clear()..addAll(filteredDirectors);
        _feedGeneration++;
      });
      final cache = HomeFeedCacheService.instance;
      cache.saveCategory('scifi', _scifiMovies);
      cache.saveCategory('classics', _classicMovies);
      cache.saveCategory('anime', _animeMovies);
      cache.saveCategory('award', _awardMovies);
    } catch (_) {}
  }

  Future<void> _fetchHeroLogos(List<Movie> movies) async {
    final results = await Future.wait(movies.map((movie) async {
      try {
        final isTv = _isTvMap[movie.id] == true || movie.mediaType == 'tv';
        return MapEntry(movie.id,
            await _detailsService.getMovieLogo(movie.id, isTv: isTv));
      } catch (_) {
        return MapEntry(movie.id, null);
      }
    }));
    if (!mounted) return;
    setState(() {
      for (final e in results) {
        if (e.value != null) _heroLogos[e.key] = e.value!;
      }
    });
  }

  Future<void> _checkForUpdate() async {
    final info = await UpdateService.checkForUpdate();
    if (!mounted || info == null) return;
    setState(() => _updateInfo = info);
    if (info.force) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showForcedUpdateDialog(context, info);
      });
    }
  }

  void _showForcedUpdateDialog(BuildContext context, UpdateInfo info) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        double progress = 0.0;
        bool downloading = false;
        return StatefulBuilder(builder: (context, setDialog) {
          return PopScope(
            canPop: false,
            child: AlertDialog(
              backgroundColor: AppDesignTokens.surfaceElevated,
              shape: RoundedRectangleBorder(
                borderRadius: AppDesignTokens.radiusMd,
                side: const BorderSide(color: AppDesignTokens.accentEmber, width: 1),
              ),
              title: const Row(children: [
                Icon(Icons.warning_amber_rounded, color: AppDesignTokens.accentEmber),
                SizedBox(width: 10),
                Text('CRITICAL UPDATE REQUIRED',
                    style: AppDesignTokens.heading),
              ]),
              content: Column(mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  'A mandatory update is required to continue using FEB. Please update to the latest version.',
                  style: AppDesignTokens.caption.copyWith(color: AppDesignTokens.textCream.withValues(alpha: 0.85)),
                ),
                const SizedBox(height: 12),
                if (info.changelog.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppDesignTokens.surfaceElevated.withValues(alpha: 0.5),
                      borderRadius: AppDesignTokens.radiusMd,
                      border: Border.all(color: AppDesignTokens.borderCork, width: 1),
                    ),
                    child: Text(info.changelog,
                        style: AppDesignTokens.caption),
                  ),
                if (downloading) ...[
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    value: progress > 0 ? progress : null,
                    color: AppDesignTokens.accentEmber,
                    backgroundColor: AppDesignTokens.surfaceElevated,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Downloading update... ${(progress * 100).toStringAsFixed(0)}%',
                    style: AppDesignTokens.caption.copyWith(color: AppDesignTokens.muted),
                  ),
                ],
              ]),
              actions: [
                if (!downloading)
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppDesignTokens.surfaceElevated,
                        foregroundColor: AppDesignTokens.textCream,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: AppDesignTokens.radiusPill,
                          side: const BorderSide(color: AppDesignTokens.textCream, width: 1),
                        ),
                        textStyle: AppDesignTokens.navLabel,
                      ),
                      onPressed: () async {
                        setDialog(() {
                          downloading = true;
                          progress = 0.0;
                        });
                        await UpdateService.downloadAndInstall(
                          url: info.downloadUrl,
                          onProgress: (p) => setDialog(() => progress = p),
                        );
                        setDialog(() => downloading = false);
                      },
                      child: const Text('UPDATE NOW'),
                    ),
                  ),
              ],
            ),
          );
        });
      },
    );
  }

  // ── Navigation / actions ───────────────────────────────────
  Future<void> _openDetail(Movie movie) async {
    if (!mounted) return;
    final isTv = _isTvMap[movie.id] == true || movie.mediaType == 'tv';
    // Standard route = one system-back / swipe-back pop. Custom fade routes
    // on some devices register an extra predictive-back frame and feel like
    // "double back".
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DetailScreen(movie: movie, isTv: isTv),
      ),
    );
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadContinueWatching();
    });
  }

  Future<void> _openContinueWatchingPlayer(Movie movie) async {
    final prog = _continueProgress[movie.id];
    final mediaType = (movie.mediaType == 'tv' ||
            _isTvMap[movie.id] == true ||
            (prog?['mediaType'] as String?) == 'tv')
        ? 'tv'
        : 'movie';
    final season = (prog?['season'] as num?)?.toInt() ?? 1;
    final episode = (prog?['episode'] as num?)?.toInt() ?? 1;
    final position = (prog?['position'] as num?)?.toInt() ?? 0;
    Movie playMovie = movie;
    if (movie.posterPath.toString().trim().isEmpty ||
        movie.title.isEmpty ||
        movie.title == 'N/A' ||
        movie.title == 'Unknown') {
      try {
        final d = await _detailsService.getMovieDetails(movie.id,
            isTv: mediaType == 'tv');
        if (d != null) {
          playMovie = Movie.fromJson({
            'id': movie.id,
            'title': d['title'] ?? d['name'] ?? movie.title,
            'poster_path': d['poster_path'],
            'backdrop_path': d['backdrop_path'],
            'overview': d['overview'] ?? '',
            'vote_average': d['vote_average'] ?? 0,
            'release_date': d['release_date'] ?? d['first_air_date'] ?? '',
            'media_type': mediaType,
          });
        }
      } catch (_) {}
    }
    final streamUrl = mediaType == 'tv'
        ? 'https://vidfast.vc/tv/${playMovie.id}/$season/$episode?autoPlay=true'
        : 'https://vidfast.vc/movie/${playMovie.id}?autoPlay=true';
    if (!mounted) return;
    await Navigator.of(context).push(PageRouteBuilder(
      transitionDuration: AppMotion.scaled(context, AppMotion.medium),
      pageBuilder: (_, _, _) => CustomPlayerScreen(
        streamUrl: streamUrl,
        title: playMovie.title,
        wisoApiKey: '',
        tmdbId: playMovie.id.toString(),
        mediaType: mediaType,
        season: mediaType == 'tv' ? season : null,
        episode: mediaType == 'tv' ? episode : null,
        movie: playMovie,
        initialPositionSeconds: position > 0 ? position : null,
        isOffline: false,
      ),
      transitionsBuilder: (_, animation, _, child) =>
          FadeTransition(opacity: animation, child: child),
    ));
    if (mounted) await _loadContinueWatching();
  }

  Future<void> _onNavTapped(int index) async {
    if (index < 0 || index > 4) return;
    if (_currentNavIndex == index && index != 0) return;
    FocusManager.instance.primaryFocus?.unfocus();
    HapticFeedback.selectionClick();
    if (index == 0) {
      if (!mounted) return;
      setState(() => _currentNavIndex = 0);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _loadContinueWatching();
      });
      return;
    }
    final Widget screen;
    switch (index) {
      case 1:
        screen = const SearchScreen();
        break;
      case 2:
        screen = const IptvChannelListScreen();
        break;
      case 3:
        screen = const LibraryScreen();
        break;
      case 4:
        screen = const ProfileScreen();
        break;
      default:
        return;
    }
    if (!mounted) return;
    setState(() => _currentNavIndex = index);
    try {
      await Navigator.of(context)
          .push(MaterialPageRoute<void>(builder: (_) => screen));
    } finally {
      // No `return` in finally: that would swallow exceptions from the push.
      // Guard with `mounted` instead so cleanup is skipped only when the
      // widget is already gone.
      if (mounted) {
        setState(() => _currentNavIndex = 0);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _loadContinueWatching();
        });
      }
    }
  }

  void _showMoviePreferenceMenu(Movie movie) {
    HapticFeedback.mediumImpact();
    final rec = RecommendationService.instance;
    final isTv = _isTvMap[movie.id] == true || movie.mediaType == 'tv';
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFF141414),
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
          border: Border(top: BorderSide(color: Color(0x33FFB800), width: 1)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 14),
              Row(children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: CachedNetworkImage(
                    imageUrl: movie.posterUrl,
                    width: 44,
                    height: 64,
                    fit: BoxFit.cover,
                    errorWidget: (_, _, _) => Container(
                      width: 44,
                      height: 64,
                      color: Colors.white10,
                      child: const Icon(Icons.movie, color: Colors.white24),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(movie.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 15)),
                        const SizedBox(height: 4),
                        Text(isTv ? 'TV Series' : 'Movie',
                            style: const TextStyle(
                                color: Colors.white54, fontSize: 12)),
                      ]),
                ),
              ]),
              const SizedBox(height: 16),
              _prefAction(
                icon: rec.isLiked(movie.id)
                    ? Icons.favorite_rounded
                    : Icons.favorite_border_rounded,
                iconColor: AppDesignTokens.gold,
                title: 'LIKED',
                subtitle: 'Show me more like this',
                onTap: () async {
                  Navigator.pop(ctx);
                  await rec.like(movie);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text('Liked "${movie.title}"'),
                      backgroundColor: AppDesignTokens.surfaceElevated,
                      behavior: SnackBarBehavior.floating,
                    ));
                  }
                },
              ),
              _prefAction(
                icon: Icons.visibility_off_rounded,
                iconColor: AppDesignTokens.textCream.withValues(alpha: 0.7),
                title: 'NOT INTERESTED',
                subtitle: 'Hide this from Home forever',
                onTap: () async {
                  Navigator.pop(ctx);
                  await rec.notInterested(movie);
                  if (mounted) {
                    setState(() {});
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text('Hidden "${movie.title}" from Home'),
                      backgroundColor: AppDesignTokens.surfaceElevated,
                      behavior: SnackBarBehavior.floating,
                    ));
                  }
                },
              ),
              _prefAction(
                icon: Icons.groups_rounded,
                iconColor: AppDesignTokens.gold,
                title: 'WATCH PARTY',
                subtitle: 'Invite friends to watch together',
                onTap: () async {
                  Navigator.pop(ctx);
                  final party = await WatchPartySheet.show(context,
                      movie: movie, mediaType: isTv ? 'tv' : 'movie');
                  if (party != null && mounted) {
                    final url = WatchPartyService.instance.streamUrlFor(party);
                    await Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => CustomPlayerScreen(
                        streamUrl: url,
                        title: party.title,
                        wisoApiKey: '',
                        tmdbId: party.tmdbId.toString(),
                        mediaType: party.mediaType,
                        season: party.season,
                        episode: party.episode,
                        movie: movie,
                        isOffline: false,
                      ),
                    ));
                  }
                },
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _prefAction({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AppCard(
        onTap: onTap,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        borderRadius: AppDesignTokens.radiusLg,
        border: true,
        borderColor: Colors.white.withValues(alpha: 0.06),
        backgroundColor: Colors.white.withValues(alpha: 0.04),
        elevation: AppCardElevation.none,
        child: Row(children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: iconColor, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: AppDesignTokens.titleMedium(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      )),
                  const SizedBox(height: 2),                        Text(subtitle,
                      style: AppDesignTokens.bodySmall(
                        color: Colors.white54,
                        fontSize: 12,
                      )),
                ]),
          ),
          const Icon(Icons.chevron_right_rounded,
              color: Colors.white38, size: 20),
        ]),
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      resizeToAvoidBottomInset: false, // no inputs on Home → no IME relayouts
      body: Stack(children: [
        RepaintBoundary(child: _buildHomeTab()),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: FloatingNavBar(
              currentIndex: _currentNavIndex, onTap: _onNavTapped),
        ),
        if (_updateInfo != null &&
            !_updateBannerDismissed &&
            !(_updateInfo?.force ?? false))
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
      ]),
    );
  }

  Widget _buildHomeTab() {
    final isEmptyData = _trendingMovies.isEmpty &&
        _actionMovies.isEmpty &&
        _scifiMovies.isEmpty;
    return RefreshIndicator(              color: AppDesignTokens.gold,
              backgroundColor: AppDesignTokens.surfaceElevated,
      onRefresh: () async {
        await _loadContinueWatching();
        await _fetchInitialData(forceRefresh: true);
      },
      child: (_hasError || isEmptyData) && !_isLoading
          ? _buildOfflineState()
          : NotificationListener<ScrollNotification>(
              onNotification: (n) {
                if (n is ScrollStartNotification) {
                  _heroKey.currentState?.pauseTemporarily();
                }
                return false;
              },
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final sideBySide = constraints.maxWidth >
                          constraints.maxHeight &&
                      constraints.maxWidth >= 640;
                  if (_isLoading) return _buildSkeleton(sideBySide);
                  return FadeTransition(
                    opacity: _fadeController,
                    child: sideBySide
                        ? _buildWide(constraints)
                        : _buildNarrow(),
                  );
                },
              ),
            ),
    );
  }

  // Portrait / narrow: single vertical scroll.
  Widget _buildNarrow() {
    final mq = MediaQuery.of(context);
    // Slightly shorter hero so content rails start sooner and the page feels
    // less top-heavy / cluttered.
    final heroH = (mq.size.height * 0.54).clamp(280.0, 480.0);
    return SingleChildScrollView(
      physics:
          const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
      padding: const EdgeInsets.only(bottom: 120),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _HeroCarousel(
          key: _heroKey,
          movies: _trendingMovies.take(5).toList(),
          logos: _heroLogos,
          isTvMap: _isTvMap,
          onOpen: _openDetail,
          height: heroH,
        ),
        const SizedBox(height: 18),
        _buildSpecialsStrip(),
        const SizedBox(height: 28),
        _contentColumn(),
      ]),
    );
  }

  // Landscape / wide: hero pinned left, feed scrolls right.
  Widget _buildWide(BoxConstraints c) {
    final paneW = (c.maxWidth * 0.44).clamp(320.0, 620.0);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: paneW,
          height: c.maxHeight,
          child: SafeArea(
            bottom: false,
            child: _HeroCarousel(
              key: _heroKey,
              movies: _trendingMovies.take(5).toList(),
              logos: _heroLogos,
              isTvMap: _isTvMap,
              onOpen: _openDetail,
              height: null, // fill
            ),
          ),
        ),
        VerticalDivider(
            width: 1, thickness: 1, color: AppDesignTokens.borderCork),
        Expanded(
          child: SafeArea(
            bottom: false,
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(
                  parent: AlwaysScrollableScrollPhysics()),
              padding: const EdgeInsets.fromLTRB(0, 12, 0, 120),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSpecialsStrip(),
                  const SizedBox(height: 28),
                  _contentColumn(),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _contentColumn() {
    return Center(
      child: ConstrainedBox(
        constraints:
            BoxConstraints(maxWidth: AppDesignTokens.contentWidth(context)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (_continueWatching.isNotEmpty) ...[
                Padding(
              padding: Adaptive.pagePadding(context),
              child: Row(
                children: [
                  Icon(Icons.watch_later_outlined,
                      size: 18, color: AppDesignTokens.gold),
                  const SizedBox(width: 8),
                  Text(
                    'CONTINUE WATCHING',
                    style: AppDesignTokens.heading.copyWith(
                      color: AppDesignTokens.textCream,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            RepaintBoundary(child: _buildContinueWatchingList()),
            const SizedBox(height: 28),
          ],
          // Downloads section - shows active downloads beside library
          _buildDownloadsSection(),
          Builder(builder: (context) {
            final pool = <Movie>[
              ..._trendingMovies,
              ..._actionMovies,
              ..._scifiMovies,
              ..._nowPlayingMovies,
              ..._tvShows,
              ..._awardMovies,
              ..._animeMovies,
            ];
            final forYou =
                RecommendationService.instance.rankForYou(pool, take: 16);
            if (forYou.isEmpty) return const SizedBox.shrink();
            return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SectionHeader(
                      title: 'FOR YOU', style: SectionHeaderStyle.compact),
                  const SizedBox(height: 10),
                  RepaintBoundary(
                    child: HomeMediaRail(
                      movies: forYou,
                      onOpen: _openDetail,
                      onLongPress: _showMoviePreferenceMenu,
                    ),
                  ),
                  const SizedBox(height: 26),
                ]);
          }),
          AddonsHomeRail(),
          RepaintBoundary(
            child: TopTenTrendingSection(
              trendingMovies: _trendingMovies,
              tvShows: _tvShows,
              animeMovies: _animeMovies,
              isTvMap: _isTvMap,
              onOpenDetail: _openDetail,
            ),
          ),
          const SizedBox(height: 26),
          RepaintBoundary(child: _buildPeopleSpotlight()),
          const SizedBox(height: 32),
          ..._buildConfiguredFeedRails(),
        ]),
      ),
    );
  }

  Widget _buildOfflineState() {
    return SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppDesignTokens.textCream.withValues(alpha: 0.05),
                shape: BoxShape.circle,
                border: Border.all(color: AppDesignTokens.textCream.withValues(alpha: 0.08)),
              ),                child: Icon(
                  Icons.wifi_off_rounded,
                  size: 34,
                  color: AppDesignTokens.textCream.withValues(alpha: 0.45),
                ),
            ),
            const SizedBox(height: 18),
            Text(
              'could not reach FEB server',
              textAlign: TextAlign.center,                style: AppDesignTokens.heading.copyWith(
                      color: AppDesignTokens.textCream,
                      fontWeight: FontWeight.w700,
                      height: 0.9,
                    ),
            ),
            const SizedBox(height: 14),
            Text(
              'Check your connection and try again.',
              textAlign: TextAlign.center,                    style: AppDesignTokens.caption.copyWith(
                      color: AppDesignTokens.textCream.withValues(alpha: 0.85),
                    ),
            ),
            const SizedBox(height: 28),
            AppButton(
              onPressed: () {
                HapticFeedback.mediumImpact();
                _fetchInitialData();
              },
              variant: AppButtonVariant.secondary,
              size: AppButtonSize.large,
              fullWidth: true,
              borderRadius: AppDesignTokens.radiusGhost,
              leadingIcon: const Icon(Icons.refresh_rounded, size: 20),
              child: const Text('Retry'),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _buildSpecialsStrip() {
    final chips = <({String label, IconData icon, VoidCallback onTap})>[
      (label: 'Editor Picks', icon: Icons.auto_awesome_rounded, onTap: () {
        Navigator.push(context, MaterialPageRoute(
          builder: (_) => DevPicksScreen(
            trending: _trendingMovies,
            nowPlaying: _nowPlayingMovies,
            awards: _awardMovies,
            tvShows: _tvShows,
            anime: _animeMovies,
            fetchedAt: _fetchedAt,
          ),
        ));
      }),
      (label: 'Watch Party', icon: Icons.groups_rounded, onTap: () async {
        final party = await WatchPartySheet.show(context);
        if (party != null && mounted) {
          final url = WatchPartyService.instance.streamUrlFor(party);
          await Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => CustomPlayerScreen(
              streamUrl: url,
              title: party.title,
              wisoApiKey: '',
              tmdbId: party.tmdbId.toString(),
              mediaType: party.mediaType,
              season: party.season,
              episode: party.episode,
              isOffline: false,
            ),
          ));
        }
      }),
      (label: 'Top 10', icon: Icons.local_fire_department_rounded, onTap: () {
        Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => const ViewMoreScreen(
                title: 'Trending Now', categoryType: 'trending')));
      }),
      (label: 'Movies', icon: Icons.movie_rounded, onTap: () {
        Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => const ViewMoreScreen(
                title: 'Movies', categoryType: 'trending')));
      }),
      (label: 'TV Shows', icon: Icons.tv_rounded, onTap: () {
        Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => const ViewMoreScreen(
                title: 'TV Shows', categoryType: 'tv')));
      }),
      (label: 'Anime', icon: Icons.animation_rounded, onTap: () {
        Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => const ViewMoreScreen(
                title: 'Anime', categoryType: 'tv', forceTv: true)));
      }),
    ];
    // Make it non-scrollable - use Wrap instead of ListView
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: chips.map((c) {
        final isPrimary = c.label == 'Editor Picks';
        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {
              HapticFeedback.selectionClick();
              c.onTap();
            },
            borderRadius: BorderRadius.circular(16),
            child: Ink(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                color: isPrimary
                    ? AppDesignTokens.surfaceElevated.withValues(alpha: 0.16)
                    : Colors.transparent,
                border: Border.all(
                  color: isPrimary
                      ? AppDesignTokens.gold.withValues(alpha: 0.55)
                      : AppDesignTokens.textCream.withValues(alpha: 0.10),
                  width: 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(c.icon,
                      size: 14,
                      color: isPrimary ? AppDesignTokens.gold : AppDesignTokens.textCream.withValues(alpha: 0.7)),
                  const SizedBox(width: 6),
                  Text(
                    c.label.toUpperCase(),
                    style: AppDesignTokens.navLabel.copyWith(
                      color: isPrimary ? AppDesignTokens.gold : AppDesignTokens.textCream,
                      fontSize: 11,
                      height: 1.0,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildDownloadsSection() {
    final activeDownloads = DownloadService.instance.items
        .where((item) =>
            item.status == DownloadStatus.downloading ||
            item.status == DownloadStatus.resolving ||
            item.status == DownloadStatus.fusing)
        .toList();
    
    if (activeDownloads.isEmpty) return const SizedBox.shrink();
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: Adaptive.pagePadding(context),
          child: Row(
            children: [
              Icon(Icons.downloading_rounded,
                  size: 18, color: AppDesignTokens.gold),
              const SizedBox(width: 8),
              Text(
                'DOWNLOADING',
                style: AppDesignTokens.heading.copyWith(
                  color: AppDesignTokens.textCream,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 80,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            scrollCacheExtent: ScrollCacheExtent.pixels(400.0),
            addAutomaticKeepAlives: false,
            padding: Adaptive.pagePadding(context),
            itemCount: activeDownloads.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),              itemBuilder: (context, index) {
              final item = activeDownloads[index];
              final progressPercent = (item.progress * 100).toStringAsFixed(0);
              return _buildDownloadProgressChip(
                item,
                progressPercent,
              );
            },
          ),
        ),
        const SizedBox(height: 28),
      ],
    );
  }

  Widget _buildContinueWatchingList() {
    if (_continueWatching.isEmpty) return const SizedBox.shrink();
    // Landscape stills — wider than the portrait poster rails.
    final pageW = MediaQuery.sizeOf(context).width;
    final cardW = (pageW * 0.62).clamp(196.0, 280.0);
    final imageH = cardW * 0.56;
    final listH = imageH + 34; // image + title under card
    return SizedBox(
      height: listH,
      child: ListView.builder(
        physics: const BouncingScrollPhysics(),
        scrollDirection: Axis.horizontal,
        scrollCacheExtent: ScrollCacheExtent.pixels(400.0),
        addAutomaticKeepAlives: false,
        padding: Adaptive.pagePadding(context),
        itemCount: _continueWatching.length,
        itemBuilder: (context, index) {
          final movie = _continueWatching[index];
          final prog = _continueProgress[movie.id];
          final pos = (prog?['position'] as num?)?.toInt() ?? 0;
          final dur = (prog?['duration'] as num?)?.toInt() ?? 0;
          final season = (prog?['season'] as num?)?.toInt();
          final episode = (prog?['episode'] as num?)?.toInt();
          final mediaType = (movie.mediaType == 'tv' ||
                  _isTvMap[movie.id] == true ||
                  (prog?['mediaType'] as String?) == 'tv')
              ? 'tv'
              : 'movie';
          return Padding(
            key: ValueKey('cw_card_${mediaType}_${movie.id}'),
            padding: const EdgeInsets.only(right: 12),
            child: ContinueWatchingCard(
              movie: movie,
              mediaType: mediaType,
              position: pos,
              duration: dur,
              season: season,
              episode: episode,
              cardWidth: cardW,
              onTap: () => _openContinueWatchingPlayer(movie),
              onRemoved: _loadContinueWatching,
            ),
          );
        },
      ),
    );
  }

  Widget _buildPeopleSpotlight() {
    final people = _directors.take(12).toList();
    if (people.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [          SectionHeader(
              title: 'PEOPLE', style: SectionHeaderStyle.compact),
      const SizedBox(height: 14),
      SizedBox(
        height: 108,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          scrollCacheExtent: ScrollCacheExtent.pixels(300.0),
          addAutomaticKeepAlives: false,
          padding: Adaptive.pagePadding(context),
          itemCount: people.length,
          separatorBuilder: (_, _) => const SizedBox(width: 14),
          itemBuilder: (context, i) {
            final person = people[i];
            final name = (person['name'] ?? 'Unknown').toString();
            final profilePath = person['profile_path']?.toString();
            final personId = (person['id'] ?? 0).toString();
            return GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                final id = int.tryParse(personId);
                if (id != null && id > 0) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => PersonCreditsScreen(
                        personId: id,
                        name: name,
                        kind: PersonCreditKind.actor,
                      ),
                    ),
                  );
                } else {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ViewMoreScreen(
                        title: name,
                        categoryType: 'trending',
                      ),
                    ),
                  );
                }
              },
              child: SizedBox(
                width: 72,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ClipOval(
                      child: SizedBox(
                        width: 64,
                        height: 64,
                        child: profilePath != null && profilePath.isNotEmpty
                            ? CachedNetworkImage(
                                imageUrl:
                                    heroImageUrl(profilePath, size: 'w185'),
                                fit: BoxFit.cover,
                                memCacheWidth: 150,
                                memCacheHeight: 150,
                                fadeInDuration: Duration.zero,
                                placeholder: (_, _) =>
                                    Container(color: const Color(0xFF1A1A1A)),
                                errorWidget: (_, _, _) => Container(
                                  color: const Color(0xFF1A1A1A),
                                  alignment: Alignment.center,
                                  child: Text(
                                    name.isNotEmpty
                                        ? name[0].toUpperCase()
                                        : '?',
                                    style: const TextStyle(
                                      color: Colors.white54,
                                      fontSize: 20,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              )
                            : Container(
                                color: const Color(0xFF1A1A1A),
                                alignment: Alignment.center,
                                child: Text(
                                  name.isNotEmpty
                                      ? name[0].toUpperCase()
                                      : '?',
                                  style: const TextStyle(
                                    color: Colors.white54,
                                    fontSize: 20,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    ]);
  }

  List<Widget> _buildConfiguredFeedRails() {
    final rec = RecommendationService.instance;
    final bags = <String, List<Movie>>{
      'action': rec.filterForHome(_actionMovies),
      'scifi': rec.filterForHome(_scifiMovies),
      'classics': rec.filterForHome(_classicMovies),
      'now_playing': rec.filterForHome(_nowPlayingMovies),
      'award': rec.filterForHome(_awardMovies),
      'tv': rec.filterForHome(_tvShows),
    };
    final out = <Widget>[];
    final usedTitles = <String>{};
    for (final section in kHomeFeedSections) {
      final list = bags[section.listKey] ?? const <Movie>[];
      if (list.isEmpty || usedTitles.contains(section.title)) continue;
      usedTitles.add(section.title);
      final isCuratedShuffle = section.id.startsWith('mood_') ||
          section.id == 'late_night' ||
          section.id == 'weekend' ||
          section.id == 'prestige';
      final List<Movie> display;
      if (isCuratedShuffle) {
        final cachedGen = _sectionShuffleGeneration[section.id];
        final cached = _sectionShuffleCache[section.id];
        if (cached != null && cachedGen == _feedGeneration) {
          display = cached;
        } else {
          display = List<Movie>.from(list)..shuffle();
          _sectionShuffleCache[section.id] = display;
          _sectionShuffleGeneration[section.id] = _feedGeneration;
        }
      } else {
        display = list;
      }
      if (isCuratedShuffle) {
        out.add(Padding(
          padding: Adaptive.pagePadding(context),
          child: Row(children: [                Icon(Icons.auto_awesome_rounded,
                size: 13, color: AppDesignTokens.gold.withValues(alpha: 0.85)),
            const SizedBox(width: 5),
            Text('CURATED PICK',
                style: FontService.instance.label(
                    color: AppDesignTokens.gold.withValues(alpha: 0.85),
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.0)),
          ]),
        ));
        out.add(            const SizedBox(height: 4));
      }
      final rail = display.take(14).toList();
      out.add(_buildSectionHeader(
        section.title,

        section.categoryType,
        seedMovies: rail,
        forceTv: section.markTv,
      ));
      out.add(const SizedBox(height: 10));
      out.add(RepaintBoundary(
        child: HomeMediaRail(
          movies: rail,
          onOpen: _openDetail,

          onLongPress: _showMoviePreferenceMenu,
          categoryLabel: section.pillLabel,
          isReleased: heroIsReleased,
          formatReleaseDate: _formatReleaseDate,
          isTvMap: _isTvMap,
        ),
      ));
      out.add(const SizedBox(height: 26));
    }
    return out;
  }

  Widget _buildSectionHeader(
    String title,
    String? categoryType, {
    List<Movie> seedMovies = const [],
    bool forceTv = false,
  }) {
    return SectionHeader(
      title: title,
      action: categoryType == null
          ? null
          : () {
              HapticFeedback.selectionClick();
              // One push only — system / gesture back returns straight to Home.
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ViewMoreScreen(
                    title: title,
                    categoryType: categoryType,
                    seedMovies: seedMovies,
                    forceTv: forceTv,
                  ),
                ),
              );
            },
      actionIcon: Icons.chevron_right_rounded,
      style: SectionHeaderStyle.compact,
    );
  }

  String _formatReleaseDate(String raw) {
    if (raw.isEmpty) return 'TBA';
    try {
      final d = DateTime.parse(raw);
      const months = [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
      ];
      return '${months[d.month - 1]} ${d.day}, ${d.year}';
    } catch (_) {
      return raw;
    }
  }

  // Static skeleton for both orientations — no ticker.
  Widget _buildSkeleton(bool wide) {
    final mq = MediaQuery.of(context);
    final heroH = wide
        ? (mq.size.height * 0.8).clamp(220.0, 520.0)
        : (mq.size.height * 0.62).clamp(280.0, 620.0);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (wide)
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
                width: (mq.size.width * 0.44).clamp(320.0, 620.0),
                height: mq.size.height,
                child: _skeletonHero(heroH)),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: _skeletonRails(),
              ),
            ),
          ],
        )
      else ...[
        _skeletonHero(heroH),
        const SizedBox(height: 20),
        _skeletonRails(),
      ],
    ]);
  }

  Widget _skeletonHero(double h) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(32)),
      child: Container(
        height: h,
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF1A1A1A), Color(0xFF0A0A0A)],
          ),
        ),
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(40, 0, 40, 48),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                height: 48,
                width: 200,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              const SizedBox(height: 16),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                for (int i = 0; i < 3; i++)
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    height: 22,
                    width: 64,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.07),
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
              ]),
              const SizedBox(height: 18),
              Container(
                height: 40,
                width: 140,
                decoration: BoxDecoration(
                  color: AppDesignTokens.gold.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(24),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _skeletonRails() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(
        height: 36,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: 6,
          itemBuilder: (_, _) => Container(
            width: 88,
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(18),
            ),
          ),
        ),
      ),
      const SizedBox(height: 28),
      for (int section = 0; section < 3; section++)
        Padding(
          padding: const EdgeInsets.only(bottom: 24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                height: 16,
                width: 140,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: 200,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: 5,
                itemBuilder: (_, _) => Container(
                  width: 130,
                  margin: const EdgeInsets.only(right: 12),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
          ]),
        ),
    ]);
  }

  Widget _buildDownloadProgressChip(DownloadItem item, String progressPercent) {
    return SizedBox(
      width: 160,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Poster thumbnail
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              height: 56,
              width: 160,
              child: item.posterUrl.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: item.posterUrl,
                      fit: BoxFit.cover,
                      memCacheWidth: 150,
                      memCacheHeight: 150,
                      placeholder: (_, __) => Container(
                        color: const Color(0xFF1A1A1A),
                        child: const Icon(Icons.movie, color: Colors.white24),
                      ),
                      errorWidget: (_, __, ___) => Container(
                        color: const Color(0xFF1A1A1A),
                        child: const Icon(Icons.movie, color: Colors.white24),
                      ),
                    )
                  : Container(
                      color: const Color(0xFF1A1A1A),
                      child: const Icon(Icons.movie, color: Colors.white24),
                    ),
            ),
          ),
          const SizedBox(height: 6),
          // Title
          Text(
            item.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          // Progress bar with percentage
          Column(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: item.progress,
                  backgroundColor: Colors.white.withValues(alpha: 0.15),
                  valueColor: AlwaysStoppedAnimation<Color>(
                    AppDesignTokens.gold,
                  ),
                  minHeight: 3,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '$progressPercent%',
                style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 10,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          // Speed info
          Text(
            item.speedLabel,
            style: const TextStyle(
              color: Colors.white38,
              fontSize: 9,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Isolated hero carousel. `height == null` → fill parent (wide pane).
//     Non-focusable tap surface (GestureDetector + Semantics) keeps the
//     focus tree unchanged.
class _HeroCarousel extends StatefulWidget {
  final List<Movie> movies;
  final Map<int, String> logos;
  final Map<int, bool> isTvMap;
  final ValueChanged<Movie> onOpen;
  final double? height;
  const _HeroCarousel({
    super.key,
    required this.movies,
    required this.logos,
    required this.isTvMap,
    required this.onOpen,
    this.height,
  });
  @override
  State<_HeroCarousel> createState() => _HeroCarouselState();
}

class _HeroCarouselState extends State<_HeroCarousel> {
  final PageController _ctrl = PageController();
  Timer? _timer;
  int _page = 0;
  static const _period = Duration(seconds: 6);

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _start() {
    _timer?.cancel();
    _timer = Timer.periodic(_period, (_) {
      if (!mounted || widget.movies.length <= 1) return;
      if (WidgetsBinding.instance.lifecycleState !=
          AppLifecycleState.resumed) {
        return;
      }
      if (!_ctrl.hasClients) return;
      _ctrl.animateToPage((_page + 1) % widget.movies.length,
          duration: AppMotion.scaled(context, AppMotion.slow),
          curve: Curves.easeInOutCubic);
    });
  }

  void pauseTemporarily() {
    _timer?.cancel();
    Future.delayed(const Duration(seconds: 8), () {
      if (mounted) _start();
    });
  }

  @override
  Widget build(BuildContext context) {
    final list = widget.movies;
    if (list.isEmpty) return const SizedBox.shrink();
    final pageView = PageView.builder(
      controller: _ctrl,
      itemCount: list.length,
      onPageChanged: (i) {
        setState(() => _page = i);
        pauseTemporarily();
      },
      itemBuilder: (context, index) => _buildItem(list[index]),
    );
    return Column(children: [
      widget.height == null
          ? Expanded(
              child: ClipRRect(
                borderRadius:
                    const BorderRadius.vertical(bottom: Radius.circular(36)),
                child: pageView,
              ),
            )
          : ClipRRect(
              borderRadius:
                  const BorderRadius.vertical(bottom: Radius.circular(36)),
              child: SizedBox(height: widget.height, child: pageView),
            ),
      if (list.length > 1)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(list.length, (idx) {
              return AnimatedContainer(
                duration: AppMotion.scaled(context, AppMotion.medium),
                margin: const EdgeInsets.symmetric(horizontal: 3),
                height: 5,
                width: _page == idx ? 22 : 5,
                decoration: BoxDecoration(
                  color: _page == idx ? AppDesignTokens.gold : AppDesignTokens.textCream.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(3),
                ),
              );
            }),
          ),
        ),
    ]);
  }

  Widget _buildItem(Movie movie) {
    final logoUrl = widget.logos[movie.id];
    final released = heroIsReleased(movie);
    final backdropUrl = movie.backdropPath != null
        ? heroImageUrl(movie.backdropPath, size: 'w1280')
        : movie.posterUrl;
    return Semantics(
      label: movie.title,
      button: true,
      child: GestureDetector(
        key: ValueKey('hero_card_${movie.mediaType}_${movie.id}'),
        behavior: HitTestBehavior.opaque,
        onTap: () => widget.onOpen(movie),
        child: Stack(fit: StackFit.expand, children: [
          CachedNetworkImage(
            imageUrl: backdropUrl,
            fit: BoxFit.cover,
            alignment: Alignment.topCenter,
            memCacheWidth: 1920,
            memCacheHeight: 1080,
            placeholder: (_, _) => Container(color: const Color(0xFF121212)),
            errorWidget: (_, _, _) => Container(color: Colors.grey[900]),
          ),
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.transparent,
                  Colors.transparent,
                  Colors.black.withValues(alpha: 0.15),
                  Colors.black.withValues(alpha: 0.55),
                  const Color(0xFF0A0A0A),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: const [0.0, 0.28, 0.55, 0.82, 1.0],
              ),
            ),
          ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            height: 100,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppDesignTokens.gold.withValues(alpha: 0.05),
                    Colors.transparent,
                  ],
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                ),
              ),
            ),
          ),
          Positioned(
            left: 28,
            right: 28,
            bottom: 40,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              SizedBox(
                height: 70,
                child: AdaptiveLogoTitle(
                  title: movie.title.toUpperCase(),
                  titleStyle: _heroTitleStyle,
                  logoUrl: logoUrl,
                  height: 70,
                  maxLogoWidth: double.infinity,
                  alignment: Alignment.center,
                  expandTitleToFullWidth: true,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    _pill((widget.isTvMap[movie.id] == true ||
                            movie.mediaType == 'tv')
                        ? 'TV Series'
                        : 'Movie'),
                    _pill(movie.releaseYear.isNotEmpty
                        ? movie.releaseYear
                        : '2026'),
                    if (movie.voteAverage > 0)
                      _pill('★ ${movie.voteAverage.toStringAsFixed(1)}',
                          gold: true),
                    if (!released) _pill('Coming Soon', gold: true),
                  ]),
              const SizedBox(height: 16),
              // Matches uploaded design: soft white pill "View Details"
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    widget.onOpen(movie);
                  },
                  borderRadius: BorderRadius.circular(28),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 28, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(28),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.35),
                          blurRadius: 16,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: const Text(
                      'View Details',
                      style: TextStyle(
                        color: Colors.black,
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  static const TextStyle _heroTitleStyle = TextStyle(
    color: Colors.white,
    fontSize: 28,
    fontWeight: FontWeight.w900,
    letterSpacing: 1.5,
    height: 1.1,
    shadows: [
      Shadow(color: Colors.black45, blurRadius: 12, offset: Offset(0, 4)),
    ],
  );

  Widget _pill(String label, {bool gold = false}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: gold
              ? AppDesignTokens.gold.withValues(alpha: 0.2)
              : Colors.black.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: gold
                ? AppDesignTokens.gold.withValues(alpha: 0.4)
                : Colors.white.withValues(alpha: 0.1),
            width: 0.8,
          ),
        ),
        child: Text(label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                color: gold
                    ? AppDesignTokens.gold
                    : AppDesignTokens.textCream.withValues(alpha: 0.7),
                fontSize: 11,
                fontWeight: FontWeight.w600)),
      ),
    );
  }

}
