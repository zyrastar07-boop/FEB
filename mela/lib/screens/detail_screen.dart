import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/movie.dart';
import '../models/cast_member.dart';
import '../services/font_service.dart';
import '../services/review_service.dart';
import '../services/user_library_service.dart';
import '../widgets/animated_toggle_icon.dart';
import '../widgets/available_downloads_sheet.dart';
import '../widgets/add_to_list_sheet.dart';
import '../widgets/pressable.dart';
import '../widgets/server_selector_sheet.dart';
import '../services/tmdb_details_service.dart';
import '../services/tmdb_service.dart';
import 'actor_detail_screen.dart';

const _gold = Color(0xFFFFB800);
const _bg = Color(0xFF0A0A0A);
const _card = Color(0xFF141414);

class RatingSource {
  final String name;
  final String logo; // optional icon/emoji
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
  /// Blocks the 3s auto-play timer after Stream/Download or dismiss.
  bool _suppressAutoTrailer = false;

  // TV Series specific state variables
  int? _selectedSeason;
  List<Map<String, dynamic>> _seasons = [];
  List<Map<String, dynamic>> _episodes = [];
  bool _loadingEpisodes = false;

  List<Movie> _similarMovies = [];
  List<Movie> _directorMovies = [];
  List<CastMember> _cast = [];
  String? _trailerKey;
  String? _logoUrl;
  String? _heroImageUrl; // clean / textless artwork for the header
  String? _directorName;
  String? _directorPhoto;
  int? _directorId;
  String _parentalRating = '';
  String _runtime = '';
  String _genres = '';
  String _countries = '';
  String _mediaLabel = 'Movie';

  late List<RatingSource> _ratings;
  late List<String> _tags;
  late List<String> _audience;

  // Studio data
  List<StudioInfo> _studios = [];
  bool _showAllStudios = false;

  YoutubePlayerController? _ytController;
  Timer? _autoPlayTimer;

  late AnimationController _fadeCtrl;
  late AnimationController _slideCtrl;
  late AnimationController _pulseCtrl;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  final TmdbDetailsService _tmdbService = TmdbDetailsService();
  final TmdbService _tmdbListService = TmdbService();

