import 'package:flutter/material.dart';
import '../design/tokens.dart';

/// ResponsiveLayout — constrains content width and applies page padding
/// based on viewport breakpoints. Wrap page/screen content with this.
class ResponsiveLayout extends StatelessWidget {
  const ResponsiveLayout({
    super.key,
    required this.child,
    this.padding,
    this.maxWidth,
    this.centerContent = true,
    this.clipContent = false,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final double? maxWidth;
  final bool centerContent;
  final bool clipContent;

  @override
  Widget build(BuildContext context) {
    final contentWidth = maxWidth ?? AppDesignTokens.contentWidth(context);
    final pagePadding = padding ?? AppDesignTokens.pagePadding(context);

    Widget content = Padding(
      padding: pagePadding,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: contentWidth),
        child: child,
      ),
    );

    if (centerContent) {
      content = Center(child: content);
    }

    if (clipContent) {
      content = ClipRect(child: content);
    }

    return content;
  }
}

/// ResponsiveGrid — adaptive grid that uses breakpoints from tokens.
/// Replaces AdaptiveGrid with token-driven column counts.
class ResponsiveGrid extends StatelessWidget {
  const ResponsiveGrid({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    this.childAspectRatio = 0.67,
    this.spacing = 12,
    this.runSpacing,
    this.padding,
    this.mobileColumns = 2,
    this.tabletColumns = 4,
    this.desktopColumns = 6,
    this.wideColumns = 8,
    this.shrinkWrap = false,
    this.physics,
  });

  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final double childAspectRatio;
  final double spacing;
  final double? runSpacing;
  final EdgeInsetsGeometry? padding;
  final int mobileColumns;
  final int tabletColumns;
  final int desktopColumns;
  final int wideColumns;
  final bool shrinkWrap;
  final ScrollPhysics? physics;

  @override
  Widget build(BuildContext context) {
    final columns = AppDesignTokens.gridColumns(
      context,
      mobile: mobileColumns,
      tablet: tabletColumns,
      desktop: desktopColumns,
      wide: wideColumns,
    );

    return GridView.builder(
      padding: padding ?? AppDesignTokens.pagePadding(context),
      shrinkWrap: shrinkWrap,
      physics: physics ??
          (shrinkWrap
              ? const NeverScrollableScrollPhysics()
              : const BouncingScrollPhysics()),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        childAspectRatio: childAspectRatio,
        crossAxisSpacing: spacing,
        mainAxisSpacing: runSpacing ?? spacing + 2,
      ),
      itemCount: itemCount,
      itemBuilder: itemBuilder,
    );
  }
}

/// ResponsiveRow — horizontal list with adaptive item width.
/// Used for "rails" (continue watching, trending, etc.).
class ResponsiveRow extends StatelessWidget {
  const ResponsiveRow({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    this.itemWidth,
    this.spacing = 8,
    this.padding,
    this.scrollDirection = Axis.horizontal,
    this.physics,
    this.shrinkWrap = false,
  });

  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final double? itemWidth;
  final double spacing;
  final EdgeInsetsGeometry? padding;
  final Axis scrollDirection;
  final ScrollPhysics? physics;
  final bool shrinkWrap;

  @override
  Widget build(BuildContext context) {
    final width = itemWidth ?? _defaultItemWidth(context);

    return SizedBox(
      height: width / 0.67 + 24, // account for metadata
      child: ListView.builder(
        padding: padding ?? AppDesignTokens.pagePadding(context),
        scrollDirection: scrollDirection,
        physics: physics ?? const BouncingScrollPhysics(),
        shrinkWrap: shrinkWrap,
        itemCount: itemCount,
        itemBuilder: (context, index) {
          return Padding(
            padding: EdgeInsets.only(
              right: index == itemCount - 1 ? 0 : spacing,
            ),
            child: SizedBox(width: width, child: itemBuilder(context, index)),
          );
        },
      ),
    );
  }

  double _defaultItemWidth(BuildContext context) {
    final type = _screenType(context);
    return switch (type) {
      _ScreenType.mobile => 140,
      _ScreenType.tablet => 155,
      _ScreenType.desktop => 170,
      _ScreenType.wide => 185,
    };
  }
}

enum _ScreenType { mobile, tablet, desktop, wide }

_ScreenType _screenType(BuildContext context) {
  final w = MediaQuery.sizeOf(context).width;
  if (w >= AppDesignTokens.bpWide) return _ScreenType.wide;
  if (w >= AppDesignTokens.bpDesktop) return _ScreenType.desktop;
  if (w >= AppDesignTokens.bpTablet) return _ScreenType.tablet;
  return _ScreenType.mobile;
}

/// Responsive value helper — returns different values per breakpoint.
/// Usage: responsiveValue(context, mobile: 16, tablet: 24, desktop: 32)
T responsiveValue<T>(BuildContext context, {
  required T mobile,
  T? tablet,
  T? desktop,
  T? wide,
}) {
  final w = MediaQuery.sizeOf(context).width;
  if (w >= AppDesignTokens.bpWide) return wide ?? desktop ?? tablet ?? mobile;
  if (w >= AppDesignTokens.bpDesktop) return desktop ?? tablet ?? mobile;
  if (w >= AppDesignTokens.bpTablet) return tablet ?? mobile;
  return mobile;
}