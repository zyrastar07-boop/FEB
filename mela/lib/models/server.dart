class Server {
  final String id;
  final String name;
  final String url;
  final String? movieUrlPattern;
  final String? tvUrlPattern;
  final String? movieAlias;
  final String? tvAlias;

  Server({
    required this.id,
    required this.name,
    required this.url,
    this.movieUrlPattern,
    this.tvUrlPattern,
    this.movieAlias,
    this.tvAlias,
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
    );
  }

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

  // Built-in list of available streaming servers
  static List<Server> defaultServers = [
    Server(
      id: "vidfast",
      name: "VidFast",
      url: "https://vidfast.vc",
    ),
    Server(
      id: "cinesrc",
      name: "CineSrc",
      url: "https://cinesrc.st/embed",
    ),
    Server(
      id: "cineplay",
      name: "CinePlay",
      url: "https://www.cineplay.to",
      movieUrlPattern: "{url}/{type}/{tmdbId}?play=true",
      tvUrlPattern: "{url}/{type}/{tmdbId}/{season}/{episode}?play=true",
    ),
    Server(
      id: "videasy",
      name: "Videasy",
      url: "https://player.videasy.to",
      movieUrlPattern: "{url}/{type}/{tmdbId}",
      tvUrlPattern: "{url}/{type}/{tmdbId}/{season}/{episode}",
    ),
  ];
}