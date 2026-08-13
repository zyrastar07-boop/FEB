import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/iptv_channel_model.dart';
import '../services/iptv_parser_service.dart';
import '../services/iptv_validator_service.dart';
import '../widgets/category_filter_bar.dart';
import '../widgets/telegram_channel_tile.dart';
import 'iptv_player_screen.dart';

/// Main IPTV Live TV screen – Telegram-style channel browser.
class IptvChannelListScreen extends StatefulWidget {
  const IptvChannelListScreen({super.key});

  @override
  State<IptvChannelListScreen> createState() => _IptvChannelListScreenState();
}

class _IptvChannelListScreenState extends State<IptvChannelListScreen> {
  final IptvParserService _parser = IptvParserService();
  final IptvValidatorService _validator = IptvValidatorService();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  List<IptvChannel> _allChannels = [];
  List<IptvChannel> _visibleChannels = [];
  String _selectedCategory = 'All';
  String _searchQuery = '';
  bool _isLoading = true;
  bool _isValidating = false;
  double _validationProgress = 0;
  String? _error;
  String? _currentlyPlayingId;

  @override
  void initState() {
    super.initState();
    _loadChannels();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  Future<void> _loadChannels() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final parsed = await _parser.fetchAndParse();

      // Optional: limit initial load for very large playlists to keep UX snappy
      // Final production apps can remove the take() or make it configurable.
      final limited = parsed.take(1200).toList();

      setState(() {
        _allChannels = limited;
        _isLoading = false;
        _isValidating = true;
      });

      // Validate in background and progressively update UI
      final healthy = await _validator.validateChannels(
        limited,
        filter: true,
        onProgress: (checked, total) {
          if (mounted) {
            setState(() {
              _validationProgress = checked / total;
            });
          }
        },
      );

      if (!mounted) return;

      setState(() {
        _allChannels = healthy;
        _isValidating = false;
        _applyFilters();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _isValidating = false;
        _error = e.toString();
      });
    }
  }

  void _onSearchChanged() {
    _searchQuery = _searchController.text.trim().toLowerCase();
    _applyFilters();
  }

  void _applyFilters() {
    var list = _allChannels;

    if (_selectedCategory != 'All') {
      list = list
          .where((c) => c.groupTitle == _selectedCategory)
          .toList(growable: false);
    }

    if (_searchQuery.isNotEmpty) {
      list = list
          .where((c) =>
              c.name.toLowerCase().contains(_searchQuery) ||
              c.groupTitle.toLowerCase().contains(_searchQuery) ||
              (c.country?.toLowerCase().contains(_searchQuery) ?? false))
          .toList(growable: false);
    }

    setState(() => _visibleChannels = list);
  }

  void _onCategorySelected(String cat) {
    HapticFeedback.selectionClick();
    setState(() {
      _selectedCategory = cat;
      _applyFilters();
    });
  }

  void _openPlayer(IptvChannel channel) {
    HapticFeedback.lightImpact();
    setState(() => _currentlyPlayingId = channel.id);

    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (_, _, _) => IptvPlayerScreen(
          channel: channel,
          allChannels: _visibleChannels.isNotEmpty
              ? _visibleChannels
              : _allChannels,
          onChannelChanged: (newCh) {
            setState(() => _currentlyPlayingId = newCh.id);
          },
        ),
        transitionsBuilder: (_, animation, _, child) {
          return FadeTransition(
            opacity: animation,
            child: child,
          );
        },
        transitionDuration: const Duration(milliseconds: 280),
      ),
    ).then((_) {
      // Optional: clear playing indicator when returning
      // setState(() => _currentlyPlayingId = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(),
            const SizedBox(height: 10),
            CategoryFilterBar(
              selectedCategory: _selectedCategory,
              onCategorySelected: _onCategorySelected,
            ),
            if (_isValidating) _buildValidationBanner(),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Live TV',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.5,
                ),
              ),
              const Spacer(),
              if (!_isLoading)
                Text(
                  '${_visibleChannels.length} channels',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.45),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          // Search field – glass style
          Container(
            height: 44,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.08),
              ),
            ),
            child: TextField(
              controller: _searchController,
              focusNode: _searchFocus,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15.5,
              ),
              cursorColor: const Color(0xFFFFB800),
              decoration: InputDecoration(
                hintText: 'Search channels, sports, news...',
                hintStyle: TextStyle(
                  color: Colors.white.withValues(alpha: 0.35),
                  fontSize: 15,
                ),
                prefixIcon: Icon(
                  Icons.search_rounded,
                  color: Colors.white.withValues(alpha: 0.45),
                  size: 22,
                ),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: Icon(
                          Icons.close_rounded,
                          color: Colors.white.withValues(alpha: 0.45),
                          size: 20,
                        ),
                        onPressed: () {
                          _searchController.clear();
                          _searchFocus.unfocus();
                        },
                      )
                    : null,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildValidationBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: const Color(0xFF1A1A1A),
      child: Row(
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              value: _validationProgress > 0 ? _validationProgress : null,
              color: const Color(0xFFFFB800),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Checking stream health… ${(_validationProgress * 100).toStringAsFixed(0)}%',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.65),
                fontSize: 12.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 36,
              height: 36,
              child: CircularProgressIndicator(
                strokeWidth: 2.8,
                color: Color(0xFFFFB800),
              ),
            ),
            SizedBox(height: 16),
            Text(
              'Loading playlist…',
              style: TextStyle(
                color: Colors.white54,
                fontSize: 14.5,
              ),
            ),
          ],
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.wifi_off_rounded,
                size: 48,
                color: Colors.white.withValues(alpha: 0.3),
              ),
              const SizedBox(height: 16),
              Text(
                'Failed to load channels',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.85),
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.45),
                  fontSize: 13.5,
                ),
              ),
              const SizedBox(height: 20),
              TextButton.icon(
                onPressed: _loadChannels,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Retry'),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFFFFB800),
                  backgroundColor:
                      const Color(0xFFFFB800).withValues(alpha: 0.12),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_visibleChannels.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.live_tv_outlined,
              size: 48,
              color: Colors.white.withValues(alpha: 0.25),
            ),
            const SizedBox(height: 14),
            Text(
              _searchQuery.isNotEmpty
                  ? 'No channels match your search'
                  : 'No healthy channels found',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.55),
                fontSize: 15,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.only(top: 6, bottom: 100),
      itemCount: _visibleChannels.length,
      itemBuilder: (context, index) {
        final channel = _visibleChannels[index];
        return TelegramChannelTile(
          channel: channel,
          isPlaying: channel.id == _currentlyPlayingId,
          onTap: () => _openPlayer(channel),
        );
      },
    );
  }
}