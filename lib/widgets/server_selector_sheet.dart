import 'dart:ui';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../screens/custom_player_screen.dart';
import '../design/tokens.dart';
import '../design/motion.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _gold = AppDesignTokens.gold;
const _bg = AppDesignTokens.backgroundCanvas;

class ServerHealthTracker {
  ServerHealthTracker._();
  static final ServerHealthTracker instance = ServerHealthTracker._();

  static const String _prefPrefix = 'server_health_';
  static const String _lastUpdatedPrefix = 'server_updated_';
  static const Duration _healthCacheDuration = Duration(hours: 2);

  final Map<String, ServerHealth> _cache = {};

  ServerHealth? getHealth(String serverId) {
    final cached = _cache[serverId];
    if (cached != null) {
      if (DateTime.now().difference(cached.lastUpdated) > _healthCacheDuration) {
        _cache.remove(serverId);
        return null;
      }
      return cached;
    }
    return null;
  }

  void recordSuccess(String serverId) {
    final health = _getOrCreateHealth(serverId);
    health.recordSuccess();
    _cache[serverId] = health;
    _persistHealth(serverId, health);
  }

  void recordFailure(String serverId) {
    final health = _getOrCreateHealth(serverId);
    health.recordFailure();
    _cache[serverId] = health;
    _persistHealth(serverId, health);
  }

  ServerHealth _getOrCreateHealth(String serverId) {
    return _cache[serverId] ?? ServerHealth(
      serverId: serverId,
      successCount: 0,
      failureCount: 0,
      lastUpdated: DateTime.now(),
    );
  }

  Future<void> _persistHealth(String serverId, ServerHealth health) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('$_prefPrefix${serverId}_success', health.successCount);
      await prefs.setInt('$_prefPrefix${serverId}_failure', health.failureCount);
      await prefs.setInt('$_lastUpdatedPrefix$serverId', health.lastUpdated.millisecondsSinceEpoch);
    } catch (_) {}
  }

  Future<ServerHealth?> loadHealth(String serverId) async {
    if (_cache.containsKey(serverId)) return _cache[serverId];
    try {
      final prefs = await SharedPreferences.getInstance();
      final success = prefs.getInt('$_prefPrefix${serverId}_success') ?? 0;
      final failure = prefs.getInt('$_prefPrefix${serverId}_failure') ?? 0;
      final timestamp = prefs.getInt('$_lastUpdatedPrefix$serverId') ?? 0;
      if (success == 0 && failure == 0) return null;
      final health = ServerHealth(
        serverId: serverId,
        successCount: success,
        failureCount: failure,
        lastUpdated: DateTime.fromMillisecondsSinceEpoch(timestamp),
      );
      _cache[serverId] = health;
      return health;
    } catch (_) {
      return null;
    }
  }

  bool isServerHealthy(String serverId) {
    final health = getHealth(serverId);
    if (health == null) return true;
    return health.isHealthy;
  }

  double getHealthScore(String serverId) {
    final health = getHealth(serverId);
    if (health == null) return 1.0;
    return health.successRate;
  }
}

class ServerHealth {
  final String serverId;
  int successCount;
  int failureCount;
  DateTime lastUpdated;

  ServerHealth({
    required this.serverId,
    required this.successCount,
    required this.failureCount,
    required this.lastUpdated,
  });

  void recordSuccess() {
    successCount++;
    lastUpdated = DateTime.now();
  }

  void recordFailure() {
    failureCount++;
    lastUpdated = DateTime.now();
  }

  double get successRate {
    final total = successCount + failureCount;
    if (total == 0) return 1.0;
    return successCount / total;
  }

  bool get isHealthy {
    final total = successCount + failureCount;
    if (total < 3) return true;
    return successRate >= 0.4;
  }