  // Availability state
  bool _isAvailable = true; // default true, will be checked
  bool _checkingAvailability = false;

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
      duration: const Duration(milliseconds: 700),
    );
    _slideCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);

    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.06),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _slideCtrl, curve: Curves.easeOutCubic));

    _loadAllMetadata();
    _checkAvailability(); // initial check
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

      // ── Critical path: details + cast + logo + director + clean hero ────
      // These power the hero, meta row, and first visible sections.
      final critical = await Future.wait([
        _tmdbService.getCast(tmdbId, isTv: _isTv),
        _tmdbService.getMovieLogo(tmdbId, isTv: _isTv),
        _tmdbService.getDirector(tmdbId, isTv: _isTv),
        _tmdbService.getMovieDetails(tmdbId, isTv: _isTv),
        _tmdbService.getTextlessPoster(tmdbId, isTv: _isTv),
      ]);

      if (!mounted) return;

      final cast = critical[0] as List<CastMember>;
      final logo = critical[1] as String?;
      final director = critical[2] as Map<String, dynamic>?;
      final details = critical[3] as Map<String, dynamic>?;
      final textlessPoster = critical[4] as String?;

      String? dirName = director?['name'] as String?;
      String? dirPhoto;
      final profilePath = director?['profile_path'] as String?;
      if (profilePath != null && profilePath.isNotEmpty) {
        dirPhoto = 'https://image.tmdb.org/t/p/w185$profilePath';
      }
      final dirId = director?['id'] as int?;

      final parental =
          _tmdbService.extractParentalRating(details, isTv: _isTv) ?? '';
      final runtime = _tmdbService.formatRuntime(details, isTv: _isTv);
      final genres = _tmdbService.formatGenres(details);
      final countries = _tmdbService.formatCountries(details);

      List<Map<String, dynamic>> parsedSeasons = [];
      if (_isTv && details != null && details['seasons'] is List) {
        parsedSeasons = (details['seasons'] as List)
            .map((s) => s as Map<String, dynamic>)
            .where((s) => (s['season_number'] as int? ?? 0) > 0)
            .toList();
      }

      final voteCount = (details?['vote_count'] as num?)?.toInt() ?? 0;
      final voteAvg = (details?['vote_average'] as num?)?.toDouble() ??
          widget.movie.voteAverage;

      // Parse production companies (studios) — cheap, keep with critical
      final List<StudioInfo> studios = [];
      if (details != null && details['production_companies'] is List) {
        final companies = details['production_companies'] as List;
        for (final company in companies) {
          final name = company['name'] as String? ?? '';
          final logoPath = company['logo_path'] as String?;
          final logoUrl = logoPath != null && logoPath.isNotEmpty
              ? 'https://image.tmdb.org/t/p/w200$logoPath'
              : '';
          studios.add(StudioInfo(name: name, logoUrl: logoUrl));
        }
      }

      setState(() {
        _cast = cast;
        _logoUrl = logo;
        // Prefer clean textless poster → original poster → backdrop
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
        _seasons = parsedSeasons;
        if (_isTv && _seasons.isNotEmpty && _selectedSeason == null) {
          _selectedSeason = _seasons[0]['season_number'] as int?;
        }
        _ratings = [
          RatingSource(
              name: 'TMDB', score: voteAvg, outOf: 10, votes: voteCount),
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
      if (dirId != null) {
        _loadDirectorFilmography(dirId);
      }

      // ── Secondary path: trailer + recommendations (after first frame) ──
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

  /// Deferred network work that is not required for the first paint.
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

      // Auto-play trailer after a short delay unless suppressed
      if (hasTrailer && !_suppressAutoTrailer) {
        _autoPlayTimer?.cancel();
        _autoPlayTimer = Timer(const Duration(seconds: 3), () {
          if (mounted &&
              !_isPlayingTrailer &&
              !_suppressAutoTrailer &&
              ModalRoute.of(context)?.isCurrent == true) {
            _startTrailer();
          }
        });
      }
    } catch (_) {
      // Secondary failure must not break the already-rendered detail page.
    }
  }

  Future<void> _loadEpisodesForSeason(int seasonNumber) async {
    setState(() => _loadingEpisodes = true);
    try {
      List<Map<String, dynamic>> eps = [];
      try {
        eps = await _tmdbService.getSeasonEpisodes(widget.movie.id, seasonNumber);
      } catch (_) {
        eps = List.generate(10, (i) => {
          'episode_number': i + 1,
          'season_number': seasonNumber,
          'name': 'Episode ${i + 1}',
          'overview': 'Overview for episode ${i + 1} of season $seasonNumber.',
          'still_path': null,
        });
      }
      if (!mounted) return;
      setState(() {
        _episodes = eps;
        _loadingEpisodes = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingEpisodes = false);
    }
  }

  Future<void> _loadDirectorFilmography(int personId) async {
    try {
      final films = await _tmdbListService.getMoviesByDirector(personId);
      if (!mounted) return;
      setState(() {
        _directorMovies = films
            .where((m) => m.id != widget.movie.id)
            .take(12)
            .toList();
      });
    } catch (_) {}
  }

  /// Placeholder for actual availability check against a relay endpoint.
  /// Replace with your own implementation.
  Future<void> _checkAvailability() async {
    if (_checkingAvailability) return;
    setState(() => _checkingAvailability = true);
    try {
      // Simulate network request – replace with actual endpoint.
      // If the movie is unreleased (release date in future), we can mark as unavailable.
      final releaseDateStr = widget.movie.releaseDate;
      DateTime? releaseDate;
      if (releaseDateStr.isNotEmpty) {
        try {
          releaseDate = DateTime.parse(releaseDateStr);
        } catch (_) {}
      }
      // For demo: if release date is after today, consider unavailable.
      final now = DateTime.now();
      bool available = releaseDate == null || releaseDate.isBefore(now) || releaseDate.isAtSameMomentAs(now);
      // Also you can query your own backend here.
      // final response = await http.get(Uri.parse('https://your-relay.com/check?tmdbId=${widget.movie.id}'));
      // available = response.body == 'available';
      if (mounted) {
        setState(() {
          _isAvailable = available;
          _checkingAvailability = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isAvailable = false; // default false on error
          _checkingAvailability = false;
        });
      }
    }
  }

  void _startTrailer() {
    if (_trailerKey == null || _trailerKey!.isEmpty) {
      _toast('No trailer available');
      return;
    }
    if (_suppressAutoTrailer && _isPlayingTrailer == false) {
      // Explicit user tap still allowed — clear suppress only for manual play.
    }

    HapticFeedback.mediumImpact();
    _autoPlayTimer?.cancel();
    _autoPlayTimer = null;

    _disposeTrailerPlayer();
    _ytController = YoutubePlayerController(
      initialVideoId: _trailerKey!,
      flags: const YoutubePlayerFlags(
        autoPlay: true,
        // Must start muted for mobile WebView autoplay to be allowed.
        // We unmute immediately after playback starts so audio plays.
        mute: true,
        enableCaption: false,
        hideControls: true,
        controlsVisibleAtStart: false,
        hideThumbnail: true,
        disableDragSeek: true,
        loop: false,
        showLiveFullscreenButton: false,
        forceHD: true,
        useHybridComposition: true,
      ),
    )..addListener(_trailerListener);

    setState(() {
      _isPlayingTrailer = true;
      _isTrailerMuted = false; // UI shows unmuted; we unmute the player next
    });

    void forceUnmuteAndPlay() {
      if (!mounted || _ytController == null || !_isPlayingTrailer) return;
      try {
        _ytController!.play();
        _ytController!.unMute();
        if (mounted) setState(() => _isTrailerMuted = false);
      } catch (_) {}
    }

    // Unmute as soon as the player can accept it (autoplay requires muted start).
    Future.delayed(const Duration(milliseconds: 300), forceUnmuteAndPlay);
    Future.delayed(const Duration(milliseconds: 700), forceUnmuteAndPlay);
    Future.delayed(const Duration(milliseconds: 1200), forceUnmuteAndPlay);
  }

  void _trailerListener() {
    if (_ytController == null) return;
    final state = _ytController!.value.playerState;
    if (state == PlayerState.ended) {
      _stopTrailer(suppressFutureAutoPlay: false);
    }
  }

  void _disposeTrailerPlayer() {
    try {
      _ytController?.removeListener(_trailerListener);
      _ytController?.pause();
      _ytController?.dispose();
    } catch (_) {}
    _ytController = null;
  }

  /// Stops the in-page trailer and optionally blocks the auto-play timer
  /// from restarting it (used when the user opens Stream / Download).
  void _stopTrailer({bool suppressFutureAutoPlay = true}) {
    _autoPlayTimer?.cancel();
    _autoPlayTimer = null;
    if (suppressFutureAutoPlay) {
      _suppressAutoTrailer = true;
    }
    _disposeTrailerPlayer();
    if (mounted) {
      setState(() {
        _isPlayingTrailer = false;
        _isTrailerMuted = false;
      });
    }
  }

  void _toggleTrailerMute() {
    HapticFeedback.selectionClick();
    if (_ytController == null || !_isPlayingTrailer) {
      setState(() => _isTrailerMuted = !_isTrailerMuted);
      return;
    }
    setState(() => _isTrailerMuted = !_isTrailerMuted);
    if (_isTrailerMuted) {
      _ytController!.mute();
    } else {
      _ytController!.unMute();
      _ytController!.play();
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
    // Opens sheet: Watchlist, My List, custom lists, create list
    await AddToListSheet.show(context, _libraryMovie);
  }

  void _openServerSelector({int? season, int? episode}) {
    HapticFeedback.mediumImpact();
    // Always kill trailer + timer so audio cannot continue under the player.
    _stopTrailer(suppressFutureAutoPlay: true);
    final seasonNum = season ?? _selectedSeason ?? 1;
    final episodeNum = episode ?? 1;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ServerSelectorSheet(
        tmdbId: widget.movie.id.toString(),
        movieTitle: widget.movie.title,
        mediaType: _isTv ? 'tv' : 'movie',
        season: seasonNum,
        episode: episodeNum,
      ),
    );
  }

  void _openDownloadSheet({int? season, int? episode}) {
    HapticFeedback.mediumImpact();
    _stopTrailer(suppressFutureAutoPlay: true);
    final seasonNum = season ?? _selectedSeason ?? 1;
    final episodeNum = episode ?? 1;
    AvailableDownloadsSheet.show(
      context,
      movieTitle: widget.movie.title,
      tmdbId: widget.movie.id.toString(),
      posterUrl: widget.movie.posterUrl,
      mediaType: _isTv ? 'tv' : 'movie',
      season: seasonNum,
      episode: episodeNum,
    );
  }

  void _shareMovie() {
    HapticFeedback.lightImpact();
    final type = _isTv ? 'tv' : 'movie';
    final link =
        'https://www.themoviedb.org/$type/${widget.movie.id}';
    Clipboard.setData(ClipboardData(text: link));
    _toast('Share link for "${widget.movie.title}" copied');
  }

  void _openActor(CastMember actor) {
    HapticFeedback.lightImpact();
    Navigator.push(
      context,
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 380),
        pageBuilder: (_, _, _) => ActorDetailScreen(actorId: actor.id),
        transitionsBuilder: (_, animation, _, child) {
          return FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0.05, 0),
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

  void _openDirector() {
    if (_directorId == null) return;
    HapticFeedback.lightImpact();
    Navigator.push(
      context,
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 380),
        pageBuilder: (_, _, _) => ActorDetailScreen(actorId: _directorId!),
        transitionsBuilder: (_, animation, _, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
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
              widget.movie.id,
              mediaType: _libraryMovie.mediaType,
            ) ==
            0
        ? 3
        : ReviewService.instance.getRating(
            widget.movie.id,
            mediaType: _libraryMovie.mediaType,
          );

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: _card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Padding(
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
                      final filled = i < rating;
                      return IconButton(
                        onPressed: () =>
                            setSheetState(() => rating = (i + 1).toDouble()),
                        icon: Icon(
                          filled
                              ? Icons.star_rounded
                              : Icons.star_border_rounded,
                          color: _gold,
                        ),
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
                  Row(
                    children: [
                      Checkbox(
                        value: spoilers,
                        activeColor: _gold,
                        onChanged: (v) =>
                            setSheetState(() => spoilers = v ?? false),
                      ),
                      const Text('Contains spoilers',
                          style: TextStyle(color: Colors.white70)),
                    ],
                  ),
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
                              if (sheetContext.mounted) {
                                Navigator.pop(sheetContext);
                              }
                              _toast('Review posted');
                            },
                      child: const Text('Post review',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  void dispose() {
    _autoPlayTimer?.cancel();
    _autoPlayTimer = null;
    _suppressAutoTrailer = true;
    _disposeTrailerPlayer();
    _fadeCtrl.dispose();
    _slideCtrl.dispose();
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final movie = widget.movie;
    final year = movie.releaseDate.isNotEmpty
        ? movie.releaseDate.split('-').first
        : 'N/A';
    final overview = (movie.overview != null && movie.overview!.isNotEmpty)
        ? movie.overview!
        : 'No overview available.';
    final size = MediaQuery.of(context).size;

    return PopScope(
      // System back gestures (Android predictive back, iOS edge swipe) skip
      // the explicit back-button handler below, so without this a trailer
      // can still be actively playing (and its Hero-wrapped child mid
      // teardown) at the exact moment the pop transition starts. Stopping
      // the trailer first on any pop path keeps the Hero flight and the
      // YouTube controller teardown from racing each other.
      canPop: !_isPlayingTrailer,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_isPlayingTrailer) _stopTrailer();
      },
      child: Scaffold(
        backgroundColor: _bg,
        body: Stack(
          children: [
          SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  height: size.height * 0.46,
                  width: double.infinity,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // Kept wrapped in a single, always-mounted Hero
                      // (tag never changes) and only swap the *child*
                      // between the video and the poster image. Making the
                      // Hero itself conditional on `_isPlayingTrailer` means
                      // it can vanish from the tree mid-flight — e.g. a
                      // predictive-back / edge-swipe gesture pop that fires
                      // while a trailer is playing — which is exactly the
                      // kind of state Flutter's Hero flight can't recover
                      // from cleanly and is a common source of a blank/black
                      // frame on the return transition.
                      Hero(
                        tag: _heroTag,
                        child: _isPlayingTrailer && _ytController != null
                            ? ClipRect(
                                child: Transform.scale(
                                  // YouTube's title/channel bar and logo
                                  // watermark are anchored to the edges of
                                  // the video frame. Zooming the whole embed
                                  // and clipping to our container pushes
                                  // that chrome outside the visible area,
                                  // leaving just the footage.
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
                                          // Unmute after autoplay has been granted.
                                          Future.delayed(
                                              const Duration(
                                                  milliseconds: 200), () {
                                            if (!mounted ||
                                                _ytController == null) {
                                              return;
                                            }
                                            try {
                                              _ytController!.unMute();
                                              setState(() =>
                                                  _isTrailerMuted = false);
                                            } catch (_) {}
                                          });
                                        } catch (_) {}
                                      },
                                    ),
                                  ),
                                ),
                              )
                            : CachedNetworkImage(
                                // Prefer the clean / textless artwork we fetched
                                imageUrl: _heroImageUrl ??
                                    (movie.posterUrl.isNotEmpty
                                        ? movie.posterUrl
                                        : (movie.backdropUrl ?? '')),
                                fit: BoxFit.cover,
                                alignment: Alignment.topCenter,
                                memCacheWidth: 600,
                                placeholder: (_, _) =>
                                    Container(color: const Color(0xFF111111)),
                                errorWidget: (_, _, _) =>
                                    Container(color: const Color(0xFF111111)),
                              ),
                      ),
                      if (!_hasTrailer && !_isPlayingTrailer)
                        AnimatedBuilder(
                          animation: _pulseCtrl,
                          builder: (_, _) {
                            return Container(
                              decoration: BoxDecoration(
                                gradient: RadialGradient(
                                  center: Alignment.center,
                                  radius: 1.2,
                                  colors: [
                                    _gold.withValues(
                                        alpha: 0.04 + 0.03 * _pulseCtrl.value),
                                    Colors.transparent,
                                  ],
                                ),
                              ),
                            );
                          },
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
                                colors: [
                                  Color(0xFF000000),
                                  Color(0xFF000000),
                                  Color(0x00000000),
                                ],
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
                          height: 92,
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.bottomCenter,
                                end: Alignment.topCenter,
                                colors: [
                                  _bg,
                                  _bg,
                                  _bg.withValues(alpha: 0.9),
                                  Colors.transparent,
                                ],
                                stops: const [0.0, 0.45, 0.75, 1.0],
                              ),
                            ),
                          ),
                        ),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.black.withValues(alpha: 0.25),
                              Colors.transparent,
                              _bg.withValues(alpha: 0.7),
                              _bg,
                            ],
                            stops: const [0.0, 0.4, 0.82, 1.0],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                FadeTransition(
                  opacity: _fadeAnim,
                  child: SlideTransition(
                    position: _slideAnim,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(18, 0, 18, 40),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Pull title/logo slightly up into the hero fade
                          // Fixed-size container + forced left alignment from frame 0
                          // prevents the logo from flashing in the center then jumping.
                          Transform.translate(
                            offset: const Offset(0, -18),
                            child: SizedBox(
                              height: 64,
                              width: double.infinity,
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: (_logoUrl != null && _logoUrl!.isNotEmpty)
                                    ? CachedNetworkImage(
                                        imageUrl: _logoUrl!,
                                        height: 64,
                                        fit: BoxFit.contain,
                                        alignment: Alignment.centerLeft,
                                        memCacheHeight: 128,
                                        placeholder: (_, _) => const SizedBox(
                                          height: 64,
                                          width: 200,
                                        ),
                                        errorWidget: (_, _, _) => Text(
                                          movie.title,
                                          style: FontService.instance.display(
                                            color: Colors.white,
                                            fontSize: 26,
                                            fontWeight: FontWeight.w800,
                                            height: 1.15,
                                          ),
                                        ),
                                      )
                                    : Text(
                                        movie.title,
                                        style: FontService.instance.display(
                                          color: Colors.white,
                                          fontSize: 26,
                                          fontWeight: FontWeight.w800,
                                          height: 1.15,
                                        ),
                                      ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          GestureDetector(
                            onTap: () => setState(
                                () => _overviewExpanded = !_overviewExpanded),
                            child: Text(
                              overview,
                              maxLines: _overviewExpanded ? 20 : 3,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 13.5,
                                height: 1.45,
                              ),
                            ),
                          ),
                          if (overview.length > 120)
                            GestureDetector(
                              onTap: () => setState(
                                  () => _overviewExpanded = !_overviewExpanded),
                              child: Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  _overviewExpanded
                                      ? 'Show less'
                                      : 'Read More ∨',
                                  style: FontService.instance.label(
                                    color: Colors.white54,
                                    fontSize: 12,
                                    letterSpacing: 0.3,
                                  ),
                                ),
                              ),
                            ),
                          const SizedBox(height: 14),
                          Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            children: [
                              _metaChip(_mediaLabel),
                              _metaChip(
                                  '★ ${movie.voteAverage.toStringAsFixed(1)}',
                                  gold: true),
                              _metaChip(year),
                              if (_runtime.isNotEmpty) _metaChip(_runtime),
                              if (_parentalRating.isNotEmpty)
                                _metaChip(_parentalRating, gold: true),
                            ],
                          ),
                          if (_genres.isNotEmpty && _genres != '—') ...[
                            const SizedBox(height: 8),
                            Text(
                              _genres,
                              style: FontService.instance.label(
                                color: Colors.white54,
                                fontSize: 12,
                                letterSpacing: 0.2,
                              ),
                            ),
                          ],
                          const SizedBox(height: 18),
                          // Stream/Download or Coming Soon
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 300),
                            transitionBuilder: (child, animation) {
                              return FadeTransition(
                                opacity: animation,
                                child: SlideTransition(
                                  position: Tween<Offset>(
                                    begin: const Offset(0.0, 0.1),
                                    end: Offset.zero,
                                  ).animate(CurvedAnimation(
                                    parent: animation,
                                    curve: Curves.easeOutCubic,
                                  )),
                                  child: child,
                                ),
                              );
                            },
                            child: _isAvailable
                                ? _buildActionButtons()
                                : _buildComingSoon(),
                          ),
                          const SizedBox(height: 16),
                          ListenableBuilder(
                            listenable: UserLibraryService.instance,
                            builder: (context, _) {
                              final lib = UserLibraryService.instance;
                              final bookmarked =
                                  lib.isInWatchlistMovie(_libraryMovie);
                              final watched =
                                  lib.isWatchedMovie(_libraryMovie);
                              final liked = lib.isLikedMovie(_libraryMovie);
                              final inList = lib.isInMyListMovie(_libraryMovie);
                              return Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  AnimatedToggleIcon(
                                    active: bookmarked,
                                    activeIcon: Icons.bookmark_rounded,
                                    inactiveIcon: Icons.bookmark_add_outlined,
                                    label: 'Watchlist',
                                    onTap: _toggleBookmark,
                                  ),
                                  AnimatedToggleIcon(
                                    active: watched,
                                    activeIcon: Icons.visibility_rounded,
                                    inactiveIcon: Icons.visibility_outlined,
                                    label: 'Watched',
                                    onTap: _toggleWatched,
                                  ),
                                  AnimatedToggleIcon(
                                    active: inList,
                                    activeIcon:
                                        Icons.playlist_add_check_rounded,
                                    inactiveIcon: Icons.playlist_add_rounded,
                                    label: 'List',
                                    onTap: _addToList,
                                  ),
                                  AnimatedToggleIcon(
                                    active: liked,
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
                                  letterSpacing: 0.3,
                                ),
                              ),
                              const SizedBox(height: 10),
                              SizedBox(
                                height: 160,
                                child: ListView.builder(
                                  scrollDirection: Axis.horizontal,
                                  physics: const BouncingScrollPhysics(),
                                  itemCount: _directorMovies.length,
                                  itemBuilder: (context, index) {
                                    final m = _directorMovies[index];
                                    return GestureDetector(
                                      onTap: () {
                                        Navigator.pushReplacement(
                                          context,
                                          PageRouteBuilder(
                                            transitionDuration: const Duration(
                                                milliseconds: 320),
                                            pageBuilder: (_, _, _) =>
                                                DetailScreen(
                                              movie: m,
                                              isTv: m.mediaType == 'tv',
                                            ),
                                            transitionsBuilder:
                                                (_, animation, _, child) =>
                                                    FadeTransition(
                                                        opacity: animation,
                                                        child: child),
                                          ),
                                        );
                                      },
                                      child: Container(
                                        width: 100,
                                        margin: const EdgeInsets.only(right: 10),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Expanded(
                                              child: ClipRRect(
                                                borderRadius:
                                                    BorderRadius.circular(10),
                                                child: CachedNetworkImage(
                                                  imageUrl: m.posterUrl,
                                                  fit: BoxFit.cover,
                                                  width: double.infinity,
                                                  memCacheWidth: 240,
                                                  placeholder: (_, _) =>
                                                      Container(
                                                          color: const Color(
                                                              0xFF1A1A1A)),
                                                  errorWidget: (_, _, _) =>
                                                      Container(
                                                          color:
                                                              Colors.grey[900]),
                                                ),
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              m.title,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 11),
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ],
                          ],
                          if (!_isLoading && _cast.isNotEmpty) ...[
                            const SizedBox(height: 22),
                            _sectionTitle('Actors'),
                            const SizedBox(height: 12),
                            _buildActorsGrid(),
                          ],

                          // ---- Studios Section ----
                          if (_studios.isNotEmpty) ...[
                            const SizedBox(height: 22),
                            _buildStudiosSection(),
                          ],

                          const SizedBox(height: 22),
                          _sectionTitle("How it's rated"),
                          const SizedBox(height: 12),
                          _buildRatingsRow(),
                          const SizedBox(height: 22),
                          _buildReviewsSection(),
                          if (!_isLoading && _similarMovies.isNotEmpty) ...[
                            const SizedBox(height: 22),
                            _sectionTitle('More like this'),
                            const SizedBox(height: 12),
                            _buildSimilarGrid(),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _circleBtn(
                        Icons.arrow_back_rounded,
                        () {
                          if (_isPlayingTrailer) {
                            _stopTrailer();
                          } else {
                            Navigator.pop(context);
                          }
                        },
                      ),
                      const SizedBox(width: 8),
                      _circleBtn(Icons.home_rounded, () {
                        Navigator.popUntil(context, (r) => r.isFirst);
                      }),
                    ],
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_isPlayingTrailer)
                        GestureDetector(
                          onTap: _toggleTrailerMute,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _isTrailerMuted
                                  ? Colors.black.withValues(alpha: 0.55)
                                  : _gold.withValues(alpha: 0.25),
                              border: Border.all(
                                color: _isTrailerMuted
                                    ? Colors.white24
                                    : _gold.withValues(alpha: 0.7),
                              ),
                            ),
                            child: Icon(
                              _isTrailerMuted
                                  ? Icons.volume_off_rounded
                                  : Icons.volume_up_rounded,
                              color:
                                  _isTrailerMuted ? Colors.white : _gold,
                              size: 18,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (_isLoading)
            const Center(
              child: CircularProgressIndicator(
                color: _gold,
                strokeWidth: 2.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButtons() {
    // Layout: [Stream] [Download] [Trailer] — Download centered between
    // Stream and Trailer for both movies and TV series.
    return Row(
      children: [
        Expanded(
          child: Pressable(
            onTap: () => _openServerSelector(),
            child: _primaryBtn(
              icon: Icons.play_arrow_rounded,
              label: 'Stream',
              filled: true,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Pressable(
            onTap: () => _openDownloadSheet(),
            child: _primaryBtn(
              icon: Icons.download_rounded,
              label: 'Download',
              filled: false,
              goldBg: true,
            ),
          ),
        ),
        if (_hasTrailer) ...[
          const SizedBox(width: 10),
          Expanded(
            child: Pressable(
              onTap: () {
                _suppressAutoTrailer = false;
                _startTrailer();
              },
              child: _primaryBtn(
                icon: Icons.play_circle_outline,
                label: 'Trailer',
                filled: false,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildComingSoon() {
    final releaseDate = widget.movie.releaseDate;
    String dateStr = 'Unknown';
    if (releaseDate.isNotEmpty) {
      try {
        final dt = DateTime.parse(releaseDate);
        dateStr = '${_monthAbbr[dt.month - 1]} ${dt.day}, ${dt.year}';
      } catch (_) {
        dateStr = releaseDate;
      }
    }
    return Container(
      height: 44,
      width: double.infinity,
      decoration: BoxDecoration(
        color: _gold.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _gold.withValues(alpha: 0.3)),
      ),
      child: Center(
        child: Text(
          'Coming Soon • $dateStr',
          style: const TextStyle(
            color: _gold,
            fontWeight: FontWeight.w700,
            fontSize: 14,
          ),
        ),
      ),
    );
  }

  static const List<String> _monthAbbr = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];

  Widget _verticalInfoCard() {
    final rows = <MapEntry<String, String>>[
      MapEntry('PARENTAL RATING', _parentalRating.isNotEmpty ? _parentalRating : '—'),
      MapEntry('TYPE', _mediaLabel),
      if (_runtime.isNotEmpty) MapEntry(_isTv ? 'EPISODE DURATION' : 'RUNTIME', _runtime),
      MapEntry('COUNTRY OF ORIGIN', _countries),
      if (_audience.isNotEmpty) MapEntry('AUDIENCE', _audience.join(', ')),
      if (_tags.isNotEmpty) MapEntry('TAGS', _tags.join(', ')),
      if (_genres.isNotEmpty && _genres != '—') MapEntry('GENRES', _genres),
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
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

  Widget _buildSeasonSelector() {
    if (_seasons.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: _seasons.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final season = _seasons[index];
          final seasonNumber = season['season_number'] as int? ?? (index + 1);
          final seasonName = season['name'] as String? ?? 'Season $seasonNumber';
          final isSelected = _selectedSeason == seasonNumber;

          return GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() => _selectedSeason = seasonNumber);
              _loadEpisodesForSeason(seasonNumber);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: isSelected ? _gold : Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: isSelected ? _gold : Colors.white.withValues(alpha: 0.12),
                ),
              ),
              child: Center(
                child: Text(
                  seasonName,
                  style: TextStyle(
                    color: isSelected ? Colors.black : Colors.white70,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
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

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _episodes.length,
      itemBuilder: (context, index) {
        final ep = _episodes[index];
        final epNum = ep['episode_number'] as int? ?? (index + 1);
        final epName = ep['name'] as String? ?? 'Episode $epNum';
        final epOverview = ep['overview'] as String? ?? 'No description available.';
        final stillPath = ep['still_path'] as String?;
        final stillUrl = stillPath != null ? 'https://image.tmdb.org/t/p/w300$stillPath' : null;

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: _card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: 110,
                  height: 68,
                  child: stillUrl != null
                      ? CachedNetworkImage(
                          imageUrl: stillUrl,
                          fit: BoxFit.cover,
                          memCacheWidth: 220,
                          placeholder: (_, _) =>
                              Container(color: const Color(0xFF1A1A1A)),
                          errorWidget: (_, _, _) =>
                              Container(color: Colors.grey[900]),
                        )
                      : Container(
                          color: Colors.grey[900],
                          child: const Icon(Icons.tv, color: Colors.white38),
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'E$epNum. $epName',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      epOverview,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white60,
                        fontSize: 11.5,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 8),
                    // TV episodes: Play only (download lives on the main action row).
                    GestureDetector(
                      onTap: () => _openServerSelector(
                        season: _selectedSeason ?? 1,
                        episode: epNum,
                      ),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 5),
                        decoration: BoxDecoration(
                          color: _gold.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.play_arrow_rounded,
                                color: _gold, size: 14),
                            SizedBox(width: 4),
                            Text(
                              'Play',
                              style: TextStyle(
                                color: _gold,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
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
    );
  }

  Widget _metaChip(String text, {bool gold = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: gold
            ? _gold.withValues(alpha: 0.15)
            : Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: gold
              ? _gold.withValues(alpha: 0.4)
              : Colors.white.withValues(alpha: 0.12),
        ),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: gold ? _gold : Colors.white70,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _primaryBtn({
    required IconData icon,
    required String label,
    bool filled = false,
    bool goldBg = false,
  }) {
    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: filled
            ? Colors.white
            : goldBg
                ? _gold
                : Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(22),
        border: filled || goldBg
            ? null
            : Border.all(color: Colors.white.withValues(alpha: 0.14)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon,
              color: filled || goldBg ? Colors.black : Colors.white70,
              size: 18),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: filled || goldBg ? Colors.black : Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
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
              style: const TextStyle(color: Colors.white70, fontSize: 13.5),
            ),
          ),
        ],
      ),
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

  Widget _personTile({
    required String name,
    required String role,
    String? photoUrl,
  }) {
    return Row(
      children: [
        CircleAvatar(
          radius: 28,
          backgroundColor: Colors.grey[850],
          backgroundImage:
              photoUrl != null ? NetworkImage(photoUrl) : null,
          child: photoUrl == null
              ? const Icon(Icons.person, color: Colors.white54)
              : null,
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
                      color: Colors.white54,
                      fontSize: 11,
                      letterSpacing: 0.3)),
            ],
          ),
        ),
        const Icon(Icons.chevron_right_rounded, color: Colors.white38, size: 20),
      ],
    );
  }

  Widget _buildActorsGrid() {
    final visible = _showAllCast ? _cast : _cast.take(8).toList();
    return Column(
      children: [
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 4,
            childAspectRatio: 0.72,
            crossAxisSpacing: 10,
            mainAxisSpacing: 12,
          ),
          itemCount: visible.length,
          itemBuilder: (context, index) {
            final actor = visible[index];
            return GestureDetector(
              onTap: () => _openActor(actor),
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 32,
                    backgroundColor: Colors.grey[850],
                    backgroundImage: actor.profilePath != null
                        ? NetworkImage(
                            'https://image.tmdb.org/t/p/w185${actor.profilePath}')
                        : null,
                    child: actor.profilePath == null
                        ? const Icon(Icons.person, color: Colors.white54)
                        : null,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    actor.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w500),
                  ),
                  Text(
                    'Actor',
                    style: FontService.instance.label(
                        color: Colors.white38,
                        fontSize: 10,
                        letterSpacing: 0.2),
                  ),
                ],
              ),
            );
          },
        ),
        if (_cast.length > 8)
          GestureDetector(
            onTap: () => setState(() => _showAllCast = !_showAllCast),
            child: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _showAllCast
                    ? 'Show less'
                    : 'Show ${_cast.length - 8} more ∨',
                style: FontService.instance.label(
                    color: Colors.white54, fontSize: 12.5, letterSpacing: 0.3),
              ),
            ),
          ),
      ],
    );
  }

  // ---- Studios Section ----
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
                color: _gold,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              'Studios',
              style: FontService.instance.display(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // Full-width studio cards (uniform width edge-to-edge within padding).
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: visible.map((studio) {
            return Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _card,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
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
                        memCacheWidth: 80,
                        errorWidget: (_, _, _) =>
                            const SizedBox.shrink(),
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
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
        if (_studios.length > 3)
          GestureDetector(
            onTap: () => setState(() => _showAllStudios = !_showAllStudios),
            child: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _showAllStudios
                    ? 'Show less'
                    : 'Show ${_studios.length - 3} more ∨',
                style: FontService.instance.label(
                  color: Colors.white54,
                  fontSize: 12.5,
                  letterSpacing: 0.3,
                ),
              ),
            ),
          ),
      ],
    );
  }

  // ---- Enhanced Ratings Row ----
  Widget _buildRatingsRow() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 100,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            itemCount: _ratings.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              final r = _ratings[index];
              return _buildRatingCard(r);
            },
          ),
        ),
        const SizedBox(height: 8),
        // Aggregate summary
        FutureBuilder<double>(
          future: _calculateMeanRating(),
          builder: (context, snapshot) {
            final mean = snapshot.data ?? 0.0;
            final totalVotes = _ratings.fold(0, (sum, r) => sum + r.votes);
            return Text(
              'Mean rating ${mean.toStringAsFixed(1)}/10 • Aggregated from $totalVotes voters across the web.',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: 11,
              ),
            );
          },
        ),
      ],
    );
  }

  Future<double> _calculateMeanRating() async {
    // Simple average of all normalized scores to /10
    double sum = 0;
    int count = 0;
    for (final r in _ratings) {
      final normalized = r.score / r.outOf * 10;
      sum += normalized;
      count++;
    }
    return count > 0 ? sum / count : 0.0;
  }

  Widget _buildRatingCard(RatingSource source) {
    // Determine card style based on source name
    if (source.name.toLowerCase() == 'letterboxd') {
      return _buildLetterboxdCard(source);
    } else if (source.name.toLowerCase() == 'imdb') {
      return _buildImdbCard(source);
    } else {
      // Default style (TMDB)
      return _buildGenericCard(source);
    }
  }

  Widget _buildLetterboxdCard(RatingSource source) {
    final double score5 = source.score; // score is out of 5
    final double score10 = score5 / 5 * 10;
    return Container(
      width: 160,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Text(
                score5.toStringAsFixed(1),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 4),
              const Text(
                '/5',
                style: TextStyle(color: Colors.white54, fontSize: 13),
              ),
              const SizedBox(width: 8),
              Text(
                '(${score10.toStringAsFixed(1)}/10)',
                style: const TextStyle(color: Colors.white38, fontSize: 11),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              // Simulate Letterboxd dots (5 dots, filled based on score)
              for (int i = 0; i < 5; i++)
                Icon(
                  i < score5.round() ? Icons.circle : Icons.circle_outlined,
                  size: 10,
                  color: i < score5.round() ? _gold : Colors.white38,
                ),
              const SizedBox(width: 8),
              Text(
                '${source.votes} votes',
                style: const TextStyle(color: Colors.white38, fontSize: 10),
              ),
            ],
          ),
          Text(
            source.name.toUpperCase(),
            style: FontService.instance.label(
              color: Colors.white70,
              fontSize: 10.5,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImdbCard(RatingSource source) {
    return Container(
      width: 160,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Text(
                source.score.toStringAsFixed(1),
                style: const TextStyle(
                  color: Colors.amber, // IMDb yellow
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 4),
              const Text(
                '/10',
                style: TextStyle(color: Colors.white54, fontSize: 13),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.amber,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'IMDb',
                  style: TextStyle(
                    color: Colors.black,
                    fontSize: 8,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${source.votes} votes',
            style: const TextStyle(color: Colors.white38, fontSize: 10),
          ),
          Text(
            source.name.toUpperCase(),
            style: FontService.instance.label(
              color: Colors.white70,
              fontSize: 10.5,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGenericCard(RatingSource source) {
    return Container(
      width: 140,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          RichText(
            text: TextSpan(
              children: [
                TextSpan(
                  text: source.score.toStringAsFixed(1),
                  style: const TextStyle(
                    color: _gold,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                TextSpan(
                  text: ' /${source.outOf.toStringAsFixed(0)}',
                  style: const TextStyle(
                    color: Colors.white54, fontSize: 13),
                ),
              ],
            ),
          ),
          Text(
            '${source.votes} votes',
            style: const TextStyle(color: Colors.white38, fontSize: 10),
          ),
          Text(
            source.name.toUpperCase(),
            style: FontService.instance.label(
              color: Colors.white70,
              fontSize: 10.5,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }

  // ---- Reviews ----
  Widget _buildReviewsSection() {
    return ListenableBuilder(
      listenable: ReviewService.instance,
      builder: (context, _) {
        final reviews = ReviewService.instance.getReviews(
          widget.movie.id,
          mediaType: _libraryMovie.mediaType,
        );
        final userRating = ReviewService.instance.getRating(
          widget.movie.id,
          mediaType: _libraryMovie.mediaType,
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _sectionTitle('Reviews  ${reviews.length}'),
                TextButton(
                  onPressed: _openPostReview,
                  style: TextButton.styleFrom(foregroundColor: _gold),
                  child: const Text('Post review',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(14),
                border:
                    Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
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
                      final filled = i < userRating;
                      return IconButton(
                        onPressed: () => _rateTitle(i + 1),
                        icon: Icon(
                          filled
                              ? Icons.star_rounded
                              : Icons.star_border_rounded,
                          color: _gold,
                          size: 28,
                        ),
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
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.4))),
              )
            else
              ...reviews.take(5).map(_buildUserReviewTile),
          ],
        );
      },
    );
  }

  Widget _buildUserReviewTile(UserReview r) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
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
                            color: Colors.white, fontWeight: FontWeight.bold)),
                    Text(
                      '${r.date.month}/${r.date.day}/${r.date.year}',
                      style: FontService.instance.label(
                          color: Colors.white38,
                          fontSize: 10.5,
                          letterSpacing: 0.3),
                    ),
                  ],
                ),
              ),
              Row(
                children: List.generate(5, (i) {
                  final filled = i < r.rating.round();
                  return Icon(
                    filled ? Icons.star_rounded : Icons.star_border_rounded,
                    color: _gold,
                    size: 14,
                  );
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
    return SizedBox(
      height: 210,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: _similarMovies.length,
        itemBuilder: (context, index) {
          final m = _similarMovies[index];
          return GestureDetector(
            onTap: () {
              Navigator.pushReplacement(
                context,
                PageRouteBuilder(
                  transitionDuration: const Duration(milliseconds: 320),
                  pageBuilder: (_, _, _) => DetailScreen(
                    movie: m,
                    isTv: m.mediaType == 'tv',
                  ),
                  transitionsBuilder: (_, animation, _, child) =>
                      FadeTransition(opacity: animation, child: child),
                ),
              );
            },
            child: Container(
              width: 120,
              margin: const EdgeInsets.only(right: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          CachedNetworkImage(
                            imageUrl: m.posterUrl,
                            fit: BoxFit.cover,
                            alignment: Alignment.topCenter,
                            memCacheWidth: 240,
                            placeholder: (_, _) =>
                                Container(color: const Color(0xFF1A1A1A)),
                            errorWidget: (_, _, _) =>
                                Container(color: Colors.grey[900]),
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
                                        m.voteAverage.toStringAsFixed(1),
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
                                    m.releaseYear,
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
                    m.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
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

  Widget _circleBtn(IconData icon, VoidCallback onTap) {
    return Pressable(
      onTap: onTap,
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.black.withValues(alpha: 0.45),
          border: Border.all(color: Colors.white24),
        ),
        child: Icon(icon, color: Colors.white, size: 18),
      ),
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
    return GestureDetector(
      onTap: () => setState(() => _revealed = true),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Row(
          children: [
            Icon(Icons.visibility_outlined, color: Colors.white54, size: 16),
            SizedBox(width: 8),
            Text('This review may contain spoilers — tap to show',
                style: TextStyle(color: Colors.white54, fontSize: 12.5)),
          ],
        ),
      ),
    );
  }
}