// Add-on detail: renders metadata from the addon's `meta` resource (for
// series this includes the episode list) and lets the user pick a stream
// across every installed add-on that offers one, then plays into
// CustomPlayerScreen (or opens externally).
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../design/tokens.dart';
import '../services/addon_catalog.dart';
import '../services/addon_content_models.dart';
import '../services/addon_models.dart';
import '../services/addon_repository.dart';
import '../services/debrid_resolver.dart';
import 'custom_player_screen.dart';
import 'debrid_screen.dart';

const _gold = AppDesignTokens.goldMuted;
const _bg = AppDesignTokens.backgroundCanvas;

class AddonDetailScreen extends StatefulWidget {
  final AddonManifest manifest;
  final AddonCatalogItem item;

  const AddonDetailScreen({
    super.key,
    required this.manifest,
    required this.item,
  });

  @override
  State<AddonDetailScreen> createState() => _AddonDetailScreenState();
}

class _AddonDetailScreenState extends State<AddonDetailScreen> {
  AddonMeta? _meta;
  AddonCatalogItem get _item => widget.item;
  AddonManifest get _manifest => widget.manifest;
  bool _metaLoading = true;
  bool _metaError = false;

  @override
  void initState() {
    super.initState();
    _loadMeta();
  }

  Future<void> _loadMeta() async {
    setState(() {
      _metaLoading = true;
      _metaError = false;
    });
    try {
      final meta = await fetchAddonMeta(
        manifest: _manifest,
        type: _item.type,
        id: _item.id,
      );
      if (!mounted) return;
      setState(() {
        _meta = meta;
        _metaLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _metaLoading = false;
        _metaError = true;
      });
    }
  }

  List<AddonVideo> get _episodes {
    final meta = _meta;
    if (meta == null) return const [];
    final videos = meta.videos
        .where((v) => v.episode != null || v.season != null)
        .toList();
    videos.sort((a, b) {
      final sa = a.season ?? 0;
      final sb = b.season ?? 0;
      if (sa != sb) return sa.compareTo(sb);
      return (a.episode ?? 0).compareTo(b.episode ?? 0);
    });
    return videos;
  }

  List<int> get _seasons =>
      _episodes.map((e) => e.season ?? 0).toSet().toList()..sort();

  Future<void> _playMovie() async {
    await _showStreams(id: _item.id, video: null);
  }

  Future<void> _playEpisode(AddonVideo video) async {
    await _showStreams(id: _item.id, video: video);
  }

  Future<void> _showStreams({
    required String id,
    required AddonVideo? video,
  }) async {
    final type = _item.type;
    final contentId = id;

    String requestId;
    if (video != null) {
      final vId = video.id?.trim();
      if (vId != null && vId.isNotEmpty && vId.contains(':')) {
        requestId = vId;
      } else if (video.season != null && video.episode != null) {
        requestId = episodeStreamId(contentId, video.season!, video.episode!);
      } else if (vId != null && vId.isNotEmpty) {
        requestId = vId;
      } else {
        requestId = contentId;
      }
    } else {
      requestId = contentId;
    }

    final addons = AddonRepository.instance.addons
        .where((a) => a.isActive && a.manifest != null)
        .map((a) => a.manifest!)
        .toList(growable: false);

    final subtitle = video == null
        ? _item.name
        : '${_item.name} — ${video.displayCode}${video.title == null ? '' : ' ${video.title}'}'
            .trim();

    await showAddonStreamsSheet(
      context,
      manifests: addons,
      type: type,
      id: requestId,
      title: subtitle,
      mediaType: _item.isSeries ? 'tv' : 'movie',
      season: video?.season,
      episode: video?.episode,
      fallbackImage: _item.poster,
    );
  }

