import 'dart:async';
import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/movie.dart';
import '../services/download_service.dart';
import '../services/font_service.dart';
import '../services/web_view_scraper.dart';
import '../screens/onboarding/action_screen.dart';

const _gold = Color(0xFFFFB800);
const _bg = Color(0xFF121212);

class DownloadOption {
  final String id;
  final String quality;
  final String codec;
  final String source;
  final String sizeLabel;
  final bool isBest;
  final String? streamUrl;

  const DownloadOption({
    required this.id,
    required this.quality,
    required this.codec,
    required this.source,
    required this.sizeLabel,
    this.isBest = false,
    this.streamUrl,
  });
}

class _ResolvedMedia {
  final String url;
  final String sourcePage;

  const _ResolvedMedia({
    required this.url,
    required this.sourcePage,
  });
}

class _HlsVariant {
  final int? height;
  final int? width;
  final int bandwidth;
  final String url;

  const _HlsVariant({
    required this.height,
    required this.width,
    required this.bandwidth,
    required this.url,
  });
}

class _TvEpisode {
  final int season;
  final int episode;
  final String name;
  final String? stillPath;
  final String? airDate;
  final int? runtime;

  _TvEpisode({
    required this.season,
    required this.episode,
    required this.name,
    this.stillPath,
    this.airDate,
    this.runtime,
  });
}

class _TvSeason {
  final int seasonNumber;
  final String name;
  final int episodeCount;
  final List<_TvEpisode> episodes;

  _TvSeason({
    required this.seasonNumber,
    required this.name,
    required this.episodeCount,
    this.episodes = const [],
  });
}

class AvailableDownloadsSheet extends StatefulWidget {
  final String movieTitle;
  final String tmdbId;
  final String posterUrl;
  final String mediaType;
  final int season;
  final int episode;
  final List<DownloadOption>? options;
  final String? resolvedStreamUrl;
  final String tmdbApiKey;

  const AvailableDownloadsSheet({
    super.key,
    required this.movieTitle,
    required this.tmdbId,
    this.posterUrl = '',
    this.mediaType = 'movie',
    this.season = 1,
    this.episode = 1,
    this.options,
    this.resolvedStreamUrl,
    this.tmdbApiKey = '7070e2fe1f83238edc3ada49acb2cb25',
  });

  static Future<void> show(
    BuildContext context, {
    required String movieTitle,
    required String tmdbId,
    String posterUrl = '',
    String mediaType = 'movie',
    int season = 1,
    int episode = 1,
    List<DownloadOption>? options,
    String? resolvedStreamUrl,
    String tmdbApiKey = '7070e2fe1f83238edc3ada49acb2cb25',
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AvailableDownloadsSheet(
        movieTitle: movieTitle,
        tmdbId: tmdbId,
        posterUrl: posterUrl,
        mediaType: mediaType,
        season: season,
        episode: episode,
        options: options,
        resolvedStreamUrl: resolvedStreamUrl,
        tmdbApiKey: tmdbApiKey,
      ),
    );
  }

  @override
  State<AvailableDownloadsSheet> createState() =>
      _AvailableDownloadsSheetState();
}

