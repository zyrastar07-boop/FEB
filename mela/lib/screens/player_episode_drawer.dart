import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/tmdb_details_service.dart';

const _gold = Color(0xFFD4AF37);

class PlayerEpisodeDrawer extends StatefulWidget {
  final String tmdbId;
  final int currentSeason;
  final int currentEpisode;
  final Function(int season, int episode) onEpisodeSelected;
  final VoidCallback onClose;

  const PlayerEpisodeDrawer({
    super.key,
    required this.tmdbId,
    required this.currentSeason,
    required this.currentEpisode,
    required this.onEpisodeSelected,
    required this.onClose,
  });

  @override
  State<PlayerEpisodeDrawer> createState() => _PlayerEpisodeDrawerState();
}

class _PlayerEpisodeDrawerState extends State<PlayerEpisodeDrawer> {
  final TmdbDetailsService _tmdbService = TmdbDetailsService();
  bool _isLoading = true;
  List<Map<String, dynamic>> _seasons = [];
  int _selectedSeasonNumber = 1;
  List<Map<String, dynamic>> _episodes = [];
  bool _isLoadingEpisodes = false;

  @override
  void initState() {
    super.initState();
    _selectedSeasonNumber = widget.currentSeason;
    _fetchTvDetails();
  }

  Future<void> _fetchTvDetails() async {
    setState(() => _isLoading = true);
    final tvId = int.tryParse(widget.tmdbId) ?? 0;
    if (tvId > 0) {
      final details = await _tmdbService.getMovieDetails(tvId, isTv: true);
      if (details != null && details['seasons'] != null) {
        final List rawSeasons = details['seasons'];
        _seasons = rawSeasons
            .map((s) => Map<String, dynamic>.from(s))
            .where((s) => (s['season_number'] ?? 0) > 0)
            .toList();
      }
    }
    setState(() {
      _isLoading = false;
    });
    if (_seasons.isNotEmpty) {
      if (!_seasons.any((s) => s['season_number'] == _selectedSeasonNumber)) {
        _selectedSeasonNumber = _seasons.first['season_number'] ?? 1;
      }
      _fetchEpisodes(_selectedSeasonNumber);
    }
  }

  Future<void> _fetchEpisodes(int seasonNumber) async {
    setState(() {
      _isLoadingEpisodes = true;
      _selectedSeasonNumber = seasonNumber;
    });
    final tvId = int.tryParse(widget.tmdbId) ?? 0;
    if (tvId > 0) {
      final eps = await _tmdbService.getSeasonEpisodes(tvId, seasonNumber);
      if (mounted) {
        setState(() {
          _episodes = eps;
          _isLoadingEpisodes = false;
        });
      }
    } else {
      if (mounted) setState(() => _isLoadingEpisodes = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  "Select Episode",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              GestureDetector(
                onTap: widget.onClose,
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: const BoxDecoration(
                    color: Color(0xFF1C1C1E),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.close, color: Colors.white, size: 16),
                ),
              ),
            ],
          ),
        ),
        if (_isLoading)
          const Expanded(
            child: Center(
              child: CircularProgressIndicator(color: _gold, strokeWidth: 2),
            ),
          )
        else ...[
          SizedBox(
            height: 50,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _seasons.length,
              itemBuilder: (context, index) {
                final season = _seasons[index];
                final seasonNum = season['season_number'] ?? (index + 1);
                final seasonName = season['name'] ?? 'Season $seasonNum';
                final isSelected = seasonNum == _selectedSeasonNumber;

                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      _fetchEpisodes(seasonNum);
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        color: isSelected ? _gold : const Color(0xFF1C1C1E),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Center(
                        child: Text(
                          seasonName,
                          style: TextStyle(
                            color: isSelected ? Colors.black : Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          const Divider(color: Colors.white12, height: 1),
          Expanded(
            child: _isLoadingEpisodes
                ? const Center(
                    child: CircularProgressIndicator(color: _gold, strokeWidth: 2),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _episodes.length,
                    itemBuilder: (context, index) {
                      final ep = _episodes[index];
                      final epNumber = ep['episode_number'] ?? (index + 1);
                      final epName = ep['name'] ?? 'Episode $epNumber';
                      final overview = ep['overview'] ?? '';
                      final stillPath = ep['still_path'];
                      final isSelected = _selectedSeasonNumber == widget.currentSeason &&
                          epNumber == widget.currentEpisode;

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: GestureDetector(
                          onTap: () {
                            HapticFeedback.selectionClick();
                            widget.onEpisodeSelected(_selectedSeasonNumber, epNumber);
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? const Color(0xFF332A15)
                                  : const Color(0xFF1C1C1E),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: isSelected ? _gold : Colors.transparent,
                                width: 1.5,
                              ),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: 70,
                                  height: 45,
                                  decoration: BoxDecoration(
                                    color: Colors.black26,
                                    borderRadius: BorderRadius.circular(8),
                                    image: stillPath != null
                                        ? DecorationImage(
                                            image: NetworkImage(
                                                'https://image.tmdb.org/t/p/w300$stillPath'),
                                            fit: BoxFit.cover,
                                          )
                                        : null,
                                  ),
                                  child: stillPath == null
                                      ? Center(
                                          child: Text(
                                            'E$epNumber',
                                            style: TextStyle(
                                              color: isSelected ? _gold : Colors.white70,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 12,
                                            ),
                                          ),
                                        )
                                      : null,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'E$epNumber. $epName',
                                        style: TextStyle(
                                          color: isSelected ? _gold : Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      if (overview.isNotEmpty) ...[
                                        const SizedBox(height: 4),
                                        Text(
                                          overview,
                                          style: const TextStyle(
                                            color: Colors.white54,
                                            fontSize: 11,
                                          ),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
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
                    },
                  ),
          ),
        ],
      ],
    );
  }
}