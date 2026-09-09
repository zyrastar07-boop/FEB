import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/movie.dart';
import 'auth_service.dart';
import 'secure_prefs.dart';

/// Lightweight social watch-party model.
///
/// Creates a short party code that friends can join. Stores the shared title
/// + optional season/episode so everyone opens the same content.
/// Real-time playhead sync would need a backend; this coordinates *what*
/// to watch and gives a shareable invite.
class WatchParty {
  final String code;
  final String hostUid;
  final String hostName;
  final int tmdbId;
  final String title;
  final String mediaType; // movie | tv
  final int? season;
  final int? episode;
  final String? posterUrl;
  final DateTime createdAt;

  WatchParty({
    required this.code,
    required this.hostUid,
    required this.hostName,
    required this.tmdbId,
    required this.title,
    required this.mediaType,
    this.season,
    this.episode,
    this.posterUrl,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'code': code,
        'hostUid': hostUid,
        'hostName': hostName,
        'tmdbId': tmdbId,
        'title': title,
        'mediaType': mediaType,
        'season': season,
        'episode': episode,
        'posterUrl': posterUrl,
        'createdAt': createdAt.toIso8601String(),
      };

  static WatchParty fromJson(Map<String, dynamic> j) => WatchParty(
        code: (j['code'] ?? '').toString(),
        hostUid: (j['hostUid'] ?? '').toString(),
        hostName: (j['hostName'] ?? 'Host').toString(),
        tmdbId: (j['tmdbId'] as num?)?.toInt() ?? 0,
        title: (j['title'] ?? '').toString(),
        mediaType: (j['mediaType'] ?? 'movie').toString(),
        season: (j['season'] as num?)?.toInt(),
        episode: (j['episode'] as num?)?.toInt(),
        posterUrl: j['posterUrl']?.toString(),
        createdAt: DateTime.tryParse(j['createdAt']?.toString() ?? '') ??
            DateTime.now(),
      );

  String get inviteLine {
    if (mediaType == 'tv' && season != null && episode != null) {
      return 'Join my FEB watch party for "$title" '
          'S${season.toString().padLeft(2, '0')}E${episode.toString().padLeft(2, '0')} — code $code';
    }
    return 'Join my FEB watch party for "$title" — code $code';
  }
}

class WatchPartyService extends ChangeNotifier {
  static final WatchPartyService instance = WatchPartyService._();
  WatchPartyService._();

  static const _activeKey = 'watch_party_active_v1';
  static const _historyKey = 'watch_party_history_v1';

  WatchParty? _active;
  final List<WatchParty> _history = [];

  WatchParty? get active => _active;
  List<WatchParty> get history => List.unmodifiable(_history);

  Future<void> ensureLoaded() async {
    try {
      // Party payloads (codes + host UID) are sensitive — read encrypted,
      // falling back to legacy plaintext values written before encryption.
      final raw = await SecurePrefs.readString(_activeKey);
      if (raw != null) {
        _active = WatchParty.fromJson(
            Map<String, dynamic>.from(jsonDecode(raw) as Map));
      }
      final hist = await SecurePrefs.readString(_historyKey);
      if (hist != null) {
        final list = jsonDecode(hist) as List;
        _history
          ..clear()
          ..addAll(list
              .whereType<Map>()
              .map((e) => WatchParty.fromJson(Map<String, dynamic>.from(e))));
      }
    } catch (e) {
      debugPrint('WatchPartyService load: $e');
    }
    notifyListeners();
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_active != null) {
        await SecurePrefs.writeString(_activeKey, jsonEncode(_active!.toJson()));
      } else {
        await prefs.remove(_activeKey);
      }
      await SecurePrefs.writeString(
        _historyKey,
        jsonEncode(_history.take(20).map((e) => e.toJson()).toList()),
      );
    } catch (_) {}
  }

  String _genCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final r = Random.secure();
    return List.generate(6, (_) => chars[r.nextInt(chars.length)]).join();
  }

  /// Host creates a party for [movie].
  Future<WatchParty> createParty({
    required Movie movie,
    String mediaType = 'movie',
    int? season,
    int? episode,
  }) async {
    final user = AuthService().currentUser;
    final party = WatchParty(
      code: _genCode(),
      hostUid: user?.uid ?? 'guest',
      hostName: user?.displayName ??
          (user?.isAnonymous == true ? 'Guest' : 'Host'),
      tmdbId: movie.id,
      title: movie.title,
      mediaType: mediaType,
      season: season,
      episode: episode,
      posterUrl: movie.posterUrl,
    );
    _active = party;
    _history.insert(0, party);
    await _persist();
    notifyListeners();
    return party;
  }

  /// Join by code (local device stores the invite; friends type the same code
  /// after you share it — for multi-device sync plug a backend later).
  Future<WatchParty?> joinByCode(String code) async {
    final normalized = code.trim().toUpperCase();
    if (normalized.length < 4) return null;

    // Match history / active first
    if (_active?.code == normalized) return _active;
    for (final h in _history) {
      if (h.code == normalized) {
        _active = h;
        await _persist();
        notifyListeners();
        return h;
      }
    }

    // Placeholder: without a shared backend we can't fetch remote parties.
    // Return null so UI can show "ask host to share the title + code again".
    return null;
  }

  Future<void> leaveParty() async {
    _active = null;
    await _persist();
    notifyListeners();
  }

  String streamUrlFor(WatchParty p) {
    if (p.mediaType == 'tv' && p.season != null && p.episode != null) {
      return 'https://vidfast.vc/tv/${p.tmdbId}/${p.season}/${p.episode}?autoPlay=true';
    }
    return 'https://vidfast.vc/movie/${p.tmdbId}?autoPlay=true';
  }
}