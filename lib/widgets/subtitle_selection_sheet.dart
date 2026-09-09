import 'package:flutter/material.dart';
import '../design/motion.dart';
import 'package:flutter/services.dart';
import '../services/wyzie_subtitle_service.dart';
import '../services/opensubtitles_service.dart';
import '../services/font_service.dart';

import '../design/tokens.dart';

const _gold = AppDesignTokens.gold;
const _bg = AppDesignTokens.backgroundCanvas;

/// Result returned when the user confirms subtitle choice for a download.
///
/// [fuseSubtitles] is kept for API compatibility with enqueue callers.
/// Burn-in is disabled — the download service always writes a sidecar .srt.
/// [localSubtitlePath] is set when the subtitle was already fetched to disk
/// during this session (OpenSubtitles), so the download service skips the
/// URL fetch entirely.
class SubtitleSelectionResult {
  final WyzieSubtitleTrack? subtitle;
  final bool fuseSubtitles;
  final String? localSubtitlePath;

  const SubtitleSelectionResult({
    this.subtitle,
    this.fuseSubtitles = false,
    this.localSubtitlePath,
  });
}

class SubtitleSelectionSheet extends StatefulWidget {
  final String tmdbId;
  final String? imdbId;
  final String mediaType;
  final int season;
  final int episode;

  const SubtitleSelectionSheet({
    super.key,
    required this.tmdbId,
    this.imdbId,
    this.mediaType = 'movie',
    this.season = 1,
    this.episode = 1,
  });

  static Future<SubtitleSelectionResult?> show(
    BuildContext context, {
    required String tmdbId,
    String? imdbId,
    String mediaType = 'movie',
    int season = 1,
    int episode = 1,
  }) {
    return showModalBottomSheet<SubtitleSelectionResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => SubtitleSelectionSheet(
        tmdbId: tmdbId,
        imdbId: imdbId,
        mediaType: mediaType,
        season: season,
        episode: episode,
      ),
    );
  }

  @override
  State<SubtitleSelectionSheet> createState() => _SubtitleSelectionSheetState();
}

class _SubtitleSelectionSheetState extends State<SubtitleSelectionSheet> {
  bool _loading = true;
  String? _error;
  List<WyzieSubtitleTrack> _subtitles = [];
  WyzieSubtitleTrack? _selected;
  bool _noneSelected = true;
  int _retryCount = 0;
  // OpenSubtitles results are downloaded at confirm-time, so they are kept
  // separately keyed by track id (unlike wyzie, whose URL is fetched later
  // by the download service).
  final Map<String, OpenSubtitlesResult> _openSubResults = {};

  final WyzieSubtitleService _wyzie = WyzieSubtitleService();
  final OpenSubtitlesService _openSubs = OpenSubtitlesService();

  static const _preferredLangs = ['en', 'es', 'fr', 'de', 'ar', 'am'];

  static const _langLabels = {
    'en': 'English',
    'es': 'Spanish',
    'fr': 'French',
    'de': 'German',
    'ar': 'Arabic',
    'am': 'Amharic',
  };

  @override
  void initState() {
    super.initState();
    _fetchSubtitles();
  }

  @override
  void dispose() {
    _wyzie.dispose();
    super.dispose();
  }

  Future<void> _fetchSubtitles() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final tmdb = widget.tmdbId.trim();
      final hasImdb =
          widget.imdbId != null && widget.imdbId!.trim().isNotEmpty;
      if ((tmdb.isEmpty || tmdb == '0') && !hasImdb) {
        setState(() {
          _loading = false;
          _error = 'No valid TMDB/IMDb ID for subtitles.';
          _subtitles = [];
        });
        return;
      }

      final isTv = widget.mediaType.toLowerCase() == 'tv';
      final results = await _wyzie.search(
        tmdbId: tmdb.isNotEmpty && tmdb != '0' ? tmdb : null,
        imdbId: hasImdb ? widget.imdbId : null,
        season: isTv ? widget.season : null,
        episode: isTv ? widget.episode : null,
      );

