import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// Make sure this import points to your actual player screen file path
import '../screens/custom_player_screen.dart';

const _gold = Color(0xFFFFB800);
const _bg = Color(0xFF0A0A0A);

class ServerSelectorSheet extends StatefulWidget {
  final String tmdbId;
  final String movieTitle;
  final String mediaType; // 'movie' or 'tv'
  final int season;
  final int episode;

  const ServerSelectorSheet({
    super.key,
    required this.tmdbId,
    required this.movieTitle,
    this.mediaType = 'movie',
    this.season = 1,
    this.episode = 1,
  });

  @override
  State<ServerSelectorSheet> createState() => _ServerSelectorSheetState();
}

class _ServerSelectorSheetState extends State<ServerSelectorSheet>
    with SingleTickerProviderStateMixin {
  int _selectedServerIndex = 0;

  // Integrated server list with custom futuristic names and quality badges
  final List<Map<String, dynamic>> _serversData = [
    {
      "id": "vidfast",
      "name": "Aetherion Direct",
      "subtitle": "4K Ultra HD • Ultra Latency",
      "url": "https://vidfast.vc",
      "movie_url_pattern": null,
      "tv_url_pattern": null,
    },
    {
      "id": "cinesrc",
      "name": "Hyperion Core",
      "subtitle": "1080p / 4K • Dolby Atmos",
      "url": "https://cinesrc.st/embed",
      "movie_url_pattern": null,
      "tv_url_pattern": null,
    },
    {
      "id": "cineplay",
      "name": "Nexus Prime Stream",
      "subtitle": "Fast CDN Node • Auto Speed",
      "url": "https://www.cineplay.to",
      "movie_url_pattern": "{url}/{type}/{tmdbId}?play=true",
      "tv_url_pattern": "{url}/{type}/{tmdbId}/{season}/{episode}?play=true",
    },
    {
      "id": "videasy",
      "name": "Chronos Fiber Relay",
      "subtitle": "Direct Stream • Lossless Audio",
      "url": "https://player.videasy.to",
      "movie_url_pattern": "{url}/{type}/{tmdbId}",
      "tv_url_pattern": "{url}/{type}/{tmdbId}/{season}/{episode}",
    }
  ];

  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _fadeCtrl.forward();
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    super.dispose();
  }

  String _buildStreamUrl(Map<String, dynamic> server) {
    final isMovie = widget.mediaType.toLowerCase() == 'movie';
    String? pattern = isMovie
        ? server['movie_url_pattern'] as String?
        : server['tv_url_pattern'] as String?;

    final id = (server['id'] ?? '').toString().toLowerCase();

    // Fallback logic for servers with null patterns in list.json
    if (pattern == null || pattern.isEmpty) {
      if (id == 'vidfast' || id == 'cinesrc') {
        pattern = isMovie
            ? '{url}/movie/{tmdbId}?autoPlay=true'
            : '{url}/tv/{tmdbId}/{season}/{episode}?autoPlay=true';
      } else {
        pattern = isMovie
            ? '{url}/{type}/{tmdbId}'
            : '{url}/{type}/{tmdbId}/{season}/{episode}';
      }
    }

    var url = pattern
        .replaceAll('{url}', server['url'] ?? '')
        .replaceAll('{type}', isMovie ? 'movie' : 'tv')
        .replaceAll('{tmdbId}', widget.tmdbId)
        .replaceAll('{season}', widget.season.toString())
        .replaceAll('{episode}', widget.episode.toString());

    // Ensure VidFast always autoplays (required for stream extraction).
    if (id == 'vidfast' && !url.contains('autoPlay=')) {
      url = '$url${url.contains('?') ? '&' : '?'}autoPlay=true';
    }

    return url;
  }

  void _startStreaming() {
    HapticFeedback.mediumImpact();
    final server = _serversData[_selectedServerIndex];
    final embedUrl = _buildStreamUrl(server);

    // Immediately pop the sheet and push to the custom player.
    Navigator.pop(context);

    Navigator.push(
      context,
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 280),
        pageBuilder: (_, _, _) => CustomPlayerScreen(
          streamUrl: embedUrl,
          title: widget.movieTitle,
          tmdbId: widget.tmdbId,
          mediaType: widget.mediaType,
          season: widget.season,
          episode: widget.episode,
          wisoApiKey: '', 
          servers: _serversData,
          headers: {
            'Referer': server['url'] ?? '',
            'User-Agent':
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
          },
        ),
        transitionsBuilder: (_, animation, _, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).padding.bottom;

    return FadeTransition(
      opacity: _fadeAnim,
      child: Container(
        padding: EdgeInsets.fromLTRB(20, 12, 20, 16 + bottomPad),
        decoration: const BoxDecoration(
          color: _bg,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 18),

            // Header
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: _gold.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _gold.withValues(alpha: 0.4)),
                  ),
                  child: const Icon(Icons.play_circle_fill_rounded,
                      color: _gold, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Choose a server',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.movieTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.close_rounded,
                        color: Colors.white70, size: 16),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 18),

            // Server list
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _serversData.length,
              itemBuilder: (context, index) {
                final server = _serversData[index];
                final isSelected = _selectedServerIndex == index;

                return GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() => _selectedServerIndex = index);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? _gold.withValues(alpha: 0.12)
                          : Colors.white.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isSelected
                            ? _gold.withValues(alpha: 0.7)
                            : Colors.white.withValues(alpha: 0.08),
                        width: isSelected ? 1.5 : 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: isSelected
                                ? _gold.withValues(alpha: 0.2)
                                : Colors.white.withValues(alpha: 0.06),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            Icons.dns_rounded,
                            color: isSelected ? _gold : Colors.white38,
                            size: 18,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                server['name'] ?? 'Unknown Server',
                                style: TextStyle(
                                  color: isSelected
                                      ? Colors.white
                                      : Colors.white70,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                server['subtitle'] ?? 'High Speed Node',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white38,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isSelected ? _gold : Colors.transparent,
                            border: Border.all(
                              color: isSelected
                                  ? _gold
                                  : Colors.white.withValues(alpha: 0.25),
                              width: 2,
                            ),
                          ),
                          child: isSelected
                              ? const Icon(Icons.check_rounded,
                                  size: 14, color: Colors.black)
                              : null,
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),

            const SizedBox(height: 16),

            // Stream Only button
            SizedBox(
              width: double.infinity,
              child: GestureDetector(
                onTap: _startStreaming,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  height: 48,
                  decoration: BoxDecoration(
                    color: _gold,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.play_arrow_rounded,
                          color: Colors.black, size: 22),
                      SizedBox(width: 6),
                      Text(
                        'Stream Only',
                        style: TextStyle(
                          color: Colors.black,
                          fontWeight: FontWeight.w800,
                          fontSize: 14.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}