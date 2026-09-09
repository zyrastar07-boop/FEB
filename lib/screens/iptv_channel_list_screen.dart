import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/iptv_channel_model.dart';
import '../services/iptv_parser_service.dart';
import '../services/iptv_validator_service.dart';
import '../widgets/category_filter_bar.dart';
import '../widgets/telegram_channel_tile.dart';
import '../widgets/app_button.dart';
import '../design/tokens.dart';
import '../design/motion.dart';
import '../utils/adaptive.dart';
import 'iptv_player_screen.dart';

/// Live TV browser — staggered entrance, glass search, favorites, health checking.
/// Parse → validate → filter → play logic preserved.
class IptvChannelListScreen extends StatefulWidget {
  const IptvChannelListScreen({super.key});

  @override
  State<IptvChannelListScreen> createState() => _IptvChannelListScreenState();
}

class _IptvChannelListScreenState extends State<IptvChannelListScreen>
    with TickerProviderStateMixin {
  final IptvParserService _parser = IptvParserService();
  final IptvValidatorService _validator = IptvValidatorService();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  List<IptvChannel> _allChannels = [];
  List<IptvChannel> _visibleChannels = [];
  final Set<String> _deadUrls = {};
  String _selectedCategory = 'All';
  String _searchQuery = '';
  bool _isLoading = true;
  bool _isValidating = false;
  double _validationProgress = 0;
  String? _error;
  String? _currentlyPlayingId;

  final Set<String> _favoriteIds = {};
  bool _showFavoritesOnly = false;

  bool _searchFocused = false;
  Map<String, int> _categoryCounts = const {'All': 0};

  late final AnimationController _shimmerCtrl;
  late final AnimationController _entranceCtrl;
  late final AnimationController _listFadeCtrl;
  bool _listFadePlayed = false;

  @override
  void initState() {
    super.initState();
    _shimmerCtrl = AnimationController(
      vsync: this,
      duration: AppMotion.slow,
    )..repeat(reverse: true);
    _entranceCtrl = AnimationController(vsync: this, duration: AppMotion.slow);
    _listFadeCtrl = AnimationController(
      vsync: this,
      duration: AppMotion.medium,
      value: 1,
    );
    _entranceCtrl.forward();
    _loadChannels();
    _searchController.addListener(_onSearchChanged);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _rescale();
    });
  }

  void _rescale() {
    if (!mounted) return;
    _shimmerCtrl.duration = AppMotion.scaled(context, AppMotion.slow);
    _entranceCtrl.duration = AppMotion.scaled(context, AppMotion.slow);
    _listFadeCtrl.duration = AppMotion.scaled(context, AppMotion.medium);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _rescale();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.removeListener(_onSearchFocusChanged);
    _searchFocus.dispose();
    _shimmerCtrl.dispose();
    _entranceCtrl.dispose();
    _listFadeCtrl.dispose();
    super.dispose();
  }

  void _onSearchFocusChanged() {
    if (_searchFocused != _searchFocus.hasFocus) {
      setState(() => _searchFocused = _searchFocus.hasFocus);
    }
  }

  void _playListFade() {
    if (!_listFadePlayed && mounted) {
      _listFadePlayed = true;
      _listFadeCtrl.value = 0;
      _listFadeCtrl.forward();
    }
  }

  Future<void> _loadChannels() async {
    setState(() {
      _isLoading = true;
      _error = null;
      _deadUrls.clear();
    });

    try {
      final parsed = await _parser.fetchAndParse();
      final limited = parsed.take(1200).toList();

      // Show the channels immediately — health checking runs in the
      // background and prunes dead streams incrementally.
      setState(() {
        _allChannels = limited;
        _isLoading = false;
        _isValidating = true;
      });
      _applyFilters();
      _playListFade();

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
        onBatchChecked: (batch, flags) {
          if (!mounted) return;
          for (var i = 0; i < batch.length; i++) {
            if (!flags[i]) _deadUrls.add(batch[i].streamUrl);
          }
          setState(() {
            _allChannels = _allChannels
                .where((c) => !_deadUrls.contains(c.streamUrl))
                .toList(growable: false);
          });
          _applyFilters();
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
      _playListFade();
    }
  }

  void _onSearchChanged() {
    _searchQuery = _searchController.text.trim().toLowerCase();
    _applyFilters();
  }

  void _applyFilters() {
    _categoryCounts = _computeCategoryCounts(_allChannels);

    var list = _allChannels;

    if (_showFavoritesOnly) {
      list = list
          .where((c) => _favoriteIds.contains(c.id))
          .toList(growable: false);
    }

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

  Map<String, int> _computeCategoryCounts(List<IptvChannel> channels) {
    final counts = <String, int>{'All': channels.length};
    for (final channel in channels) {
      counts.update(channel.groupTitle, (v) => v + 1, ifAbsent: () => 1);
    }
    return counts;
  }

  void _onCategorySelected(String cat) {
    HapticFeedback.selectionClick();
    setState(() {
      _selectedCategory = cat;
      _applyFilters();
    });
  }

  void _toggleFavorite(IptvChannel channel) {
    HapticFeedback.selectionClick();
    setState(() {
      if (_favoriteIds.contains(channel.id)) {
        _favoriteIds.remove(channel.id);
      } else {
        _favoriteIds.add(channel.id);
      }
      if (_showFavoritesOnly) _applyFilters();
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
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: AppMotion.medium,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final padding = Adaptive.pagePadding(context);

    return Scaffold(
      backgroundColor: AppDesignTokens.bg,
      body: SafeArea(
        child: Column(
          children: [
            _FadeSlide(
              animation: _entranceCtrl,
              interval: const Interval(0.0, 0.45),
              offset: 10,
              child: _buildTopBar(padding),
            ),
            const SizedBox(height: 10),
            _FadeSlide(
              animation: _entranceCtrl,
              interval: const Interval(0.25, 0.7),
              offset: 8,
              child: CategoryFilterBar(
                selectedCategory: _selectedCategory,
                onCategorySelected: _onCategorySelected,
                counts: _categoryCounts,
              ),
            ),
            if (_isValidating)
              _FadeSlide(
                animation: _entranceCtrl,
                interval: const Interval(0.4, 0.85),
                offset: 8,
                child: _buildValidationBanner(),
              ),
            Expanded(
              child: FadeTransition(
                opacity: _listFadeCtrl,
                child: FocusTraversalGroup(
                  policy: OrderedTraversalPolicy(),
                  child: RefreshIndicator(
                    color: AppDesignTokens.gold,
                    backgroundColor: AppDesignTokens.card,
                    onRefresh: _loadChannels,
                    child: _buildBody(),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar(EdgeInsets padding) {
    return Container(
      padding: EdgeInsets.fromLTRB(padding.left, 12, padding.right, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const _LiveDot(),
              const SizedBox(width: 9),
              Text(
                'Live TV',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: Adaptive.of(context) == ScreenType.mobile ? 26 : 30,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.5,
                ),
              ),
              const Spacer(),
              AppButton(
                variant: AppButtonVariant.ghost,
                onPressed: () {
                  HapticFeedback.selectionClick();
                  setState(() {
                    _showFavoritesOnly = !_showFavoritesOnly;
                    _applyFilters();
                  });
                },
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                borderRadius: AppDesignTokens.radiusFull,
                semanticLabel: 'Toggle favorites',
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _showFavoritesOnly
                          ? Icons.star_rounded
                          : Icons.star_outline_rounded,
                      color:
                          _showFavoritesOnly ? AppDesignTokens.gold : Colors.white54,
                      size: 16,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _favoriteIds.isEmpty
                          ? 'Favs'
                          : 'Favs (${_favoriteIds.length})',
                      style: TextStyle(
                        color: _showFavoritesOnly
                            ? AppDesignTokens.gold
                            : Colors.white70,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (!_isLoading) _buildCountChip(),
            ],
          ),
          const SizedBox(height: 14),
          AnimatedContainer(
            duration: AppMotion.scaled(context, AppMotion.fast),
            curve: AppMotion.easeOut,
            height: 46,
            decoration: BoxDecoration(
              color: _searchFocused
                  ? Colors.white.withValues(alpha: 0.09)
                  : Colors.white.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: _searchFocused
                    ? AppDesignTokens.gold.withValues(alpha: 0.55)
                    : Colors.white.withValues(alpha: 0.09),
              ),
              boxShadow: _searchFocused
                  ? [
                      BoxShadow(
                        color: AppDesignTokens.gold.withValues(alpha: 0.10),
                        blurRadius: 18,
                        spreadRadius: -4,
                      ),
                    ]
                  : null,
            ),
            child: TextField(
              controller: _searchController,
              focusNode: _searchFocus,
              style: const TextStyle(color: Colors.white, fontSize: 15.5),
              cursorColor: AppDesignTokens.gold,
              decoration: InputDecoration(
                hintText: 'Search channels, sports, news…',
                hintStyle: TextStyle(
                  color: Colors.white.withValues(alpha: 0.35),
                  fontSize: 15,
                ),
                prefixIcon: Icon(
                  Icons.search_rounded,
                  color: _searchFocused
                      ? AppDesignTokens.gold.withValues(alpha: 0.7)
                      : Colors.white.withValues(alpha: 0.45),
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

  Widget _buildCountChip() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: AppDesignTokens.radiusFull,
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.tv_rounded,
            size: 13,
            color: Colors.white.withValues(alpha: 0.45),
          ),
          const SizedBox(width: 5),
          Text(
            '${_visibleChannels.length}',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.65),
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildValidationBanner() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppDesignTokens.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppDesignTokens.gold.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              value: _validationProgress > 0 ? _validationProgress : null,
              color: AppDesignTokens.gold,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Checking stream health… ${(_validationProgress * 100).toStringAsFixed(0)}%',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 12.5,
              ),
            ),
          ),
          const Icon(Icons.health_and_safety_outlined, color: AppDesignTokens.gold, size: 18),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) return _buildSkeletonList();

    if (_error != null) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(height: MediaQuery.of(context).size.height * 0.22),
          Center(
            child: Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: Icon(
                Icons.wifi_off_rounded,
                size: 32,
                color: Colors.white.withValues(alpha: 0.4),
              ),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Failed to load channels',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              'Please check your internet connection and try again.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.45),
                fontSize: 13.5,
              ),
            ),
          ),
          const SizedBox(height: 28),
          Center(
            child: AppButton(
              variant: AppButtonVariant.primary,
              size: AppButtonSize.medium,
              onPressed: () {
                HapticFeedback.mediumImpact();
                _loadChannels();
              },
              leadingIcon: const Icon(Icons.refresh_rounded, size: 20),
              semanticLabel: 'Retry',
              child: const Text('Retry'),
            ),
          ),
        ],
      );
    }

    if (_visibleChannels.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(height: MediaQuery.of(context).size.height * 0.2),
          Icon(
            _showFavoritesOnly
                ? Icons.star_border_rounded
                : Icons.live_tv_outlined,
            size: 48,
            color: Colors.white.withValues(alpha: 0.25),
          ),
          const SizedBox(height: 14),
          Text(
            _showFavoritesOnly
                ? 'No favorite channels yet'
                : (_searchQuery.isNotEmpty
                    ? 'No channels match your search'
                    : 'No healthy channels found'),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.55),
              fontSize: 15,
            ),
          ),
        ],
      );
    }

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      padding: const EdgeInsets.only(top: 6, bottom: 100),
      itemCount: _visibleChannels.length,
      itemBuilder: (context, index) {
        final channel = _visibleChannels[index];
        final fav = _favoriteIds.contains(channel.id);
        return TelegramChannelTile(
          channel: channel,
          isPlaying: channel.id == _currentlyPlayingId,
          isFavorite: fav,
          onTap: () => _openPlayer(channel),
          onFavoriteTap: () => _toggleFavorite(channel),
        );
      },
    );
  }

  Widget _buildSkeletonList() {
    return AnimatedBuilder(
      animation: _shimmerCtrl,
      builder: (context, _) {
        final o = 0.08 + _shimmerCtrl.value * 0.1;
        Color block() => Colors.white.withValues(alpha: o);
        return ListView.builder(
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
          itemCount: 10,
          itemBuilder: (_, _) => Container(
            margin: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    color: block(),
                    borderRadius: AppDesignTokens.radiusMd,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 150,
                        height: 14,
                        decoration: BoxDecoration(
                          color: block(),
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Container(
                        width: 90,
                        height: 11,
                        decoration: BoxDecoration(
                          color: block(),
                          borderRadius: BorderRadius.circular(5),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// One-shot fade + slide used to stagger the screen sections on entry.
class _FadeSlide extends StatelessWidget {
  const _FadeSlide({
    required this.animation,
    required this.interval,
    this.offset = 8,
    required this.child,
  });

  final Animation<double> animation;
  final Interval interval;
  final double offset;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (AppMotion.shouldReduceMotion(context)) return child;
    final curved = CurvedAnimation(parent: animation, curve: interval);
    return AnimatedBuilder(
      animation: curved,
      child: child,
      builder: (context, child) => Opacity(
        opacity: curved.value,
        child: Transform.translate(
          offset: Offset(0, offset * (1 - curved.value)),
          child: child,
        ),
      ),
    );
  }
}

/// Small gold dot that gently pulses — a quiet "live" status indicator.
class _LiveDot extends StatefulWidget {
  const _LiveDot();

  @override
  State<_LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<_LiveDot> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: AppMotion.slow,
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _rescale();
    });
  }

  void _rescale() {
    if (!mounted) return;
    _ctrl.duration = AppMotion.scaled(context, AppMotion.slow);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _rescale();
    if (!_started) {
      _started = true;
      if (!AppMotion.shouldReduceMotion(context)) {
        _ctrl.repeat(reverse: true);
      }
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const dot = DecoratedBox(
      decoration: BoxDecoration(
        color: AppDesignTokens.gold,
        shape: BoxShape.circle,
      ),
      child: SizedBox(width: 9, height: 9),
    );

    if (AppMotion.shouldReduceMotion(context)) return dot;

    return FadeTransition(
      opacity: Tween<double>(begin: 0.35, end: 1.0).animate(
        CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
      ),
      child: dot,
    );
  }
}