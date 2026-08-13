import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/custom_lists_service.dart';
import '../services/download_service.dart';
import '../services/font_service.dart';
import '../views/downloads_tab_view.dart';
import '../views/my_lists_tab_view.dart';
import '../widgets/new_list_modal.dart';
import '../widgets/floating_nav_bar.dart';
import 'search_screen.dart';
import 'profile_screen.dart';

const _gold = Color(0xFFFFB800);
const _bg = Color(0xFF0A0A0A);

/// Library / Collections hub screen.
class LibraryScreen extends StatefulWidget {
  /// 0 = Lists, 1 = Downloads
  final int initialTab;

  const LibraryScreen({super.key, this.initialTab = 0});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  late int _selectedTab;
  bool _searchOpen = false;
  final TextEditingController _searchCtrl = TextEditingController();

  /// all | movie | tv
  String _mediaFilter = 'all';

  /// updated | name | progress | voted
  final String _sortMode = 'voted';

  @override
  void initState() {
    super.initState();
    _selectedTab = widget.initialTab.clamp(0, 1);
    CustomListsService.instance.hydrate();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _openNewList() async {
    HapticFeedback.lightImpact();
    final created = await NewListModal.show(context);
    if (created == true && mounted) {
      setState(() => _selectedTab = 0);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('List created'),
          backgroundColor: const Color(0xFF1A1A1A),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
    }
  }

  void _onNavTapped(int index) {
    if (index == 2) return;
    HapticFeedback.selectionClick();
    if (index == 0) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    } else if (index == 1) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const SearchScreen()),
      );
    } else if (index == 3) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const ProfileScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          SafeArea(
            bottom: false, // Let content flow behind the bottom bar area
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Top Row: [Lists | Downloads] Capsule + Search Button
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(24),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _tabPill(0, 'Lists'),
                                ListenableBuilder(
                                  listenable: DownloadService.instance,
                                  builder: (_, _) {
                                    final n = DownloadService
                                        .instance.items.length;
                                    return _tabPill(
                                      1,
                                      n > 0 ? 'Downloads ($n)' : 'Downloads',
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),
                          GestureDetector(
                            onTap: () {
                              HapticFeedback.selectionClick();
                              setState(() {
                                _searchOpen = !_searchOpen;
                                if (!_searchOpen) _searchCtrl.clear();
                              });
                            },
                            child: Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.08),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                _searchOpen
                                    ? Icons.close_rounded
                                    : Icons.search_rounded,
                                color: Colors.white70,
                                size: 20,
                              ),
                            ),
                          ),
                        ],
                      ),

                      if (_searchOpen) ...[
                        const SizedBox(height: 10),
                        TextField(
                          controller: _searchCtrl,
                          autofocus: true,
                          onChanged: (_) => setState(() {}),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                          ),
                          decoration: InputDecoration(
                            hintText: _selectedTab == 0
                                ? 'Search lists…'
                                : 'Search downloads…',
                            hintStyle: const TextStyle(color: Colors.white38),
                            prefixIcon: const Icon(
                              Icons.search_rounded,
                              color: Colors.white38,
                              size: 20,
                            ),
                            filled: true,
                            fillColor: Colors.white.withValues(alpha: 0.06),
                            contentPadding: const EdgeInsets.symmetric(
                              vertical: 10,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                      ],

                      const SizedBox(height: 12),

                      // Row 2: Filter Dropdowns (Movies, Top voted) + Plus Button
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              _filterChip(
                                label: _mediaLabel(),
                                onTap: _pickMediaFilter,
                              ),
                              const SizedBox(width: 8),
                              _filterChip(
                                label: _sortLabel(),
                                onTap: _pickSort,
                              ),
                            ],
                          ),
                          GestureDetector(
                            onTap: _openNewList,
                            child: Container(
                              width: 40,
                              height: 40,
                              decoration: const BoxDecoration(
                                color: _gold,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.add_rounded,
                                color: Colors.black,
                                size: 22,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
                Expanded(
                  child: IndexedStack(
                    index: _selectedTab,
                    children: [
                      MyListsTabView(
                        searchQuery: _searchCtrl.text,
                        mediaFilter: _mediaFilter,
                        sortMode: _sortMode,
                      ),
                      const DownloadsTabView(),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: FloatingNavBar(
              currentIndex: 2,
              onTap: _onNavTapped,
            ),
          ),
        ],
      ),
    );
  }

  Widget _tabPill(int index, String label) {
    final selected = _selectedTab == index;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() => _selectedTab = index);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? _gold : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: FontService.instance.label(
            color: selected ? Colors.black : Colors.white70,
            fontSize: 13,
            letterSpacing: 0.2,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _filterChip({
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: FontService.instance.label(
                color: Colors.white70,
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(width: 4),
            const Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 16,
              color: Colors.white54,
            ),
          ],
        ),
      ),
    );
  }

  String _mediaLabel() {
    switch (_mediaFilter) {
      case 'movie':
        return 'Movies';
      case 'tv':
        return 'TV Series';
      default:
        return 'Movies';
    }
  }

  String _sortLabel() {
    switch (_sortMode) {
      case 'name':
        return 'Name (A-Z)';
      case 'progress':
        return 'Progress %';
      case 'voted':
        return 'Top voted';
      default:
        return 'Top voted';
    }
  }

  Future<void> _pickMediaFilter() async {
    final v = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _sheetTile('Movies', 'movie'),
            _sheetTile('TV Series', 'tv'),
            _sheetTile('All', 'all'),
          ],
        ),
      ),
    );
    if (v != null) setState(() => _mediaFilter = v);
  }

  Future<void> _pickSort() async {
    final v = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _sheetTile('Top voted', 'voted'),
            _sheetTile('Recently Updated', 'updated'),
            _sheetTile('Name (A-Z)', 'name'),
            _sheetTile('Progress %', 'progress'),
          ],
        ),
      ),
    );
  }

  Widget _sheetTile(String label, String value) {
    final selected = (_mediaFilter == value) || (_sortMode == value);
    return ListTile(
      title: Text(label, style: const TextStyle(color: Colors.white)),
      trailing: selected
          ? const Icon(Icons.check_rounded, color: _gold, size: 20)
          : null,
      onTap: () => Navigator.pop(context, value),
    );
  }
}