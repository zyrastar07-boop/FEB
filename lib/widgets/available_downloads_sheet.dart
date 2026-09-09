// ignore_for_file: use_build_context_synchronously
import '../design/tokens.dart';
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
import '../services/app_settings_service.dart';
import '../services/cellular_data_service.dart';
import '../screens/onboarding/action_screen.dart';
import '../widgets/subtitle_selection_sheet.dart';
import '../widgets/download_tile.dart';
import '../widgets/download_skeleton_loader.dart';

const _gold = AppDesignTokens.gold;
const _bg = Color(0xFF121212);
const _cloudflareProxy = 'https://phonofilm-proxy.mela-media-2026.workers.dev';
const _ua =
    'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/126.0.0.0 Mobile Safari/537.36';

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
  final List<StreamVariant> allStreams;
  const _ResolvedMedia({
    required this.url,
    required this.sourcePage,
    this.allStreams = const [],
  });
}

class _HlsVariant {
  final int height;
  final int width;
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
    this.tmdbApiKey = '',
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
    String tmdbApiKey = '',
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
  late AnimationController _pulse;
  final Map<String, _ResolvedMedia> _resolvedCache = {};

  bool get _isTv => widget.mediaType.toLowerCase() == 'tv';

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _qualities = widget.options ?? const <DownloadOption>[];
    DownloadService.instance.addListener(_onDownloadChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_isTv) {
        _loadTvStructure();
      } else if (_qualities.isEmpty) {
        unawaited(_prepareQualitiesForEpisode(1, 1));
      }
    });
  }

  @override
  void dispose() {
    DownloadService.instance.removeListener(_onDownloadChanged);
    _pulse.dispose();
    super.dispose();
  }

  void _onDownloadChanged() {
    if (!mounted) return;
    setState(() {});
  }

  String _downloadIdForOption(DownloadOption option, int season, int episode) {
    final movieId = int.tryParse(widget.tmdbId) ?? 0;
    if (_isTv) {
      return '${movieId}_s${season}_e${episode}_${option.quality}';
    } else {
      return '${movieId}_${option.quality}';
    }
  }

  bool _isOptionDownloaded(DownloadOption option, int season, int episode) {
    final id = _downloadIdForOption(option, season, episode);
    return DownloadService.instance.isDownloadedLocally(id);
  }

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

  // ─── TV Structure ───────────────────────────────────────────────────

  Future<void> _loadTvStructure() async {
    setState(() {
      _loadingTv = true;
      _tvError = null;
    });
    try {
      final showRes = await http.get(Uri.parse(
        '$_cloudflareProxy/tmdb/tv/${widget.tmdbId}?language=en-US',
      ));
      if (showRes.statusCode != 200) {
        throw Exception('Proxy server error: ${showRes.statusCode}');
      }
      final showData = jsonDecode(showRes.body) as Map<String, dynamic>;
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

  Future<void> _fetchSeasonEpisodes(int seasonNumber) async {
    final existingSeasonIndex =
        _seasons.indexWhere((s) => s.seasonNumber == seasonNumber);
    if (existingSeasonIndex == -1) return;
    final existingSeason = _seasons[existingSeasonIndex];
    if (existingSeason.episodes.isNotEmpty) return;
    try {
      final res = await http.get(Uri.parse(
        '$_cloudflareProxy/tmdb/tv/${widget.tmdbId}/season/$seasonNumber?language=en-US',
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

  // ─── Quality Resolution (100% accurate) ─────────────────────────────

  Future<void> _prepareQualitiesForEpisode(int season, int episode) async {
    final cacheKey = '$season-$episode';
    if (_resolvedCache.containsKey(cacheKey)) {
      _resolvedMedia = _resolvedCache[cacheKey];
      if (!mounted) return;
      _safeSetState(() {
        _loadingQualities = true;
        _loadingStatus = 'Building quality list…';
      });
      try {
        final options = await _buildQualityOptions(
          _resolvedMedia!,
          season,
          episode,
        );
        if (!mounted) return;
        _safeSetState(() => _qualities = options);
      } catch (_) {
        _resolvedCache.remove(cacheKey);
        _resolvedMedia = null;
        unawaited(_prepareQualitiesForEpisode(season, episode));
        return;
      }
      _safeSetState(() => _loadingQualities = false);
      return;
    }

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
      _resolvedCache[cacheKey] = resolved;
      _safeSetState(() => _loadingStatus = 'Reading available qualities…');
      final options = await _buildQualityOptions(resolved, season, episode);
      if (!mounted) return;
      _safeSetState(() => _qualities = options);
    } catch (e) {
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
      });
    }
  }

  /// Builds the quality list using **only real RESOLUTION data** from the HLS master.
  /// No height guessing. Exact matches preferred.
  Future<List<DownloadOption>> _buildQualityOptions(
    _ResolvedMedia resolved,
    int season,
    int episode,
  ) async {
    final preferredH = AppSettingsService.instance.preferredDownloadHeight;
    final options = <DownloadOption>[];
    final seenUrls = <String>{};

    // 1. Primary source: real HLS variants with RESOLUTION
    try {
      final hls = await _discoverHlsVariants(
        resolved.url,
        sourcePage: resolved.sourcePage,
      );
      for (final o in hls) {
        if (o.streamUrl != null && seenUrls.add(o.streamUrl!)) {
          options.add(o);
        }
      }
    } catch (_) {}

    // 2. Secondary: streams that came from the scraper (already have height)
    if (resolved.allStreams.isNotEmpty) {
      final fromScraper = _optionsFromScraperStreams(
        resolved.allStreams,
        preferredH: preferredH,
      );
      for (final o in fromScraper) {
        if (o.streamUrl != null && seenUrls.add(o.streamUrl!)) {
          options.add(o);
        }
      }
    }

    // 3. Last resort: single original if nothing was detected
    if (options.isEmpty) {
      final codec = _isHls(resolved.url)
          ? 'HLS'
          : (_isWebM(resolved.url) ? 'WebM' : 'H.264');
      options.add(DownloadOption(
        id: 'direct_original',
        quality: 'Original',
        codec: codec,
        source: 'Original · Available',
        sizeLabel: 'Unknown',
        isBest: true,
        streamUrl: resolved.url,
      ));
    }

    // Deduplicate by exact height (keep highest bandwidth)
    final byHeight = <int, DownloadOption>{};
    final unknown = <DownloadOption>[];

    for (final o in options) {
      final h = _heightFromQuality(o.quality);
      if (h <= 0) {
        unknown.add(o);
        continue;
      }
      final existing = byHeight[h];
      if (existing == null) {
        byHeight[h] = o;
      } else {
        // Prefer the one that reports real Mbps
        final preferNew = o.sizeLabel.contains('Mbps') &&
            !existing.sizeLabel.contains('Mbps');
        if (preferNew) byHeight[h] = o;
      }
    }

    final deduped = <DownloadOption>[
      ...byHeight.entries.map((e) {
        final h = e.key;
        final o = e.value;
        final label = _labelForHeight(h);
        return DownloadOption(
          id: o.id,
          quality: label,
          codec: o.codec,
          source: o.source.contains('Recommended')
              ? '$label · Recommended'
              : '$label · Available',
          sizeLabel: o.sizeLabel,
          isBest: o.isBest,
          streamUrl: o.streamUrl,
        );
      }),
      // Only keep unknown if we have zero real heights
      if (byHeight.isEmpty && unknown.isNotEmpty) unknown.first,
    ];

    // Sort: exact preferred height first, then higher → lower
    deduped.sort((a, b) {
      final ah = _heightFromQuality(a.quality);
      final bh = _heightFromQuality(b.quality);

      // Exact match to preferred always wins
      final aExact = ah == preferredH;
      final bExact = bh == preferredH;
      if (aExact && !bExact) return -1;
      if (!aExact && bExact) return 1;

      // Then closest
      final da = (ah - preferredH).abs();
      final db = (bh - preferredH).abs();
      if (da != db) return da.compareTo(db);

      // Then higher resolution
      return bh.compareTo(ah);
    });

    return [
      for (var i = 0; i < deduped.length; i++)
        DownloadOption(
          id: deduped[i].id,
          quality: deduped[i].quality,
          codec: deduped[i].codec,
          source: deduped[i].source,
          sizeLabel: deduped[i].sizeLabel,
          isBest: i == 0,
          streamUrl: deduped[i].streamUrl,
        ),
    ];
  }

  String _labelForHeight(int h) {
    if (h >= 2160) return '4K';
    if (h >= 1440) return '1440p';
    if (h >= 1080) return '1080p';
    if (h >= 720) return '720p';
    if (h >= 480) return '480p';
    if (h >= 360) return '360p';
    return '${h}p';
  }

  List<DownloadOption> _optionsFromScraperStreams(
    List<StreamVariant> streams, {
    required int preferredH,
  }) {
    final byHeight = <int, StreamVariant>{};
    final noHeight = <StreamVariant>[];

    for (final s in streams) {
      final h = s.height;
      if (h != null && h > 0) {
        final old = byHeight[h];
        if (old == null || _formatRank(s.format) > _formatRank(old.format)) {
          byHeight[h] = StreamVariant(
            url: s.url,
            height: h,
            bitrate: s.bitrate,
            format: s.format,
          );
        }
      } else {
        noHeight.add(s);
      }
    }

    final list = <DownloadOption>[];
    final heights = byHeight.keys.toList()..sort((a, b) => b.compareTo(a));

    for (final h in heights) {
      final s = byHeight[h]!;
      final codec = s.format == 'hls'
          ? 'HLS'
          : (s.format == 'webm' ? 'WebM' : s.format.toUpperCase());
      list.add(DownloadOption(
        id: 'scraper_$h',
        quality: _labelForHeight(h),
        codec: codec,
        source: '${_labelForHeight(h)} · Available',
        sizeLabel: s.bitrate != null && s.bitrate! > 0
            ? '${(s.bitrate! / 1000000).toStringAsFixed(1)} Mbps'
            : 'Unknown',
        streamUrl: s.url,
      ));
    }

    // Only add unknown if we have no real heights
    if (list.isEmpty && noHeight.isNotEmpty) {
      final s = noHeight.first;
      list.add(DownloadOption(
        id: 'scraper_unknown',
        quality: 'Original',
        codec: s.format == 'hls' ? 'HLS' : s.format.toUpperCase(),
        source: 'Original · Available',
        sizeLabel: 'Unknown',
        streamUrl: s.url,
      ));
    }
    return list;
  }

  int _formatRank(String format) {
    switch (format) {
      case 'hls':
        return 4;
      case 'mp4':
        return 3;
      case 'mkv':
        return 2;
      case 'webm':
        return 1;
      default:
        return 0;
    }
  }

  int _heightFromQuality(String quality) {
    final m =
        RegExp(r'(\d{3,4})\s*p', caseSensitive: false).firstMatch(quality);
    if (m != null) return int.tryParse(m.group(1)!) ?? 0;
    final q = quality.toLowerCase();
    if (q.contains('4k') || q.contains('uhd') || q.contains('2160')) return 2160;
    if (q.contains('1440') || q.contains('2k')) return 1440;
    return 0;
  }

  // ─── Embed candidates ───────────────────────────────────────────────

  List<String> _buildEmbedCandidates(int season, int episode) {
    final id = widget.tmdbId;
    if (_isTv) {
      return [
        'https://vidfast.vc/tv/$id/$season/$episode?autoPlay=true',
        'https://cinesrc.st/embed/tv/$id/$season/$episode?autoPlay=true',
        'https://www.vidking.net/embed/tv/$id/$season/$episode?autoPlay=true',
        'https://player.videasy.net/tv/$id/$season/$episode?autoPlay=true',
        'https://player.videasy.to/tv/$id/$season/$episode?autoPlay=true',
        'https://vidfast.vc/embed/tv/$id/$season/$episode?autoPlay=true',
      ];
    }
    return [
      'https://vidfast.vc/movie/$id?autoPlay=true',
      'https://cinesrc.st/embed/movie/$id?autoPlay=true',
      'https://www.vidking.net/embed/movie/$id?autoPlay=true',
      'https://player.videasy.net/movie/$id?autoPlay=true',
      'https://player.videasy.to/movie/$id?autoPlay=true',
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
      });
      final data = await _resolveInBackground(
        embeds[i],
        season: season,
        episode: episode,
      );
      if (data != null && data.bestUrl.isNotEmpty) {
        _safeSetState(() => _loadingStatus = 'Stream found. Reading qualities…');
        return _ResolvedMedia(
          url: data.bestUrl,
          sourcePage: embeds[i],
          allStreams: data.allStreams,
        );
      }
    }
    return null;
  }

  /// Strict HLS variant discovery — only uses real RESOLUTION tags.
  Future<List<DownloadOption>> _discoverHlsVariants(
    String streamUrl, {
    required String sourcePage,
  }) async {
    String masterUrl = streamUrl;
    final headers = _mediaHeaders(streamUrl, sourcePage);
    http.Response? res;

    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        res = await http
            .get(Uri.parse(masterUrl), headers: headers)
            .timeout(const Duration(seconds: 14));
        if (res.statusCode == 200) break;
      } catch (_) {
        await Future.delayed(Duration(milliseconds: 300 * (attempt + 1)));
      }
    }
    if (res == null || res.statusCode != 200) {
      return const <DownloadOption>[];
    }

    var body = res.body;

    // If we received a media playlist, try to locate the master
    if (!body.contains('#EXT-X-STREAM-INF') && body.contains('#EXTINF')) {
      final candidates = _guessMasterUrls(streamUrl);
      for (final cand in candidates) {
        try {
          final r = await http
              .get(Uri.parse(cand), headers: headers)
              .timeout(const Duration(seconds: 10));
          if (r.statusCode == 200 && r.body.contains('#EXT-X-STREAM-INF')) {
            masterUrl = cand;
            body = r.body;
            break;
          }
        } catch (_) {}
      }
    }

    // No master → treat as single original
    if (!body.contains('#EXT-X-STREAM-INF')) {
      return [
        DownloadOption(
          id: 'hls_media_original',
          quality: 'Original',
          codec: 'HLS',
          source: 'Original · Available',
          sizeLabel: 'Unknown',
          isBest: true,
          streamUrl: streamUrl,
        ),
      ];
    }

    final lines = body.split(RegExp(r'\r?\n'));
    final variants = <_HlsVariant>[];

    for (var i = 0; i < lines.length; i++) {
      final info = lines[i].trim();
      if (!info.startsWith('#EXT-X-STREAM-INF')) continue;

      String? next;
      for (var j = i + 1; j < lines.length; j++) {
        final candidate = lines[j].trim();
        if (candidate.isEmpty || candidate.startsWith('#')) continue;
        next = candidate;
        i = j;
        break;
      }
      if (next == null) continue;

      final url = Uri.parse(masterUrl).resolve(next).toString();

      // ONLY accept real RESOLUTION
      final resMatch = RegExp(r'RESOLUTION=(\d+)x(\d+)', caseSensitive: false)
          .firstMatch(info);
      if (resMatch == null) continue; // skip variants without height

      final width = int.tryParse(resMatch.group(1)!) ?? 0;
      final height = int.tryParse(resMatch.group(2)!) ?? 0;
      if (height <= 0) continue;

      final bandwidth = int.tryParse(
            RegExp(r'BANDWIDTH=(\d+)', caseSensitive: false)
                    .firstMatch(info)
                    ?.group(1) ??
                '',
          ) ??
          0;

      variants.add(_HlsVariant(
        width: width,
        height: height,
        bandwidth: bandwidth,
        url: url,
      ));
    }

    if (variants.isEmpty) return const <DownloadOption>[];

    // Keep highest bandwidth per exact height
    final byHeight = <int, _HlsVariant>{};
    for (final v in variants) {
      final old = byHeight[v.height];
      if (old == null || v.bandwidth > old.bandwidth) {
        byHeight[v.height] = v;
      }
    }

    final preferredH = AppSettingsService.instance.preferredDownloadHeight;
    final unique = byHeight.values.toList()
      ..sort((a, b) {
        // Exact match first
        final aExact = a.height == preferredH;
        final bExact = b.height == preferredH;
        if (aExact && !bExact) return -1;
        if (!aExact && bExact) return 1;

        // Then closest
        final da = (a.height - preferredH).abs();
        final db = (b.height - preferredH).abs();
        if (da != db) return da.compareTo(db);

        // Then higher
        return b.height.compareTo(a.height);
      });

    return unique.asMap().entries.map((entry) {
      final index = entry.key;
      final v = entry.value;
      final quality = _labelForHeight(v.height);
      final bitrate = v.bandwidth > 0
          ? '${(v.bandwidth / 1000000).toStringAsFixed(1)} Mbps'
          : 'Unknown';
      final isPreferred = index == 0;

      return DownloadOption(
        id: 'hls_${v.height}_${v.bandwidth}',
        quality: quality,
        codec: 'HLS',
        source: isPreferred ? '$quality · Recommended' : '$quality · Available',
        sizeLabel: bitrate,
        isBest: isPreferred,
        streamUrl: v.url, // exact variant URL
      );
    }).toList();
  }

  List<String> _guessMasterUrls(String mediaUrl) {
    final uri = Uri.parse(mediaUrl);
    final path = uri.path;
    final guesses = <String>[];
    final stripped = path.replaceAll(RegExp(r'/\d{3,4}p?/'), '/');
    for (final name in [
      'master.m3u8',
      'playlist.m3u8',
      'index.m3u8',
      'manifest.m3u8'
    ]) {
      final segs = stripped.split('/');
      if (segs.isNotEmpty) {
        segs[segs.length - 1] = name;
        guesses.add(uri.replace(path: segs.join('/')).toString());
      }
    }
    final parent =
        path.contains('/') ? path.substring(0, path.lastIndexOf('/')) : path;
    for (final name in ['master.m3u8', 'playlist.m3u8']) {
      guesses.add(uri.replace(path: '$parent/$name').toString());
    }
    return guesses.toSet().toList();
  }

  Map<String, String> _mediaHeaders(String mediaUrl, String sourcePage) {
    final headers = <String, String>{
      'User-Agent': _ua,
      'Accept': '*/*',
      'Accept-Language': 'en-US,en;q=0.9',
      'Accept-Encoding': 'identity',
      'Connection': 'keep-alive',
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
    return u.contains('.m3u8') ||
        u.contains('/hls/') ||
        u.contains('mpegurl') ||
        u.contains('manifest') ||
        u.contains('playlist');
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
    return u.contains('.m3u8') ||
        u.contains('.mp4') ||
        u.contains('.webm') ||
        u.contains('/hls/') ||
        u.contains('googlevideo') ||
        u.contains('videoplayback') ||
        u.contains('manifest') ||
        u.contains('playlist');
  }

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

  Future<void> _downloadEntireSeason(
    _TvSeason season, {
    required int preferHeight,
  }) async {
    HapticFeedback.mediumImpact();
    if (preferHeight >= 720) {
      final allowed = await _ensureHdAccess();
      if (!allowed || !mounted) return;
    }
    if (season.episodes.isEmpty) {
      await _fetchSeasonEpisodes(season.seasonNumber);
    }
    final eps = season.episodes;
    if (eps.isEmpty) {
      _toast('No episodes found for this season');
      return;
    }

    final subResult = await SubtitleSelectionSheet.show(
      context,
      tmdbId: widget.tmdbId,
      mediaType: widget.mediaType,
      season: season.seasonNumber,
      episode: eps.first.episode,
    );
    if (!mounted) return;
    // OpenSubtitles tracks are already fetched to disk at confirm-time;
    // wyzie tracks carry a URL the download service fetches later.
    final subtitleUrl = subResult?.localSubtitlePath ??
        ((subResult?.subtitle?.url.trim().isNotEmpty ?? false)
            ? subResult!.subtitle!.url
            : null);

    _safeSetState(() {
      _preparing = true;
    });

    for (final ep in eps) {
      if (!mounted) return;
      try {
        final resolved = await _resolveEpisodeStream(
          ep.season,
          ep.episode,
          null,
          showPreparingOverlay: false,
        );
        if (resolved == null) continue;
        final options = await _buildQualityOptions(
          resolved,
          ep.season,
          ep.episode,
        );
        DownloadOption? chosen;
        // Prefer exact height match
        for (final o in options) {
          if (_heightFromQuality(o.quality) == preferHeight) {
            chosen = o;
            break;
          }
        }
        // Fallback to closest
        if (chosen == null) {
          var bestDist = 1 << 30;
          for (final o in options) {
            final h = _heightFromQuality(o.quality);
            final d = (h - preferHeight).abs();
            if (d < bestDist) {
              bestDist = d;
              chosen = o;
            }
          }
        }
        chosen ??= options.isNotEmpty
            ? options.first
            : DownloadOption(
                id: 'fallback',
                quality: 'Original',
                codec: 'HLS',
                source: 'Available',
                sizeLabel: 'Unknown',
                isBest: true,
                streamUrl: resolved.url,
              );
        _enqueue(
          chosen.streamUrl ?? resolved.url,
          chosen,
          ep.season,
          ep.episode,
          sourcePage: resolved.sourcePage,
          subtitleUrl: subtitleUrl,
        );
      } catch (_) {}
      await Future.delayed(const Duration(milliseconds: 350));
    }
    if (!mounted) return;
    _safeSetState(() => _preparing = false);
    Navigator.pop(context);
    _toast('Queued ${eps.length} episodes · ~${preferHeight}p');
  }

  Future<void> _startDownload(DownloadOption option) async {
    HapticFeedback.mediumImpact();
    if (_isHdOrAbove(option.quality)) {
      final allowed = await _ensureHdAccess();
      if (!allowed || !mounted) return;
    }

    final season =
        _isTv ? (_selectedEpisode?.season ?? widget.season) : widget.season;
    final episode =
        _isTv ? (_selectedEpisode?.episode ?? widget.episode) : widget.episode;

    final subResult = await SubtitleSelectionSheet.show(
      context,
      tmdbId: widget.tmdbId,
      mediaType: widget.mediaType,
      season: season,
      episode: episode,
    );
    if (!mounted) return;
    // OpenSubtitles tracks are already fetched to disk at confirm-time;
    // wyzie tracks carry a URL the download service fetches later.
    final subtitleUrl = subResult?.localSubtitlePath ??
        ((subResult?.subtitle?.url.trim().isNotEmpty ?? false)
            ? subResult!.subtitle!.url
            : null);

    if (option.streamUrl != null && option.streamUrl!.isNotEmpty) {
      final sourcePage = _resolvedMedia?.sourcePage ??
          _buildEmbedCandidates(season, episode).first;
      _enqueue(
        option.streamUrl!,
        option,
        season,
        episode,
        sourcePage: sourcePage,
        subtitleUrl: subtitleUrl,
      );
      return;
    }

    _safeSetState(() {
      _preparing = true;
    });

    try {
      final resolved = await _resolveEpisodeStream(
        season,
        episode,
        option.streamUrl,
        showPreparingOverlay: true,
      );
      if (resolved == null) {
        throw Exception('Could not resolve stream');
      }
      final chosen = option.streamUrl != null
          ? option
          : DownloadOption(
              id: option.id,
              quality: option.quality,
              codec: option.codec,
              source: option.source,
              sizeLabel: option.sizeLabel,
              isBest: option.isBest,
              streamUrl: resolved.url,
            );
      if (!mounted) return;
      _safeSetState(() => _preparing = false);
      _enqueue(
        chosen.streamUrl ?? resolved.url,
        chosen,
        season,
        episode,
        sourcePage: resolved.sourcePage,
        subtitleUrl: subtitleUrl,
      );
    } catch (e) {
      _resolvedCache.remove('$season-$episode');
      if (!mounted) return;
      _safeSetState(() {
        _preparing = false;
      });
      _toast(
        _isTv
            ? 'Could not prepare S${season.toString().padLeft(2, '0')}E${episode.toString().padLeft(2, '0')}. ${_shortError(e)}'
            : 'Could not prepare this file. ${_shortError(e)}',
      );
    }
  }

  void _enqueue(
    String videoUrl,
    DownloadOption option,
    int season,
    int episode, {
    String? sourcePage,
    String? subtitleUrl,
  }) {
    final movie = Movie(
      id: int.tryParse(widget.tmdbId) ?? 0,
      title: widget.movieTitle,
      posterPath: widget.posterUrl,
      overview: '',
      voteAverage: 0.0,
      releaseDate: '',
    );
    final referer = sourcePage ??
        (_isTv
            ? 'https://vidfast.vc/tv/${widget.tmdbId}/$season/$episode'
            : 'https://vidfast.vc/movie/${widget.tmdbId}');
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
      subtitleUrl: subtitleUrl,
    );
    if (!AppSettingsService.instance.downloadOverWifiOnly) {
      final est = CellularDataService.parseSizeLabel(option.sizeLabel);
      if (est > 0) {
        CellularDataService.instance.recordDownloadBytes(est, isCellular: true);
      }
    }
    Navigator.pop(context);
    final subLabel = subtitleUrl != null ? ' · subs' : '';
    _toast(_isTv
        ? 'Downloading S${season.toString().padLeft(2, '0')}E${episode.toString().padLeft(2, '0')} · ${option.quality}$subLabel'
        : 'Downloading ${option.quality} · ${option.sizeLabel}$subLabel');
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg,
          style: FontService.instance.label(color: Colors.white, fontSize: 13)),
      backgroundColor: const Color(0xFF222222),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  Future<ExtractedStreamData?> _resolveInBackground(
    String embedUrl, {
    required int season,
    required int episode,
  }) async {
    final completer = Completer<ExtractedStreamData?>();
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _StreamResolverOverlay(
        embedUrl: embedUrl,
        mediaType: widget.mediaType,
        season: season,
        episode: episode,
        onProgress: (_, _) {},
        onDone: (data) {
          if (!completer.isCompleted) completer.complete(data);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            try {
              entry.remove();
            } catch (_) {}
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
    final timeoutSecs = _isTv ? 16 : 14;
    return completer.future.timeout(Duration(seconds: timeoutSecs),
        onTimeout: () {
      try {
        entry.remove();
      } catch (_) {}
      return null;
    });
  }

  // ─── UI ─────────────────────────────────────────────────────────────

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
            color: _bg.withValues(alpha: 0.92),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border.all(
              color: _gold.withValues(alpha: 0.15),
              width: 0.8,
            ),
          ),
          child: Column(
            children: [
              const SizedBox(height: 8),
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
              _buildCompactHeader(),
              const Divider(
                color: Colors.white10,
                height: 1,
                thickness: 0.5,
              ),
              Expanded(
                child: _isTv && _step == 0
                    ? _buildEpisodePicker(bottom)
                    : _buildQualityList(bottom),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCompactHeader() {
    final subtitle = _isTv
        ? (_step == 1 && _selectedEpisode != null
            ? 'S${_selectedEpisode!.season.toString().padLeft(2, '0')}E${_selectedEpisode!.episode.toString().padLeft(2, '0')}'
            : 'Choose episode')
        : widget.movieTitle;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
      child: Row(
        children: [
          if (_step == 1)
            GestureDetector(
              onTap: () {
                setState(() {
                  _step = 0;
                  _selectedEpisode = null;
                });
              },
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.06),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.arrow_back_ios_new_rounded,
                  color: Colors.white70,
                  size: 16,
                ),
              ),
            ),
          if (widget.posterUrl.isNotEmpty) ...[
            const SizedBox(width: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Image.network(
                widget.posterUrl.startsWith('http')
                    ? widget.posterUrl
                    : 'https://image.tmdb.org/t/p/w92${widget.posterUrl}',
                width: 32,
                height: 44,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Container(
                  width: 32,
                  height: 44,
                  color: Colors.grey[850],
                  child:
                      const Icon(Icons.movie, color: Colors.white24, size: 14),
                ),
              ),
            ),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Available Downloads',
                  style: FontService.instance.style(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: FontService.instance.label(
                    color: Colors.white54,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded,
                color: Colors.white70, size: 20),
            onPressed: () {
              final season = _isTv
                  ? (_selectedEpisode?.season ?? widget.season)
                  : widget.season;
              final episode = _isTv
                  ? (_selectedEpisode?.episode ?? widget.episode)
                  : widget.episode;
              _resolvedCache.remove('$season-$episode');
              unawaited(_prepareQualitiesForEpisode(season, episode));
            },
            tooltip: 'Refresh',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
          const SizedBox(width: 4),
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close_rounded,
                color: Colors.white70, size: 20),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }

  Widget _buildEpisodePicker(double bottom) {
    if (_loadingTv) {
      return DownloadSkeletonLoader(
        itemCount: 5,
        padding: EdgeInsets.fromLTRB(16, 8, 16, bottom + 20),
      );
    }
    if (_tvError != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_tvError!, style: const TextStyle(color: Colors.white54)),
            TextButton(
              onPressed: _loadTvStructure,
              child: const Text('Retry', style: TextStyle(color: _gold)),
            ),
          ],
        ),
      );
    }
    if (_seasons.isEmpty) {
      return const Center(
        child: Text(
          'No episodes found',
          style: TextStyle(color: Colors.white54),
        ),
      );
    }

    return ListView.builder(
      padding: EdgeInsets.fromLTRB(12, 6, 12, bottom + 12),
      itemCount: _seasons.length,
      itemBuilder: (context, index) {
        final season = _seasons[index];
        final expanded = _expandedSeason == season.seasonNumber;
        final currentlyLoading =
            expanded && season.episodes.isEmpty && !_loadingTv;
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
          ),
          child: Column(
            children: [
              InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () async {
                  setState(() {
                    _expandedSeason = expanded ? null : season.seasonNumber;
                  });
                  if (season.episodes.isEmpty && season.seasonNumber > 0) {
                    await _fetchSeasonEpisodes(season.seasonNumber);
                  }
                },
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: _gold.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'S${season.seasonNumber}',
                          style: const TextStyle(
                            color: _gold,
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          season.name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      Text(
                        '${season.episodeCount} eps',
                        style:
                            const TextStyle(color: Colors.white38, fontSize: 11),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        expanded
                            ? Icons.keyboard_arrow_up_rounded
                            : Icons.keyboard_arrow_down_rounded,
                        color: Colors.white54,
                        size: 18,
                      ),
                    ],
                  ),
                ),
              ),
              if (expanded) ...[
                if (currentlyLoading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        color: _gold,
                        strokeWidth: 2,
                      ),
                    ),
                  )
                else ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 0, 10, 6),
                    child: Column(
                      children: [
                        DownloadTile(
                          title:
                              'S${season.seasonNumber.toString().padLeft(2, '0')} [720p]',
                          subtitle:
                              'All ${season.episodes.length} episodes · 720p',
                          onDownload: () => unawaited(
                            _downloadEntireSeason(season, preferHeight: 720),
                          ),
                        ),
                        DownloadTile(
                          title:
                              'S${season.seasonNumber.toString().padLeft(2, '0')} [1080p]',
                          subtitle:
                              'All ${season.episodes.length} episodes · 1080p',
                          highlighted: true,
                          onDownload: () => unawaited(
                            _downloadEntireSeason(season, preferHeight: 1080),
                          ),
                        ),
                        const Padding(
                          padding: EdgeInsets.only(top: 2, bottom: 4),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'OR PICK AN EPISODE',
                              style: TextStyle(
                                color: Colors.white38,
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
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
    final still = ep.stillPath != null
        ? 'https://image.tmdb.org/t/p/w300${ep.stillPath}'
        : null;
    return InkWell(
      onTap: () => _pickEpisode(ep),
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
          ),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: still != null
                  ? Image.network(
                      still,
                      width: 56,
                      height: 32,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => _stillPlaceholder(),
                    )
                  : _stillPlaceholder(),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'E${ep.episode.toString().padLeft(2, '0')}  ·  ${ep.name}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (ep.runtime != null || ep.airDate != null) ...[
                    const SizedBox(height: 1),
                    Text(
                      [
                        if (ep.runtime != null) '${ep.runtime} min',
                        if (ep.airDate != null && ep.airDate!.isNotEmpty)
                          ep.airDate,
                      ].join(' · '),
                      style:
                          const TextStyle(color: Colors.white38, fontSize: 10),
                    ),
                  ],
                ],
              ),
            ),
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: _gold.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.download_rounded,
                color: _gold,
                size: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stillPlaceholder() => Container(
        width: 56,
        height: 32,
        color: Colors.white10,
        child: const Icon(Icons.tv_rounded, color: Colors.white24, size: 14),
      );

  Widget _buildQualityList(double bottom) {
    if (_loadingQualities) {
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Text(
              _loadingStatus,
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ),
          Expanded(
            child: DownloadSkeletonLoader(
              itemCount: 4,
              padding: EdgeInsets.fromLTRB(12, 8, 12, bottom + 12),
            ),
          ),
        ],
      );
    }
    if (_qualityError != null) {
      return Center(
        child: Padding(
          padding: EdgeInsets.fromLTRB(24, 20, 24, bottom + 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_rounded,
                  color: Colors.white38, size: 28),
              const SizedBox(height: 10),
              Text(
                _qualityError!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white54, fontSize: 13),
              ),
              const SizedBox(height: 10),
              TextButton(
                onPressed: () {
                  final season = _isTv
                      ? (_selectedEpisode?.season ?? widget.season)
                      : widget.season;
                  final episode = _isTv
                      ? (_selectedEpisode?.episode ?? widget.episode)
                      : widget.episode;
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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.movie_rounded,
                color: Colors.white.withValues(alpha: 0.15),
                size: 48,
              ),
              const SizedBox(height: 12),
              Text(
                'No downloads available',
                style: FontService.instance.display(
                  color: Colors.white54,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'This title does not have any downloadable streams right now.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.3),
                  fontSize: 12.5,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final seasonTag = _isTv
        ? 'S${(_selectedEpisode?.season ?? widget.season).toString().padLeft(2, '0')}'
        : null;
    final currentSeason = _isTv
        ? (_selectedEpisode?.season ?? widget.season)
        : widget.season;
    final currentEpisode = _isTv
        ? (_selectedEpisode?.episode ?? widget.episode)
        : widget.episode;

    return ListView.builder(
      padding: EdgeInsets.fromLTRB(12, 6, 12, bottom + 12),
      itemCount: _qualities.length,
      itemBuilder: (context, index) {
        final q = _qualities[index];
        final title = seasonTag != null
            ? '$seasonTag [${q.quality}]'
            : '${q.quality}${q.isBest ? ' · Best' : ''}';

        final downloaded =
            _isOptionDownloaded(q, currentSeason, currentEpisode);

        return Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: DownloadTile(
            title: title,
            subtitle: q.sizeLabel.isNotEmpty
                ? '${q.codec} · ${q.sizeLabel}'
                : q.codec,
            highlighted: q.isBest,
            enabled: !_preparing,
            onDownload: () => _startDownload(q),
            trailing: downloaded
                ? const Icon(
                    Icons.check_circle_rounded,
                    color: Colors.green,
                    size: 20,
                  )
                : null,
          ),
        );
      },
    );
  }
}

class _StreamResolverOverlay extends StatefulWidget {
  final String embedUrl;
  final String mediaType;
  final int season;
  final int episode;
  final void Function(double progress, String? label) onProgress;
  final void Function(ExtractedStreamData? data) onDone;
  const _StreamResolverOverlay({
    required this.embedUrl,
    required this.mediaType,
    required this.season,
    required this.episode,
    required this.onProgress,
    required this.onDone,
  });

  @override
  State<_StreamResolverOverlay> createState() =>
      _StreamResolverOverlayState();
}

class _StreamResolverOverlayState extends State<_StreamResolverOverlay> {
  bool _finished = false;

  void _finish(ExtractedStreamData? data) {
    if (_finished) return;
    _finished = true;
    widget.onDone(data);
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
        timeoutSeconds: widget.mediaType.toLowerCase() == 'tv' ? 14 : 12,
        onLoading: (loading) {
          if (loading) {
            widget.onProgress(0.2, 'Finding the video stream…');
          }
        },
        onDataExtracted: (data) {
          widget.onProgress(0.98, 'Stream found. Checking qualities…');
          _finish(data);
        },
        onError: (_) => _finish(null),
      ),
    );
  }
}