import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/movie.dart';
import '../services/download_service.dart';
import '../services/font_service.dart';

const _gold = Color(0xFFFFB800);

class DownloadOption {
  final String id;
  final String fileName;
  final String quality;
  final String codec;
  final String source;
  final String sizeLabel;
  final String durationLabel;
  final bool isBest;
  final String language;
  final String? streamUrl;
  final bool hasSubtitles;

  const DownloadOption({
    required this.id,
    required this.fileName,
    required this.quality,
    required this.codec,
    required this.source,
    required this.sizeLabel,
    required this.durationLabel,
    this.isBest = false,
    this.language = 'EN',
    this.streamUrl,
    this.hasSubtitles = true,
  });
}

class AvailableDownloadsSheet extends StatefulWidget {
  final String movieTitle;
  final String tmdbId;
  final String posterUrl;
  final String mediaType; // 'movie' or 'tv'
  final int season;
  final int episode;
  final List<DownloadOption>? options;

  const AvailableDownloadsSheet({
    super.key,
    required this.movieTitle,
    required this.tmdbId,
    this.posterUrl = '',
    this.mediaType = 'movie',
    this.season = 1,
    this.episode = 1,
    this.options,
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
      ),
    );
  }

  @override
  State<AvailableDownloadsSheet> createState() =>
      _AvailableDownloadsSheetState();
}

class _AvailableDownloadsSheetState extends State<AvailableDownloadsSheet> {
  final List<DownloadOption> _allOptions = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadVidFastProfiles();
  }

  Future<void> _loadVidFastProfiles() async {
    setState(() => _isLoading = true);

    final baseUrl = widget.mediaType == 'tv'
        ? 'https://vidfast.vc/tv/${widget.tmdbId}/${widget.season}/${widget.episode}'
        : 'https://vidfast.vc/movie/${widget.tmdbId}';

    final cleanedTitle = widget.movieTitle.replaceAll(RegExp(r'\(\d{4}\)'), '').trim();

    await Future.delayed(const Duration(milliseconds: 300));

    if (!mounted) return;

    setState(() {
      _allOptions.addAll([
        DownloadOption(
          id: 'vidfast_1080p_${widget.tmdbId}',
          fileName: '${cleanedTitle.replaceAll(' ', '.')}.1080p.WEB-DL.VidFast.mp4',
          quality: '1080p',
          codec: 'x264',
          source: 'VidFast Pro (1080p)',
          sizeLabel: '2.1 GB',
          durationLabel: 'Full Feature',
          isBest: true,
          language: 'EN',
          streamUrl: baseUrl,
          hasSubtitles: true,
        ),
        DownloadOption(
          id: 'vidfast_720p_${widget.tmdbId}',
          fileName: '${cleanedTitle.replaceAll(' ', '.')}.720p.WEB-DL.VidFast.mp4',
          quality: '720p',
          codec: 'x264',
          source: 'VidFast Pro (720p)',
          sizeLabel: '1.2 GB',
          durationLabel: 'Full Feature',
          isBest: false,
          language: 'EN',
          streamUrl: baseUrl,
          hasSubtitles: true,
        ),
        DownloadOption(
          id: 'vidfast_480p_${widget.tmdbId}',
          fileName: '${cleanedTitle.replaceAll(' ', '.')}.480p.WEB-DL.VidFast.mp4',
          quality: '480p',
          codec: 'x264',
          source: 'VidFast Pro (480p)',
          sizeLabel: '650 MB',
          durationLabel: 'Full Feature',
          isBest: false,
          language: 'EN',
          streamUrl: baseUrl,
          hasSubtitles: true,
        ),
      ]);
      _isLoading = false;
    });
  }

  void _onTapDownload(DownloadOption option) {
    HapticFeedback.mediumImpact();
    
    // Construct a dummy movie object to pass into the updated DownloadService
    final movie = Movie(
      id: int.tryParse(widget.tmdbId) ?? 0,
      title: widget.movieTitle,
      posterPath: widget.posterUrl,
      overview: '',
      voteAverage: 0.0,
      releaseDate: '',
    );

    DownloadService.instance.enqueueDownload(
      movie: movie,
      videoUrl: option.streamUrl ?? '',
      quality: option.quality,
      codec: option.codec,
      sizeLabel: option.sizeLabel,
    );

    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Queued download: ${option.quality} (${option.sizeLabel})',
          style: FontService.instance.label(color: Colors.white, fontSize: 13),
        ),
        backgroundColor: const Color(0xFF222222),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    final sheetHeight = MediaQuery.of(context).size.height * 0.70;

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20.0, sigmaY: 20.0),
        child: Container(
          height: sheetHeight,
          decoration: BoxDecoration(
            color: const Color(0xFF121212).withValues(alpha: 0.95),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 10),
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 14, 12, 10),
                child: Row(
                  children: [
                    if (widget.posterUrl.isNotEmpty)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(
                          widget.posterUrl,
                          width: 42,
                          height: 58,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => Container(
                            width: 42,
                            height: 58,
                            color: Colors.grey[850],
                            child: const Icon(Icons.movie, color: Colors.white24, size: 18),
                          ),
                        ),
                      ),
                    if (widget.posterUrl.isNotEmpty) const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Download Options',
                            style: FontService.instance.display(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            widget.movieTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: FontService.instance.label(
                              color: Colors.white54,
                              fontSize: 12.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded, color: Colors.white70, size: 22),
                    ),
                  ],
                ),
              ),
              const Divider(color: Colors.white10),
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator(color: _gold))
                    : ListView.builder(
                        padding: EdgeInsets.fromLTRB(18, 10, 18, bottomPadding + 20),
                        itemCount: _allOptions.length,
                        itemBuilder: (context, index) {
                          final file = _allOptions[index];
                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.04),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: file.isBest
                                    ? _gold.withValues(alpha: 0.3)
                                    : Colors.white.withValues(alpha: 0.06),
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.cloud_download_outlined,
                                  color: file.isBest ? _gold : Colors.white38,
                                  size: 24,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        file.source,
                                        style: FontService.instance.display(
                                          color: Colors.white,
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Row(
                                        children: [
                                          _tag(file.quality, isGold: file.isBest),
                                          const SizedBox(width: 6),
                                          _tag(file.sizeLabel),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                GestureDetector(
                                  onTap: () => _onTapDownload(file),
                                  child: Container(
                                    width: 42,
                                    height: 42,
                                    decoration: BoxDecoration(
                                      color: _gold,
                                      shape: BoxShape.circle,
                                      boxShadow: [
                                        BoxShadow(
                                          color: _gold.withValues(alpha: 0.3),
                                          blurRadius: 8,
                                          offset: const Offset(0, 3),
                                        ),
                                      ],
                                    ),
                                    child: const Icon(
                                      Icons.arrow_downward_rounded,
                                      color: Colors.black,
                                      size: 20,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tag(String text, {bool isGold = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: isGold ? _gold.withValues(alpha: 0.18) : Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text(
        text,
        style: FontService.instance.label(
          color: isGold ? _gold : Colors.white70,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}