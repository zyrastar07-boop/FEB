class Server {
  final String id;
  final String name;
  final String url;
  final String? movieUrlPattern;
  final String? tvUrlPattern;
  final String? movieAlias;
  final String? tvAlias;

  /// Server-side scrape timeout in seconds. Used by the WebView scraper
  /// when probing the embed page. Null = caller falls back to default.
  final int? scraperTimeoutSeconds;

  Server({
    required this.id,
    required this.name,
    required this.url,
    this.movieUrlPattern,
    this.tvUrlPattern,
    this.movieAlias,
    this.tvAlias,
    this.scraperTimeoutSeconds,
  });

  factory Server.fromJson(Map<String, dynamic> json) {
    return Server(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      url: json['url'] ?? '',
      movieUrlPattern: json['movie_url_pattern'],
      tvUrlPattern: json['tv_url_pattern'],
      movieAlias: json['movie_alias'],
      tvAlias: json['tv_alias'],
      scraperTimeoutSeconds: json['scraper_timeout_seconds'] as int?,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'url': url,
        if (movieUrlPattern != null) 'movie_url_pattern': movieUrlPattern,
        if (tvUrlPattern != null) 'tv_url_pattern': tvUrlPattern,
        if (movieAlias != null) 'movie_alias': movieAlias,
        if (tvAlias != null) 'tv_alias': tvAlias,
        if (scraperTimeoutSeconds != null)
          'scraper_timeout_seconds': scraperTimeoutSeconds,
      };

  /// Builds the full streaming URL dynamically
  String buildStreamUrl({
    required String tmdbId,
    String type = 'movie', // 'movie' or 'tv'
    int season = 1,
    int episode = 1,
  }) {
    String? pattern = type == 'movie' ? movieUrlPattern : tvUrlPattern;

    // Fallback default patterns for servers with null pattern values
    if (pattern == null || pattern.isEmpty) {
      pattern = type == 'movie'
          ? '{url}/movie/{tmdbId}'
          : '{url}/tv/{tmdbId}/{season}/{episode}';
    }

    final mediaType = type == 'movie'
        ? (movieAlias ?? type)
        : (tvAlias ?? type);

    return pattern
        .replaceAll('{url}', url)
        .replaceAll('{type}', mediaType)
        .replaceAll('{tmdbId}', tmdbId)
        .replaceAll('{season}', season.toString())
        .replaceAll('{episode}', episode.toString());
  }

  /// Canonical server catalog. Mirrors `list.json` so the player, the
  /// server-selector sheet, and any future entry points share the same
  /// definitions (id, base url, movie/tv URL patterns, aliases,
  /// scrape timeout).
  ///
  /// Keep this list in sync with `/attachments/list.json` (also embedded
  /// in `docs/server_side_notes.md`). Any new server added there should
  /// be added here; any removed server should be removed here.
  static final List<Server> defaultServers = <Server>[
    Server(
      id: 'rive',
      name: 'Rive',
      url: 'https://www.rivestream.app',
      movieUrlPattern: '{url}/watch?type=movie&id={tmdbId}',
      tvUrlPattern:
          '{url}/watch?type=tv&id={tmdbId}&season={season}&episode={episode}',
      scraperTimeoutSeconds: 45,
    ),
    Server(
      id: 'vidlink',
      name: 'VidLink',
      url: 'https://vidlink.pro',
      movieUrlPattern: '{url}/movie/{tmdbId}?autoplay=true',
      tvUrlPattern:
          '{url}/tv/{tmdbId}/{season}/{episode}?autoplay=true',
      scraperTimeoutSeconds: 45,
    ),
    Server(
      id: 'vidsrc',
      name: 'VidSrc',
      url: 'https://vidsrc.sbs',
      movieUrlPattern: '{url}/embed/movie/{tmdbId}?autoplay=true',
      tvUrlPattern:
          '{url}/embed/tv/{tmdbId}/{season}/{episode}?autoplay=true',
      scraperTimeoutSeconds: 45,
    ),
    Server(
      id: 'cinejoy',
      name: 'CineJoy',
      url: 'https://cinejoy.to',
      movieUrlPattern: '{url}/watch/{type}/{tmdbId}',
      tvUrlPattern:
          '{url}/watch/{type}/{tmdbId}/{season}/{episode}',
      movieAlias: 'movie',
      tvAlias: 'tv',
      scraperTimeoutSeconds: 30,
    ),
    Server(
      id: 'vidfast',
      name: 'VidFast',
      url: 'https://vidfast.vc',
      // list.json ships with null patterns; keep the well-known embed
      // pattern as a fallback so buildStreamUrl still resolves.
      movieUrlPattern: '{url}/movie/{tmdbId}?autoplay=true',
      tvUrlPattern:
          '{url}/tv/{tmdbId}/{season}/{episode}?autoplay=true',
      scraperTimeoutSeconds: 30,
    ),
    Server(
      id: 'cinesrc',
      name: 'CineSrc',
      url: 'https://cinesrc.st/embed',
      movieUrlPattern: '{url}/embed/movie/{tmdbId}?autoplay=true',
      tvUrlPattern:
          '{url}/embed/tv/{tmdbId}/{season}/{episode}?autoplay=true',
      scraperTimeoutSeconds: 30,
    ),
    Server(
      id: 'cineplay',
      name: 'CinePlay',
      url: 'https://www.cineplay.to',
      movieUrlPattern: '{url}/{type}/{tmdbId}?play=true',
      tvUrlPattern:
          '{url}/{type}/{tmdbId}/{season}/{episode}?play=true',
      scraperTimeoutSeconds: 30,
    ),
    Server(
      id: 'screenscape',
      name: 'ScreenScape',
      url: 'https://screenscape.me',
      movieUrlPattern:
          '{url}/embed?tmdb={tmdbId}&type=movie&autoplay=true',
      tvUrlPattern:
          '{url}/embed?tmdb={tmdbId}&type=tv&s={season}&e={episode}&autoplay=true',
      scraperTimeoutSeconds: 45,
    ),
    Server(
      id: 'videasy',
      name: 'Videasy',
      url: 'https://player.videasy.to',
      movieUrlPattern: '{url}/{type}/{tmdbId}',
      tvUrlPattern:
          '{url}/{type}/{tmdbId}/{season}/{episode}',
      scraperTimeoutSeconds: 30,
    ),
  ];
}