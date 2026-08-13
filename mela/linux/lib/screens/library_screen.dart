import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/movie.dart';
import '../services/font_service.dart';
import '../services/download_service.dart';
import '../widgets/liquid_glass.dart';
import '../widgets/movie_card.dart';
import 'detail_screen.dart';

const _gold = Color(0xFFD4AF37);
const _bg = Color(0xFF0A0A0A);

enum _DownloadSort { recent, nameAZ }

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  int _selectedTab = 0;

  String _searchQuery = '';
  _DownloadSort _sortMode = _DownloadSort.recent;

  List<Movie> _watchlist = [];
  List<Movie> _finished = [];
  bool _loadingWatchlist = true;
  bool _loadingFinished = true;

  final double _totalGb = 128;

  @override
  void initState() {
    super.initState();
    _loadWatchlist();
    _loadFinished();
  }

  Future<void> _loadWatchlist() async {
    setState(() => _loadingWatchlist = true);
    try {
      final box = Hive.isBoxOpen('watchlist')
          ? Hive.box<Movie>('watchlist')
          : await Hive.openBox<Movie>('watchlist');
      if (!mounted) return;
      setState(() {
        _watchlist = box.values.toList().reversed.toList();
        _loadingWatchlist = false;
      });
    } catch (e) {
      if (mounted) setState(() => _loadingWatchlist = false);
    }
  }

  Future<void> _loadFinished() async {
    setState(() => _loadingFinished = true);
    try {
      final box = Hive.isBoxOpen('watched')
          ? Hive.box<Movie>('watched')
          : await Hive.openBox<Movie>('watched');
      if (!mounted) return;
      setState(() {
        _finished = box.values.toList().reversed.toList();
        _loadingFinished = false;
      });
    } catch (e) {
      if (mounted) setState(() => _loadingFinished = false);
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: const Color(0xFF1A1A1A),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _openDetail(Movie movie) {
    HapticFeedback.lightImpact();
    Navigator.push(
      context,
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 380),
        pageBuilder: (_, _, _) => DetailScreen(movie: movie),
        transitionsBuilder: (_, animation, _, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    ).then((_) {
      _loadWatchlist();
      _loadFinished();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Library",
                    style: FontService.instance
                        .display(color: Colors.white, fontSize: 28),
                  ),
                  const SizedBox(height: 16),
                  _buildStorageTile(),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      ListenableBuilder(
                        listenable: DownloadService.instance,
                        builder: (context, _) {
                          final count = DownloadService.instance.items.length;
                          return _buildTabPill(0, "Downloads ($count)");
                        },
                      ),
                      const SizedBox(width: 8),
                      _buildTabPill(1, "Watchlist"),
                      const SizedBox(width: 8),
                      _buildTabPill(2, "Finished"),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
            Expanded(
              child: IndexedStack(
                index: _selectedTab,
                children: [
                  _buildDownloadsTab(),
                  _buildWatchlistTab(),
                  _buildFinishedTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStorageTile() {
    return ListenableBuilder(
      listenable: DownloadService.instance,
      builder: (context, _) {
        final items = DownloadService.instance.items;
        final totalBytes = items.fold<int>(0, (sum, item) {
          final p = item.progress > 0 ? item.progress : 0.0;
          return sum + (p * 1024 * 1024 * 1024).toInt();
        });
        final usedGb = (totalBytes / (1024 * 1024 * 1024)).clamp(0.0, _totalGb);
        final fraction = (usedGb / _totalGb).clamp(0.0, 1.0);

        return LiquidGlassContainer(
          borderRadius: 24,
          padding: const EdgeInsets.all(16),
          backgroundColor: Colors.white.withValues(alpha: 0.04),
          borderColor: _gold.withValues(alpha: 0.3),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      "Device Storage",
                      style: FontService.instance.display(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.bold),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () => _toast('Cache cleared'),
                    child: Text(
                      "Clear cache",
                      style: FontService.instance.label(
                          color: _gold, fontSize: 11, letterSpacing: 0.4),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: SizedBox(
                      width: MediaQuery.of(context).size.width * 0.55,
                      child: LinearProgressIndicator(
                        value: fraction,
                        minHeight: 6,
                        backgroundColor: Colors.white12,
                        valueColor: const AlwaysStoppedAnimation<Color>(_gold),
                      ),
                    ),
                  ),
                  Text(
                    "${usedGb.toStringAsFixed(1)} GB / ${_totalGb.toStringAsFixed(0)} GB",
                    style: FontService.instance
                        .label(color: _gold, fontSize: 11, letterSpacing: 0.3),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTabPill(int index, String label) {
    final bool isSelected = _selectedTab == index;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          setState(() => _selectedTab = index);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? _gold : Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Center(
            child: Text(
              label,
              style: FontService.instance.label(
                color: isSelected ? Colors.black : Colors.white70,
                fontSize: 11.5,
                letterSpacing: 0.3,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDownloadsTab() {
    return ListenableBuilder(
      listenable: DownloadService.instance,
      builder: (context, _) {
        final items = DownloadService.instance.items;

        var filtered = items.where((i) {
          if (_searchQuery.isEmpty) return true;
          return i.title.toLowerCase().contains(_searchQuery.toLowerCase());
        }).toList();

        if (_sortMode == _DownloadSort.nameAZ) {
          filtered.sort((a, b) => a.title.compareTo(b.title));
        }

        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
          physics: const BouncingScrollPhysics(),
          children: [
            if (items.isNotEmpty) ...[
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      onChanged: (v) => setState(() => _searchQuery = v),
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      decoration: InputDecoration(
                        hintText: 'Search downloads',
                        hintStyle: const TextStyle(color: Colors.white38),
                        prefixIcon: const Icon(Icons.search_rounded,
                            color: Colors.white38, size: 20),
                        filled: true,
                        fillColor: Colors.white.withValues(alpha: 0.06),
                        contentPadding:
                            const EdgeInsets.symmetric(vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  PopupMenuButton<_DownloadSort>(
                    color: const Color(0xFF1A1A1A),
                    icon: const Icon(Icons.sort_rounded, color: Colors.white70),
                    onSelected: (v) => setState(() => _sortMode = v),
                    itemBuilder: (context) => const [
                      PopupMenuItem(
                        value: _DownloadSort.recent,
                        child: Text('Recently added',
                            style: TextStyle(color: Colors.white)),
                      ),
                      PopupMenuItem(
                        value: _DownloadSort.nameAZ,
                        child: Text('Name A–Z',
                            style: TextStyle(color: Colors.white)),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],
            if (items.isEmpty)
              _buildEmptyState(
                icon: Icons.download_outlined,
                message: "No downloads yet",
                subtitle:
                    "Tap the download icon on any title to save it offline.",
              )
            else if (filtered.isEmpty)
              _buildEmptyState(
                icon: Icons.search_off_rounded,
                message: "No matches",
                subtitle: "Try a different search term.",
              )
            else ...[
              ...filtered.map(_buildDownloadTile),
              const SizedBox(height: 8),
              Center(
                child: TextButton.icon(
                  onPressed: () => DownloadService.instance.clearAll(),
                  icon: const Icon(Icons.delete_outline_rounded,
                      color: Colors.redAccent, size: 18),
                  label: const Text('Clear all downloads',
                      style: TextStyle(color: Colors.redAccent)),
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _buildDownloadTile(DownloadItem item) {
    final isComplete = item.status == DownloadStatus.completed;
    final isPaused = item.status == DownloadStatus.paused;

    return Dismissible(
      key: ValueKey(item.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Colors.redAccent.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Icon(Icons.delete_rounded, color: Colors.redAccent),
      ),
      onDismissed: (_) => DownloadService.instance.clearAll(),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        child: LiquidGlassContainer(
          borderRadius: 20,
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: item.posterUrl.isNotEmpty
                    ? Image.network(item.posterUrl,
                        width: 70, height: 90, fit: BoxFit.cover)
                    : Container(
                        width: 70,
                        height: 90,
                        color: Colors.grey[900],
                        child: const Icon(Icons.movie_rounded,
                            color: Colors.white24),
                      ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      style: FontService.instance.display(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${item.quality} · ${item.codec} · ${item.sizeLabel}',
                      style: FontService.instance.label(
                          color: Colors.white54,
                          fontSize: 10.5,
                          letterSpacing: 0.2),
                    ),
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: item.progress > 0 ? item.progress : null,
                        minHeight: 4,
                        backgroundColor: Colors.white10,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          isPaused ? Colors.white38 : _gold,
                        ),
                      ),
                    ),
                    if (!isComplete) ...[
                      const SizedBox(height: 4),
                      Text(
                        isPaused
                            ? 'Paused · ${(item.progress > 0 ? item.progress * 100 : 0).round()}%'
                            : (item.progress > 0
                                ? 'Downloading · ${(item.progress * 100).round()}%'
                                : 'Connecting...'),
                        style: FontService.instance.label(
                            color: Colors.white38,
                            fontSize: 9.5,
                            letterSpacing: 0.2),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 6),
              IconButton(
                icon: Icon(
                  isComplete
                      ? Icons.play_circle_fill_rounded
                      : (isPaused
                          ? Icons.play_circle_outline_rounded
                          : Icons.pause_circle_outline_rounded),
                  color: _gold,
                  size: 36,
                ),
                onPressed: () {
                  if (isComplete) {
                    _toast('Playing "${item.title}" offline');
                  } else {
                    if (isPaused) {
                      DownloadService.instance.resumeDownload(item.id);
                    } else {
                      DownloadService.instance.pauseDownload(item.id);
                    }
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWatchlistTab() {
    if (_loadingWatchlist) {
      return const Center(
          child: CircularProgressIndicator(color: _gold, strokeWidth: 2.5));
    }
    if (_watchlist.isEmpty) {
      return _buildEmptyState(
        icon: Icons.bookmark_border_rounded,
        message: "Your watchlist is empty",
        subtitle: "Tap the bookmark icon on any movie to save it here.",
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 14,
        crossAxisSpacing: 14,
        childAspectRatio: 0.62,
      ),
      itemCount: _watchlist.length,
      itemBuilder: (context, index) {
        final movie = _watchlist[index];
        return GestureDetector(
          onTap: () => _openDetail(movie),
          child: MovieCard(movie: movie, isLarge: true),
        );
      },
    );
  }

  Widget _buildFinishedTab() {
    if (_loadingFinished) {
      return const Center(
          child: CircularProgressIndicator(color: _gold, strokeWidth: 2.5));
    }
    if (_finished.isEmpty) {
      return _buildEmptyState(
        icon: Icons.check_circle_outline_rounded,
        message: "Nothing finished yet",
        subtitle: "Titles you mark as watched will show up here.",
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 14,
        crossAxisSpacing: 14,
        childAspectRatio: 0.62,
      ),
      itemCount: _finished.length,
      itemBuilder: (context, index) {
        final movie = _finished[index];
        return GestureDetector(
          onTap: () => _openDetail(movie),
          child: MovieCard(movie: movie, isLarge: true),
        );
      },
    );
  }

  Widget _buildEmptyState({
    required IconData icon,
    required String message,
    String? subtitle,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 60, horizontal: 24),
      child: Center(
        child: Column(
          children: [
            Icon(icon, color: Colors.white24, size: 40),
            const SizedBox(height: 14),
            Text(
              message,
              style: FontService.instance.display(
                  color: Colors.white54,
                  fontSize: 15,
                  fontWeight: FontWeight.w700),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 6),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Colors.white30, fontSize: 12.5, height: 1.4),
              ),
            ],
          ],
        ),
      ),
    );
  }
}