      // Second provider: OpenSubtitles.com (best-quality human-synced subs).
      // Search works without a key; downloads need one (Settings → Subtitles).
      // Failures here never break the wyzie results — just additive supply.
      if (hasImdb) {
        try {
          final osResults = await _openSubs.searchByImdbId(
            imdbId: widget.imdbId!,
            languageCode: 'en',
            season: isTv ? widget.season : null,
            episode: isTv ? widget.episode : null,
          );
          for (final r in osResults.take(4)) {
            _openSubResults[r.track.id] = r;
          }
        } catch (e) {
          debugPrint('OpenSubtitles search skipped: $e');
        }
      }

      final byLang = <String, WyzieSubtitleTrack>{};
      final extras = <WyzieSubtitleTrack>[];

      for (final s in results) {
        final iso = s.languageCode.length == 2
            ? s.languageCode.toLowerCase()
            : WyzieSubtitleService.toIsoLanguage(s.displayLanguage)
                .toLowerCase();
        if (_preferredLangs.contains(iso) && !byLang.containsKey(iso)) {
          byLang[iso] = s;
        } else if (!_preferredLangs.contains(iso)) {
          extras.add(s);
        }
      }

      final ordered = <WyzieSubtitleTrack>[];
      for (final code in _preferredLangs) {
        if (byLang.containsKey(code)) ordered.add(byLang[code]!);
      }
      ordered.addAll(extras.take(12));
      // OpenSubtitles hits are appended after wyzie's so the familiar
      // ordering is untouched; duplicate language entries are acceptable
      // because each is labelled with its source.
      ordered.addAll(_openSubResults.values.map((r) => r.track));

