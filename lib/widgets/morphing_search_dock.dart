import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../design/tokens.dart';
import '../design/motion.dart';
import 'app_button.dart';

/// React Bits Pro · Mobile 3 — Flutter port.
///
/// Floating dock at the bottom that morphs into a full-width search field
/// with an animated results panel above it. Gold accent preserved.
///
/// Usage:
///   MorphingSearchDock(
///     onQuery: (q) async => results,
///     resultBuilder: (ctx, q) => ...,
///   )
///
/// The widget manages its own focus, keyboard inset, results sheet,
/// and dock ↔ search-field morph animation.
class MorphingSearchDock<T> extends StatefulWidget {
  const MorphingSearchDock({
    super.key,
    required this.onQuery,
    required this.resultBuilder,
    this.queryHint = 'Search movies, shows, people…',
    this.initialResults,
    this.debounce = const Duration(milliseconds: 220),
    this.dockItems = const [
      MobileThreeDockItem(Icons.home_rounded, 'Home'),
      MobileThreeDockItem(Icons.search_rounded, 'Search'),
      MobileThreeDockItem(Icons.bookmark_rounded, 'Saved'),
      MobileThreeDockItem(Icons.person_rounded, 'Me'),
    ],
    this.onDockItemTap,
    this.activeDockIndex = 1,
    this.maxResultsPanelHeight = 360,
  });

  /// Runs when the query string changes (post-debounce).
  /// Return whatever you want shown in the result builder.
  final Future<List<T>> Function(String query) onQuery;

  /// Builds the list of result tiles from the current results.
  /// Called with the most recent query + result list.
  final Widget Function(BuildContext context, String query, List<T> results)
      resultBuilder;

  final String queryHint;
  final List<T>? initialResults;
  final Duration debounce;

  /// Compact dock icons shown when the search field is collapsed.
  final List<MobileThreeDockItem> dockItems;

  /// Fires when a dock icon is tapped (outside of Search). The Search icon
  /// is owned by this widget and does not invoke the callback.
  final ValueChanged<int>? onDockItemTap;
  final int activeDockIndex;

  /// Max height the results panel can grow to (logical px).
  final double maxResultsPanelHeight;

  @override
  State<MorphingSearchDock<T>> createState() => _MorphingSearchDockState<T>();
}

class MobileThreeDockItem {
  const MobileThreeDockItem(this.icon, this.label);
  final IconData icon;
  final String label;
}

