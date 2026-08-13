import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';
import '../models/movie.dart';
import '../models/cast_member.dart';
import '../services/font_service.dart';
import '../widgets/available_downloads_sheet.dart';
import '../widgets/server_selector_sheet.dart';
import '../services/tmdb_details_service.dart';
import 'actor_detail_screen.dart';

const _gold = Color(0xFFFFB800);
const _bg = Color(0xFF0A0A0A);
const _card = Color(0xFF141414);

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
  final List<RatingSource>? ratingSources;
  final List<StudioInfo>? studios;
  final List<String>? tags;
  final List<String>? audience;
  final List<Review>? reviews;

  const DetailScreen({
    super.key,
    required this.movie,
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
  bool _isBookmarked = false;
  bool _isWatched = false;
  bool _isLiked = false;
  bool _isInList = false;
  bool _isLoading = true;
  bool _isPlayingTrailer = false;
  bool _isTrailerMuted = false; // start unmuted; user toggles via top-bar mute
  final bool _showAllStudios = false;
  bool _showAllCast = false;
  bool _overviewExpanded = false;
  double _userRating = 0;

  List<Movie> _similarMovies = [];
  List<CastMember> _cast = [];
  String? _trailerKey;
  String? _logoUrl;
  String? _directorName;
  String? _directorPhoto;

  late List<RatingSource> _ratings;
  late List<StudioInfo> _studios;
  late List<String> _tags;
  late List<String> _audience;
  late List<Review> _reviews;

  YoutubePlayerController? _ytController;
  Timer? _autoPlayTimer;

  late AnimationController _fadeCtrl;
  late AnimationController _slideCtrl;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  final TmdbDetailsService _tmdbService = TmdbDetailsService();

  @override
  void initState() {
    super.initState();

    _ratings = widget.ratingSources ?? _fallbackRatings();
    _studios = widget.studios ?? _fallbackStudios();
    _tags = widget.tags ?? const ['sci-fi', 'action', 'drama'];
    _audience = widget.audience ?? const ['adult'];
    _reviews = widget.reviews ?? [];

    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _slideCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.06),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _slideCtrl, curve: Curves.easeOutCubic));

    _loadAllMetadata();
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
          score: widget.movie.voteAverage,
          outOf: 10,
          votes: 0,
        ),
      ];

  List<StudioInfo> _fallbackStudios() => const [];

  Future<void> _loadAllMetadata() async {
    try {
      final tmdbId = widget.movie.id;

      final results = await Future.wait([
        _tmdbService.getSimilarMovies(tmdbId),
        _tmdbService.getCast(tmdbId),
        _tmdbService.getTrailerKey(tmdbId),
        _tmdbService.getMovieLogo(tmdbId),
      ]);

      if (!mounted) return;

      final cast = results[1] as List<CastMember>;
      String? dirName;
      String? dirPhoto;
      if (cast.isNotEmpty) {
        dirName = null;
      }

      setState(() {
        _similarMovies = (results[0] as List<Movie>)
            .where((m) => m.id != widget.movie.id)
            .take(14)
            .toList();
        _cast = cast;
        _trailerKey = results[2] as String?;
        _logoUrl = results[3] as String?;
        _directorName = dirName;
        _directorPhoto = dirPhoto;
        _isLoading = false;
      });

      _fadeCtrl.forward();
      _slideCtrl.forward();

      if (_trailerKey != null && _trailerKey!.isNotEmpty) {
        _autoPlayTimer?.cancel();
        _autoPlayTimer = Timer(const Duration(seconds: 3), () {
          if (mounted && !_isPlayingTrailer) {
            _startTrailer();
          }
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoading = false);
        _fadeCtrl.forward();
        _slideCtrl.forward();
      }
    }
  }

  void _startTrailer() {
    if (_trailerKey == null || _trailerKey!.isEmpty) {
      _toast('No trailer available');
      return;
    }

    HapticFeedback.mediumImpact();

    _ytController?.dispose();
    _ytController = YoutubePlayerController(
      initialVideoId: _trailerKey!,
      flags: const YoutubePlayerFlags(
        autoPlay: true,
        mute: false,
        enableCaption: false,
        hideControls: true,
        controlsVisibleAtStart: false,
        disableDragSeek: true,
        showLiveFullscreenButton: false,
        forceHD: true,
        useHybridComposition: true,
      ),
    )..addListener(_trailerListener);

    setState(() {
      _isPlayingTrailer = true;
      _isTrailerMuted = false;
    });

    Future.delayed(const Duration(milliseconds: 400), () {
      if (mounted && _ytController != null && _isPlayingTrailer) {
        _ytController!.play();
        if (!_isTrailerMuted) {
          _ytController!.unMute();
        }
      }
    });
  }

  void _trailerListener() {
    if (_ytController == null) return;
    final state = _ytController!.value.playerState;
    if (state == PlayerState.ended) {
      _stopTrailer();
    }
  }

  void _stopTrailer() {
    _ytController?.removeListener(_trailerListener);
    try {
      _ytController?.pause();
    } catch (_) {}
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

  void _toggleBookmark() {
    HapticFeedback.selectionClick();
    setState(() => _isBookmarked = !_isBookmarked);
    _toast(_isBookmarked
        ? '"${widget.movie.title}" added to Watchlist'
        : '"${widget.movie.title}" removed from Watchlist');
  }

  void _toggleWatched() {
    HapticFeedback.selectionClick();
    setState(() => _isWatched = !_isWatched);
    _toast(_isWatched
        ? 'Marked "${widget.movie.title}" as watched'
        : 'Marked "${widget.movie.title}" as unwatched');
  }

  void _toggleLiked() {
    HapticFeedback.selectionClick();
    setState(() => _isLiked = !_isLiked);
    _toast(_isLiked ? 'Added to Liked titles' : 'Removed from Liked titles');
  }

  void _addToList() {
    HapticFeedback.selectionClick();
    setState(() => _isInList = !_isInList);
    _toast(_isInList ? 'Added to a list' : 'Removed from list');
  }

  void _openServerSelector() {
    HapticFeedback.mediumImpact();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ServerSelectorSheet(
        tmdbId: widget.movie.id.toString(),
        movieTitle: widget.movie.title,
        mediaType: 'movie',
      ),
    );
  }

  void _openDownloadSheet() {
    HapticFeedback.mediumImpact();
    AvailableDownloadsSheet.show(
      context,
      movieTitle: widget.movie.title,
      tmdbId: widget.movie.id.toString(),
      posterUrl: widget.movie.posterUrl,
    );
  }

  void _shareMovie() {
    HapticFeedback.lightImpact();
    _toast('Share link for "${widget.movie.title}" copied');
  }

  void _openMoreMenu() {
    HapticFeedback.selectionClick();
    showModalBottomSheet(
      context: context,
      backgroundColor: _card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 12),
            _menuTile(Icons.playlist_add_rounded, 'Add to a list', _addToList),
            _menuTile(
              _isWatched
                  ? Icons.check_circle_rounded
                  : Icons.check_circle_outline_rounded,
              _isWatched ? 'Mark as unwatched' : 'Mark as watched',
              _toggleWatched,
            ),
            _menuTile(Icons.ios_share_rounded, 'Share', _shareMovie),
            _menuTile(Icons.flag_outlined, 'Report an issue',
                () => _toast('Thanks — we\'ll take a look')),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _menuTile(IconData icon, String label, VoidCallback onTap) {
    return ListTile(
      leading: Icon(icon, color: Colors.white),
      title: Text(label, style: const TextStyle(color: Colors.white)),
      onTap: () {
        Navigator.pop(context);
        onTap();
      },
    );
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

  void _rateTitle(int stars) {
    HapticFeedback.mediumImpact();
    setState(() => _userRating = stars.toDouble());
    _toast('You rated this $stars/5');
  }

  void _openPostReview() {
    HapticFeedback.selectionClick();
    final controller = TextEditingController();
    bool spoilers = false;
    double rating = _userRating == 0 ? 3 : _userRating;

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
                          : () {
                              setState(() {
                                _reviews.insert(
                                  0,
                                  Review(
                                    username: 'you',
                                    date: DateTime.now(),
                                    rating: rating,
                                    body: controller.text.trim(),
                                    containsSpoilers: spoilers,
                                  ),
                                );
                                _userRating = rating;
                              });
                              Navigator.pop(sheetContext);
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
    _ytController?.removeListener(_trailerListener);
    _ytController?.dispose();
    _fadeCtrl.dispose();
    _slideCtrl.dispose();
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

    return Scaffold(
      backgroundColor: _bg,
      body: Stack(
        children: [
          SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  height: size.height * 0.38,
                  width: double.infinity,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (_isPlayingTrailer && _ytController != null)
                        IgnorePointer(
                          child: YoutubePlayer(
                            controller: _ytController!,
                            showVideoProgressIndicator: false,
                            bottomActions: const [],
                            topActions: const [],
                            onReady: () {
                              _ytController!.play();
                            },
                          ),
                        )
                      else
                        Image.network(
                          movie.backdropUrl ?? movie.posterUrl,
                          fit: BoxFit.cover,
                          alignment: Alignment.topCenter,
                          errorBuilder: (_, _, _) =>
                              Container(color: const Color(0xFF111111)),
                        ),
                      if (_isPlayingTrailer)
                        Positioned(
                          top: 0,
                          left: 0,
                          right: 0,
                          height: 72,
                          child: Container(
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Color(0xF2000000),
                                  Color(0xCC000000),
                                  Color(0x00000000),
                                ],
                              ),
                            ),
                          ),
                        ),
                      if (_isPlayingTrailer)
                        Positioned(
                          bottom: 0,
                          left: 0,
                          right: 0,
                          height: 64,
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.bottomCenter,
                                end: Alignment.topCenter,
                                colors: [
                                  _bg,
                                  _bg,
                                  _bg.withValues(alpha: 0.85),
                                  Colors.transparent,
                                ],
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
                          if (_logoUrl != null && _logoUrl!.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8.0),
                              child: Image.network(
                                _logoUrl!,
                                height: 60,
                                fit: BoxFit.contain,
                                alignment: Alignment.centerLeft,
                                errorBuilder: (_, _, _) => Text(
                                  movie.title,
                                  style: FontService.instance.display(
                                    color: Colors.white,
                                    fontSize: 26,
                                    fontWeight: FontWeight.w800,
                                    height: 1.15,
                                  ),
                                ),
                              ),
                            )
                          else
                            Text(
                              movie.title,
                              style: FontService.instance.display(
                                color: Colors.white,
                                fontSize: 26,
                                fontWeight: FontWeight.w800,
                                height: 1.15,
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
                              _metaChip('Movie'),
                              _metaChip(
                                  '★ ${movie.voteAverage.toStringAsFixed(1)}',
                                  gold: true),
                              _metaChip(year),
                              _metaChip('2h 44m'),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Action, Drama, Mystery',
                            style: FontService.instance.label(
                              color: Colors.white54,
                              fontSize: 12,
                              letterSpacing: 0.2,
                            ),
                          ),
                          const SizedBox(height: 18),
                          Row(
                            children: [
                              Expanded(
                                child: _primaryBtn(
                                  icon: Icons.play_arrow_rounded,
                                  label: 'Stream',
                                  filled: true,
                                  onTap: _openServerSelector,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _primaryBtn(
                                  icon: Icons.download_rounded,
                                  label: 'Download',
                                  filled: false,
                                  goldBg: true,
                                  onTap: _openDownloadSheet,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _primaryBtn(
                                  icon: Icons.play_circle_outline,
                                  label: 'Trailer',
                                  filled: false,
                                  onTap: _startTrailer,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              _quickAction(
                                _isBookmarked
                                    ? Icons.bookmark_rounded
                                    : Icons.bookmark_add_outlined,
                                'Watchlist',
                                _isBookmarked,
                                _toggleBookmark,
                              ),
                              _quickAction(
                                _isWatched
                                    ? Icons.visibility_rounded
                                    : Icons.visibility_outlined,
                                'Watched',
                                _isWatched,
                                _toggleWatched,
                              ),
                              _quickAction(
                                _isInList
                                    ? Icons.playlist_add_check_rounded
                                    : Icons.playlist_add_rounded,
                                'List',
                                _isInList,
                                _addToList,
                              ),
                              _quickAction(
                                _isLiked
                                    ? Icons.favorite_rounded
                                    : Icons.favorite_border_rounded,
                                'Like',
                                _isLiked,
                                _toggleLiked,
                              ),
                              _quickAction(Icons.ios_share_rounded, 'Share',
                                  false, _shareMovie),
                            ],
                          ),
                          const SizedBox(height: 22),
                          _infoRow('PARENTAL RATING', 'R'),
                          _infoRow('COUNTRY OF ORIGIN',
                              'United States, Canada, Spain'),
                          if (_audience.isNotEmpty)
                            _infoRow('AUDIENCE', _audience.join(', ')),
                          if (_tags.isNotEmpty)
                            _infoRow('TAGS', _tags.join(', ')),
                          if (_directorName != null) ...[
                            const SizedBox(height: 22),
                            _sectionTitle('Director'),
                            const SizedBox(height: 12),
                            _personTile(
                              name: _directorName!,
                              role: 'Director',
                              photoUrl: _directorPhoto,
                            ),
                          ],
                          if (!_isLoading && _cast.isNotEmpty) ...[
                            const SizedBox(height: 22),
                            _sectionTitle('Actors'),
                            const SizedBox(height: 12),
                            _buildActorsGrid(),
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
                      _circleBtn(Icons.search_rounded, () {
                        Navigator.pushNamed(context, '/search');
                      }),
                      const SizedBox(height: 8),
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
                            color: _isTrailerMuted ? Colors.white : _gold,
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
    required VoidCallback onTap,
    bool filled = false,
    bool goldBg = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
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
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
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
        Column(
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

  Widget _buildRatingsRow() {
    return SizedBox(
      height: 88,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: _ratings.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (context, i) {
          final r = _ratings[i];
          return Container(
            width: 140,
            padding: const EdgeInsets.all(14),
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
                        text: r.score.toStringAsFixed(1),
                        style: const TextStyle(
                            color: _gold,
                            fontSize: 22,
                            fontWeight: FontWeight.w800),
                      ),
                      TextSpan(
                        text: ' /${r.outOf.toStringAsFixed(0)}',
                        style: const TextStyle(
                            color: Colors.white54, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                Text(r.name.toUpperCase(),
                    style: FontService.instance.label(
                        color: Colors.white70,
                        fontSize: 10.5,
                        letterSpacing: 0.8)),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildReviewsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _sectionTitle('Reviews  ${_reviews.length}'),
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
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
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
                  final filled = i < _userRating;
                  return IconButton(
                    onPressed: () => _rateTitle(i + 1),
                    icon: Icon(
                      filled ? Icons.star_rounded : Icons.star_border_rounded,
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
        if (_reviews.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text('No reviews yet — be the first.',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.4))),
          )
        else
          ..._reviews.take(5).map(_buildReviewTile),
      ],
    );
  }

  Widget _buildReviewTile(Review r) {
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
                  pageBuilder: (_, _, _) => DetailScreen(movie: m),
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
                          Image.network(
                            m.posterUrl,
                            fit: BoxFit.cover,
                            alignment: Alignment.topCenter,
                            errorBuilder: (_, _, _) =>
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
                    style: FontService.instance.style(
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

  Widget _quickAction(
      IconData icon, String label, bool active, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
            ),
            child: Icon(icon,
                color: active ? _gold : Colors.white70, size: 20),
          ),
          const SizedBox(height: 4),
          Text(label,
              style: TextStyle(
                  color: active ? _gold : Colors.white54, fontSize: 10)),
        ],
      ),
    );
  }

  Widget _circleBtn(IconData icon, VoidCallback onTap) {
    return GestureDetector(
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