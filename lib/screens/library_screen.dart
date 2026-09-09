import 'package:flutter/material.dart';

import 'package:flutter/services.dart';
import '../services/custom_lists_service.dart';
import '../services/font_service.dart';
import '../views/my_lists_tab_view.dart';
import '../widgets/new_list_modal.dart';
import '../widgets/floating_nav_bar.dart';
import 'search_screen.dart';
import 'profile_screen.dart';
import 'iptv_channel_list_screen.dart';

import '../design/tokens.dart';

const _gold = AppDesignTokens.gold;
const _bg = AppDesignTokens.backgroundCanvas;

/// Library / Collections hub screen.
class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
    bool _searchOpen = false;
  final TextEditingController _searchCtrl = TextEditingController();

  /// all | movie | tv
  String _mediaFilter = 'all';

  /// updated | name | progress | voted
  final String _sortMode = 'voted';

  @override
  void initState() {
    super.initState();
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('List created'),
        ),
      );
    }
  }

  /// 5-tab mapping (must match FloatingNavBar + HomeScreen):
  /// 0 Home · 1 Search · 2 Live · 3 Collection (this screen) · 4 Me
  void _onNavTapped(int index) {
    if (index == 3) return; // already on Collection
    HapticFeedback.selectionClick();
    if (index == 0) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    } else if (index == 1) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const SearchScreen()),
      );
    } else if (index == 2) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const IptvChannelListScreen()),
      );
    } else if (index == 4) {
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
                       // Lists + Search
                       Row(
                         mainAxisAlignment: MainAxisAlignment.spaceBetween,
                         children: [
                           _tabPill('Lists'),
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
                          // Explicitly zero out every border state — without
                          // this, the global input theme's gold underline
                          // bleeds through on focus, leaving a visible
                          // "white line" beneath the search field.
                          decoration: InputDecoration(
                             hintText: 'Search lists…',
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
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide.none,
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide.none,
                            ),
                            disabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide.none,
                            ),
                            errorBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide.none,
                            ),
                            focusedErrorBorder: OutlineInputBorder(
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
                  child: MyListsTabView(
                    searchQuery: _searchCtrl.text,
                    mediaFilter: _mediaFilter,
                    sortMode: _sortMode,
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
              currentIndex: 3, // Collection
              onTap: _onNavTapped,
            ),
          ),
        ],
      ),
    );
  }

   Widget _tabPill(String label) {
     return GestureDetector(
       onTap: () {
         HapticFeedback.selectionClick();
       },
       child: Container(
         padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
         decoration: BoxDecoration(
           color: _gold,
           borderRadius: BorderRadius.circular(20),
         ),
         child: Text(
           label,
           style: FontService.instance.label(
             color: AppDesignTokens.textOnGold,
             fontSize: 13,
             letterSpacing: 0.2,
             fontWeight: FontWeight.w700,
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
    await showModalBottomSheet<String>(
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
