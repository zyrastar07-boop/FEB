import 'package:flutter/material.dart';
import '../utils/adaptive.dart';

/// Responsive grid that automatically chooses column count based on screen size.
class AdaptiveGrid extends StatelessWidget {
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final double childAspectRatio;
  final double spacing;
  final EdgeInsetsGeometry? padding;
  final ScrollPhysics? physics;
  final bool shrinkWrap;
  final int mobileColumns;
  final int tabletColumns;
  final int desktopColumns;

  const AdaptiveGrid({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    this.childAspectRatio = 0.64,
    this.spacing = 12,
    this.padding,
    this.physics,
    this.shrinkWrap = false,
    this.mobileColumns = 2,
    this.tabletColumns = 4,
    this.desktopColumns = 6,
  });

  @override
  Widget build(BuildContext context) {
    final cols = Adaptive.gridColumns(
      context,
      mobile: mobileColumns,
      tablet: tabletColumns,
      desktop: desktopColumns,
      tv: desktopColumns,
    );

    return GridView.builder(
      padding: padding ?? Adaptive.pagePadding(context),
      shrinkWrap: shrinkWrap,
      physics: physics ??
          (shrinkWrap
              ? const NeverScrollableScrollPhysics()
              : const BouncingScrollPhysics()),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: cols,
        childAspectRatio: childAspectRatio,
        crossAxisSpacing: spacing,
        mainAxisSpacing: spacing + 2,
      ),
      itemCount: itemCount,
      itemBuilder: itemBuilder,
    );
  }
}