  @override
  Widget build(BuildContext context) {
    final item = _item;
    final meta = _meta;
    final name = meta?.name ?? item.name;
    final backdrop =
        meta?.background ?? item.background ?? item.poster;
    final series = item.isSeries;

    return Scaffold(
      backgroundColor: _bg,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            backgroundColor: _bg,
            foregroundColor: Colors.white,
            expandedHeight: 280,
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  if (backdrop != null && backdrop.isNotEmpty)
                    CachedNetworkImage(
                      imageUrl: backdrop,
                      fit: BoxFit.cover,
                      errorWidget: (_, _, _) =>
                          const SizedBox.shrink(),
                    ),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, _bg],
                      ),
                    ),
                  ),
                  Positioned(
                    left: 16,
                    right: 16,
                    bottom: 12,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 26,
                              fontWeight: FontWeight.w800,
                              height: 1.1,
                              shadows: [
                                Shadow(blurRadius: 12, color: Colors.black54)
                              ]),
                        ),
                        const SizedBox(height: 6),
                        _metaLine(meta ?? item),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                Row(children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: series ? null : _playMovie,
                      icon: const Icon(Icons.play_arrow_rounded, size: 22),
                      label: Text(series ? 'SELECT AN EPISODE' : 'PLAY'),
                      style: FilledButton.styleFrom(
                        backgroundColor: _gold,
                        foregroundColor: Colors.black,
                        disabledBackgroundColor:
                            _gold.withValues(alpha: 0.25),
                        disabledForegroundColor: Colors.black45,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ]),
                if (series && _metaLoading) ...[
                  const SizedBox(height: 20),
                  const Center(
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: _gold),
                    ),
                  ),
                ],
                if (_metaError) ...[
                  const SizedBox(height: 20),
                  const Text(
                    'Could not load episode list for this title.',
                    style: TextStyle(color: Colors.white54, fontSize: 13),
                  ),
                ],
                if (series && _meta != null && _meta!.videos.isEmpty) ...[
                  const SizedBox(height: 16),
                  const Text('This add-on did not provide episode details.',
                      style: TextStyle(color: Colors.white54, fontSize: 13)),
                ],
                if (series && !_metaLoading && !_metaError && _episodes.isNotEmpty)
                  ..._buildSeries(meta!),
                const SizedBox(height: 20),
                if ((meta?.description ?? item.description) != null)
                  _sectionText(
                    'OVERVIEW',
                    meta?.description ?? item.description ?? '',
                  ),
                if ((meta?.genres.isNotEmpty ?? false) ||
                    (item.genres.isNotEmpty)) ...[
                  const SizedBox(height: 18),
                  const Text('GENRES',
                      style: TextStyle(
                          color: Colors.white54,
                          fontSize: 11,
                          letterSpacing: 1.4,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final genre in (meta?.genres.isNotEmpty ?? false)
                          ? meta!.genres
                          : item.genres)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.07),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: Colors.white10),
                          ),
                          child: Text(genre,
                              style: const TextStyle(
                                  color: Colors.white70, fontSize: 11)),
                        ),
                    ],
                  ),
                ],
                if (meta != null && meta.cast.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  const Text('CAST',
                      style: TextStyle(
                          color: Colors.white54,
                          fontSize: 11,
                          letterSpacing: 1.4,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 96,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: meta.cast.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 10),
                      itemBuilder: (context, i) {
                        final member = meta.cast[i];
                        return SizedBox(
                          width: 66,
                          child: Column(
                            children: [
                              ClipOval(
                                child: member.image == null
                                    ? Container(
                                        width: 56,
                                        height: 56,
                                        color:
                                            Colors.white.withValues(alpha: 0.08),
                                        child: const Icon(
                                            Icons.person_outline_rounded,
                                            color: Colors.white38,
                                            size: 26),
                                      )
                                    : CachedNetworkImage(
                                        imageUrl: member.image!,
                                        width: 56,
                                        height: 56,
                                        fit: BoxFit.cover,
                                        errorWidget: (_, _, _) => Container(
                                          color: Colors.white
                                              .withValues(alpha: 0.08),
                                          child: const Icon(
                                              Icons.person_outline_rounded,
                                              color: Colors.white38,
                                              size: 26),
                                        ),
                                      ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                member.name ?? '',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                    color: Colors.white60, fontSize: 9.5),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ]),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildSeries(AddonMeta meta) {
    return [
      const SizedBox(height: 24),
      const Text('EPISODES',
          style: TextStyle(
              color: Colors.white54,
              fontSize: 11,
              letterSpacing: 1.4,
              fontWeight: FontWeight.w700)),
      const SizedBox(height: 8),
      for (final season in _seasons) ...[
        Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 8),
          child: Text(
            season == 0 ? 'Special' : 'Season $season',
            style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w700),
          ),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final episode in _episodes.where(
                (e) => (e.season ?? 0) == season))
              ActionChip(
                backgroundColor: Colors.white.withValues(alpha: 0.06),
                side: const BorderSide(color: Colors.white12),
                label: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(episode.displayCode,
                        style: const TextStyle(
                            color: Colors.white, fontSize: 12)),
                    if (episode.title != null) ...[
                      const SizedBox(width: 6),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 160),
                        child: Text(
                          episode.title!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Colors.white60, fontSize: 12),
                        ),
                      ),
                    ],
                  ],
                ),
                onPressed: () => _playEpisode(episode),
              ),
          ],
        ),
      ],
    ];
  }

  Widget _metaLine(Object source) {
    final year = source is AddonMeta
        ? source.releaseInfo
        : (source as AddonCatalogItem).releaseInfo;
    final rating = source is AddonMeta
        ? source.imdbRating
        : (source as AddonCatalogItem).imdbRating;
    final runtime = source is AddonMeta ? source.runtime : null;
    final parts = <String>[
      if (source is AddonMeta)
        source.isSeries
            ? 'SERIES'
            : 'MOVIE'
      else if ((source as AddonCatalogItem).isSeries)
        'SERIES'
      else
        'MOVIE',
      if (year != null && year.isNotEmpty) year,
      if (runtime != null && runtime.isNotEmpty) runtime,
    ];
    return Row(
      children: [
        if (rating != null && rating.isNotEmpty) ...[
          const Icon(Icons.star_rounded, color: _gold, size: 15),
          const SizedBox(width: 3),
          Text(rating,
              style: const TextStyle(
                  color: _gold,
                  fontSize: 12,
                  fontWeight: FontWeight.w700)),
          const SizedBox(width: 10),
        ],
        Expanded(
          child: Text(
            parts.join('  ·  '),
            style: const TextStyle(color: Colors.white70, fontSize: 12),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _sectionText(String title, String body) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 18),
        Text(title,
            style: const TextStyle(
                color: Colors.white54,
                fontSize: 11,
                letterSpacing: 1.4,
                fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Text(
          body,
          style: const TextStyle(
              color: Colors.white70, fontSize: 13.5, height: 1.5),
        ),
      ],
    );
  }
}

/// Bottom sheet that aggregates streams from every installed add-on that
/// supports [type]/[id] and plays the selection.
Future<void> showAddonStreamsSheet(
  BuildContext context, {
  required List<AddonManifest> manifests,
  required String type,
  required String id,
  required String title,
  required String mediaType,
  int? season,
  int? episode,
  String? fallbackImage,
}) {
  return showModalBottomSheet(
    context: context,
    backgroundColor: AppDesignTokens.surfaceElevated,
    isScrollControlled: true,
    isDismissible: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => FractionallySizedBox(
      heightFactor: 0.82,
      child: _StreamsSheetBody(
        manifests: manifests,
        type: type,
        id: id,
        title: title,
        mediaType: mediaType,
        season: season,
        episode: episode,
        fallbackImage: fallbackImage,
      ),
    ),
  );
}

class _StreamsSheetBody extends StatefulWidget {
  final List<AddonManifest> manifests;
  final String type;
  final String id;
  final String title;
  final String mediaType;
  final int? season;
  final int? episode;
  final String? fallbackImage;

  const _StreamsSheetBody({
    required this.manifests,
    required this.type,
    required this.id,
    required this.title,
    required this.mediaType,
    this.season,
    this.episode,
    this.fallbackImage,
  });

  @override
  State<_StreamsSheetBody> createState() => _StreamsSheetBodyState();
}

class _StreamsSheetBodyState extends State<_StreamsSheetBody> {
  List<AddonStreamGroup>? _groups;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final groups = await fetchStreamsFromAddons(
        manifests: widget.manifests,
        type: widget.type,
        id: widget.id,
      );
      if (!mounted) return;
      setState(() {
        _groups = groups;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _groups = const [];
        _loading = false;
      });
    }
  }

  Future<void> _play(AddonStream stream) async {
    // Capture the navigator up-front so we can dismiss the sheet and then
    // push the player without touching a context that is going away.
    final navigator = Navigator.of(context);

    final direct = stream.playableDirectUrl;
    if (direct != null) {
      navigator.pop();
      await navigator.push(MaterialPageRoute(
        builder: (_) => CustomPlayerScreen(
          streamUrl: direct,
          title: widget.title,
          wisoApiKey: '',
          mediaType: widget.mediaType,
          season: widget.season,
          episode: widget.episode,
          isOffline: false,
        ),
      ));
      return;
    }
    final external = stream.openExternalUrl;
    if (external != null) {
      navigator.pop();
      await launchUrl(Uri.parse(external),
          mode: LaunchMode.externalApplication);
      return;
    }
    if (stream.isTorrent) {
      // Debrid instant resolve: turn the torrent into a direct HTTPS link.
      final result = await resolveAddonStreamTorrent(
        stream: stream,
        season: widget.season,
        episode: widget.episode,
      );
      if (!mounted) return;
      if (result.success && result.url != null) {
        navigator.pop();
        await navigator.push(MaterialPageRoute(
          builder: (_) => CustomPlayerScreen(
            streamUrl: result.url!,
            title: widget.title,
            wisoApiKey: '',
            mediaType: widget.mediaType,
            season: widget.season,
            episode: widget.episode,
            isOffline: false,
          ),
        ));
        return;
      }
      final configure =
          result.failure == DebridResolveFailure.notConfigured ||
          result.failure == DebridResolveFailure.missingApiKey;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(result.failureMessage),
        behavior: SnackBarBehavior.floating,
        action: configure
            ? SnackBarAction(
                label: 'Set up',
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                      builder: (_) => const DebridScreen()),
                ),
              )
            : null,
      ));
      return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('This stream has no playable link.'),
      behavior: SnackBarBehavior.floating,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final total = _groups
            ?.fold<int>(0, (sum, g) => sum + g.streams.length) ??
        0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold)),
                    const SizedBox(height: 2),
                    Text(
                      _loading
                          ? 'Looking for streams…'
                          : '$total stream${total == 1 ? '' : 's'} found',
                      style: const TextStyle(
                          color: Colors.white38, fontSize: 11),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded,
                    color: Colors.white54, size: 22),
              ),
            ],
          ),
        ),
        const Divider(color: Colors.white12, height: 1),
        Expanded(child: _buildList()),
      ],
    );
  }

  Widget _buildList() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(strokeWidth: 2, color: _gold),
      );
    }
    final groups = _groups ?? const <AddonStreamGroup>[];
    final withStreams = groups.where((g) => g.streams.isNotEmpty).toList();
    if (withStreams.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.search_off_rounded,
                  color: Colors.white30, size: 40),
              const SizedBox(height: 12),
              const Text(
                'No playable streams returned.\n'
                'Install an add-on that provides sources for this title.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white54, fontSize: 12.5),
              ),
            ],
          ),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.only(bottom: 20),
      children: [
        for (final group in withStreams) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
            child: Row(
              children: [
                Icon(Icons.widgets_rounded, color: _gold, size: 14),
                const SizedBox(width: 6),
                Text(group.name.toUpperCase(),
                    style: const TextStyle(
                        color: Colors.white60,
                        fontSize: 11,
                        letterSpacing: 1.2,
                        fontWeight: FontWeight.w700)),
                const Spacer(),
                Text('${group.streams.length}',
                    style: const TextStyle(
                        color: Colors.white38, fontSize: 11)),
              ],
            ),
          ),
          for (final stream in group.streams)
            _StreamTile(stream: stream, onTap: () => _play(stream)),
        ],
      ],
    );
  }
}