  String get statusLabel {
    if (successCount == 0 && failureCount == 0) return 'No data';
    if (isHealthy) return 'Working';
    return 'Unstable';
  }
}

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
  final Map<String, ServerHealth> _serverHealth = {};
  bool _showAllServers = false;
  bool _loadingHealth = true;

  final List<Map<String, dynamic>> _serversData = [
    {
        "id": "rive",
        "name": "Rive",
        "url": "https://rivestream.live",
        "movie_url_pattern": "{url}/watch?type=movie&id={tmdbId}",
        "tv_url_pattern": "{url}/watch?type=tv&id={tmdbId}&season={season}&episode={episode}",
        "movie_alias": null,
        "tv_alias": null,
        "scraper_timeout_seconds": 45
    },
    {
        "id": "vidlink",
        "name": "VidLink",
        "url": "https://vidlink.pro",
        "movie_url_pattern": "{url}/movie/{tmdbId}?autoplay=true",
        "tv_url_pattern": "{url}/tv/{tmdbId}/{season}/{episode}?autoplay=true",
        "movie_alias": null,
        "tv_alias": null,
        "scraper_timeout_seconds": 45
    },
    {
        "id": "vidsrc",
        "name": "VixSrc",
        "url": "https://vidsrc.sbs",
        "movie_url_pattern": "{url}/embed/movie/{tmdbId}?autoplay=true",
        "tv_url_pattern": "{url}/embed/tv/{tmdbId}/{season}/{episode}?autoplay=true",
        "movie_alias": null,
        "tv_alias": null,
        "scraper_timeout_seconds": 45
    },
    {
        "id": "cinejoy",
        "name": "MoviesJoy",
        "url": "https://moviesjoy.to",
        "movie_url_pattern": "{url}/watch/{type}/{tmdbId}",
        "tv_url_pattern": "{url}/watch/{type}/{tmdbId}/{season}/{episode}",
        "movie_alias": "movie",
        "tv_alias": "tv",
        "scraper_timeout_seconds": 30
    },
    {
        "id": "vidfast",
        "name": "VidFast",
        "url": "https://vidfast.vc",
        "movie_url_pattern": null,
        "tv_url_pattern": null,
        "movie_alias": null,
        "tv_alias": null,
        "scraper_timeout_seconds": 30
    },
    {
        "id": "cinesrc",
        "name": "CineSrc",
        "url": "https://cinesrc.st/embed",
        "movie_url_pattern": null,
        "tv_url_pattern": null,
        "movie_alias": null,
        "tv_alias": null,
        "scraper_timeout_seconds": 30
    },
    {
        "id": "cineplay",
        "name": "Fmovies",
        "url": "https://fmovies.co",
        "movie_url_pattern": "{url}/watch/{tmdbId}",
        "tv_url_pattern": "{url}/watch/{tmdbId}/{season}/{episode}",
        "movie_alias": null,
        "tv_alias": null,
        "scraper_timeout_seconds": 30
    },
    {
        "id": "screenscape",
        "name": "ScreenScape",
        "url": "https://screenscape.me",
        "movie_url_pattern": "{url}/embed?tmdb={tmdbId}&type=movie&autoplay=true",
        "tv_url_pattern": "{url}/embed?tmdb={tmdbId}&type=tv&s={season}&e={episode}&autoplay=true",
        "movie_alias": null,
        "tv_alias": null,
        "scraper_timeout_seconds": 45
    },
    {
        "id": "videasy",
        "name": "Videasy",
        "url": "https://player.videasy.to",
        "movie_url_pattern": "{url}/{type}/{tmdbId}",
        "tv_url_pattern": "{url}/{type}/{tmdbId}/{season}/{episode}",
        "movie_alias": null,
        "tv_alias": null,
        "scraper_timeout_seconds": 30
    },
    {
        "id": "2embed",
        "name": "2Embed",
        "url": "https://2embed.cc",
        "movie_url_pattern": "{url}/movie/{tmdbId}?autoplay=true",
        "tv_url_pattern": "{url}/tv/{tmdbId}/{season}/{episode}?autoplay=true",
        "movie_alias": null,
        "tv_alias": null,
        "scraper_timeout_seconds": 45
    },
    {
        "id": "embedsu",
        "name": "Embed.su",
        "url": "https://embed.su",
        "movie_url_pattern": "{url}/embed/movie/{tmdbId}?autoplay=true",
        "tv_url_pattern": "{url}/embed/tv/{tmdbId}/{season}/{episode}?autoplay=true",
        "movie_alias": null,
        "tv_alias": null,
        "scraper_timeout_seconds": 45
    }
];

  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: AppMotion.standard,
    );
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _fadeCtrl.forward();
    _loadServerHealth();

    // Scale animation duration to the device's refresh rate once the
    // inherited widgets (MediaQuery) are available — initState() runs
    // before that, so the call must happen after the first frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _rescaleAnimations();
    });
  }

  void _rescaleAnimations() {
    if (!mounted) return;
    _fadeCtrl.duration = AppMotion.scaled(context, AppMotion.standard);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _rescaleAnimations();
  }

  Future<void> _loadServerHealth() async {
    final tracker = ServerHealthTracker.instance;
    final healthMap = <String, ServerHealth>{};
    for (final server in _serversData) {
      final id = server['id'] as String? ?? '';
      final health = await tracker.loadHealth(id);
      if (health != null) {
        healthMap[id] = health;
      }
    }
    if (!mounted) return;
    setState(() {
      _serverHealth.clear();
      _serverHealth.addAll(healthMap);
      _loadingHealth = false;
      _selectFirstHealthyServer();
    });
  }

  void _selectFirstHealthyServer() {
    final availableServers = _getAvailableServers();
    if (availableServers.isEmpty) return;
    for (var i = 0; i < _serversData.length; i++) {
      final server = _serversData[i];
      final id = server['id'] as String? ?? '';
      if (availableServers.any((s) => s['id'] == id)) {
        setState(() => _selectedServerIndex = i);
        break;
      }
    }
  }

  List<Map<String, dynamic>> _getAvailableServers() {
    if (_showAllServers) return _serversData;
    return _serversData.where((server) {
      final id = server['id'] as String? ?? '';
      final health = _serverHealth[id];
      if (health == null) return true;
      return health.isHealthy;
    }).toList();
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

    if (pattern == null || pattern.isEmpty) {
      if (id == 'vidfast') {
        pattern = isMovie
            ? '{url}/movie/{tmdbId}?autoPlay=true'
            : '{url}/tv/{tmdbId}/{season}/{episode}?autoPlay=true';
      } else if (id == 'cinesrc' || id == 'embedsu') {
        pattern = isMovie
            ? '{url}/embed/movie/{tmdbId}?autoPlay=true'
            : '{url}/embed/tv/{tmdbId}/{season}/{episode}?autoPlay=true';
      } else if (id == '2embed') {
        pattern = isMovie
            ? '{url}/movie/{tmdbId}?autoPlay=true'
            : '{url}/tv/{tmdbId}/{season}/{episode}?autoPlay=true';
      } else if (id == 'videasy') {
        pattern = isMovie
            ? '{url}/movie/{tmdbId}?autoPlay=true'
            : '{url}/tv/{tmdbId}/{season}/{episode}?autoPlay=true';
      } else {
        pattern = isMovie
            ? '{url}/{type}/{tmdbId}?autoPlay=true'
            : '{url}/{type}/{tmdbId}/{season}/{episode}?autoPlay=true';
      }
    }

    var url = pattern
        .replaceAll('{url}', server['url'] ?? '')
        .replaceAll('{type}', isMovie ? 'movie' : 'tv')
        .replaceAll('{tmdbId}', widget.tmdbId)
        .replaceAll('{season}', widget.season.toString())
        .replaceAll('{episode}', widget.episode.toString());

    if (!url.toLowerCase().contains('autoplay=')) {
      url = '$url${url.contains('?') ? '&' : '?'}autoplay=true';
    }

    return url;
  }

  void _startStreaming() {
    HapticFeedback.mediumImpact();
    final server = _serversData[_selectedServerIndex];
    final embedUrl = _buildStreamUrl(server);
    final serverName = (server['name'] as String?) ?? 'Server ${_selectedServerIndex + 1}';
    final serverId = (server['id'] as String?) ?? '';

    ServerHealthTracker.instance.recordSuccess(serverId);

    Navigator.pop(context);

    Navigator.push(
      context,
      PageRouteBuilder(
        transitionDuration: AppMotion.scaled(context, AppMotion.fast),
        pageBuilder: (_, _, _) => CustomPlayerScreen(
          streamUrl: embedUrl,
          title: widget.movieTitle,
          tmdbId: widget.tmdbId,
          mediaType: widget.mediaType,
          season: widget.season,
          episode: widget.episode,
          wisoApiKey: '',
          servers: _serversData,
          initialServerName: serverName,
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
    final reduceGlass = AppMotion.shouldReduceTransparency(context);

    return FadeTransition(
      opacity: _fadeAnim,
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        child: BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: AppMotion.glassBlur(context, AppDesignTokens.glassBlurSheet),
            sigmaY: AppMotion.glassBlur(context, AppDesignTokens.glassBlurSheet),
          ),
          child: Container(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 12 + bottomPad),
            decoration: BoxDecoration(
              color: _bg.withValues(alpha: reduceGlass ? 0.98 : 0.92),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              border: Border.all(
                color: _gold.withValues(alpha: 0.15),
                width: 0.8,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Handle
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
                const SizedBox(height: 12),

                // Header
                Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: _gold.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: _gold.withValues(alpha: 0.4)),
                      ),
                      child: const Icon(
                        Icons.play_circle_fill_rounded,
                        color: _gold,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            'Select Server',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            widget.movieTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 11.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.08),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.close_rounded,
                          color: Colors.white70,
                          size: 14,
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 14),

                // Filter toggle
                if (!_loadingHealth && !_showAllServers) ...[
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Icon(
                          Icons.filter_list_rounded,
                          color: Colors.white54,
                          size: 14,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Showing ${_getAvailableServers().length} working servers',
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 11,
                          ),
                        ),
                        const Spacer(),
                        GestureDetector(
                          onTap: () {
                            HapticFeedback.selectionClick();
                            setState(() => _showAllServers = true);
                          },
                          child: Text(
                            'Show all',
                            style: TextStyle(
                              color: _gold,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ] else if (!_loadingHealth) ...[
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Icon(
                          Icons.warning_amber_rounded,
                          color: Colors.orange.shade400,
                          size: 14,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Showing all ${_serversData.length} servers',
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 11,
                          ),
                        ),
                        const Spacer(),
                        GestureDetector(
                          onTap: () {
                            HapticFeedback.selectionClick();
                            setState(() => _showAllServers = false);
                          },
                          child: Text(
                            'Hide unstable',
                            style: TextStyle(
                              color: _gold,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                // Server list
                Expanded(
                  child: ListView.builder(
                    itemCount: _showAllServers ? _serversData.length : _getAvailableServers().length,
                    itemBuilder: (context, index) {
                    final availableServers = _showAllServers ? _serversData : _getAvailableServers();
                    if (index >= availableServers.length) return const SizedBox.shrink();
                    final server = availableServers[index];
                    final originalIndex = _serversData.indexOf(server);
                    final isSelected = _selectedServerIndex == originalIndex;
                    final serverId = server['id'] as String? ?? '';
                    final health = _serverHealth[serverId];
                    final isHealthy = health?.isHealthy ?? true;

                    return GestureDetector(
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setState(() => _selectedServerIndex = originalIndex);
                      },
                      child: AnimatedContainer(                         duration: AppMotion.scaled(context, AppMotion.standard),

                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? _gold.withValues(alpha: 0.12)
                              : Colors.white.withValues(alpha: 0.03),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isSelected
                                ? _gold.withValues(alpha: 0.6)
                                : (!isHealthy && !_showAllServers
                                    ? Colors.red.withValues(alpha: 0.2)
                                    : Colors.white.withValues(alpha: 0.06)),
                            width: isSelected ? 1.2 : 0.8,
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? _gold.withValues(alpha: 0.2)
                                    : Colors.white.withValues(alpha: 0.05),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  Icon(
                                    Icons.dns_rounded,
                                    color: isSelected ? _gold : Colors.white38,
                                    size: 16,
                                  ),
                                  if (!_showAllServers && !isHealthy)
                                    Positioned(
                                      right: 0,
                                      top: 0,
                                      child: Container(
                                        width: 8,
                                        height: 8,
                                        decoration: BoxDecoration(
                                          color: Colors.red.shade400,
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: Color(0xFF1A1A1E),
                                            width: 1,
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Row(
                                    children: [
                                      Flexible(
                                        child: Text(
                                          server['name'] ?? 'Unknown Server',
                                          style: TextStyle(
                                            color: isSelected
                                                ? Colors.white
                                                : (!isHealthy
                                                    ? Colors.white54
                                                    : Colors.white70),
                                            fontWeight: FontWeight.w700,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ),
                                      if (!_showAllServers && !isHealthy) ...[
                                        const SizedBox(width: 6),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.red.withValues(alpha: 0.2),
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: const Text(
                                            'Unstable',
                                            style: TextStyle(
                                              color: Colors.red,
                                              fontSize: 9,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    health != null
                                        ? '${(health.successRate * 100).toStringAsFixed(0)}% success rate'
                                        : (server['subtitle'] ?? 'High Speed Node'),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: _showAllServers && !isHealthy
                                          ? Colors.orange.shade300
                                          : Colors.white38,
                                      fontSize: 10.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            AnimatedContainer(
                              duration: AppMotion.scaled(context, AppMotion.standard),
                              width: 20,
                              height: 20,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: isSelected ? _gold : Colors.transparent,
                                border: Border.all(
                                  color: isSelected
                                      ? _gold
                                      : Colors.white.withValues(alpha: 0.2),
                                  width: 1.8,
                                ),
                              ),
                              child: isSelected
                                  ? const Icon(
                                      Icons.check_rounded,
                                      size: 12,
                                      color: Colors.black,
                                    )
                                  : null,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),

                const SizedBox(height: 12),

                // Stream Now button
                SizedBox(
                  width: double.infinity,
                  child: GestureDetector(
                    onTap: _startStreaming,
                    child: AnimatedContainer(                               duration: AppMotion.scaled(context, AppMotion.standard),

                      height: 38,
                      decoration: BoxDecoration(
                        color: _gold,
                        borderRadius: BorderRadius.circular(19),
                        boxShadow: [
                          BoxShadow(
                            color: _gold.withValues(alpha: 0.3),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.play_arrow_rounded,
                            color: Colors.black,
                            size: 18,
                          ),
                          SizedBox(width: 6),
                          Text(
                            'Stream Now',
                            style: TextStyle(
                              color: Colors.black,
                              fontWeight: FontWeight.w800,
                              fontSize: 13,
                              letterSpacing: 0.3,
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
        ),
      ),
    );
  }
}
