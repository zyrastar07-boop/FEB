import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/movie.dart';
import '../services/custom_lists_service.dart';
import '../services/font_service.dart';
import '../services/user_library_service.dart';
import '../widgets/movie_card.dart';
import 'detail_screen.dart';

const _gold = Color(0xFFD4AF37);
const _bg = Color(0xFF0A0A0A);

/// Detail screen for a system or custom list.
class ListDetailScreen extends StatefulWidget {
  final String title;
  final String description;
  final List<Movie> items;
  final bool isSystemList;
  final String? listId;

  const ListDetailScreen({
    super.key,
    required this.title,
    this.description = '',
    required this.items,
    this.isSystemList = false,
    this.listId,
  });

  @override
  State<ListDetailScreen> createState() => _ListDetailScreenState();
}

class _ListDetailScreenState extends State<ListDetailScreen> {
  late List<Movie> _items;

  @override
  void initState() {
    super.initState();
    _items = List<Movie>.from(widget.items);
  }

  void _openDetail(Movie movie) {
    HapticFeedback.lightImpact();
    Navigator.push(
      context,
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 320),
        pageBuilder: (_, _, _) => DetailScreen(
          movie: movie,
          isTv: movie.mediaType == 'tv',
        ),
        transitionsBuilder: (_, anim, _, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
    );
  }

  Future<void> _remove(Movie movie) async {
    HapticFeedback.mediumImpact();
    setState(() => _items.removeWhere((m) => m.id == movie.id));

    if (widget.isSystemList) {
      try {
        final svc = UserLibraryService.instance;
        if (widget.title == 'Watchlist') {
          // Common method names across app versions
          try {
            (svc as dynamic).removeFromWatchlist(movie.id);
          } catch (_) {
            try {
              (svc as dynamic).toggleWatchlist(movie);
            } catch (_) {}
          }
        } else if (widget.title == 'Finished') {
          try {
            (svc as dynamic).removeFromWatched(movie.id);
          } catch (_) {
            try {
              (svc as dynamic).toggleWatched(movie);
            } catch (_) {}
          }
        }
      } catch (_) {}
    } else if (widget.listId != null) {
      await CustomListsService.instance
          .removeMovie(widget.listId!, movie.id);
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Removed "${movie.title}"'),
        backgroundColor: const Color(0xFF1A1A1A),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Future<void> _deleteList() async {
    if (widget.isSystemList || widget.listId == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text('Delete list?', style: TextStyle(color: Colors.white)),
        content: Text(
          '“${widget.title}” will be removed permanently.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (ok == true && widget.listId != null) {
      await CustomListsService.instance.deleteList(widget.listId!);
      if (!mounted) return;
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          widget.title,
          style: FontService.instance.display(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          if (!widget.isSystemList)
            IconButton(
              onPressed: _deleteList,
              icon: const Icon(Icons.delete_outline_rounded,
                  color: Colors.white54),
            ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.description.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                widget.description,
                style: const TextStyle(color: Colors.white54, fontSize: 13),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Text(
              '${_items.length} title${_items.length == 1 ? '' : 's'}',
              style: const TextStyle(color: Colors.white38, fontSize: 12),
            ),
          ),
          Expanded(
            child: _items.isEmpty
                ? const Center(
                    child: Text(
                      'This list is empty',
                      style: TextStyle(color: Colors.white38),
                    ),
                  )
                : GridView.builder(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
                    physics: const BouncingScrollPhysics(),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      childAspectRatio: 0.62,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                    ),
                    itemCount: _items.length,
                    itemBuilder: (context, index) {
                      final movie = _items[index];
                      return Stack(
                        children: [
                          Positioned.fill(
                            child: MovieCard(
                              movie: movie,
                              isLarge: true,
                              onTap: () => _openDetail(movie),
                            ),
                          ),
                          Positioned(
                            top: 6,
                            right: 6,
                            child: Material(
                              color: Colors.black54,
                              shape: const CircleBorder(),
                              child: InkWell(
                                customBorder: const CircleBorder(),
                                onTap: () => _remove(movie),
                                child: const Padding(
                                  padding: EdgeInsets.all(6),
                                  child: Icon(Icons.close_rounded,
                                      size: 16, color: Colors.white70),
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}