class _MorphingSearchDockState<T> extends State<MorphingSearchDock<T>>
    with TickerProviderStateMixin {
  static const _gold = AppDesignTokens.gold;

  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  /// 0 = compact dock, 1 = expanded search.
  late final AnimationController _morph;
  late final Animation<double> _morphEase;

  /// Drives the results panel reveal + the dock scale-down.
  late final AnimationController _resultsAnim;
  late final Animation<double> _resultsEase;

  Timer? _debounceTimer;
  String _lastQuery = '';
  List<T> _results = <T>[];
  bool _isLoading = false;
  bool _expanded = false;
  int _requestSeq = 0;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _focusNode = FocusNode();
    if (widget.initialResults != null) {
      _results = widget.initialResults!;
    }

    _morph = AnimationController(
      vsync: this,
      duration: AppMotion.medium,
      reverseDuration: AppMotion.fast,
      value: 0,
    );
    _morphEase = CurvedAnimation(parent: _morph, curve: AppMotion.easeOut);

    _resultsAnim = AnimationController(
      vsync: this,
      duration: AppMotion.standard,
      reverseDuration: AppMotion.fast,
      value: 0,
    );
    _resultsEase = CurvedAnimation(parent: _resultsAnim, curve: AppMotion.easeOut);

    // Scale durations to the device refresh rate once the build context is
    // available (initState doesn't have a build context for scaled()).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _rescaleDurations();
    });
  }

  void _rescaleDurations() {
    if (!mounted) return;
    _morph.duration = AppMotion.scaled(context, AppMotion.medium);
    _morph.reverseDuration = AppMotion.scaled(context, AppMotion.fast);
    _resultsAnim.duration = AppMotion.scaled(context, AppMotion.standard);
    _resultsAnim.reverseDuration = AppMotion.scaled(context, AppMotion.fast);
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    _controller.removeListener(_onTextChange);
    _debounceTimer?.cancel();
    _morph.dispose();
    _resultsAnim.dispose();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Re-scale when the context changes (e.g. theme change, locale change)
    // or when the refresh rate service updates its estimate.
    _rescaleDurations();
  }

  void _onFocusChange() {
    final hasFocus = _focusNode.hasFocus;
    if (hasFocus && !_expanded) _expand();
    if (!hasFocus && _expanded && _controller.text.isEmpty) _collapse();
  }

  void _onTextChange() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(widget.debounce, _runQuery);
  }

  Future<void> _runQuery() async {
    final q = _controller.text.trim();
    if (q == _lastQuery) return;
    _lastQuery = q;
    if (q.isEmpty) {
      if (mounted) {
        setState(() {
          _results = <T>[];
          _isLoading = false;
        });
      }
      _hideResults();
      return;
    }
    final seq = ++_requestSeq;
    if (mounted) setState(() => _isLoading = true);
    _showResults();
    try {
      final list = await widget.onQuery(q);
      if (!mounted || seq != _requestSeq) return;
      setState(() {
        _results = list;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted || seq != _requestSeq) return;
      setState(() {
        _results = <T>[];
        _isLoading = false;
      });
    }
  }

  void _expand() {
    HapticFeedback.lightImpact();
    setState(() => _expanded = true);
    _morphForward();
    if (_controller.text.trim().isNotEmpty) _showResults();
  }

  void _collapse() {
    HapticFeedback.selectionClick();
    setState(() => _expanded = false);
    _morphReverse();
    _hideResults();
    _controller.clear();
    _lastQuery = '';
    _results = <T>[];
  }

  void _morphForward() {
    if (AppMotion.shouldReduceMotion(context)) {
      _morph.value = 1;
    } else {
      _morph.forward();
    }
  }

  void _morphReverse() {
    if (AppMotion.shouldReduceMotion(context)) {
      _morph.value = 0;
    } else {
      _morph.reverse();
    }
  }

  void _showResults() {
    if (AppMotion.shouldReduceMotion(context)) {
      _resultsAnim.value = 1;
    } else {
      _resultsAnim.forward();
    }
  }

  void _hideResults() {
    if (AppMotion.shouldReduceMotion(context)) {
      _resultsAnim.value = 0;
    } else {
      _resultsAnim.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    final keyboard = MediaQuery.of(context).viewInsets.bottom;
    return Stack(
      alignment: Alignment.bottomCenter,
      children: [
        // Scrim — only when expanded, fades in to mute the content beneath.
        AnimatedBuilder(
          animation: _morphEase,
          builder: (context, _) {
            if (_morphEase.value == 0) return const SizedBox.shrink();
            return Positioned.fill(
              child: IgnorePointer(
                ignoring: _morphEase.value < 0.5,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _collapse,
                  child: Container(
                    color: Colors.black.withValues(
                      alpha: 0.55 * _morphEase.value,
                    ),
                  ),
                ),
              ),
            );
          },
        ),
        // Results panel — pinned above the dock, only visible when expanded.
        AnimatedBuilder(
          animation: _resultsEase,
          builder: (context, _) {
            if (_resultsEase.value == 0) return const SizedBox.shrink();
            final bottomOffset = _dockHeight() + 12 + keyboard;
            final h = widget.maxResultsPanelHeight * _resultsEase.value;
            return Positioned(
              left: 12,
              right: 12,
              bottom: bottomOffset,
              child: Opacity(
                opacity: _resultsEase.value,
                child: Transform.translate(
                  offset: Offset(0, 16 * (1 - _resultsEase.value)),
                  child: SizedBox(
                    height: h,
                    child: _ResultsPanel<T>(
                      isLoading: _isLoading,
                      isEmpty: _results.isEmpty && !_isLoading,
                      child: widget.resultBuilder(
                        context,
                        _controller.text,
                        _results,
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
        // The morphing surface itself: compact dock ↔ search field.
        SafeArea(
          top: false,
          minimum: EdgeInsets.only(bottom: 16),
          child: Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              bottom: keyboard > 0 ? 8 : 0,
            ),
            child: AnimatedBuilder(
              animation: _morphEase,
              builder: (context, _) {
                return _MorphSurface(
                  progress: _morphEase.value,
                  expanded: _expanded,
                  child: _expanded
                      ? _buildExpanded()
                      : _buildDock(),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  // The expanded-state surface measures 56px tall in compact mode; the
  // dock always shows at ~64px. The morph blends between them via
  // border-radius (28 ↔ 28) and horizontal padding.
  double _dockHeight() => 64;

  Widget _buildDock() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        for (var i = 0; i < widget.dockItems.length; i++)
          _DockIcon(
            item: widget.dockItems[i],
            active: widget.activeDockIndex == i,
            isSearch: i == _searchIconIndex(),
            onTap: () {
              if (i == _searchIconIndex()) {
                _focusNode.requestFocus();
                return;
              }
              widget.onDockItemTap?.call(i);
            },
          ),
      ],
    );
  }

  int _searchIconIndex() {
    final i = widget.dockItems.indexWhere(
      (d) => d.icon == Icons.search_rounded,
    );
    return i < 0 ? 1 : i;
  }

  Widget _buildExpanded() {
    return Row(
      children: [
        const Icon(Icons.search_rounded, color: _gold, size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: TextField(
            controller: _controller,
            focusNode: _focusNode,
            autocorrect: false,
            textInputAction: TextInputAction.search,
            cursorColor: _gold,
            cursorWidth: 1.4,
            style: AppDesignTokens.titleMedium(),
            decoration: InputDecoration(
              isCollapsed: true,
              contentPadding: EdgeInsets.zero,
              border: InputBorder.none,
              hintText: widget.queryHint,
              hintStyle: AppDesignTokens.titleMedium(
                color: AppDesignTokens.textCream.withValues(alpha: 0.45),
              ),
            ),
          ),
        ),
        if (_controller.text.isNotEmpty)
          GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              _controller.clear();
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Icon(
                Icons.close_rounded,
                size: 18,
                color: AppDesignTokens.textCream.withValues(alpha: 0.55),
              ),
            ),
          ),
        AppButton(
          variant: AppButtonVariant.ghost,
          size: AppButtonSize.small,
          padding: EdgeInsets.zero,
          borderRadius: AppDesignTokens.radiusFull,
          semanticLabel: 'Close search',
          onPressed: () {
            _focusNode.unfocus();
            _collapse();
          },
          child: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: _gold.withValues(alpha: 0.18),
              shape: BoxShape.circle,
              border: Border.all(color: _gold.withValues(alpha: 0.55)),
            ),
            child: const Icon(
              Icons.arrow_forward_rounded,
              size: 16,
              color: _gold,
            ),
          ),
        ),
      ],
    );
  }
}

class _MorphSurface extends StatelessWidget {
  const _MorphSurface({
    required this.progress,
    required this.expanded,
    required this.child,
  });

  final double progress;
  final bool expanded;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final compactRadius = AppDesignTokens.radiusFull;
    final expandedRadius = AppDesignTokens.radius2xl;
    final radius = BorderRadius.lerp(compactRadius, expandedRadius, progress)!;
    final borderColor = Color.lerp(
      AppDesignTokens.borderCork,
      AppDesignTokens.gold.withValues(alpha: 0.55),
      progress,
    )!;
    final glow = progress > 0
        ? [
            BoxShadow(
              color: AppDesignTokens.gold.withValues(alpha: 0.22 * progress),
              blurRadius: 28 * progress,
              spreadRadius: 1 * progress,
            ),
          ]
        : const <BoxShadow>[];
    return Container(
      height: 56,
      decoration: BoxDecoration(
        // Tokenized glass fill (was opaque surfaceElevated) so the dock
        // frosts the content scrolling beneath it.
        color: AppDesignTokens.glassFillBar,
        borderRadius: radius,
        border: Border.all(color: borderColor, width: 1.2),
        boxShadow: glow,
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: AppDesignTokens.glassBlurBar,
            sigmaY: AppDesignTokens.glassBlurBar,
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: 12 + 4 * progress,
              vertical: 8,
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

class _DockIcon extends StatelessWidget {
  const _DockIcon({
    required this.item,
    required this.active,
    required this.isSearch,
    required this.onTap,
  });

  final MobileThreeDockItem item;
  final bool active;
  final bool isSearch;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = isSearch
        ? AppDesignTokens.gold
        : (active
            ? AppDesignTokens.textCream
            : AppDesignTokens.textCream.withValues(alpha: 0.55));
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: AppMotion.scaled(context, AppMotion.fast),
          curve: AppMotion.easeOut,
          margin: const EdgeInsets.symmetric(horizontal: 2),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSearch
                ? AppDesignTokens.gold.withValues(alpha: 0.14)
                : (active
                    ? AppDesignTokens.textCream.withValues(alpha: 0.06)
                    : Colors.transparent),
            borderRadius: BorderRadius.circular(18),
            border: isSearch
                ? Border.all(
                    color: AppDesignTokens.gold.withValues(alpha: 0.55),
                  )
                : null,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(item.icon, size: 18, color: color),
              const SizedBox(height: 3),
              Text(
                item.label.toUpperCase(),
                style: AppDesignTokens.navLabel.copyWith(
                  color: color,
                  fontSize: 9,
                  height: 1.0,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ResultsPanel<T> extends StatelessWidget {
  const _ResultsPanel({
    required this.isLoading,
    required this.isEmpty,
    required this.child,
  });

  final bool isLoading;
  final bool isEmpty;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: ClipRRect(
        borderRadius: AppDesignTokens.radius2xl,
        child: BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: AppDesignTokens.glassBlurSheet,
            sigmaY: AppDesignTokens.glassBlurSheet,
          ),
          child: Container(
            decoration: BoxDecoration(
              color: AppDesignTokens.glassFillSheet,
              borderRadius: AppDesignTokens.radius2xl,
              border: Border.all(
                color: AppDesignTokens.glassBorderStrong,
                width: 1,
              ),
              boxShadow: AppDesignTokens.glassShadow,
            ),
            child: isLoading
                ? const _LoadingState()
                : isEmpty
                    ? const _EmptyState()
                    : child,
          ),
        ),
      ),
    );
  }
}

class _LoadingState extends StatelessWidget {
  const _LoadingState();
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppDesignTokens.gold,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'SEARCHING',
            style: TextStyle(
              color: AppDesignTokens.textCream.withValues(alpha: 0.55),
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.search_rounded,
            size: 28,
            color: AppDesignTokens.textCream.withValues(alpha: 0.4),
          ),
          const SizedBox(height: 10),
          Text(
            'NO RESULTS',
            style: TextStyle(
              color: AppDesignTokens.textCream.withValues(alpha: 0.6),
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }
}