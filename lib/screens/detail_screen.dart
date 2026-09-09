import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/movie.dart';
import '../models/cast_member.dart';
import '../services/font_service.dart';
import '../services/review_service.dart';
import '../services/user_library_service.dart';
import '../services/addon_repository.dart';
import '../services/addon_playback.dart';
import '../services/debrid_resolver.dart';
import '../widgets/animated_toggle_icon.dart';
import '../widgets/available_downloads_sheet.dart';
import '../widgets/add_to_list_sheet.dart';
import '../widgets/server_selector_sheet.dart';
import '../screens/custom_player_screen.dart';
import '../services/app_settings_service.dart';
import '../services/web_view_scraper.dart';
import '../design/tokens.dart';
import '../design/motion.dart';
import '../widgets/app_card.dart';
import '../widgets/app_button.dart';
import '../widgets/app_chip.dart';
import '../widgets/poster_card.dart';
import '../services/tmdb_details_service.dart';
import '../services/tmdb_service.dart';
import '../navigation/app_navigator.dart';

const _gold = AppDesignTokens.goldMuted;
const _accentBlue = Color(0xFF6EA8FF);
const _bg = AppDesignTokens.backgroundCanvas;
const _card = AppDesignTokens.surfaceElevated;

class RatingSource {
  final String name;
  final String logo;
  final double score;
  final double outOf;
  final int votes;
  const RatingSource({
    required this.name,
    this.logo = '',
    required this.score,
    required this.outOf,
    required this.votes,
  });
}

/// Snapshot of the background stream-availability probe.
/// `unavailableReason` distinguishes "not released yet" (show Coming Soon +
/// countdown) from "released but servers dead" (show Unavailable + Retry).
class _AvailabilityState {
  final bool isAvailable;
  final bool checking;
  final String? probeEmbedUrl;
  final bool probeDone;
  final String? unavailableReason; // 'unreleased' | 'probe'
  final int probeAttempt;
  const _AvailabilityState({
    this.isAvailable = true,
    this.checking = false,
    this.probeEmbedUrl,
    this.probeDone = false,
    this.unavailableReason,
    this.probeAttempt = 0,
  });
  _AvailabilityState copyWith({
    bool? isAvailable,
    bool? checking,
    String? probeEmbedUrl,
    bool clearProbeEmbedUrl = false,
    bool? probeDone,
    String? unavailableReason,
    bool clearReason = false,
    int? probeAttempt,
  }) {
    return _AvailabilityState(
      isAvailable: isAvailable ?? this.isAvailable,
      checking: checking ?? this.checking,
      probeEmbedUrl:
          clearProbeEmbedUrl ? null : (probeEmbedUrl ?? this.probeEmbedUrl),
      probeDone: probeDone ?? this.probeDone,
      unavailableReason:
          clearReason ? null : (unavailableReason ?? this.unavailableReason),
      probeAttempt: probeAttempt ?? this.probeAttempt,
    );
  }
}

/// 30-minute in-memory cache of probe results → repeat opens resolve
/// instantly without mounting the hidden WebView.
class _ProbeCache {
  static final Map<String, MapEntry<bool, int>> _store = {};
  static const _ttlMs = 30 * 60 * 1000;
  static bool? get(String key) {
    final e = _store[key];
    if (e == null) return null;
    if (DateTime.now().millisecondsSinceEpoch - e.value > _ttlMs) {
      _store.remove(key);
      return null;
    }
    return e.key;
  }

  static void put(String key, bool available) {
    _store[key] =
        MapEntry(available, DateTime.now().millisecondsSinceEpoch);
  }

  static void invalidate(String key) => _store.remove(key);
}

class StudioInfo {
  final String name;
  final String logoUrl;
  const StudioInfo({required this.name, this.logoUrl = ''});
}

class Review {
  final String username;
  final DateTime date;
  final double rating;
  final String body;
  final bool containsSpoilers;
  int upvotes;
  Review({
    required this.username,
    required this.date,
    required this.rating,
    required this.body,
    this.containsSpoilers = false,
    this.upvotes = 0,
  });
}

enum _ActionVisual { filled, outline, neutral }