class _StreamTile extends StatelessWidget {
  const _StreamTile({required this.stream, required this.onTap});

  final AddonStream stream;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final direct = stream.playableDirectUrl;
    final external = stream.openExternalUrl;
    final IconData icon;
    final Color iconColor;
    if (direct != null) {
      icon = Icons.play_circle_outline_rounded;
      iconColor = Colors.greenAccent;
    } else if (external != null) {
      icon = Icons.open_in_new_rounded;
      iconColor = Colors.lightBlueAccent;
    } else {
      icon = Icons.link_off_rounded;
      iconColor = Colors.white30;
    }

    final badge = stream.description?.trim() ?? stream.name?.trim();

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        child: Row(
          children: [
            Icon(icon, color: iconColor, size: 26),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    stream.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600),
                  ),
                  if (badge != null && badge.isNotEmpty && badge != stream.label)
                    Text(
                      badge,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white38, fontSize: 11),
                    ),
                  if (stream.isTorrent && stream.infoHash != null)
                    Text(
                      'Torrent · ${stream.infoHash!.substring(0, 8).toUpperCase()}…',
                      style: const TextStyle(
                          color: Colors.orangeAccent, fontSize: 10),
                    ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded,
                color: Colors.white24, size: 20),
          ],
        ),
      ),
    );
  }
}