class _AvailableDownloadsSheetState extends State<AvailableDownloadsSheet>
    with SingleTickerProviderStateMixin {
  int _step = 0;

  // Initial basic season list (episodes empty)
  List<_TvSeason> _seasons = [];
  bool _loadingTv = false;
  String? _tvError;
  int? _expandedSeason;
  _TvEpisode? _selectedEpisode;

  List<DownloadOption> _qualities = [];
  bool _loadingQualities = false;
  String? _qualityError;
  String _loadingStatus = 'Looking for the best stream…';
  _ResolvedMedia? _resolvedMedia;
  bool _preparing = false;
  String _prepareLabel = 'Preparing download…';
  double _prepareProgress = 0;

  late AnimationController _pulse;

  // CACHE: This "buffer" stores resolved streams so we don't re-scrape!
  final Map<String, _ResolvedMedia> _resolvedCache = {};

  bool get _isTv => widget.mediaType.toLowerCase() == 'tv';

  void _safeSetState(VoidCallback fn) {
    if (!mounted) return;
    final phase = WidgetsBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.idle ||
        phase == SchedulerPhase.postFrameCallbacks) {
      setState(fn);
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(fn);
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _qualities = widget.options ?? const <DownloadOption>[];
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_isTv) {
        _loadTvStructure(); // Loads minimal season data only
      } else if (_qualities.isEmpty) {
        unawaited(_prepareQualitiesForEpisode(1, 1));
      }
    });
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  // --- OPTIMIZATION 1: Lazy load episodes ---
  Future<void> _loadTvStructure() async {
    setState(() {
      _loadingTv = true;
      _tvError = null;
    });
    try {
      final showRes = await http.get(Uri.parse(
        'https://api.themoviedb.org/3/tv/${widget.tmdbId}?api_key=${widget.tmdbApiKey}&language=en-US',
      ));
      if (showRes.statusCode != 200) throw Exception('TMDB ${showRes.statusCode}');
      final showData = jsonDecode(showRes.body) as Map<String, dynamic>;
      
      // Only fetch basic season info (no episode data yet!)
      final seasonList = (showData['seasons'] as List? ?? [])
          .where((s) => (s['season_number'] as int? ?? 0) > 0)
          .map((s) => _TvSeason(
            seasonNumber: s['season_number'] as int,
            name: s['name'] as String? ?? 'Season ${s['season_number']}',
            episodeCount: s['episode_count'] as int? ?? 0,
          ))
          .toList();
      seasonList.sort((a, b) => a.seasonNumber.compareTo(b.seasonNumber));

      if (!mounted) return;

      _TvEpisode? preselected;
      setState(() {
        _seasons = seasonList;
        _loadingTv = false;
        _expandedSeason = widget.season;
      });

      // If we can find the requested season, fetch its details immediately
      // so the user sees the selected episode pre-loaded.
      for (final season in _seasons) {
        if (season.seasonNumber == widget.season) {
          await _fetchSeasonEpisodes(season.seasonNumber);
          for (final ep in season.episodes) {
            if (ep.episode == widget.episode) {
              preselected = ep;
              break;
            }
          }
          break;
        }
      }

      if (preselected != null) {
        setState(() {
          _selectedEpisode = preselected;
          _step = 1;
        });
        unawaited(
          _prepareQualitiesForEpisode(preselected.season, preselected.episode),
        );
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingTv = false;
        _tvError = 'Could not load seasons. Tap retry.';
      });
    }
  }

  // Fetch details for ONE specific season at a time
  Future<void> _fetchSeasonEpisodes(int seasonNumber) async {
    final existingSeasonIndex = _seasons.indexWhere((s) => s.seasonNumber == seasonNumber);
    if (existingSeasonIndex == -1) return;
    final existingSeason = _seasons[existingSeasonIndex];
    // Already loaded
    if (existingSeason.episodes.isNotEmpty) return;

    try {
      final res = await http.get(Uri.parse(
        'https://api.themoviedb.org/3/tv/${widget.tmdbId}/season/$seasonNumber?api_key=${widget.tmdbApiKey}&language=en-US',
      ));
      if (res.statusCode != 200) return;
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final eps = (data['episodes'] as List? ?? []).map((e) {
        return _TvEpisode(
          season: seasonNumber,
          episode: e['episode_number'] as int? ?? 0,
          name: e['name'] as String? ?? 'Episode',
          stillPath: e['still_path'] as String?,
          airDate: e['air_date'] as String?,
          runtime: e['runtime'] as int?,
        );
      }).toList();

      if (!mounted) return;
      setState(() {
        _seasons[existingSeasonIndex] = _TvSeason(
          seasonNumber: seasonNumber,
          name: existingSeason.name,
          episodeCount: eps.length,
          episodes: eps,
        );
      });
    } catch (_) {}
  }

  void _pickEpisode(_TvEpisode ep) {
    HapticFeedback.selectionClick();
    setState(() {
      _selectedEpisode = ep;
      _step = 1;
      _qualities = const <DownloadOption>[];
      _qualityError = null;
      _resolvedMedia = null;
    });
    unawaited(_prepareQualitiesForEpisode(ep.season, ep.episode));
  }

  // --- OPTIMIZATION 2: Prioritized Host List + Cache check ---
  Future<void> _prepareQualitiesForEpisode(int season, int episode) async {
    final cacheKey = '$season-$episode';
    
    // Check the "buffer" cache first!
    if (_resolvedCache.containsKey(cacheKey)) {
      _resolvedMedia = _resolvedCache[cacheKey];
      if (!mounted) return;
      // We already have the resolved media. Call the discovery logic immediately.
      _safeSetState(() {
        _loadingQualities = true;
        _loadingStatus = 'Fetching quality variants from cache…';
      });
      // Bypass the resolveEpisodeStream loop:
      try {
        final discovered = await _discoverHlsVariants(
          _resolvedMedia!.url,
          season,
          episode,
          sourcePage: _resolvedMedia!.sourcePage,
        );
        if (!mounted) return;
        if (discovered.isEmpty) {
           _safeSetState(() {
            _qualities = [
              DownloadOption(
                id: 'cached',
                quality: 'Original',
                codec: _isWebM(_resolvedMedia!.url) ? 'WebM' : 'H.264',
                source: 'Original · Available',
                sizeLabel: 'Available',
                isBest: true,
                streamUrl: _resolvedMedia!.url,
              ),
            ];
          });
        } else {
          _safeSetState(() => _qualities = discovered);
        }
      } catch (_) {
        // If cache discovery fails, remove cache and fallback to standard retry.
        _resolvedCache.remove(cacheKey);
        _resolvedMedia = null;
        // Re-run the standard network flow.
        unawaited(_prepareQualitiesForEpisode(season, episode));
        return;
      }
      _safeSetState(() => _loadingQualities = false);
      return;
    }

    // Standard flow if not in cache
    _safeSetState(() {
      _loadingQualities = true;
      _qualityError = null;
      _loadingStatus = 'Checking available streams…';
      if (_isTv) _qualities = const <DownloadOption>[];
    });

    try {
      _ResolvedMedia? resolved = _resolvedMedia;
      if (resolved == null && _isDirect(widget.resolvedStreamUrl)) {
        resolved = _ResolvedMedia(
          url: widget.resolvedStreamUrl!,
          sourcePage: _buildEmbedCandidates(season, episode).first,
        );
      }

      resolved ??= await _resolveEpisodeStream(
          season,
          episode,
          null,
          showPreparingOverlay: false,
        );

      if (resolved == null) {
        throw Exception('No playable stream was found');
      }

      _resolvedMedia = resolved;
      // Populate the cache!
      _resolvedCache[cacheKey] = resolved;

      List<DownloadOption> discovered = const [];
      try {
        discovered = await _discoverHlsVariants(
          resolved.url,
          season,
          episode,
          sourcePage: resolved.sourcePage,
        );
      } catch (_) {}

      if (!mounted) return;

      if (discovered.isEmpty) {
        _safeSetState(() {
          _qualities = [
            DownloadOption(
              id: 'original',
              quality: 'Original',
              codec: _isWebM(resolved!.url) ? 'WebM' : 'H.264',
              source: 'Original · Available',
              sizeLabel: 'Available',
              isBest: true,
              streamUrl: resolved.url,
            ),
          ];
        });
      } else {
        _safeSetState(() => _qualities = discovered);
      }
    } catch (e) {
      // Clear the cache if an error occurred so retries don't use stale data
      _resolvedCache.remove(cacheKey);
      if (!mounted) return;
      final msg = _shortError(e);
      _safeSetState(() {
        _qualities = const <DownloadOption>[];
        _qualityError = msg;
      });
    } finally {
      _safeSetState(() {
        _loadingQualities = false;
        _preparing = false;
        _prepareProgress = 0;
      });
    }
  }

  // Prioritized host list (Top performing hosts first)
  List<String> _buildEmbedCandidates(int season, int episode) {
    final id = widget.tmdbId;
    if (_isTv) {
      return [
        // VidFast (Best success rate)
        'https://vidfast.vc/tv/$id/$season/$episode?autoPlay=true',
        // CineSrc (Fast fallback)
        'https://cinesrc.st/embed/tv/$id/$season/$episode',
        // Quick backup mirrors
        'https://player.videasy.to/tv/$id/$season/$episode',
        'https://www.cineplay.to/tv/$id/$season/$episode?play=true',
        'https://vidfast.vc/embed/tv/$id/$season/$episode?autoPlay=true',
      ];
    }
    return [
      'https://vidfast.vc/movie/$id?autoPlay=true',
      'https://cinesrc.st/embed/movie/$id',
      'https://player.videasy.to/movie/$id',
      'https://www.cineplay.to/movie/$id?play=true',
      'https://vidfast.vc/embed/movie/$id?autoPlay=true',
    ];
  }

  Future<_ResolvedMedia?> _resolveEpisodeStream(
    int season,
    int episode,
    String? preferredUrl, {
    bool showPreparingOverlay = false,
  }) async {
    final direct = _isDirect(preferredUrl) ? preferredUrl : null;
    if (direct != null) {
      return _ResolvedMedia(
        url: direct,
        sourcePage: _buildEmbedCandidates(season, episode).first,
      );
    }

    if (showPreparingOverlay) {
      _safeSetState(() {
        _preparing = true;
        _prepareLabel = 'Finding the episode stream…';
        _prepareProgress = 0.12;
      });
    }

    final embeds = _buildEmbedCandidates(season, episode);
    for (var i = 0; i < embeds.length; i++) {
      if (!mounted) return null;
      final labels = [
        'Looking for the best stream…',
        'Checking alternate sources…',
        'Almost there…',
        'Finding a playable link…',
      ];
      final status = labels[i.clamp(0, labels.length - 1)];
      _safeSetState(() {
        _loadingStatus = status;
        if (showPreparingOverlay) {
          _prepareLabel = status;
          _prepareProgress = (0.12 + (i * 0.25)).clamp(0.12, 0.8);
        }
      });

      final resolved = await _resolveInBackground(
        embeds[i],
        season: season,
        episode: episode,
        reportProgress: showPreparingOverlay,
      );
      if (resolved != null) {
        _safeSetState(() => _loadingStatus = 'Stream found. Reading qualities…');
        return _ResolvedMedia(
          url: resolved,
          sourcePage: embeds[i],
        );
      }
    }
    return null;
  }

  Future<List<DownloadOption>> _discoverHlsVariants(
    String streamUrl,
    int season,
    int episode, {
    required String sourcePage,
  }) async {
    if (!_isHls(streamUrl)) return const <DownloadOption>[];
    final headers = _mediaHeaders(streamUrl, sourcePage);
    final res = await http
        .get(Uri.parse(streamUrl), headers: headers)
        .timeout(const Duration(seconds: 12));

    if (res.statusCode != 200) throw Exception('Stream playlist returned HTTP ${res.statusCode}');

    final body = res.body;
    if (!body.contains('#EXT-X-STREAM-INF')) return const <DownloadOption>[];

    final lines = body.split(RegExp(r'\r?\n'));
    final variants = <_HlsVariant>[];

    for (var i = 0; i < lines.length; i++) {
      final info = lines[i].trim();
      if (!info.startsWith('#EXT-X-STREAM-INF')) continue;
      String? next;
      for (var j = i + 1; j < lines.length; j++) {
        final candidate = lines[j].trim();
        if (candidate.isEmpty) continue;
        if (candidate.startsWith('#')) continue;
        next = candidate;
        i = j;
        break;
      }
      if (next == null) continue;

      final url = Uri.parse(streamUrl).resolve(next).toString();
      final resMatch = RegExp(r'RESOLUTION=(\d+)x(\d+)', caseSensitive: false).firstMatch(info);
      final width = int.tryParse(resMatch?.group(1) ?? '');
      final height = int.tryParse(resMatch?.group(2) ?? '');
      final bandwidth = int.tryParse(RegExp(r'BANDWIDTH=(\d+)', caseSensitive: false).firstMatch(info)?.group(1) ?? '') ?? 0;

      variants.add(_HlsVariant(width: width, height: height, bandwidth: bandwidth, url: url));
    }

    final byKey = <String, _HlsVariant>{};
    for (final v in variants) {
      final key = v.height != null && v.height! > 0 ? 'h${v.height}' : 'u${v.url}';
      final old = byKey[key];
      if (old == null || v.bandwidth > old.bandwidth) byKey[key] = v;
    }

    final unique = byKey.values.toList()
      ..sort((a, b) {
        final ah = a.height ?? 0;
        final bh = b.height ?? 0;
        if (ah != bh) return bh.compareTo(ah);
        return b.bandwidth.compareTo(a.bandwidth);
      });

    return unique.asMap().entries.map((entry) {
      final index = entry.key;
      final v = entry.value;
      final h = v.height;
      final quality = h != null && h > 0 ? '${h}p' : 'Auto ${index + 1}';
      final bitrate = v.bandwidth > 0 ? '${(v.bandwidth / 1000000).toStringAsFixed(1)} Mbps' : 'Adaptive';
      final label = h != null && h > 0 ? '$quality · ${index == 0 ? 'Best' : 'Available'}' : '$quality · Available';

      return DownloadOption(
        id: 'hls_${h ?? index}_${v.bandwidth}',
        quality: quality,
        codec: 'HLS',
        source: label,
        sizeLabel: bitrate,
        isBest: index == 0,
        streamUrl: v.url,
      );
    }).toList();
  }

  Map<String, String> _mediaHeaders(String mediaUrl, String sourcePage) {
    final headers = <String, String>{
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/120.0.0.0 Safari/537.36',
      'Accept': '*/*',
      'Accept-Language': 'en-US,en;q=0.9',
      'Referer': sourcePage,
    };
    try {
      final uri = Uri.parse(sourcePage);
      headers['Origin'] = '${uri.scheme}://${uri.host}';
    } catch (_) {}
    return headers;
  }

  bool _isHls(String url) {
    final u = url.toLowerCase();
    return u.contains('.m3u8') || u.contains('/hls/');
  }

  bool _isWebM(String url) => url.toLowerCase().contains('.webm');
  String _shortError(Object e) {
    final s = e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '').trim();
    if (s.length > 120) return '${s.substring(0, 117)}…';
    return s;
  }

  bool _isDirect(String? url) {
    if (url == null || url.isEmpty) return false;
    final u = url.toLowerCase();
    return u.contains('.m3u8') || u.contains('.mp4') || u.contains('.webm') || 
           u.contains('/hls/') || u.contains('googlevideo') || u.contains('videoplayback');
  }

  /// True when quality is 720p or higher (including 1080p / 4K).
  bool _isHdOrAbove(String quality) {
    final q = quality.toLowerCase();
    if (q.contains('4k') || q.contains('uhd') || q.contains('2160')) {
      return true;
    }
    final match = RegExp(r'(\d{3,4})\s*p').firstMatch(q);
    if (match != null) {
      final h = int.tryParse(match.group(1) ?? '') ?? 0;
      return h >= 720;
    }
    return false;
  }

  Future<bool> _ensureHdAccess() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool('hd_unlocked') == true) return true;
    } catch (_) {}

    if (!mounted) return false;

    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => const ActionScreen(reason: '1080p'),
        fullscreenDialog: true,
      ),
    );

    return result == true;
  }

  Future<void> _startDownload(DownloadOption option) async {
    HapticFeedback.mediumImpact();
    final season = _isTv ? (_selectedEpisode?.season ?? widget.season) : widget.season;
    final episode = _isTv ? (_selectedEpisode?.episode ?? widget.episode) : widget.episode;

    // Gate 720p+ downloads behind sign-in
    if (_isHdOrAbove(option.quality)) {
      final allowed = await _ensureHdAccess();
      if (!allowed || !mounted) return;
    }

    if (option.streamUrl != null && _isDirect(option.streamUrl)) {
      _enqueue(option.streamUrl!, option, season, episode, sourcePage: _resolvedMedia?.sourcePage);
      return;
    }

    _safeSetState(() {
      _preparing = true;
      _prepareLabel = 'Preparing download…';
      _prepareProgress = 0.1;
    });

    try {
      final resolved = _resolvedMedia ?? await _resolveEpisodeStream(
        season, episode, option.streamUrl, showPreparingOverlay: true
      );

      if (resolved == null) throw Exception('No playable stream was found for this episode');

      _resolvedMedia = resolved;
      var selectedUrl = option.streamUrl;
      if (!_isDirect(selectedUrl)) selectedUrl = resolved.url;

      final discovered = await _discoverHlsVariants(selectedUrl ?? resolved.url, season, episode, sourcePage: resolved.sourcePage);

      DownloadOption chosen = option;
      if (discovered.isNotEmpty) {
        final match = discovered.firstWhere((q) => q.quality == option.quality, orElse: () => discovered.first);
        chosen = match;
      } else {
        chosen = DownloadOption(
          id: option.id, quality: option.quality, codec: option.codec,
          source: option.source, sizeLabel: option.sizeLabel, isBest: option.isBest,
          streamUrl: selectedUrl ?? resolved.url,
        );
      }

      if (!mounted) return;
      _safeSetState(() {
        _prepareProgress = 1.0;
        _prepareLabel = 'Starting download…';
      });
      await Future.delayed(const Duration(milliseconds: 200));
      if (!mounted) return;
      _safeSetState(() => _preparing = false);

      _enqueue(chosen.streamUrl ?? resolved.url, chosen, season, episode, sourcePage: resolved.sourcePage);
    } catch (e) {
      // Invalidate cache on failure so a retry works
      _resolvedCache.remove('$season-$episode');
      if (!mounted) return;
      _safeSetState(() {
        _preparing = false;
        _prepareProgress = 0;
      });
      _toast(
        _isTv
            ? 'Could not prepare S${season.toString().padLeft(2, '0')}E${episode.toString().padLeft(2, '0')}. ${_shortError(e)}'
            : 'Could not prepare this file. ${_shortError(e)}',
      );
    }
  }

  void _enqueue(String videoUrl, DownloadOption option, int season, int episode, {String? sourcePage}) {
    final movie = Movie(
      id: int.tryParse(widget.tmdbId) ?? 0,
      title: widget.movieTitle,
      posterPath: widget.posterUrl,
      overview: '',
      voteAverage: 0.0,
      releaseDate: '',
    );
    final referer = sourcePage ?? (_isTv ? 'https://vidfast.vc/tv/${widget.tmdbId}/$season/$episode' : 'https://vidfast.vc/movie/${widget.tmdbId}');

    DownloadService.instance.enqueueDownload(
      movie: movie,
      videoUrl: videoUrl,
      quality: option.quality,
      codec: option.codec,
      sizeLabel: option.sizeLabel,
      mediaType: widget.mediaType,
      season: season,
      episode: episode,
      referer: referer,
    );
    Navigator.pop(context);
    _toast(_isTv
        ? 'Downloading S${season.toString().padLeft(2, '0')}E${episode.toString().padLeft(2, '0')} · ${option.quality}'
        : 'Downloading ${option.quality} · ${option.sizeLabel}');
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: FontService.instance.label(color: Colors.white, fontSize: 13)),
      backgroundColor: const Color(0xFF222222),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  Future<String?> _resolveInBackground(String embedUrl, {required int season, required int episode, bool reportProgress = false}) async {
    final completer = Completer<String?>();
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _StreamResolverOverlay(
        embedUrl: embedUrl,
        mediaType: widget.mediaType,
        season: season,
        episode: episode,
        onProgress: (p, label) {
          if (!reportProgress) return;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            setState(() {
              _prepareProgress = p;
              if (label != null) _prepareLabel = label;
            });
          });
        },
        onDone: (url) {
          if (!completer.isCompleted) completer.complete(url);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            try { entry.remove(); } catch (_) {}
          });
        },
      ),
    );

    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) {
      if (!completer.isCompleted) completer.complete(null);
      return completer.future;
    }
    Overlay.of(context, rootOverlay: true).insert(entry);
    final timeoutSecs = _isTv ? 10 : 7;
    return completer.future.timeout(Duration(seconds: timeoutSecs), onTimeout: () {
      try { entry.remove(); } catch (_) {}
      return null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;
    final height = MediaQuery.of(context).size.height * (_isTv ? 0.82 : 0.70);

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          height: height,
          decoration: BoxDecoration(
            color: _bg.withValues(alpha: 0.96),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
          ),
          child: Stack(
            children: [
              Column(
                children: [
                  const SizedBox(height: 10),
                  Container(width: 36, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
                  _buildHeader(),
                  const Divider(color: Colors.white10, height: 1),
                  Expanded(child: _buildBody(bottom)),
                ],
              ),
              if (_preparing) _buildPreparingOverlay(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final subtitle = _isTv
        ? (_step == 1 && _selectedEpisode != null
            ? 'S${_selectedEpisode!.season.toString().padLeft(2, '0')}E${_selectedEpisode!.episode.toString().padLeft(2, '0')} · ${_selectedEpisode!.name}'
            : 'Choose an episode to download')
        : widget.movieTitle;

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 8, 12),
      child: Row(
        children: [
          if (_step == 1)
            IconButton(
              onPressed: () => setState(() {
                _step = 0;
                _selectedEpisode = null;
              }),
              icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white70, size: 18),
            ),
          if (widget.posterUrl.isNotEmpty) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                widget.posterUrl.startsWith('http') ? widget.posterUrl : 'https://image.tmdb.org/t/p/w92${widget.posterUrl}',
                width: 40, height: 56, fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Container(width: 40, height: 56, color: Colors.grey[850], child: const Icon(Icons.movie, color: Colors.white24, size: 16)),
              ),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Download Options', style: FontService.instance.display(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold)),
                const SizedBox(height: 2),
                Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: FontService.instance.label(color: Colors.white54, fontSize: 12)),
              ],
            ),
          ),
          IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded, color: Colors.white70)),
        ],
      ),
    );
  }

  Widget _buildBody(double bottom) {
    if (_isTv && _step == 0) return _buildEpisodePicker(bottom);
    return _buildQualityList(bottom);
  }

  // --- PARTIAL UPDATE: Lazy Loading UI ---
  Widget _buildEpisodePicker(double bottom) {
    if (_loadingTv) {
      return const Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(width: 32, height: 32, child: CircularProgressIndicator(color: _gold, strokeWidth: 2.5)),
          SizedBox(height: 12),
          Text('Loading episodes…', style: TextStyle(color: Colors.white54, fontSize: 13)),
        ]),
      );
    }
    if (_tvError != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_tvError!, style: const TextStyle(color: Colors.white54)),
            TextButton(onPressed: _loadTvStructure, child: const Text('Retry', style: TextStyle(color: _gold))),
          ],
        ),
      );
    }
    if (_seasons.isEmpty) {
      return const Center(child: Text('No episodes found', style: TextStyle(color: Colors.white54)));
    }

    return ListView.builder(
      padding: EdgeInsets.fromLTRB(16, 8, 16, bottom + 20),
      itemCount: _seasons.length,
      itemBuilder: (context, index) {
        final season = _seasons[index];
        final expanded = _expandedSeason == season.seasonNumber;
        final currentlyLoading = expanded && season.episodes.isEmpty && !_loadingTv;

        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
          ),
          child: Column(
            children: [
              InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () async {
                  setState(() {
                    _expandedSeason = expanded ? null : season.seasonNumber;
                  });
                  if (season.episodes.isEmpty && season.seasonNumber > 0) {
                    await _fetchSeasonEpisodes(season.seasonNumber);
                  }
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(color: _gold.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
                        child: Text('S${season.seasonNumber}', style: const TextStyle(color: _gold, fontWeight: FontWeight.bold, fontSize: 12)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(season.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14)),
                      ),
                      Text('${season.episodeCount} eps', style: const TextStyle(color: Colors.white38, fontSize: 12)),
                      const SizedBox(width: 6),
                      Icon(expanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded, color: Colors.white54),
                    ],
                  ),
                ),
              ),
              if (expanded) ...[
                if (currentlyLoading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: _gold, strokeWidth: 2))),
                  )
                else ...[
                  ...season.episodes.map(_episodeRow),
                ],
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _episodeRow(_TvEpisode ep) {
    final still = ep.stillPath != null ? 'https://image.tmdb.org/t/p/w300${ep.stillPath}' : null;
    return InkWell(
      onTap: () => _pickEpisode(ep),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        decoration: BoxDecoration(border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.06)))),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: still != null
                  ? Image.network(still, width: 72, height: 42, fit: BoxFit.cover, errorBuilder: (_, _, _) => _stillPlaceholder())
                  : _stillPlaceholder(),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('E${ep.episode.toString().padLeft(2, '0')}  ·  ${ep.name}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 3),
                  Text([if (ep.runtime != null) '${ep.runtime} min', if (ep.airDate != null && ep.airDate!.isNotEmpty) ep.airDate].join(' · '), style: const TextStyle(color: Colors.white38, fontSize: 11)),
                ],
              ),
            ),
            Container(width: 34, height: 34, decoration: BoxDecoration(color: _gold.withValues(alpha: 0.15), shape: BoxShape.circle), child: const Icon(Icons.download_rounded, color: _gold, size: 18)),
          ],
        ),
      ),
    );
  }

  Widget _stillPlaceholder() => Container(width: 72, height: 42, color: Colors.white10, child: const Icon(Icons.tv_rounded, color: Colors.white24, size: 18));

  Widget _buildQualityList(double bottom) {
    if (_loadingQualities) {
      return Center(
        child: Padding(
          padding: EdgeInsets.fromLTRB(24, 20, 24, bottom + 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ScaleTransition(
                scale: Tween(begin: 0.88, end: 1.08).animate(CurvedAnimation(parent: _pulse, curve: Curves.easeInOut)),
                child: Container(
                  width: 56, height: 56,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: _gold.withValues(alpha: 0.12), border: Border.all(color: _gold.withValues(alpha: 0.45), width: 1.5)),
                  child: const Icon(Icons.hd_rounded, color: _gold, size: 26),
                ),
              ),
              const SizedBox(height: 18),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 320),
                transitionBuilder: (child, anim) => FadeTransition(opacity: anim, child: SlideTransition(position: Tween<Offset>(begin: const Offset(0, 0.15), end: Offset.zero).animate(anim), child: child)),
                child: Text(_loadingStatus, key: ValueKey(_loadingStatus), textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70, fontSize: 13.5, fontWeight: FontWeight.w500)),
              ),
              const SizedBox(height: 10),
              SizedBox(width: 120, child: ClipRRect(borderRadius: BorderRadius.circular(4), child: LinearProgressIndicator(minHeight: 3, backgroundColor: Colors.white12, valueColor: const AlwaysStoppedAnimation(_gold)))),
            ],
          ),
        ),
      );
    }

    if (_qualityError != null) {
      return Center(
        child: Padding(
          padding: EdgeInsets.fromLTRB(24, 20, 24, bottom + 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_rounded, color: Colors.white38, size: 30),
              const SizedBox(height: 12),
              Text(_qualityError!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white54, fontSize: 13)),
              const SizedBox(height: 10),
              TextButton(
                onPressed: () {
                  final season = _isTv ? (_selectedEpisode?.season ?? widget.season) : widget.season;
                  final episode = _isTv ? (_selectedEpisode?.episode ?? widget.episode) : widget.episode;
                  unawaited(_prepareQualitiesForEpisode(season, episode));
                },
                child: const Text('Retry', style: TextStyle(color: _gold)),
              ),
            ],
          ),
        ),
      );
    }

    if (_qualities.isEmpty) {
      return Center(
        child: Padding(
          padding: EdgeInsets.fromLTRB(24, 20, 24, bottom + 20),
          child: const Text('No downloadable qualities were found for this episode.', textAlign: TextAlign.center, style: TextStyle(color: Colors.white54, fontSize: 13)),
        ),
      );
    }

    return ListView.builder(
      padding: EdgeInsets.fromLTRB(16, 10, 16, bottom + 20),
      itemCount: _qualities.length,
      itemBuilder: (context, index) {
        final q = _qualities[index];
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: q.isBest ? _gold.withValues(alpha: 0.35) : Colors.white.withValues(alpha: 0.06)),
          ),
          child: Row(
            children: [
              Icon(Icons.cloud_download_outlined, color: q.isBest ? _gold : Colors.white38, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(q.source, style: FontService.instance.display(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 5),
                    Row(children: [_chip(q.quality, gold: q.isBest), const SizedBox(width: 6), _chip(q.sizeLabel)]),
                  ],
                ),
              ),
              GestureDetector(
                onTap: _preparing ? null : () => _startDownload(q),
                child: Container(width: 42, height: 42, decoration: BoxDecoration(color: _gold, shape: BoxShape.circle, boxShadow: [BoxShadow(color: _gold.withValues(alpha: 0.3), blurRadius: 8, offset: const Offset(0, 3))]), child: const Icon(Icons.arrow_downward_rounded, color: Colors.black, size: 20)),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _chip(String text, {bool gold = false}) => Container(padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3), decoration: BoxDecoration(color: gold ? _gold.withValues(alpha: 0.18) : Colors.white.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(7)), child: Text(text, style: TextStyle(color: gold ? _gold : Colors.white70, fontSize: 11, fontWeight: FontWeight.bold)));

  Widget _buildPreparingOverlay() {
    return Positioned.fill(
      child: Container(
        color: Colors.black.withValues(alpha: 0.72),
        child: Center(
          child: Container(
            width: 220,
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 24),
            decoration: BoxDecoration(color: const Color(0xFF1A1A1A), borderRadius: BorderRadius.circular(20), border: Border.all(color: _gold.withValues(alpha: 0.25))),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ScaleTransition(scale: Tween(begin: 0.92, end: 1.08).animate(CurvedAnimation(parent: _pulse, curve: Curves.easeInOut)), child: Container(width: 52, height: 52, decoration: BoxDecoration(color: _gold.withValues(alpha: 0.15), shape: BoxShape.circle), child: const Icon(Icons.download_rounded, color: _gold, size: 26))),
                const SizedBox(height: 16),
                Text(_prepareLabel, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
                const SizedBox(height: 14),
                ClipRRect(borderRadius: BorderRadius.circular(4), child: LinearProgressIndicator(value: _prepareProgress.clamp(0.05, 1.0), minHeight: 5, backgroundColor: Colors.white12, valueColor: const AlwaysStoppedAnimation(_gold))),
                const SizedBox(height: 8),
                Text('${(_prepareProgress * 100).clamp(0, 99).toInt()}%', style: const TextStyle(color: Colors.white38, fontSize: 11)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── MISSING OVERLAY CLASS ADDED BACK ────────────────────────────
/// Off-screen resolver using the same scraper as playback (iframe-aware).
class _StreamResolverOverlay extends StatefulWidget {
  final String embedUrl;
  final String mediaType;
  final int season;
  final int episode;
  final void Function(double progress, String? label) onProgress;
  final void Function(String? url) onDone;

  const _StreamResolverOverlay({
    required this.embedUrl,
    required this.mediaType,
    required this.season,
    required this.episode,
    required this.onProgress,
    required this.onDone,
  });

  @override
  State<_StreamResolverOverlay> createState() => _StreamResolverOverlayState();
}

class _StreamResolverOverlayState extends State<_StreamResolverOverlay> {
  bool _finished = false;

  void _finish(String? url) {
    if (_finished) return;
    _finished = true;
    widget.onDone(url);
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: -400,
      top: -300,
      width: 360,
      height: 240,
      child: WebViewScraper(
        embedUrl: widget.embedUrl,
        mediaType: widget.mediaType,
        season: widget.season,
        episode: widget.episode,
        timeoutSeconds: widget.mediaType.toLowerCase() == 'tv' ? 9 : 6,
        onLoading: (loading) {
          if (loading) {
            widget.onProgress(0.2, 'Finding the video stream…');
          }
        },
        onDataExtracted: (data) {
          widget.onProgress(0.98, 'Stream found. Checking qualities…');
          _finish(data.bestUrl);
        },
        onError: (_) => _finish(null),
      ),
    );
  }
}