class DetailScreen extends StatefulWidget {
  final Movie movie;
  final bool isTv;
  final List<RatingSource>? ratingSources;
  final List<StudioInfo>? studios;
  final List<String>? tags;
  final List<String>? audience;
  final List<Review>? reviews;
  const DetailScreen({
    super.key,
    required this.movie,
    this.isTv = false,
    this.ratingSources,
    this.studios,
    this.tags,
    this.audience,
    this.reviews,
  });
  @override
  State<DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends State<DetailScreen>
    with TickerProviderStateMixin {
  bool _isLoading = true;
  bool _isPlayingTrailer = false;
  bool _isTrailerMuted = false;
  bool _showAllCast = false;
  bool _overviewExpanded = false;
  bool _hasTrailer = false;
  bool _suppressAutoTrailer = false;
  int? _selectedSeason;
  List<Map<String, dynamic>> _seasons = [];
  List<Map<String, dynamic>> _episodes = [];
  bool _loadingEpisodes = false;
  List<Movie> _similarMovies = [];
  List<Movie> _directorMovies = [];
  List<CastMember> _cast = [];
  String? _trailerKey;
  String? _logoUrl;
  String? _heroImageUrl;
  String? _directorName;
  String? _directorPhoto;
  int? _directorId;
  String _parentalRating = '';
  String _runtime = '';
  String _genres = '';
  String _countries = '';
  String _mediaLabel = 'Movie';
  String _releaseDateValue = '';
  late List<RatingSource> _ratings;
  late List<String> _tags;
  late List<String> _audience;
  List<StudioInfo> _studios = [];
  bool _showAllStudios = false;
  YoutubePlayerController? _ytController;
  Timer? _autoPlayTimer;
  Timer? _trailerWatchdog;
  final ValueNotifier<double> _topBarProgress = ValueNotifier<double>(0.0);
  late final ScrollController _scrollController;
  late final AnimationController _fadeCtrl;
  late final AnimationController _slideCtrl;
  late final AnimationController _actionsPulseCtrl;
  late final Animation<double> _fadeAnim;
  late final Animation<Offset> _slideAnim;
  int _trailerGeneration = 0;
  bool _isDisposing = false;
  final TmdbDetailsService _tmdbService = TmdbDetailsService();
  final TmdbService _tmdbListService = TmdbService();
  final ValueNotifier<_AvailabilityState> _availability =
      ValueNotifier(const _AvailabilityState());
  String _probeCacheKey = '';
  int _episodeRequestId = 0;
  bool _isOpeningSheet = false;

  bool get _isTv => widget.isTv || widget.movie.mediaType == 'tv';

  Movie get _libraryMovie {
    final m = widget.movie;
    final type = _isTv ? 'tv' : 'movie';
    if (m.mediaType == type) return m;
    return Movie(
      id: m.id,
      title: m.title,
      posterPath: m.posterPath,
      backdropPath: m.backdropPath,
      overview: m.overview,
      voteAverage: m.voteAverage,
      releaseDate: m.releaseDate,
      mediaType: type,
    );
  }

  String get _heroTag =>
      'poster-${_libraryMovie.mediaType}-${_libraryMovie.id}';

  @override
  void initState() {
    super.initState();
    _ratings = widget.ratingSources ?? _fallbackRatings();
    _tags = widget.tags ?? const [];
    _audience = widget.audience ?? const [];
    _mediaLabel = _isTv ? 'Series' : 'Movie';
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: AppMotion.medium,
    );
    _slideCtrl = AnimationController(
      vsync: this,
      duration: AppMotion.medium,
    );
    _actionsPulseCtrl = AnimationController(
      vsync: this,
      duration: AppMotion.slow,
    )..repeat(reverse: true);
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.025),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _slideCtrl, curve: Curves.easeOutCubic));
    _scrollController = ScrollController()..addListener(_onScroll);
    _loadAllMetadata();
    _primeAvailabilityFromReleaseDate();
    // Kick off the stream-availability probe (cache fast-path, else the
    // hidden WebView). Without this the action area would assume the title
    // is playable and never surface Unavailable / Coming Soon states.
    _checkAvailability();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _rescaleAnimations();
    });
  }

  void _rescaleAnimations() {
    if (!mounted) return;
    _fadeCtrl.duration = AppMotion.scaled(context, AppMotion.medium);
    _slideCtrl.duration = AppMotion.scaled(context, AppMotion.medium);
    _actionsPulseCtrl.duration = AppMotion.scaled(context, AppMotion.slow);
  }

  bool _isWide() {
    final size = MediaQuery.of(context).size;
    return size.width > size.height && size.width >= 640;
  }

  void _onScroll() {
    if (!mounted) return;
    if (_isWide()) {
      if (_topBarProgress.value != 0) _topBarProgress.value = 0;
      return;
    }
    final size = MediaQuery.of(context).size;
    final heroHeight = size.height * 0.52;
    final threshold = (heroHeight - 120).clamp(60.0, heroHeight);
    final progress = (_scrollController.offset / threshold).clamp(0.0, 1.0);
    if (_topBarProgress.value != progress) {
      _topBarProgress.value = progress;
    }
  }

  List<RatingSource> _fallbackRatings() => [
        RatingSource(
          name: 'TMDB',
          score: widget.movie.voteAverage,
          outOf: 10,
          votes: 0,
        ),
        RatingSource(
          name: 'IMDb',
          score: (widget.movie.voteAverage * 0.95).clamp(0, 10),
          outOf: 10,
          votes: 0,
        ),
      ];

  Future<void> _loadAllMetadata() async {
    try {
      final tmdbId = widget.movie.id;

      // The main detail response already asks TMDB for credits, release dates,
      // and content ratings. Reuse that payload instead of issuing a second
      // credits request during startup.
      final critical = await Future.wait<dynamic>([
        _tmdbService.getMovieDetails(tmdbId, isTv: _isTv),
        _tmdbService.getMovieLogo(tmdbId, isTv: _isTv),
        _tmdbService.getTextlessPoster(tmdbId, isTv: _isTv),
      ]);

      if (!mounted) return;

      Map<String, dynamic>? details = critical[0] is Map
          ? Map<String, dynamic>.from(critical[0] as Map)
          : null;
      final logo = critical[1] as String?;
      final textlessPoster = critical[2] as String?;

      List<CastMember> cast = _parseCastFromDetails(details);
      Map<String, dynamic>? director = _parseDirectorFromDetails(details);

      // Resilience fallback: if the worker returned a reduced detail payload,
      // use the dedicated endpoints instead of leaving actors/director blank.
      if (cast.isEmpty) {
        try {
          cast = await _tmdbService.getCast(tmdbId, isTv: _isTv);
        } catch (_) {}
      }
      if (director == null) {
        try {
          director = await _tmdbService.getDirector(tmdbId, isTv: _isTv);
        } catch (_) {}
      }

      String? dirName = director?['name'] as String?;
      String? dirPhoto;
      final profilePath = director?['profile_path'] as String?;
      if (profilePath != null && profilePath.isNotEmpty) {
        dirPhoto = 'https://image.tmdb.org/t/p/w185$profilePath';
      }
      final dirId = (director?['id'] as num?)?.toInt();

      final parental =
          _tmdbService.extractParentalRating(details, isTv: _isTv) ?? '';
      final runtime = _tmdbService.formatRuntime(details, isTv: _isTv);
      final genres = _tmdbService.formatGenres(details);
      final countries = _tmdbService.formatCountries(details);

      final releaseDate = _firstNonEmpty([
        details?['release_date'],
        details?['first_air_date'],
        widget.movie.releaseDate,
      ]);

      final parsedSeasons = <Map<String, dynamic>>[];
      if (_isTv && details?['seasons'] is List) {
        for (final item in details!['seasons'] as List) {
          if (item is! Map) continue;
          final season = Map<String, dynamic>.from(item);
          final seasonNumber = (season['season_number'] as num?)?.toInt() ?? 0;
          if (seasonNumber > 0) parsedSeasons.add(season);
        }
      }

      final voteCount = (details?['vote_count'] as num?)?.toInt() ?? 0;
      final voteAvg = (details?['vote_average'] as num?)?.toDouble() ??
          widget.movie.voteAverage;

      final studios = <StudioInfo>[];
      if (details?['production_companies'] is List) {
        for (final company in details!['production_companies'] as List) {
          if (company is! Map) continue;
          final map = Map<String, dynamic>.from(company);
          final name = (map['name'] ?? '').toString().trim();
          if (name.isEmpty) continue;
          final logoPath = map['logo_path'] as String?;
          studios.add(StudioInfo(
            name: name,
            logoUrl: logoPath != null && logoPath.isNotEmpty
                ? 'https://image.tmdb.org/t/p/w200$logoPath'
                : '',
          ));
        }
      }

      setState(() {
        _cast = cast;
        _logoUrl = logo;
        _heroImageUrl = textlessPoster ??
            (widget.movie.posterUrl.isNotEmpty
                ? widget.movie.posterUrl
                : (widget.movie.backdropUrl ?? ''));
        _directorName = dirName;
        _directorPhoto = dirPhoto;
        _directorId = dirId;
        _parentalRating =
            parental.isNotEmpty ? parental : (_isTv ? 'TV-14' : 'NR');
        _runtime = runtime;
        _genres = genres.isNotEmpty ? genres : '—';
        _countries = countries.isNotEmpty ? countries : '—';
        _releaseDateValue = releaseDate;
        _seasons = parsedSeasons;
        if (_isTv && _seasons.isNotEmpty && _selectedSeason == null) {
          _selectedSeason =
              (_seasons[0]['season_number'] as num?)?.toInt();
        }
        _ratings = [
          RatingSource(
            name: 'TMDB',
            score: voteAvg,
            outOf: 10,
            votes: voteCount,
          ),
          RatingSource(
            name: 'IMDb',
            score: (voteAvg * 0.95).clamp(0, 10),
            outOf: 10,
            votes: voteCount,
          ),
          RatingSource(
            name: 'Letterboxd',
            score: (voteAvg / 2).clamp(0, 5),
            outOf: 5,
            votes: voteCount,
          ),
        ];
        _studios = studios;
        _isLoading = false;
      });

      _fadeCtrl.forward();
      _slideCtrl.forward();

      if (_isTv && _selectedSeason != null) {
        _loadEpisodesForSeason(_selectedSeason!);
      }
      if (dirId != null) _loadDirectorFilmography(dirId);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _loadSecondaryMetadata(tmdbId);
      });
    } catch (_) {
      if (mounted) {
        setState(() => _isLoading = false);
        _fadeCtrl.forward();
        _slideCtrl.forward();
      }
    }
  }

  String _firstNonEmpty(Iterable<dynamic> values) {
    for (final value in values) {
      final text = value?.toString().trim() ?? '';
      if (text.isNotEmpty && text != 'null') return text;
    }
    return '';
  }

  List<CastMember> _parseCastFromDetails(Map<String, dynamic>? details) {
    final credits = details?['credits'];
    if (credits is! Map) return [];
    final raw = credits['cast'];
    if (raw is! List) return [];

    final result = <CastMember>[];
    for (final item in raw) {
      if (item is! Map) continue;
      try {
        final map = Map<String, dynamic>.from(item);
        if (map['adult'] == true) continue;
        result.add(CastMember.fromJson(map));
      } catch (_) {}
    }
    return result;
  }

  Map<String, dynamic>? _parseDirectorFromDetails(
      Map<String, dynamic>? details) {
    if (details == null) return null;

    if (_isTv) {
      final creators = details['created_by'];
      if (creators is List) {
        for (final item in creators) {
          if (item is! Map) continue;
          final map = Map<String, dynamic>.from(item);
          if (map['adult'] == true) continue;
          final id = (map['id'] as num?)?.toInt();
          final name = map['name']?.toString().trim() ?? '';
          if (id != null && id > 0 && name.isNotEmpty) {
            return {
              'id': id,
              'name': name,
              'profile_path': map['profile_path'],
            };
          }
        }
      }
    }

    final credits = details['credits'];
    final crew = credits is Map ? credits['crew'] : null;
    if (crew is List) {
      for (final item in crew) {
        if (item is! Map) continue;
        final map = Map<String, dynamic>.from(item);
        if (map['adult'] == true) continue;
        final job = map['job']?.toString().toLowerCase().trim() ?? '';
        final id = (map['id'] as num?)?.toInt();
        final name = map['name']?.toString().trim() ?? '';
        if (job == 'director' && id != null && id > 0 && name.isNotEmpty) {
          return {
            'id': id,
            'name': name,
            'profile_path': map['profile_path'],
          };
        }
      }
    }
    return null;
  }

  Future<void> _loadSecondaryMetadata(int tmdbId) async {
    try {
      final results = await Future.wait([
        _tmdbService.getSimilarMovies(tmdbId, isTv: _isTv),
        _tmdbService.getTrailerKey(tmdbId, isTv: _isTv),
      ]);
      if (!mounted) return;
      final similar = (results[0] as List<Movie>)
          .where((m) => m.id != widget.movie.id)
          .take(14)
          .toList();
      final trailerKey = results[1] as String?;
      final hasTrailer = trailerKey != null && trailerKey.isNotEmpty;
      setState(() {
        _similarMovies = similar;
        _trailerKey = trailerKey;
        _hasTrailer = hasTrailer;
      });
      if (hasTrailer && !_suppressAutoTrailer && !_isDisposing) {
        _autoPlayTimer?.cancel();
        final gen = _trailerGeneration;
        _autoPlayTimer = Timer(const Duration(seconds: 3), () {
          if (!mounted ||
              _isDisposing ||
              gen != _trailerGeneration ||
              _isPlayingTrailer ||
              _suppressAutoTrailer) {
            return;
          }
          // Must still be looking at this detail screen.
          if (ModalRoute.of(context)?.isCurrent != true) return;
          _startTrailer();
        });
      }
    } catch (_) {}
  }

  Future<void> _loadEpisodesForSeason(int seasonNumber) async {
    final requestId = ++_episodeRequestId;
    if (!mounted) return;
    setState(() => _loadingEpisodes = true);
    try {
      List<Map<String, dynamic>> eps = [];
      try {
        eps =
            await _tmdbService.getSeasonEpisodes(widget.movie.id, seasonNumber);
      } catch (_) {
        eps = List.generate(10, (i) => {
              'episode_number': i + 1,
              'season_number': seasonNumber,
              'name': 'Episode ${i + 1}',
              'overview':
                  'Overview for episode ${i + 1} of season $seasonNumber.',
              'still_path': null,
            });
      }
      if (!mounted || requestId != _episodeRequestId) return;
      setState(() {
        _episodes = eps;
        _loadingEpisodes = false;
      });
    } catch (_) {
      if (!mounted || requestId != _episodeRequestId) return;
      setState(() {
        _episodes = [];
        _loadingEpisodes = false;
      });
    }
  }

  Future<void> _loadDirectorFilmography(int personId) async {
    try {
      final films = await _tmdbListService.getMoviesByDirector(personId);
      if (!mounted) return;
      setState(() {
        _directorMovies =
            films.where((m) => m.id != widget.movie.id).take(12).toList();
      });
    } catch (_) {}
  }

  String _buildPrimaryEmbedUrl({int season = 1, int episode = 1}) {
    final id = widget.movie.id;
    // Try VidFast first (most reliable), fall back to VidSrc embed path.
    return _isTv
        ? 'https://vidfast.vc/tv/$id/$season/$episode'
        : 'https://vidfast.vc/movie/$id';
  }

  void _primeAvailabilityFromReleaseDate() {
    final releaseDateStr = widget.movie.releaseDate;
    if (releaseDateStr.isEmpty) return;
    try {
      final releaseDate = DateTime.parse(releaseDateStr);
      final now = DateTime.now();
      if (releaseDate.isAfter(now)) {
        _availability.value = _availability.value.copyWith(
          isAvailable: false,
          checking: false,
          probeDone: true,
          unavailableReason: 'unreleased',
          clearProbeEmbedUrl: true,
        );
      }
    } catch (_) {}
  }

  // ── Availability: cache-first, reason-aware, faster ─────────────
  Future<void> _checkAvailability() async {
    final cur = _availability.value;
    if (cur.checking || cur.probeDone) return;
    if (!mounted) return;
    _availability.value = cur.copyWith(checking: true);

    // Fast path 1: officially unreleased → Coming Soon.
    final releaseDateStr = widget.movie.releaseDate;
    DateTime? releaseDate;
    if (releaseDateStr.isNotEmpty) {
      try {
        releaseDate = DateTime.parse(releaseDateStr);
      } catch (_) {}
    }
    final now = DateTime.now();
    if (releaseDate != null &&
        releaseDate.isAfter(now) &&
        !releaseDate.isAtSameMomentAs(now)) {
      _availability.value = _availability.value.copyWith(
        isAvailable: false,
        checking: false,
        probeDone: true,
        unavailableReason: 'unreleased',
        clearProbeEmbedUrl: true,
      );
      return;
    }

    // Fast path 2: cached probe result → instant, no WebView.
    _probeCacheKey =
        '${widget.movie.id}-${_isTv ? 'tv' : 'm'}-${_selectedSeason ?? 1}';
    final cached = _ProbeCache.get(_probeCacheKey);
    if (cached != null) {
      _availability.value = _availability.value.copyWith(
        isAvailable: cached,
        checking: false,
        probeDone: true,
        unavailableReason: cached ? null : 'probe',
        clearReason: cached,
        clearProbeEmbedUrl: true,
      );
      return;
    }

    // Probe path (6s timeout instead of 10s).
    _availability.value = _availability.value.copyWith(
        probeEmbedUrl:
            _buildPrimaryEmbedUrl(season: _selectedSeason ?? 1, episode: 1));
  }

  void _onAvailabilityProbeSuccess(ExtractedStreamData data) {
    if (!mounted || _availability.value.probeDone) return;
    if (_probeCacheKey.isNotEmpty) _ProbeCache.put(_probeCacheKey, true);
    _availability.value = _availability.value.copyWith(
      isAvailable: true,
      checking: false,
      probeDone: true,
      clearReason: true,
      clearProbeEmbedUrl: true,
    );
  }

  void _onAvailabilityProbeError(String message) {
    if (!mounted || _availability.value.probeDone) return;
    if (_probeCacheKey.isNotEmpty) _ProbeCache.put(_probeCacheKey, false);
    _availability.value = _availability.value.copyWith(
      isAvailable: false,
      checking: false,
      probeDone: true,
      unavailableReason: 'probe',
      clearProbeEmbedUrl: true,
    );
  }

  void _retryAvailability() {
    if (!mounted) return;
    HapticFeedback.mediumImpact();
    if (_probeCacheKey.isNotEmpty) _ProbeCache.invalidate(_probeCacheKey);
    _availability.value = _AvailabilityState(
      checking: true,
      probeAttempt: _availability.value.probeAttempt + 1,
      probeEmbedUrl:
          _buildPrimaryEmbedUrl(season: _selectedSeason ?? 1, episode: 1),
    );
  }

  // ── Trailer ───────────────────────────────────────────────────
  void _startTrailer() {
    final key = _trailerKey;
    if (key == null || key.isEmpty || !mounted || _isDisposing) {
      if (key == null || key.isEmpty) _toast('No trailer available');
      return;
    }
    HapticFeedback.mediumImpact();
    _autoPlayTimer?.cancel();
    _autoPlayTimer = null;
    _trailerGeneration++;
    final generation = _trailerGeneration;
    _disposeTrailerPlayer();
    final controller = YoutubePlayerController(
      initialVideoId: key,
      flags: const YoutubePlayerFlags(
        autoPlay: true,
        mute: true,
        enableCaption: false,
        hideControls: true,
        controlsVisibleAtStart: false,
        hideThumbnail: true,
        disableDragSeek: true,
        loop: false,
        showLiveFullscreenButton: false,
        forceHD: false,
        useHybridComposition: true,
      ),
    );
    controller.addListener(_trailerListener);
    setState(() {
      _ytController = controller;
      _isPlayingTrailer = true;
      _isTrailerMuted = true;
    });
    // Watchdog: a dead embed must never leave the player "stuck on",
    // which previously made Back look broken.
    _trailerWatchdog?.cancel();
    _trailerWatchdog = Timer(const Duration(seconds: 5), () {
      if (!mounted ||
          _isDisposing ||
          generation != _trailerGeneration ||
          !_isPlayingTrailer) {
        return;
      }
      final c = _ytController;
      if (c == null || !c.value.isReady) {
        _stopTrailer();
        _toast('Trailer could not be loaded');
      }
    });
    Future<void>.delayed(const Duration(milliseconds: 500), () {
      if (!mounted ||
          _isDisposing ||
          generation != _trailerGeneration ||
          !_isPlayingTrailer ||
          _ytController != controller) {
        return;
      }
      try {
        controller.play();
        controller.unMute();
        if (mounted &&
            generation == _trailerGeneration &&
            _ytController == controller) {
          setState(() => _isTrailerMuted = false);
        }
      } catch (_) {}
    });
  }

  void _trailerListener() {
    if (_ytController == null) return;
    if (_ytController!.value.playerState == PlayerState.ended) {
      _stopTrailer(suppressFutureAutoPlay: false);
    }
  }

  void _disposeTrailerPlayer() {
    final controller = _ytController;
    _ytController = null;
    if (controller == null) return;
    try {
      controller.removeListener(_trailerListener);
      controller.pause();
      controller.dispose();
    } catch (_) {}
  }

  void _stopTrailer({bool suppressFutureAutoPlay = true}) {
    _trailerGeneration++;
    _trailerWatchdog?.cancel();
    _autoPlayTimer?.cancel();
    _autoPlayTimer = null;
    if (suppressFutureAutoPlay) _suppressAutoTrailer = true;
    _disposeTrailerPlayer();
    if (!mounted || _isDisposing) return;
    setState(() {
      _isPlayingTrailer = false;
      _isTrailerMuted = false;
    });
  }

  void _toggleTrailerMute() {
    HapticFeedback.selectionClick();
    setState(() => _isTrailerMuted = !_isTrailerMuted);
    if (_ytController != null && _isPlayingTrailer) {
      if (_isTrailerMuted) {
        _ytController!.mute();
      } else {
        _ytController!.unMute();
        _ytController!.play();
      }
    }
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: const Color(0xFF1A1A1A),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // ── Library / share / nav ──────────────────────────────────────
  Future<void> _toggleBookmark() async {
    HapticFeedback.mediumImpact();
    try {
      final added =
          await UserLibraryService.instance.toggleWatchlist(_libraryMovie);
      if (!mounted) return;
      _toast(added
          ? '"${widget.movie.title}" added to Watchlist'
          : '"${widget.movie.title}" removed from Watchlist');
    } catch (e) {
      if (mounted) _toast('Could not update Watchlist');
    }
  }

  Future<void> _toggleWatched() async {
    HapticFeedback.mediumImpact();
    try {
      final added =
          await UserLibraryService.instance.toggleWatched(_libraryMovie);
      if (!mounted) return;
      _toast(added
          ? 'Marked "${widget.movie.title}" as watched'
          : 'Marked "${widget.movie.title}" as unwatched');
    } catch (e) {
      if (mounted) _toast('Could not update Watched');
    }
  }

  Future<void> _toggleLiked() async {
    HapticFeedback.mediumImpact();
    try {
      final added =
          await UserLibraryService.instance.toggleLiked(_libraryMovie);
      if (!mounted) return;
      _toast(added ? 'Added to Liked titles' : 'Removed from Liked titles');
    } catch (e) {
      if (mounted) _toast('Could not update Liked');
    }
  }

  Future<void> _addToList() async {
    HapticFeedback.selectionClick();
    await AddToListSheet.show(context, _libraryMovie);
  }

  void _showStreamDownloadOptions({required bool isDownload, int? season, int? episode}) {
    if (_isOpeningSheet) return;
    _isOpeningSheet = true;
    HapticFeedback.mediumImpact();
    _stopTrailer(suppressFutureAutoPlay: true);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black54,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      builder: (sheetContext) => _SourceEpisodeSheet(
        isTv: _isTv,
        isDownload: isDownload,
        seasons: _seasons,
        episodes: _episodes,
        selectedSeason: season ?? _selectedSeason ?? 1,
        selectedEpisode: episode,
        onSelect: (source, s, ep, downloadEntireSeason) {
          Navigator.pop(sheetContext);
          _isOpeningSheet = false;
          if (source == 'addon') {
            if (isDownload) {
              _openDownloadSheet(season: s, episode: ep);
            } else {
              _streamWithAddon(season: s, episode: ep);
            }
          } else {
            if (isDownload) {
              if (downloadEntireSeason && _isTv) {
                _downloadEntireSeason(s);
              } else {
                _openDownloadSheet(season: s, episode: ep);
              }
            } else {
              _openServerSelector(season: s, episode: ep);
            }
          }
        },
        onUseAddon: (source, s, ep) {
          Navigator.pop(sheetContext);
          _isOpeningSheet = false;
          if (isDownload) {
            _openDownloadSheet(season: s, episode: ep);
          } else {
            _streamWithAddon(season: s, episode: ep);
          }
        },
      ),
    ).whenComplete(() {
      if (mounted) {
        Future.delayed(const Duration(milliseconds: 100), () {
          if (mounted) _isOpeningSheet = false;
        });
      }
    });
  }

  Future<void> _streamWithAddon({int? season, int? episode}) async {
    HapticFeedback.mediumImpact();
    _stopTrailer(suppressFutureAutoPlay: true);

    final s = season ?? _selectedSeason ?? 1;
    final ep = episode ?? 1;

    final status = ValueNotifier<String>('Finding streams...');

    unawaited(
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => _AddonLoadingOverlay(
            backdropUrl: widget.movie.backdropUrl ?? widget.movie.posterUrl,
            subtitle: status,
          ),
        ),
      ),
    );

    try {
      final manifests = AddonRepository.instance.addons
          .where((a) => a.isActive && a.manifest != null)
          .map((a) => a.manifest!)
          .toList();

      if (manifests.isEmpty) {
        if (mounted) Navigator.pop(context);
        _toast('No addons installed. Add addons in Settings.');
        return;
      }

      final sources = await resolveAddonStreamsForContent(
        manifests: manifests,
        tmdbId: widget.movie.id.toString(),
        mediaType: _isTv ? 'tv' : 'movie',
        season: _isTv ? s : null,
        episode: _isTv ? ep : null,
      );

      if (!mounted) return;
      Navigator.pop(context);

      if (sources.isEmpty) {
        _toast('No streams found from addons. Try server source.');
        return;
      }

      AddonPlaybackSource? resolvedBest;
      String? streamUrl;
      String? externalUrl;
      String? lastFailureMessage;

       for (final source in sources) {
         final direct = source.stream.playableDirectUrl;
         if (direct != null && direct.isNotEmpty) {
           resolvedBest = source;
           streamUrl = direct;
           break;
         }
         if (source.stream.isTorrent) {
           final ssUrl = source.stream.streamingServerUrl(
             AppSettingsService.instance.streamingServerUrl,
           );
           if (ssUrl != null && ssUrl.isNotEmpty) {
             resolvedBest = source;
             streamUrl = ssUrl;
             break;
           }
           status.value = 'Resolving via debrid...';
           final result = await resolveAddonStreamTorrent(
             stream: source.stream,
             season: _isTv ? s : null,
             episode: _isTv ? ep : null,
           );
           if (result.success && result.url != null) {
             resolvedBest = source;
             streamUrl = result.url;
             break;
           }
           lastFailureMessage = result.failureMessage;
           continue;
         }
         final ext = source.stream.openExternalUrl;
         if (ext != null && ext.isNotEmpty) {
           resolvedBest = source;
           externalUrl = ext;
           break;
         }
       }

      if (!mounted) return;
      // Navigator.pop(context); // already popped above

      if (resolvedBest == null) {
        _toast(lastFailureMessage?.isNotEmpty == true
            ? lastFailureMessage!
            : 'No playable streams found from addons.');
        return;
      }

      if (externalUrl != null && (streamUrl == null || streamUrl.isEmpty)) {
        await launchUrl(Uri.parse(externalUrl), mode: LaunchMode.externalApplication);
        return;
      }

      if (streamUrl != null && streamUrl.isNotEmpty) {
        if (!mounted) return;
        Navigator.push(
          context,
          PageRouteBuilder(
            transitionDuration: AppMotion.scaled(context, AppMotion.medium),
            pageBuilder: (_, _, _) => CustomPlayerScreen(
              streamUrl: streamUrl!,
              title: widget.movie.title,
              tmdbId: widget.movie.id.toString(),
              mediaType: _isTv ? 'tv' : 'movie',
              season: s,
              episode: ep,
              wisoApiKey: '',
              servers: const [],
              initialServerName: 'Addon',
              headers: const {},
            ),
            transitionsBuilder: (_, animation, _, child) {
              return FadeTransition(opacity: animation, child: child);
            },
          ),
        );
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
      _toast('Failed to load addon streams.');
    }
  }

  void _downloadEntireSeason(int season) {
    final seasonData = _seasons.firstWhere(
      (s) => (s['season_number'] as int? ?? 0) == season,
      orElse: () => {'name': 'Season $season', 'episode_count': 0},
    );
    final episodeCount = (seasonData['episode_count'] as int?) ?? 0;
    _toast('Queuing Season $season ($episodeCount episodes) for download...');
  }

  void _openServerSelector({int? season, int? episode}) {
    if (_isOpeningSheet) return;
    _isOpeningSheet = true;
    HapticFeedback.mediumImpact();
    _stopTrailer(suppressFutureAutoPlay: true);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.78,
      ),
      builder: (_) => ServerSelectorSheet(
        tmdbId: widget.movie.id.toString(),
        movieTitle: widget.movie.title,
        mediaType: _isTv ? 'tv' : 'movie',
        season: season ?? _selectedSeason ?? 1,
        episode: episode ?? 1,
      ),
    );
    Future.delayed(const Duration(milliseconds: 600), () {
      _isOpeningSheet = false;
    });
  }

  void _openDownloadSheet({int? season, int? episode}) {
    if (_isOpeningSheet) return;
    _isOpeningSheet = true;
    HapticFeedback.mediumImpact();
    _stopTrailer(suppressFutureAutoPlay: true);
    AvailableDownloadsSheet.show(
      context,
      movieTitle: widget.movie.title,
      tmdbId: widget.movie.id.toString(),
      posterUrl: widget.movie.posterUrl,
      mediaType: _isTv ? 'tv' : 'movie',
      season: season ?? _selectedSeason ?? 1,
      episode: episode ?? 1,
      // Every entry point here already knows exactly which episode it
      // wants (either explicitly, or via the season/episode-1 default
      // above) — the sheet's TV flow preselects this episode and jumps
      // straight to its quality list.
    );
    Future.delayed(const Duration(milliseconds: 600), () {
      _isOpeningSheet = false;
    });
  }

  void _shareMovie() {
    HapticFeedback.lightImpact();
    Clipboard.setData(ClipboardData(
        text: 'https://www.themoviedb.org/${_isTv ? 'tv' : 'movie'}/${widget.movie.id}'));
    _toast('Share link for "${widget.movie.title}" copied');
  }

  void _openActor(CastMember actor) {
    HapticFeedback.lightImpact();
    // Never let the trailer keep playing under the actor screen.
    _stopTrailer(suppressFutureAutoPlay: true);
    AppNavigator.openActor(context, actor.id);
  }

  void _openDirector() {
    if (_directorId == null) return;
    HapticFeedback.lightImpact();
    _stopTrailer(suppressFutureAutoPlay: true);
    AppNavigator.openActor(context, _directorId!);
  }

  Future<void> _rateTitle(int stars) async {
    HapticFeedback.mediumImpact();
    await ReviewService.instance.setRating(
      widget.movie.id,
      stars.toDouble(),
      mediaType: _libraryMovie.mediaType,
    );
    _toast('You rated this $stars/5');
  }

  void _openPostReview() {
    HapticFeedback.selectionClick();
    final controller = TextEditingController();
    bool spoilers = false;
    double rating = ReviewService.instance.getRating(
              widget.movie.id, mediaType: _libraryMovie.mediaType) ==
          0
        ? 3
        : ReviewService.instance
            .getRating(widget.movie.id, mediaType: _libraryMovie.mediaType);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: _card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(context).viewInsets.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Write a review',
                  style: FontService.instance.display(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 14),
              Row(
                children: List.generate(5, (i) {
                  return IconButton(
                    onPressed: () =>
                        setSheetState(() => rating = (i + 1).toDouble()),
                    icon: Icon(
                        i < rating
                            ? Icons.star_rounded
                            : Icons.star_border_rounded,
                        color: _gold),
                  );
                }),
              ),
              TextField(
                controller: controller,
                maxLines: 4,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'What did you think?',
                  hintStyle: const TextStyle(color: Colors.white38),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.06),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
                onChanged: (_) => setSheetState(() {}),
              ),
              const SizedBox(height: 8),
              Row(children: [
                Checkbox(
                  value: spoilers,
                  activeColor: _gold,
                  onChanged: (v) => setSheetState(() => spoilers = v ?? false),
                ),
                const Text('Contains spoilers',
                    style: TextStyle(color: Colors.white70)),
              ]),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                height: 46,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _gold,
                    foregroundColor: Colors.black,
                    shape: const StadiumBorder(),
                  ),
                  onPressed: controller.text.trim().isEmpty
                      ? null
                      : () async {
                          await ReviewService.instance.addReview(
                            tmdbId: widget.movie.id,
                            body: controller.text.trim(),
                            rating: rating,
                            mediaType: _libraryMovie.mediaType,
                            containsSpoilers: spoilers,
                          );
                          if (sheetContext.mounted) Navigator.pop(sheetContext);
                          _toast('Review posted');
                        },
                  child: const Text('Post review',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _isDisposing = true;
    _trailerGeneration++;
    _autoPlayTimer?.cancel();
    _autoPlayTimer = null;
    _trailerWatchdog?.cancel();
    _suppressAutoTrailer = true;
    _disposeTrailerPlayer();
    _availability.value =
        _availability.value.copyWith(probeDone: true, clearProbeEmbedUrl: true);
    _availability.dispose();
    _fadeCtrl.dispose();
    _slideCtrl.dispose();
    _actionsPulseCtrl.dispose();
    _scrollController.dispose();
    _topBarProgress.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (mounted) {
      _fadeCtrl.duration = AppMotion.scaled(context, AppMotion.medium);
      _slideCtrl.duration = AppMotion.scaled(context, AppMotion.medium);
      _actionsPulseCtrl.duration = AppMotion.scaled(context, AppMotion.slow);
    }
  }

  // ── Date helpers ───────────────────────────────────────────────
  static const List<String> _monthFull = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December'
  ];
  String _formatFullDate(String iso) {
    if (iso.isEmpty) return 'TBA';
    try {
      final dt = DateTime.parse(iso);
      return '${_monthFull[dt.month - 1]} ${dt.day}, ${dt.year}';
    } catch (_) {
      return iso;
    }
  }

  String? _daysUntilText(String iso) {
    if (iso.isEmpty) return null;
    try {
      final dt = DateTime.parse(iso);
      final now = DateTime.now();
      final target = DateTime(dt.year, dt.month, dt.day);
      final today = DateTime(now.year, now.month, now.day);
      final diff = target.difference(today).inDays;
      if (diff <= 0) return null;
      if (diff == 1) return 'Releases tomorrow';
      if (diff < 30) return 'Releases in $diff days';
      final months = (diff / 30).round();
      return 'Releases in $months ${months == 1 ? 'month' : 'months'}';
    } catch (_) {
      return null;
    }
  }

  // ═══════════════════════ BUILD (responsive) ═══════════════════════
  @override
  Widget build(BuildContext context) {
    final movie = widget.movie;
    final routeIsCurrent = ModalRoute.of(context)?.isCurrent ?? true;
    // Platform YouTube views ignore TickerMode — stop audio/video whenever
    // another screen (actor detail, sheets, etc.) is on top.
    if (!routeIsCurrent && (_isPlayingTrailer || _ytController != null)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (ModalRoute.of(context)?.isCurrent == true) return;
        _stopTrailer(suppressFutureAutoPlay: false);
      });
    }
    return PopScope(
      canPop: !_isPlayingTrailer,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_isPlayingTrailer) _stopTrailer();
      },
      child: TickerMode(
        enabled: routeIsCurrent,
        child: Scaffold(
          backgroundColor: _bg,
          body: Stack(
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth > constraints.maxHeight &&
                      constraints.maxWidth >= 640;
                  return wide
                      ? _buildWideLayout(constraints)
                      : _buildNarrowLayout(constraints);
                },
              ),
              _buildTopBar(movie.title),
              ValueListenableBuilder<_AvailabilityState>(
                valueListenable: _availability,
                builder: (context, avail, _) {
                  if (avail.probeEmbedUrl == null || avail.probeDone) {
                    return const SizedBox.shrink();
                  }
                  return Positioned(
                    left: -9999,
                    top: -9999,
                    width: 1,
                    height: 1,
                    child: RepaintBoundary(
                      child: Opacity(
                        opacity: 0.01,
                        child: WebViewScraper(
                          key: ValueKey(
                              'avail-probe-${widget.movie.id}-${avail.probeEmbedUrl}-${avail.probeAttempt}'),
                          embedUrl: avail.probeEmbedUrl!,
                          mediaType: _isTv ? 'tv' : 'movie',
                          season: _selectedSeason ?? 1,
                          episode: 1,
                          timeoutSeconds: 6,
                          debug: false,
                          onDataExtracted: _onAvailabilityProbeSuccess,
                          onError: _onAvailabilityProbeError,
                        ),
                      ),
                    ),
                  );
                },
              ),
              if (_isLoading)
                const Center(
                  child: CircularProgressIndicator(
                      color: _gold, strokeWidth: 2.5),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // Portrait / narrow: classic vertical scroll with collapsing bar.
  Widget _buildNarrowLayout(BoxConstraints c) {
    final heroH = c.maxHeight * 0.52;
    // Content pulls up over the poster so the transition is only a soft
    // gradient — no hard horizontal edge.
    const fadeOverlap = 96.0;
    return SingleChildScrollView(
      controller: _scrollController,
      physics: const BouncingScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: heroH,
            width: double.infinity,
            child: _buildHeroVisual(),
          ),
          Transform.translate(
            offset: const Offset(0, -fadeOverlap),
            child: _buildContentColumn(topPad: fadeOverlap * 0.55),
          ),
        ],
      ),
    );
  }

  // Landscape / tablet / desktop: hero pinned left, metadata scrolls right.
  Widget _buildWideLayout(BoxConstraints c) {
    final paneW = (c.maxWidth * 0.45).clamp(300.0, 620.0);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: paneW,
          height: c.maxHeight,
          child: _buildHeroVisual(),
        ),
        const VerticalDivider(width: 1, thickness: 1, color: Color(0xFF1E1E1E)),
        Expanded(
          child: SingleChildScrollView(
            controller: _scrollController,
            physics: const BouncingScrollPhysics(),
            child: _buildContentColumn(topPad: 16),
          ),
        ),
      ],
    );
  }

  // Hero artwork + trailer (shared by both layouts).
  Widget _buildHeroVisual() {
    final movie = widget.movie;
    return Stack(
      fit: StackFit.expand,
      children: [
        Hero(
          tag: _heroTag,
          // Fly ONLY the poster between routes — the YouTube platform
          // view must never enter a hero flight (black-frame / frozen
          // pop glitches).
          flightShuttleBuilder:
              (flightContext, animation, direction, fromContext, toContext) {
            return CachedNetworkImage(
              imageUrl: _heroImageUrl ??
                  (movie.posterUrl.isNotEmpty
                      ? movie.posterUrl
                      : (movie.backdropUrl ?? '')),
              fit: BoxFit.cover,
            );
          },
          child: _isPlayingTrailer && _ytController != null
              ? ClipRect(
                  child: Transform.scale(
                    scale: 1.42,
                    child: IgnorePointer(
                      child: YoutubePlayer(
                        controller: _ytController!,
                        showVideoProgressIndicator: false,
                        bottomActions: const [],
                        topActions: const [],
                        onReady: () {
                          try {
                            _ytController!.play();
                            Future.delayed(const Duration(milliseconds: 200),
                                () {
                              if (!mounted || _ytController == null) return;
                              try {
                                _ytController!.unMute();
                                setState(() => _isTrailerMuted = false);
                              } catch (_) {}
                            });
                          } catch (_) {}
                        },
                      ),
                    ),
                  ),
                )
              : CachedNetworkImage(
                  imageUrl: _heroImageUrl ??
                      (movie.posterUrl.isNotEmpty
                          ? movie.posterUrl
                          : (movie.backdropUrl ?? '')),
                  fit: BoxFit.cover,
                  alignment: Alignment.topCenter,
                  memCacheWidth: 600,
                  fadeInDuration: AppMotion.scaled(context, AppMotion.fast),
                  fadeInCurve: Curves.easeOut,
                  placeholder: (_, _) => Container(color: const Color(0xFF111111)),
                  errorWidget: (_, _, _) =>
                      Container(color: const Color(0xFF111111)),
                ),
        ),
        if (!_hasTrailer && !_isPlayingTrailer)
          const IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment.center,
                  radius: 1.2,
                  colors: [Color(0x0DFFB800), Colors.transparent],
                ),
              ),
            ),
          ),
        if (_isPlayingTrailer)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 110,
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFF000000), Color(0xFF000000), Color(0x00000000)],
                  stops: [0.0, 0.55, 1.0],
                ),
              ),
            ),
          ),
        if (_isPlayingTrailer)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            height: 110,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    _bg,
                    _bg.withValues(alpha: 0.85),
                    _bg.withValues(alpha: 0.4),
                    Colors.transparent,
                  ],
                  stops: const [0.0, 0.35, 0.7, 1.0],
                ),
              ),
            ),
          ),
        // Long, gentle dissolve — no ClipRect/BackdropFilter (those create
        // a visible straight edge). Poster melts into the page background.
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withValues(alpha: 0.20),
                Colors.transparent,
                Colors.transparent,
                _bg.withValues(alpha: 0.08),
                _bg.withValues(alpha: 0.22),
                _bg.withValues(alpha: 0.42),
                _bg.withValues(alpha: 0.65),
                _bg.withValues(alpha: 0.88),
                _bg,
              ],
              stops: const [
                0.0,
                0.22,
                0.42,
                0.55,
                0.66,
                0.76,
                0.86,
                0.94,
                1.0,
              ],
            ),
          ),
        ),
        // Title logo overlaid on the poster — stays visible during trailer too.
        if (_logoUrl != null && _logoUrl!.isNotEmpty)
          Positioned(
            left: 18,
            right: 18,
            bottom: 48,
            child: Align(
              alignment: Alignment.centerLeft,
              child: CachedNetworkImage(
                key: ValueKey('logo_${widget.movie.id}_$_logoUrl'),
                imageUrl: _logoUrl!,
                height: 64,
                width: 220,
                fit: BoxFit.contain,
                alignment: Alignment.centerLeft,
                memCacheHeight: 128,
                fadeInDuration: const Duration(milliseconds: 180),
                placeholder: (_, _) =>
                    const SizedBox(height: 64, width: 220),
                errorWidget: (_, _, _) => const SizedBox.shrink(),
              ),
            ),
          ),
      ],
    );
  }

  // Collapsing frosted top bar.
  Widget _buildTopBar(String title) {
    return ValueListenableBuilder<double>(
      valueListenable: _topBarProgress,
      builder: (context, progress, _) {
        final reduce = AppMotion.shouldReduceTransparency(context);
        return ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(
              sigmaX: reduce ? 0 : AppDesignTokens.glassBlurSheet * progress,
              sigmaY: reduce ? 0 : AppDesignTokens.glassBlurSheet * progress,
            ),
            child: Container(
              color:
                  _bg.withValues(alpha: reduce ? 0.98 : 0.82 * progress),
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      AppButton(
                        onPressed: () {
                          if (_isPlayingTrailer) {
                            _stopTrailer();
                          } else {
                            Navigator.maybePop(context);
                          }
                        },
                        variant: AppButtonVariant.ghost,
                        size: AppButtonSize.small,
                        padding: EdgeInsets.zero,
                        borderRadius: AppDesignTokens.radiusFull,
                        semanticLabel: 'Back',
                        child: _circleBtn(Icons.arrow_back_rounded),
                      ),
                      Expanded(
                        child: Opacity(
                          opacity: progress,
                          child: Text(
                            title,
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: FontService.instance.display(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_isPlayingTrailer) ...[
                            AppButton(
                              onPressed: () => _stopTrailer(),
                              variant: AppButtonVariant.ghost,
                              size: AppButtonSize.small,
                              padding: EdgeInsets.zero,
                              borderRadius: AppDesignTokens.radiusFull,
                              semanticLabel: 'Stop trailer',
                              child: _circleBtn(Icons.stop_rounded),
                            ),
                            const SizedBox(width: 8),
                            AppButton(
                              onPressed: _toggleTrailerMute,
                              variant: AppButtonVariant.ghost,
                              size: AppButtonSize.small,
                              padding: EdgeInsets.zero,
                              borderRadius: AppDesignTokens.radiusFull,
                              semanticLabel: _isTrailerMuted
                                  ? 'Unmute trailer'
                                  : 'Mute trailer',
                              child: AnimatedContainer(
                                duration: AppMotion.standardScaled(context),
                                width: 38,
                                height: 38,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: _isTrailerMuted
                                      ? Colors.black.withValues(alpha: 0.55)
                                      : AppDesignTokens.goldMuted.withValues(alpha: 0.25),
                                  border: Border.all(
                                    color: _isTrailerMuted
                                        ? Colors.white24
                                        : AppDesignTokens.goldMuted.withValues(alpha: 0.7),
                                  ),
                                ),
                                child: Icon(
                                  _isTrailerMuted
                                      ? Icons.volume_off_rounded
                                      : Icons.volume_up_rounded,
                                  color: _isTrailerMuted
                                      ? Colors.white
                                      : AppDesignTokens.goldMuted,
                                  size: 18,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                          ],
                          AppButton(
                            onPressed: _shareMovie,
                            variant: AppButtonVariant.ghost,
                            size: AppButtonSize.small,
                            padding: EdgeInsets.zero,
                            borderRadius: AppDesignTokens.radiusFull,
                            semanticLabel: 'Share',
                            child: _circleBtn(Icons.share_rounded),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // ═══════════════════════ CONTENT COLUMN ═══════════════════════
  Widget _buildContentColumn({double topPad = 0}) {
    final movie = widget.movie;
    final overview = (movie.overview != null && movie.overview!.isNotEmpty)
        ? movie.overview!
        : 'No overview available.';
    return FadeTransition(
      opacity: _fadeAnim,
      child: SlideTransition(
        position: _slideAnim,
        child: Center(
          child: ConstrainedBox(
            constraints:
                BoxConstraints(maxWidth: AppDesignTokens.contentWidth(context)),
            child: Padding(
              padding: EdgeInsets.fromLTRB(18, topPad, 18, 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Logo lives on the hero (with blur fade under it).
                  // Text title only when TMDB has no logo asset.
                  if (_logoUrl == null || _logoUrl!.isEmpty)
                    Text(
                      movie.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: FontService.instance.display(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        height: 1.15,
                      ),
                    ),
                  const SizedBox(height: 10),
                  _buildOverviewSection(overview),
                  const SizedBox(height: 14),
                  if (_genres.isNotEmpty && _genres != '—') ...[
                    Text(
                      _genres,
                      style: FontService.instance.label(
                        color: Colors.white54,
                        fontSize: 12,
                        letterSpacing: 0.2,
                      ),
                    ),
                    const SizedBox(height: 4),
                  ],
                  const SizedBox(height: 18),
                  ValueListenableBuilder<_AvailabilityState>(
                    valueListenable: _availability,
                    builder: (context, avail, _) {
                      return AnimatedSwitcher(
                        duration: AppMotion.scaled(context, AppMotion.medium),
                        transitionBuilder: (child, animation) => FadeTransition(
                          opacity: animation,
                          child: SlideTransition(
                            position: Tween<Offset>(
                              begin: const Offset(0.0, 0.1),
                              end: Offset.zero,
                            ).animate(CurvedAnimation(
                                parent: animation, curve: Curves.easeOutCubic)),
                            child: child,
                          ),
                        ),
                        child: avail.checking
                            ? KeyedSubtree(
                                key: const ValueKey('actions-loading'),
                                child: _buildActionsLoading())
                            : avail.isAvailable
                                ? KeyedSubtree(
                                    key: const ValueKey('actions-available'),
                                    child: _buildActionButtons())
                                : (avail.unavailableReason == 'unreleased'
                                    ? KeyedSubtree(
                                        key: const ValueKey('coming-soon'),
                                        child: _buildComingSoon())
                                    : KeyedSubtree(
                                        key: const ValueKey('unavailable'),
                                        child: _buildUnavailable())),
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  ListenableBuilder(
                    listenable: UserLibraryService.instance,
                    builder: (context, _) {
                      final lib = UserLibraryService.instance;
                      return Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          AnimatedToggleIcon(
                            active: lib.isInWatchlistMovie(_libraryMovie),
                            activeIcon: Icons.bookmark_rounded,
                            inactiveIcon: Icons.bookmark_add_outlined,
                            label: 'Watchlist',
                            onTap: _toggleBookmark,
                          ),
                          AnimatedToggleIcon(
                            active: lib.isWatchedMovie(_libraryMovie),
                            activeIcon: Icons.visibility_rounded,
                            inactiveIcon: Icons.visibility_outlined,
                            label: 'Watched',
                            onTap: _toggleWatched,
                          ),
                          AnimatedToggleIcon(
                            active: lib.isInMyListMovie(_libraryMovie),
                            activeIcon: Icons.playlist_add_check_rounded,
                            inactiveIcon: Icons.playlist_add_rounded,
                            label: 'List',
                            onTap: _addToList,
                          ),
                          AnimatedToggleIcon(
                            active: lib.isLikedMovie(_libraryMovie),
                            activeIcon: Icons.favorite_rounded,
                            inactiveIcon: Icons.favorite_border_rounded,
                            activeColor: Colors.redAccent,
                            label: 'Like',
                            onTap: _toggleLiked,
                          ),
                          AnimatedToggleIcon(
                            active: false,
                            activeIcon: Icons.ios_share_rounded,
                            inactiveIcon: Icons.ios_share_rounded,
                            label: 'Share',
                            onTap: _shareMovie,
                          ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 22),
                  _sectionTitle('Details'),
                  const SizedBox(height: 12),
                  _verticalInfoCard(),
                  if (_isTv) ...[
                    const SizedBox(height: 22),
                    _sectionTitle('Seasons & Episodes'),
                    const SizedBox(height: 12),
                    _buildSeasonSelector(),
                    const SizedBox(height: 14),
                    _buildEpisodeList(),
                  ],
                  if (_directorName != null) ...[
                    const SizedBox(height: 22),
                    _sectionTitle(_isTv ? 'Creator / Director' : 'Director'),
                    const SizedBox(height: 12),
                    GestureDetector(
                      onTap: _openDirector,
                      child: _personTile(
                        name: _directorName!,
                        role: _isTv ? 'Creator / Showrunner' : 'Director',
                        photoUrl: _directorPhoto,
                      ),
                    ),
                    if (_directorMovies.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      Text(
                        _isTv ? 'Also created / directed' : 'Also directed',
                        style: FontService.instance.label(
                            color: Colors.white54,
                            fontSize: 12,
                            letterSpacing: 0.3),
                      ),
                      const SizedBox(height: 10),
                      _buildDirectorRail(),
                    ],
                  ],
                  if (!_isLoading && _cast.isNotEmpty) ...[
                    const SizedBox(height: 22),
                    _sectionTitle('Actors'),
                    const SizedBox(height: 12),
                    RepaintBoundary(child: _buildActorsGrid()),
                  ],
                  if (_studios.isNotEmpty) ...[
                    const SizedBox(height: 22),
                    RepaintBoundary(child: _buildStudiosSection()),
                  ],
                  const SizedBox(height: 22),
                  _sectionTitle("How it's rated"),
                  const SizedBox(height: 12),
                  RepaintBoundary(child: _buildRatingsRow()),
                  const SizedBox(height: 22),
                  _buildReviewsSection(),
                  if (!_isLoading && _similarMovies.isNotEmpty) ...[
                    const SizedBox(height: 22),
                    _sectionTitle('More like this'),
                    const SizedBox(height: 12),
                    RepaintBoundary(child: _buildSimilarGrid()),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDirectorRail() {
    return SizedBox(
      height: 160,
      child: ListView.builder(
        scrollCacheExtent: ScrollCacheExtent.pixels(400),
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: _directorMovies.length,
        itemBuilder: (context, index) {
          final m = _directorMovies[index];
          return GestureDetector(
            onTap: () {
              AppNavigator.openDetail(
                context,
                m,
                isTv: m.mediaType == 'tv',
              );
            },
            child: Container(
              width: 100,
              margin: const EdgeInsets.only(right: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: CachedNetworkImage(
                        imageUrl: m.posterUrl,
                        fit: BoxFit.cover,
                        width: double.infinity,
                        memCacheWidth: 480,
                        placeholder: (_, _) =>
                            Container(color: const Color(0xFF1A1A1A)),
                        errorWidget: (_, _, _) =>
                            Container(color: Colors.grey[900]),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(m.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 11)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  static const TextStyle _overviewStyle = TextStyle(
    color: Colors.white70,
    fontSize: 13.5,
    height: 1.45,
  );

  Widget _buildOverviewSection(String overview) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final painter = TextPainter(
          text: TextSpan(text: overview, style: _overviewStyle),
          maxLines: 3,
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: constraints.maxWidth);
        final overflowing = painter.didExceedMaxLines;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              onTap: (overflowing || _overviewExpanded)
                  ? () => setState(() => _overviewExpanded = !_overviewExpanded)
                  : null,
              child: Text(
                overview,
                maxLines: _overviewExpanded ? 30 : 3,
                overflow: TextOverflow.ellipsis,
                style: _overviewStyle,
              ),
            ),
            if (overflowing)
              GestureDetector(
                onTap: () =>
                    setState(() => _overviewExpanded = !_overviewExpanded),
                child: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    _overviewExpanded ? 'Show less' : 'Read More ∨',
                    style: FontService.instance.label(
                      color: Colors.white54,
                      fontSize: 12,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  // ── Action row: full labels guaranteed (no ellipsis) ──────────
  Widget _buildActionButtons() {
    return SizedBox(
      height: 56,
      child: Row(
        children: [
          Expanded(
            flex: 5,
            child: _actionTile(
              icon: Icons.play_arrow_rounded,
              label: 'Stream',
              kind: _ActionVisual.filled,
              onTap: () => _showStreamDownloadOptions(isDownload: false),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 6,
            child: _actionTile(
              icon: Icons.download_rounded,
              label: 'Download',
              kind: _ActionVisual.outline,
              onTap: () => _showStreamDownloadOptions(isDownload: true),
            ),
          ),
          if (_hasTrailer) ...[
            const SizedBox(width: 10),
            Expanded(
              flex: 5,
              child: _actionTile(
                icon: Icons.movie_filter_rounded,
                label: 'Trailer',
                kind: _ActionVisual.neutral,
                onTap: () {
                  _suppressAutoTrailer = false;
                  _startTrailer();
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _actionTile({
    required IconData icon,
    required String label,
    required _ActionVisual kind,
    required VoidCallback onTap,
  }) {
    final bool filled = kind == _ActionVisual.filled;
    final bool outline = kind == _ActionVisual.outline;
    final Color fg = filled
        ? Colors.black
        : (outline ? AppDesignTokens.goldMuted : Colors.white);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          HapticFeedback.mediumImpact();
          onTap();
        },
        borderRadius: BorderRadius.circular(16),
        child: Container(
          height: 56,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: filled
                ? const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFFF2C94C), AppDesignTokens.gold, Color(0xFFD89400)],
                  )
                : null,
            color: filled
                ? null
                : (outline
                    ? AppDesignTokens.goldMuted.withValues(alpha: 0.12)
                    : Colors.white.withValues(alpha: 0.08)),
            border: filled
                ? null
                : Border.all(
                    color: outline
                        ? AppDesignTokens.goldMuted.withValues(alpha: 0.85)
                        : Colors.white.withValues(alpha: 0.22),
                    width: 1.4,
                  ),
            boxShadow: filled
                ? [
                    BoxShadow(
                      color: AppDesignTokens.goldMuted.withValues(alpha: 0.35),
                      blurRadius: 18,
                      offset: const Offset(0, 6),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: fg, size: 21),
              const SizedBox(width: 7),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    maxLines: 1,
                    style: TextStyle(
                      color: fg,
                      fontWeight: FontWeight.w800,
                      fontSize: 14.5,
                      letterSpacing: 0.2,
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

  Widget _buildComingSoon() {
    final releaseDate = widget.movie.releaseDate;
    final dateStr = _formatFullDate(releaseDate);
    final countdown = _daysUntilText(releaseDate);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      decoration: BoxDecoration(
        color: AppDesignTokens.goldMuted.withValues(alpha: 0.12),
        borderRadius: AppDesignTokens.radiusXl,
        border: Border.all(color: AppDesignTokens.goldMuted.withValues(alpha: 0.3)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.calendar_today_rounded,
                  color: AppDesignTokens.goldMuted, size: 15),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  'Coming Soon • $dateStr',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppDesignTokens.goldMuted,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
          if (countdown != null) ...[
            const SizedBox(height: 4),
            Text(
              countdown,
              style: TextStyle(
                color: AppDesignTokens.goldMuted.withValues(alpha: 0.75),
                fontSize: 11.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Released title whose streams are dead right now.
  Widget _buildUnavailable() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: AppDesignTokens.radiusXl,
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
      ),
      child: Row(
        children: [
          Icon(Icons.wifi_off_rounded,
              color: AppDesignTokens.goldMuted.withValues(alpha: 0.9), size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Unavailable right now',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Streaming servers didn\'t respond. Please try again in a moment.',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: 11.5,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          AppButton(
            onPressed: _retryAvailability,
            variant: AppButtonVariant.secondary,
            size: AppButtonSize.small,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            borderRadius: AppDesignTokens.radiusFull,
            semanticLabel: 'Retry availability check',
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.refresh_rounded, color: AppDesignTokens.goldMuted, size: 14),
                SizedBox(width: 5),
                Text('Retry',
                    style: TextStyle(
                      color: AppDesignTokens.goldMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    )),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionsLoading() {
    return AnimatedBuilder(
      animation: _actionsPulseCtrl,
      builder: (_, _) {
        final alpha = 0.06 + 0.05 * _actionsPulseCtrl.value;
        return Row(
          children: [
            Expanded(
              flex: 3,
              child: Container(
                height: 56,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: alpha),
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: Container(
                height: 56,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: alpha),
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _verticalInfoCard() {
    final rows = <MapEntry<String, String>>[
      MapEntry('RELEASE DATE',
          _releaseDateValue.isNotEmpty
              ? _formatFullDate(_releaseDateValue)
              : '—'),
      MapEntry('PARENTAL RATING',
          _parentalRating.isNotEmpty ? _parentalRating : '—'),
      MapEntry('TYPE', _mediaLabel),
      if (_runtime.isNotEmpty)
        MapEntry(_isTv ? 'EPISODE DURATION' : 'RUNTIME', _runtime),
      MapEntry('COUNTRY OF ORIGIN', _countries),
      if (_audience.isNotEmpty) MapEntry('AUDIENCE', _audience.join(', ')),
      if (_tags.isNotEmpty) MapEntry('TAGS', _tags.join(', ')),
      if (_genres.isNotEmpty && _genres != '—') MapEntry('GENRES', _genres),
    ];
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      borderRadius: AppDesignTokens.radiusMd,
      border: true,
      borderColor: Colors.white.withValues(alpha: 0.08),
      backgroundColor: AppDesignTokens.card,
      elevation: AppCardElevation.none,
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            _infoRow(rows[i].key, rows[i].value),
            if (i < rows.length - 1)
              Divider(height: 1, color: Colors.white.withValues(alpha: 0.06)),
          ],
        ],
      ),
    );
  }

  IconData _iconForInfoLabel(String label) {
    switch (label) {
      case 'RELEASE DATE':
        return Icons.calendar_today_rounded;
      case 'PARENTAL RATING':
        return Icons.shield_outlined;
      case 'TYPE':
        return Icons.category_outlined;
      case 'RUNTIME':
      case 'EPISODE DURATION':
        return Icons.schedule_rounded;
      case 'COUNTRY OF ORIGIN':
        return Icons.public_rounded;
      case 'AUDIENCE':
        return Icons.groups_outlined;
      case 'TAGS':
        return Icons.sell_outlined;
      case 'GENRES':
        return Icons.theater_comedy_outlined;
      default:
        return Icons.info_outline_rounded;
    }
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 11),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(_iconForInfoLabel(label), color: Colors.white38, size: 16),
          const SizedBox(width: 10),
          SizedBox(
            width: 118,
            child: Text(
              label,
              style: FontService.instance.label(
                color: Colors.white38,
                fontSize: 10.5,
                letterSpacing: 0.8,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                  color: Colors.white70, fontSize: 13.5, height: 1.3),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSeasonSelector() {
    if (_seasons.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        scrollCacheExtent: ScrollCacheExtent.pixels(300),
        itemCount: _seasons.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final season = _seasons[index];
          final seasonNumber = season['season_number'] as int? ?? (index + 1);
          final seasonName = season['name'] as String? ?? 'Season $seasonNumber';
          final isSelected = _selectedSeason == seasonNumber;
          return AppChip(
            label: seasonName,
            variant: AppChipVariant.primary,
            selected: isSelected,
            size: AppChipSize.medium,
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() => _selectedSeason = seasonNumber);
              _loadEpisodesForSeason(seasonNumber);
            },
          );
        },
      ),
    );
  }

  Widget _buildEpisodeList() {
    if (_loadingEpisodes) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: CircularProgressIndicator(color: _gold, strokeWidth: 2),
        ),
      );
    }
    if (_episodes.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Text(
          'No episodes available for this season.',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.4)),
        ),
      );
    }
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _episodes.length,
      separatorBuilder: (_, _) =>
          Divider(height: 1, color: Colors.white.withValues(alpha: 0.08)),
      itemBuilder: (context, index) {
        final ep = _episodes[index];
        final epNum = ep['episode_number'] as int? ?? (index + 1);
        final epName = ep['name'] as String? ?? 'Episode $epNum';
        final stillPath = ep['still_path'] as String?;
        final stillUrl =
            stillPath != null ? 'https://image.tmdb.org/t/p/w300$stillPath' : null;
        final airDate = ep['air_date'] as String?;
        final runtimeMin = (ep['runtime'] as num?)?.toInt();
        final epLabel = 'E${epNum.toString().padLeft(2, '0')}';
        final metaParts = <String>[
          if (runtimeMin != null && runtimeMin > 0) '$runtimeMin min',
          if (airDate != null && airDate.isNotEmpty) airDate,
        ];
        return RepaintBoundary(
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => _showStreamDownloadOptions(
                isDownload: false,
                season: _selectedSeason ?? 1,
                episode: epNum,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: SizedBox(
                        width: 118,
                        height: 74,
                        child: stillUrl != null
                            ? CachedNetworkImage(
                                imageUrl: stillUrl,
                                fit: BoxFit.cover,
                                memCacheWidth: 236,
                                placeholder: (_, _) =>
                                    Container(color: const Color(0xFF1A1A1A)),
                                errorWidget: (_, _, _) =>
                                    Container(color: Colors.grey[900]),
                              )
                            : Container(
                                color: Colors.grey[900],
                                child: const Icon(Icons.tv,
                                    color: Colors.white38),
                              ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(text: '$epLabel  ·  '),
                                TextSpan(text: epName),
                              ],
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: FontService.instance.label(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.2,
                            ),
                          ),
                          if (metaParts.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text(
                              metaParts.join('  ·  '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: FontService.instance.label(
                                color: Colors.white54,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w500,
                                letterSpacing: 0.2,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Material(
                      color: AppDesignTokens.goldMuted,
                      shape: const CircleBorder(),
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: () => _showStreamDownloadOptions(
                          isDownload: true,
                          season: _selectedSeason ?? 1,
                          episode: epNum,
                        ),
                        child: const Padding(
                          padding: EdgeInsets.all(14),
                          child: Icon(Icons.download_rounded,
                              color: Colors.black87, size: 20),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _sectionTitle(String title) {
    return Text(
      title,
      style: FontService.instance.display(
        color: Colors.white,
        fontSize: 16,
        fontWeight: FontWeight.bold,
      ),
    );
  }

  Widget _personTile(
      {required String name, required String role, String? photoUrl}) {
    return Row(
      children: [
        ClipOval(
          child: SizedBox(
            width: 56,
            height: 56,
            child: (photoUrl != null && photoUrl.isNotEmpty)
                ? CachedNetworkImage(
                    imageUrl: photoUrl,
                    fit: BoxFit.cover,
                    memCacheWidth: 112,
                    placeholder: (_, _) => Container(
                        color: Colors.grey[850],
                        child:
                            const Icon(Icons.person, color: Colors.white54)),
                    errorWidget: (_, _, _) => Container(
                        color: Colors.grey[850],
                        child:
                            const Icon(Icons.person, color: Colors.white54)),
                  )
                : Container(
                    color: Colors.grey[850],
                    child: const Icon(Icons.person, color: Colors.white54),
                  ),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w600)),
              Text(role,
                  style: FontService.instance.label(
                      color: Colors.white54, fontSize: 11, letterSpacing: 0.3)),
            ],
          ),
        ),
        const Icon(Icons.chevron_right_rounded,
            color: Colors.white38, size: 20),
      ],
    );
  }

  String _castRoleLabel(CastMember actor) {
    try {
      final dynamic a = actor;
      final c = a.character ?? a.role ?? a.job;
      if (c is String && c.trim().isNotEmpty) return c.trim();
    } catch (_) {}
    return 'Cast';
  }

  Widget _buildActorsGrid() {
    final visible = _showAllCast ? _cast : _cast.take(8).toList();
    return Column(
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final count = constraints.maxWidth >= 980
                ? 6
                : constraints.maxWidth >= 720
                    ? 5
                    : constraints.maxWidth >= 520
                        ? 4
                        : 3;
            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: count,
                mainAxisSpacing: 12,
                crossAxisSpacing: 10,
                mainAxisExtent: 148,
              ),
              itemCount: visible.length,
              itemBuilder: (context, index) {
                final actor = visible[index];
                final hasPhoto =
                    actor.profilePath != null && actor.profilePath!.isNotEmpty;
                return RepaintBoundary(
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => _openActor(actor),
                      borderRadius: BorderRadius.circular(18),
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(7, 8, 7, 8),
                        decoration: BoxDecoration(
                          color: _card,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                              color: Colors.white.withValues(alpha: 0.06)),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(2),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: _gold.withValues(alpha: 0.34),
                                ),
                              ),
                              child: ClipOval(
                                child: SizedBox(
                                  width: 70,
                                  height: 70,
                                  child: hasPhoto
                                      ? CachedNetworkImage(
                                          imageUrl:
                                              'https://image.tmdb.org/t/p/w185${actor.profilePath}',
                                          fit: BoxFit.cover,
                                          memCacheWidth: 256,
                                          placeholder: (_, _) => Container(
                                              color: const Color(0xFF1A1F28),
                                              child: const Icon(Icons.person,
                                                  color: Colors.white30)),
                                          errorWidget: (_, _, _) => Container(
                                              color: const Color(0xFF1A1F28),
                                              child: const Icon(Icons.person,
                                                  color: Colors.white30)),
                                        )
                                      : Container(
                                          color: const Color(0xFF1A1F28),
                                          child: const Icon(Icons.person,
                                              color: Colors.white30),
                                        ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 7),
                            Text(
                              actor.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Container(
                              constraints: const BoxConstraints(maxWidth: 116),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 7, vertical: 3),
                              decoration: BoxDecoration(
                                color: _accentBlue.withValues(alpha: 0.10),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                _castRoleLabel(actor),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Colors.white54,
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            );
          },
        ),
        if (_cast.length > 8)
          TextButton.icon(
            onPressed: () => setState(() => _showAllCast = !_showAllCast),
            icon: Icon(
              _showAllCast
                  ? Icons.keyboard_arrow_up_rounded
                  : Icons.keyboard_arrow_down_rounded,
              color: _gold,
              size: 18,
            ),
            label: Text(
              _showAllCast ? 'Show less' : 'Show ${_cast.length - 8} more',
              style: const TextStyle(
                color: _gold,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildStudiosSection() {
    final visible = _showAllStudios ? _studios : _studios.take(3).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 4,
              height: 20,
              decoration: BoxDecoration(
                color: AppDesignTokens.goldMuted,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 10),
            Text('Studios',
                style: FontService.instance.display(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 12),
        ...visible.map((studio) => AppCard(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              borderRadius: AppDesignTokens.radiusMd,
              border: true,
              borderColor: Colors.white.withValues(alpha: 0.08),
              backgroundColor: AppDesignTokens.card,
              elevation: AppCardElevation.none,
              semanticLabel: studio.name,
              child: Row(
                children: [
                  if (studio.logoUrl.isNotEmpty)
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      padding: const EdgeInsets.all(4),
                      child: CachedNetworkImage(
                        imageUrl: studio.logoUrl,
                        fit: BoxFit.contain,
                        memCacheWidth: 160,
                        errorWidget: (_, _, _) => const SizedBox.shrink(),
                      ),
                    )
                  else
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Icon(Icons.business,
                          color: Colors.white38, size: 20),
                    ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      studio.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            )),
        if (_studios.length > 3)
          GestureDetector(
            onTap: () => setState(() => _showAllStudios = !_showAllStudios),
            child: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _showAllStudios ? 'Show less' : 'Show ${_studios.length - 3} more ∨',
                style: FontService.instance.label(
                    color: Colors.white54,
                    fontSize: 12.5,
                    letterSpacing: 0.3),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildRatingsRow() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 100,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            scrollCacheExtent: ScrollCacheExtent.pixels(300),
            itemCount: _ratings.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (context, index) => _buildRatingCard(_ratings[index]),
          ),
        ),
        const SizedBox(height: 8),
        Builder(
          builder: (context) {
            final mean = _calculateMeanRating();
            final totalVotes =
                _ratings.fold<int>(0, (sum, r) => sum + r.votes);
            return Text(
              'Mean rating ${mean.toStringAsFixed(1)}/10 • Aggregated from $totalVotes voters across the web.',
              style:
                  TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 11),
            );
          },
        ),
      ],
    );
  }

  double _calculateMeanRating() {
    if (_ratings.isEmpty) return 0;
    double total = 0;
    for (final r in _ratings) {
      if (r.outOf <= 0) continue;
      total += r.score / r.outOf * 10;
    }
    return total / _ratings.length;
  }

  Widget _buildRatingCard(RatingSource source) {
    if (source.name.toLowerCase() == 'letterboxd') {
      return _buildLetterboxdCard(source);
    } else if (source.name.toLowerCase() == 'imdb') {
      return _buildImdbCard(source);
    }
    return _buildGenericCard(source);
  }

  Widget _buildLetterboxdCard(RatingSource source) {
    final double score5 = source.score;
    final double score10 = score5 / 5 * 10;
    return SizedBox(
      width: 160,
      child: AppCard(
        padding: const EdgeInsets.all(12),
        borderRadius: AppDesignTokens.radiusMd,
        border: true,
        borderColor: Colors.white.withValues(alpha: 0.08),
        backgroundColor: AppDesignTokens.card,
        elevation: AppCardElevation.none,
        child: SizedBox(
          height: 76,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(children: [
                Text(score5.toStringAsFixed(1),
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w800)),
                const SizedBox(width: 4),
                const Text('/5',
                    style: TextStyle(color: Colors.white54, fontSize: 13)),
                const SizedBox(width: 8),
                Text('(${score10.toStringAsFixed(1)}/10)',
                    style:
                        const TextStyle(color: Colors.white38, fontSize: 11)),
              ]),
              Row(children: [
                for (int i = 0; i < 5; i++)
                  Icon(i < score5.round() ? Icons.circle : Icons.circle_outlined,
                      size: 10,
                      color: i < score5.round()
                          ? AppDesignTokens.goldMuted
                          : Colors.white38),
                const SizedBox(width: 8),
                Text('${source.votes} votes',
                    style:
                        const TextStyle(color: Colors.white38, fontSize: 10)),
              ]),
              Text(source.name.toUpperCase(),
                  style: FontService.instance.label(
                      color: Colors.white70,
                      fontSize: 10.5,
                      letterSpacing: 0.8)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildImdbCard(RatingSource source) {
    return SizedBox(
      width: 160,
      child: AppCard(
        padding: const EdgeInsets.all(12),
        borderRadius: AppDesignTokens.radiusMd,
        border: true,
        borderColor: Colors.white.withValues(alpha: 0.08),
        backgroundColor: AppDesignTokens.card,
        elevation: AppCardElevation.none,
        child: SizedBox(
          height: 76,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(children: [
                Text(source.score.toStringAsFixed(1),
                    style: const TextStyle(
                        color: Colors.amber,
                        fontSize: 22,
                        fontWeight: FontWeight.w800)),
                const SizedBox(width: 4),
                const Text('/10',
                    style: TextStyle(color: Colors.white54, fontSize: 13)),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.amber,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text('IMDb',
                      style: TextStyle(
                          color: Colors.black,
                          fontSize: 8,
                          fontWeight: FontWeight.bold)),
                ),
              ]),
              Text('${source.votes} votes',
                  style: const TextStyle(color: Colors.white38, fontSize: 10)),
              Text(source.name.toUpperCase(),
                  style: FontService.instance.label(
                      color: Colors.white70,
                      fontSize: 10.5,
                      letterSpacing: 0.8)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGenericCard(RatingSource source) {
    final ratio = source.outOf > 0
        ? (source.score / source.outOf).clamp(0.0, 1.0)
        : 0.0;
    return SizedBox(
      width: 140,
      child: AppCard(
        padding: const EdgeInsets.all(12),
        borderRadius: AppDesignTokens.radiusMd,
        border: true,
        borderColor: Colors.white.withValues(alpha: 0.08),
        backgroundColor: AppDesignTokens.card,
        elevation: AppCardElevation.none,
        child: SizedBox(
          height: 76,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: RichText(
                      text: TextSpan(children: [
                        TextSpan(
                          text: source.score.toStringAsFixed(1),
                          style: const TextStyle(
                              color: AppDesignTokens.goldMuted,
                              fontSize: 22,
                              fontWeight: FontWeight.w800),
                        ),
                        TextSpan(
                          text: ' /${source.outOf.toStringAsFixed(0)}',
                          style: const TextStyle(
                              color: Colors.white54, fontSize: 13),
                        ),
                      ]),
                    ),
                  ),
                  SizedBox(
                    width: 26,
                    height: 26,
                    child: CircularProgressIndicator(
                      value: ratio,
                      strokeWidth: 3,
                      backgroundColor: Colors.white.withValues(alpha: 0.1),
                      valueColor: const AlwaysStoppedAnimation<Color>(
                          AppDesignTokens.goldMuted),
                    ),
                  ),
                ],
              ),
              Text('${source.votes} votes',
                  style: const TextStyle(color: Colors.white38, fontSize: 10)),
              Text(source.name.toUpperCase(),
                  style: FontService.instance.label(
                      color: Colors.white70,
                      fontSize: 10.5,
                      letterSpacing: 0.8)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildReviewsSection() {
    return ListenableBuilder(
      listenable: ReviewService.instance,
      builder: (context, _) {
        final reviews = ReviewService.instance
            .getReviews(widget.movie.id, mediaType: _libraryMovie.mediaType);
        final userRating = ReviewService.instance
            .getRating(widget.movie.id, mediaType: _libraryMovie.mediaType);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _sectionTitle('Reviews  ${reviews.length}'),
                AppButton(
                  onPressed: _openPostReview,
                  variant: AppButtonVariant.ghost,
                  size: AppButtonSize.small,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  semanticLabel: 'Post review',
                  child: const Text('Post review',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            AppCard(
              padding: const EdgeInsets.all(16),
              borderRadius: AppDesignTokens.radiusMd,
              border: true,
              borderColor: Colors.white.withValues(alpha: 0.08),
              backgroundColor: Colors.white.withValues(alpha: 0.06),
              elevation: AppCardElevation.none,
              child: Column(
                children: [
                  const Text('Rate this title',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(5, (i) {
                      return IconButton(
                        onPressed: () => _rateTitle(i + 1),
                        icon: Icon(
                            i < userRating
                                ? Icons.star_rounded
                                : Icons.star_border_rounded,
                            color: AppDesignTokens.goldMuted,
                            size: 28),
                      );
                    }),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            if (reviews.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text('No reviews yet — be the first.',
                    style:
                        TextStyle(color: Colors.white.withValues(alpha: 0.4))),
              )
            else
              ...reviews.take(5).map(_buildUserReviewTile),
          ],
        );
      },
    );
  }

  Widget _buildUserReviewTile(UserReview r) {
    return AppCard(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      borderRadius: AppDesignTokens.radiusMd,
      border: true,
      borderColor: Colors.white.withValues(alpha: 0.08),
      backgroundColor: Colors.white.withValues(alpha: 0.06),
      elevation: AppCardElevation.none,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: Colors.grey[800],
                child: Text(r.username.isNotEmpty
                    ? r.username[0].toUpperCase()
                    : '?'),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(r.username,
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold)),
                    Text('${r.date.month}/${r.date.day}/${r.date.year}',
                        style: FontService.instance.label(
                            color: Colors.white38,
                            fontSize: 10.5,
                            letterSpacing: 0.3)),
                  ],
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(5, (i) {
                  return Icon(
                      i < r.rating.round()
                          ? Icons.star_rounded
                          : Icons.star_border_rounded,
                      color: AppDesignTokens.goldMuted,
                      size: 14);
                }),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (r.containsSpoilers)
            _SpoilerReveal(text: r.body)
          else
            Text(r.body,
                style: const TextStyle(color: Colors.white70, height: 1.4)),
        ],
      ),
    );
  }

  Widget _buildSimilarGrid() {
    if (_similarMovies.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 210,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        scrollCacheExtent: ScrollCacheExtent.pixels(400),
        itemCount: _similarMovies.length,
        itemBuilder: (context, index) {
          final m = _similarMovies[index];
          return RepaintBoundary(
            child: SizedBox(
              width: 120,
              child: PosterCard(
                movie: m,
                size: PosterCardSize.small,
                heroTagPrefix: 'detail-similar',
                showQuickActions: false,
                onTap: () {
                  AppNavigator.openDetail(
                    context,
                    m,
                    isTv: m.mediaType == 'tv',
                  );
                },
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _circleBtn(IconData icon) {
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.black.withValues(alpha: 0.45),
        border: Border.all(color: Colors.white24),
      ),
      child: Icon(icon, color: Colors.white, size: 18),
    );
  }
}

class _SpoilerReveal extends StatefulWidget {
  final String text;
  const _SpoilerReveal({required this.text});
  @override
  State<_SpoilerReveal> createState() => _SpoilerRevealState();
}

class _SpoilerRevealState extends State<_SpoilerReveal> {
  bool _revealed = false;
  @override
  Widget build(BuildContext context) {
    if (_revealed) {
      return Text(widget.text,
          style: const TextStyle(color: Colors.white70, height: 1.4));
    }
    return AppButton(
      onPressed: () => setState(() => _revealed = true),
      variant: AppButtonVariant.ghost,
      size: AppButtonSize.small,
      padding: const EdgeInsets.all(12),
      borderRadius: AppDesignTokens.radiusSm,
      fullWidth: true,
      semanticLabel: 'Reveal spoiler',
      child: const Row(
        children: [
          Icon(Icons.visibility_outlined, color: Colors.white54, size: 16),
          SizedBox(width: 8),
          Text('This review may contain spoilers — tap to show',
              style: TextStyle(color: Colors.white54, fontSize: 12.5)),
        ],
      ),
    );
  }
}

class _SourceEpisodeSheet extends StatefulWidget {
  final bool isTv;
  final bool isDownload;
  final List<Map<String, dynamic>> seasons;
  final List<Map<String, dynamic>> episodes;
  final int selectedSeason;
  final int? selectedEpisode;
  final void Function(String source, int season, int episode, bool downloadEntire) onSelect;
  final void Function(String source, int season, int episode) onUseAddon;

  const _SourceEpisodeSheet({
    required this.isTv,
    required this.isDownload,
    required this.seasons,
    required this.episodes,
    required this.selectedSeason,
    this.selectedEpisode,
    required this.onSelect,
    required this.onUseAddon,
  });

  @override
  State<_SourceEpisodeSheet> createState() => _SourceEpisodeSheetState();
}

class _SourceEpisodeSheetState extends State<_SourceEpisodeSheet> {
  late int _selectedSeason;
  int? _selectedEpisode;
  String _sourceType = 'server';

  @override
  void initState() {
    super.initState();
    _selectedSeason = widget.selectedSeason;
    _selectedEpisode = widget.selectedEpisode;
  }

  List<Map<String, dynamic>> get _episodesForSelectedSeason {
    return widget.episodes
        .where((e) => (e['season_number'] as int? ?? 0) == _selectedSeason)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).padding.bottom;
    final episodes = _episodesForSelectedSeason;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF141008),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(color: AppDesignTokens.goldMuted.withValues(alpha: 0.15), width: 0.8),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Text(
                  widget.isDownload ? 'Download Options' : 'Stream Options',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded, color: Colors.white70),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _SourceToggle(
              sourceType: _sourceType,
              onChanged: (s) => setState(() => _sourceType = s),
            ),
          ),
          if (widget.isTv) ...[
            const SizedBox(height: 16),
            _SeasonSelector(
              seasons: widget.seasons,
              selectedSeason: _selectedSeason,
              onSeasonSelected: (s) {
                setState(() {
                  _selectedSeason = s;
                  _selectedEpisode = null;
                });
              },
            ),
            if (episodes.isNotEmpty) ...[
              const SizedBox(height: 12),
              _EpisodeSelector(
                episodes: episodes,
                selectedEpisode: _selectedEpisode,
                onEpisodeSelected: (e) => setState(() => _selectedEpisode = e),
              ),
              if (widget.isDownload) ...[
                const SizedBox(height: 12),
                _DownloadEntireSeasonOption(
                  season: _selectedSeason,
                  episodeCount: episodes.length,
                  onTap: () => widget.onSelect(_sourceType, _selectedSeason, _selectedEpisode ?? 1, true),
                ),
              ],
            ],
          ],
          const SizedBox(height: 20),
          Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 12 + bottomPad),
            child: SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: () {
                  widget.onSelect(
                    _sourceType,
                    _selectedSeason,
                    _selectedEpisode ?? 1,
                    false,
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppDesignTokens.goldMuted,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      widget.isDownload ? Icons.download_rounded : Icons.play_arrow_rounded,
                      size: 22,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      widget.isDownload
                          ? (_selectedEpisode != null
                              ? 'Download S${_selectedSeason.toString().padLeft(2, '0')}E${_selectedEpisode.toString().padLeft(2, '0')}'
                              : 'Download Season $_selectedSeason')
                          : (_selectedEpisode != null
                              ? 'Stream S${_selectedSeason.toString().padLeft(2, '0')}E${_selectedEpisode.toString().padLeft(2, '0')} →'
                              : 'Choose Server →'),
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
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
}

class _SourceToggle extends StatelessWidget {
  final String sourceType;
  final ValueChanged<String> onChanged;

  const _SourceToggle({required this.sourceType, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: _SourceToggleButton(
              label: 'Server',
              icon: Icons.cloud_outlined,
              isSelected: sourceType == 'server',
              onTap: () => onChanged('server'),
            ),
          ),
          Expanded(
            child: _SourceToggleButton(
              label: 'Addons',
              icon: Icons.apps_rounded,
              isSelected: sourceType == 'addon',
              onTap: () => onChanged('addon'),
            ),
          ),
        ],
      ),
    );
  }
}

class _SourceToggleButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _SourceToggleButton({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(                      duration: AppMotion.scaled(context, AppMotion.standard),

        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? AppDesignTokens.goldMuted.withValues(alpha: 0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 18,
              color: isSelected ? AppDesignTokens.goldMuted : Colors.white54,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? AppDesignTokens.goldMuted : Colors.white70,
                fontSize: 14,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SeasonSelector extends StatelessWidget {
  final List<Map<String, dynamic>> seasons;
  final int selectedSeason;
  final ValueChanged<int> onSeasonSelected;

  const _SeasonSelector({
    required this.seasons,
    required this.selectedSeason,
    required this.onSeasonSelected,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: seasons.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final season = seasons[index];
          final seasonNum = season['season_number'] as int? ?? (index + 1);
          final name = season['name'] as String? ?? 'Season $seasonNum';
          final isSelected = selectedSeason == seasonNum;
          return GestureDetector(
            onTap: () => onSeasonSelected(seasonNum),
            child: AnimatedContainer(
              duration: AppMotion.scaled(context, AppMotion.standard),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: isSelected
                    ? AppDesignTokens.goldMuted.withValues(alpha: 0.2)
                    : Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isSelected
                      ? AppDesignTokens.goldMuted.withValues(alpha: 0.5)
                      : Colors.white.withValues(alpha: 0.1),
                ),
              ),
              child: Text(
                name,
                style: TextStyle(
                  color: isSelected ? AppDesignTokens.goldMuted : Colors.white70,
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _EpisodeSelector extends StatelessWidget {
  final List<Map<String, dynamic>> episodes;
  final int? selectedEpisode;
  final ValueChanged<int> onEpisodeSelected;

  const _EpisodeSelector({
    required this.episodes,
    required this.selectedEpisode,
    required this.onEpisodeSelected,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 80,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: episodes.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final ep = episodes[index];
          final epNum = ep['episode_number'] as int? ?? (index + 1);
          final name = ep['name'] as String? ?? 'Episode $epNum';
          final isSelected = selectedEpisode == epNum;
          return GestureDetector(
            onTap: () => onEpisodeSelected(epNum),
            child: AnimatedContainer(
              duration: AppMotion.scaled(context, AppMotion.standard),
              width: 70,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isSelected
                    ? AppDesignTokens.goldMuted.withValues(alpha: 0.2)
                    : Colors.white.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isSelected
                      ? AppDesignTokens.goldMuted.withValues(alpha: 0.5)
                      : Colors.white.withValues(alpha: 0.08),
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'E${epNum.toString().padLeft(2, '0')}',
                    style: TextStyle(
                      color: isSelected ? AppDesignTokens.goldMuted : Colors.white70,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    name,
                    maxLines: 2,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isSelected ? AppDesignTokens.goldMuted.withValues(alpha: 0.8) : Colors.white38,
                      fontSize: 10,
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
}

class _DownloadEntireSeasonOption extends StatelessWidget {
  final int season;
  final int episodeCount;
  final VoidCallback onTap;

  const _DownloadEntireSeasonOption({
    required this.season,
    required this.episodeCount,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                AppDesignTokens.goldMuted.withValues(alpha: 0.12),
                AppDesignTokens.goldMuted.withValues(alpha: 0.06),
              ],
            ),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: AppDesignTokens.goldMuted.withValues(alpha: 0.25),
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppDesignTokens.goldMuted.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.archive_rounded,
                  color: AppDesignTokens.goldMuted,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Download Entire Season',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      'S${season.toString().padLeft(2, '0')} · $episodeCount episodes compressed',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.5),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: AppDesignTokens.goldMuted.withValues(alpha: 0.7),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AddonLoadingOverlay extends StatelessWidget {
  final String backdropUrl;
  final ValueNotifier<String> subtitle;

  const _AddonLoadingOverlay({
    required this.backdropUrl,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Full-bleed backdrop
          Positioned.fill(
            child: Opacity(
              opacity: 0.6,
              child: CachedNetworkImage(
                imageUrl: backdropUrl,
                fit: BoxFit.cover,
                placeholder: (_, _) => const SizedBox.shrink(),
                errorWidget: (_, _, _) => const SizedBox.shrink(),
              ),
            ),
          ),
          // Dark glassmorphism overlay (tokenized warm-noir glass)
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(
                sigmaX: AppDesignTokens.glassBlurSheet,
                sigmaY: AppDesignTokens.glassBlurSheet,
              ),
              child: Container(
                color: AppDesignTokens.glassFillSheet,
              ),
            ),
          ),
          // Center content
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Branded wordmark
                Text(
                  'MelaFilm',
                  style: FontService.instance.display(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: 64,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 24),
                // Status subtitle
                ValueListenableBuilder<String>(
                  valueListenable: subtitle,
                  builder: (context, text, _) {
                    return Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(
                            color: AppDesignTokens.goldMuted,
                            strokeWidth: 2,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          text,
                          style: FontService.instance.label(
                            color: Colors.white70,
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
