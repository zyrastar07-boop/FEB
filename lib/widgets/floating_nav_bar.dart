// floating_nav_bar.dart
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../design/tokens.dart';
import '../design/motion.dart';

/// Floating nav bar (5 tabs) with frosted-glass pill and gold active accent.
/// Index mapping (must match HomeScreen._onNavTapped):
///   0 = Home · 1 = Search · 2 = Live · 3 = Library · 4 = Me
class FloatingNavBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  const FloatingNavBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  static const List<_NavTab> _tabs = [
    _NavTab(
      icon: Icons.home_outlined,
      activeIcon: Icons.home_rounded,
      label: 'Home',
    ),
    _NavTab(
      icon: Icons.search_rounded,
      activeIcon: Icons.search_rounded,
      label: 'Search',
    ),
    _NavTab(
      icon: Icons.live_tv_outlined,
      activeIcon: Icons.live_tv_rounded,
      label: 'Live',
    ),
    _NavTab(
      icon: Icons.collections_bookmark_outlined,
      activeIcon: Icons.collections_bookmark_rounded,
      label: 'Library',
    ),
    _NavTab(
      icon: Icons.person_outline_rounded,
      activeIcon: Icons.person_rounded,
      label: 'Me',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    final reduceMotion = AppMotion.shouldReduceMotion(context);

    final barHeight = isLandscape ? 58.0 : 70.0;
    final horizontalMargin = isLandscape ? 24.0 : 18.0;
    final bottomMargin = isLandscape ? 12.0 : 18.0;
    final iconSize = isLandscape ? 22.0 : 24.0;
    final labelSize = isLandscape ? 9.0 : 10.5;

    return RepaintBoundary(
      child: SafeArea(
        top: false,
        minimum: EdgeInsets.only(bottom: bottomMargin),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: horizontalMargin),
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: isLandscape ? 460 : double.infinity,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(barHeight / 2),
                child: BackdropFilter(
                  filter: ImageFilter.blur(
                    sigmaX: AppMotion.glassBlur(context, AppDesignTokens.glassBlurBar),
                    sigmaY: AppMotion.glassBlur(context, AppDesignTokens.glassBlurBar),
                  ),
                  child: Container(
                    height: barHeight,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      // Frosted glass: tokenized warm-noir fill + cream
                      // highlight hairline (was ad-hoc 0xE6121418 + white 10%).
                      color: AppDesignTokens.glassFillBar,
                      borderRadius: BorderRadius.circular(barHeight / 2),
                      border: Border.all(
                        color: AppDesignTokens.glassHighlight,
                        width: 1,
                      ),
                      boxShadow: AppDesignTokens.glassShadow,
                    ),
                    child: Row(
                      children: List.generate(_tabs.length, (index) {
                        final isActive = currentIndex == index;
                        return _NavTabButton(
                          tab: _tabs[index],
                          isActive: isActive,
                          iconSize: iconSize,
                          labelSize: labelSize,
                          barHeight: barHeight,
                          reduceMotion: reduceMotion,
                          onTap: () {
                            HapticFeedback.selectionClick();
                            onTap(index);
                          },
                        );
                      }),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavTab {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  const _NavTab({
    required this.icon,
    required this.activeIcon,
    required this.label,
  });
}

class _NavTabButton extends StatelessWidget {
  final _NavTab tab;
  final bool isActive;
  final double iconSize;
  final double labelSize;
  final double barHeight;
  final bool reduceMotion;
  final VoidCallback onTap;

  const _NavTabButton({
    required this.tab,
    required this.isActive,
    required this.iconSize,
    required this.labelSize,
    required this.barHeight,
    required this.reduceMotion,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = isActive
        ? AppDesignTokens.gold
        : AppDesignTokens.textCream.withValues(alpha: 0.55);

    // Active gold “pill” behind icon + label (matches uploaded design).
    final highlightHeight = barHeight * 0.78;
    final highlightWidth = barHeight * 0.92;

    return Expanded(
      child: Semantics(
        selected: isActive,
        button: true,
        label: tab.label,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,            child: Center(
              child: AnimatedContainer(
                duration: reduceMotion ? Duration.zero : AppMotion.standardScaled(context),
                curve: AppMotion.easeOut,
              width: isActive ? highlightWidth : highlightWidth * 0.85,
              height: highlightHeight,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(highlightHeight / 2),
                color: isActive
                    ? AppDesignTokens.gold.withValues(alpha: 0.18)
                    : Colors.transparent,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    isActive ? tab.activeIcon : tab.icon,
                    size: iconSize,
                    color: color,
                  ),
                  SizedBox(height: barHeight * 0.03),
                  Text(
                    tab.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppDesignTokens.navLabel.copyWith(
                      color: color,
                      fontSize: labelSize,
                      height: 1.0,
                      fontWeight:
                          isActive ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