      if (!mounted) return;
      setState(() {
        _subtitles = ordered;
        _loading = false;
        _retryCount = 0;
        // Surface API / rate-limit problems instead of a blank "none found".
        if (ordered.isEmpty &&
            _wyzie.lastError != null &&
            _wyzie.lastError!.isNotEmpty) {
          _error = _wyzie.lastError;
        } else {
          _error = null;
        }
        if (ordered.isNotEmpty) {
          final eng = ordered.cast<WyzieSubtitleTrack?>().firstWhere(
                (s) =>
                    s!.languageCode.toLowerCase() == 'en' ||
                    s.displayLanguage.toLowerCase().contains('english'),
                orElse: () => null,
              );
          if (eng != null) {
            _selected = eng;
            _noneSelected = false;
          }
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error =
            'Could not load subtitles from Wyzie. You can still download without them.';
        _subtitles = [];
      });
    }
  }

  String _labelFor(WyzieSubtitleTrack s) {
    final code = s.languageCode.toLowerCase().trim();
    final name = _langLabels[code] ??
        (s.displayLanguage.isNotEmpty ? s.displayLanguage : s.languageCode);
    final fmt = (s.format.isNotEmpty ? s.format : 'srt').toLowerCase();
    return '$name ($fmt)';
  }

  /// OpenSubtitles tracks carry no direct URL — the file must be fetched
  /// through the /download endpoint now, while we still have the context.
  /// Returns the local path, or null when the download failed / was skipped.
  Future<String?> _resolveOpenSubtitlesPath(WyzieSubtitleTrack track) async {
    final result = _openSubResults[track.id];
    if (result == null) return null;
    try {
      return await _openSubs.downloadSubtitle(result);
    } catch (e) {
      if (!mounted) return null;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'OpenSubtitles download failed: ${e.toString().replaceFirst("OpenSubtitlesException: ", "")}',
            style: const TextStyle(color: Colors.white),
          ),
          backgroundColor: const Color(0xFF332A15),
        ),
      );
      return null;
    }
  }

  Future<void> _confirm() async {
    HapticFeedback.selectionClick();
    final track = _noneSelected ? null : _selected;
    String? localPath;
    if (track != null && track.source == 'OpenSubtitles') {
      localPath = await _resolveOpenSubtitlesPath(track);
      if (localPath == null) return; // download failed — stay in the sheet
    }
    if (!mounted) return;
    Navigator.of(context).pop(
      SubtitleSelectionResult(
        subtitle: track,
        fuseSubtitles: false,
        localSubtitlePath: localPath,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;
    final height = MediaQuery.of(context).size.height * 0.55;

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: _bg.withValues(alpha: 0.98),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Select Subtitle Language',
                          style: FontService.instance.display(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Saved as a sidecar file next to the video',
                          style: FontService.instance.label(
                            color: Colors.white54,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded, color: Colors.white70),
                  ),
                ],
              ),
            ),
            const Divider(color: Colors.white10, height: 1),
            Expanded(child: _buildBody()),
            Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, bottom + 16),
              child: SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _gold,
                    foregroundColor: Colors.black,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                  ),
                  onPressed: _confirm,
                  child: Text(
                    _noneSelected
                        ? 'Continue without subtitles'
                        : 'Confirm · ${_labelFor(_selected!)}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 14.5,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 32,
              height: 32,
              child: CircularProgressIndicator(color: _gold, strokeWidth: 2.5),
            ),
            SizedBox(height: 12),
            Text(
              'Fetching subtitles from Wyzie...',
              style: TextStyle(color: Colors.white54, fontSize: 13),
            ),
          ],
        ),
      );
    }

    if (_error != null && _subtitles.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.subtitles_off_rounded,
                  color: Colors.white38, size: 28),
              const SizedBox(height: 10),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white54, fontSize: 13),
              ),
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: () {
                  _retryCount++;
                  _fetchSubtitles();
                },
                icon: const Icon(Icons.refresh_rounded, color: _gold, size: 18),
                label: Text(
                  _retryCount > 0 ? 'Retry again' : 'Retry',
                  style: const TextStyle(color: _gold),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
      children: [
        _optionTile(
          title: 'None / No Subtitles',
          subtitle: 'Download video only',
          selected: _noneSelected,
          onTap: () {
            HapticFeedback.selectionClick();
            setState(() {
              _noneSelected = true;
              _selected = null;
            });
          },
        ),
        if (_subtitles.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.only(top: 8, bottom: 6, left: 4),
            child: Text(
              'AVAILABLE LANGUAGES',
              style: TextStyle(
                color: Colors.white38,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          ..._subtitles.map((s) {
            final selected = !_noneSelected && identical(_selected, s);
            final isOs = s.source == 'OpenSubtitles';
            final osResult = isOs ? _openSubResults[s.id] : null;
            final needsKey = isOs && !_openSubs.isDownloadAvailable;
            final osMeta = isOs
                ? (needsKey
                    ? 'OpenSubtitles · API key required'
                    : 'OpenSubtitles${osResult?.rating != null ? ' · ★${osResult!.rating!.toStringAsFixed(1)}' : ''}')
                : null;
            return _optionTile(
              title: _labelFor(s),
              subtitle: osMeta ??
                  (s.displayLanguage.isNotEmpty
                      ? s.displayLanguage
                      : s.languageCode),
              selected: selected,
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() {
                  _noneSelected = false;
                  _selected = s;
                });
              },
            );
          }),
        ] else if (_error == null)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Center(
              child: Text(
                'No subtitles found for this title.',
                style: TextStyle(color: Colors.white38, fontSize: 13),
              ),
            ),
          ),
      ],
    );
  }

  Widget _optionTile({
    required String title,
    String? subtitle,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: AppMotion.scaled(context, AppMotion.standard),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: selected
                ? const Color(0xFF332A15)
                : Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color:
                  selected ? _gold.withValues(alpha: 0.55) : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: Row(
            children: [
              Icon(
                selected
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_off_rounded,
                color: selected ? _gold : Colors.white38,
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: selected ? _gold : Colors.white,
                        fontWeight:
                            selected ? FontWeight.bold : FontWeight.w500,
                        fontSize: 14,
                      ),
                    ),
                    if (subtitle != null && subtitle.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(
                          color: selected
                              ? _gold.withValues(alpha: 0.7)
                              : Colors.white38,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
