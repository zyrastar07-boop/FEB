/// Model representing a single IPTV channel parsed from an M3U playlist.
class IptvChannel {
  final String id;
  final String name;
  final String streamUrl;
  final String? logoUrl;
  final String groupTitle;
  final String? language;
  final String? country;
  final String? tvgId;
  final bool isHealthy;
  final String quality; // e.g. "HD", "SD", "4K", "FHD"
  final DateTime? lastValidated;

  const IptvChannel({
    required this.id,
    required this.name,
    required this.streamUrl,
    this.logoUrl,
    this.groupTitle = 'Uncategorized',
    this.language,
    this.country,
    this.tvgId,
    this.isHealthy = true,
    this.quality = 'HD',
    this.lastValidated,
  });

  IptvChannel copyWith({
    String? id,
    String? name,
    String? streamUrl,
    String? logoUrl,
    String? groupTitle,
    String? language,
    String? country,
    String? tvgId,
    bool? isHealthy,
    String? quality,
    DateTime? lastValidated,
  }) {
    return IptvChannel(
      id: id ?? this.id,
      name: name ?? this.name,
      streamUrl: streamUrl ?? this.streamUrl,
      logoUrl: logoUrl ?? this.logoUrl,
      groupTitle: groupTitle ?? this.groupTitle,
      language: language ?? this.language,
      country: country ?? this.country,
      tvgId: tvgId ?? this.tvgId,
      isHealthy: isHealthy ?? this.isHealthy,
      quality: quality ?? this.quality,
      lastValidated: lastValidated ?? this.lastValidated,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'streamUrl': streamUrl,
        'logoUrl': logoUrl,
        'groupTitle': groupTitle,
        'language': language,
        'country': country,
        'tvgId': tvgId,
        'isHealthy': isHealthy,
        'quality': quality,
        'lastValidated': lastValidated?.toIso8601String(),
      };

  factory IptvChannel.fromJson(Map<String, dynamic> json) {
    return IptvChannel(
      id: json['id'] as String,
      name: json['name'] as String,
      streamUrl: json['streamUrl'] as String,
      logoUrl: json['logoUrl'] as String?,
      groupTitle: json['groupTitle'] as String? ?? 'Uncategorized',
      language: json['language'] as String?,
      country: json['country'] as String?,
      tvgId: json['tvgId'] as String?,
      isHealthy: json['isHealthy'] as bool? ?? true,
      quality: json['quality'] as String? ?? 'HD',
      lastValidated: json['lastValidated'] != null
          ? DateTime.tryParse(json['lastValidated'] as String)
          : null,
    );
  }

  /// Infer a simple quality badge from name or group.
  static String inferQuality(String name, String group) {
    final lower = '${name.toLowerCase()} ${group.toLowerCase()}';
    if (lower.contains('4k') || lower.contains('uhd')) return '4K';
    if (lower.contains('fhd') || lower.contains('1080')) return 'FHD';
    if (lower.contains('hd') || lower.contains('720')) return 'HD';
    if (lower.contains('sd') || lower.contains('480')) return 'SD';
    return 'HD';
  }

  /// Map raw group-title into one of the top-level categories used by the UI.
  static String mapToCategory(String groupTitle) {
    final g = groupTitle.toLowerCase();
    if (g.contains('sport') ||
        g.contains('football') ||
        g.contains('soccer') ||
        g.contains('nba') ||
        g.contains('nfl') ||
        g.contains('mlb') ||
        g.contains('f1') ||
        g.contains('tennis') ||
        g.contains('golf') ||
        g.contains('racing')) {
      return 'Sports';
    }
    if (g.contains('news') ||
        g.contains('cnn') ||
        g.contains('bbc') ||
        g.contains('al jazeera') ||
        g.contains('fox news') ||
        g.contains('sky news')) {
      return 'News';
    }
    if (g.contains('movie') ||
        g.contains('cinema') ||
        g.contains('film') ||
        g.contains('hbo') ||
        g.contains('cinemax') ||
        g.contains('starz')) {
      return 'Movies';
    }
    if (g.contains('kid') ||
        g.contains('cartoon') ||
        g.contains('disney') ||
        g.contains('nick') ||
        g.contains('pbs kids') ||
        g.contains('baby')) {
      return 'Kids';
    }
    if (g.contains('music') ||
        g.contains('mtv') ||
        g.contains('vh1') ||
        g.contains('radio')) {
      return 'Music';
    }
    if (g.contains('docu') ||
        g.contains('discovery') ||
        g.contains('national geographic') ||
        g.contains('history') ||
        g.contains('animal')) {
      return 'Documentary';
    }
    // Default entertainment / general
    return 'Entertainment';
  }
}