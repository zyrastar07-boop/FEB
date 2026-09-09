import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/iptv_parser_service.dart';
import '../widgets/focusable_scale.dart';
import '../widgets/glass_surface.dart';
import '../design/tokens.dart';
import '../design/motion.dart';

/// Compact glass category navigation used throughout the app.
///
/// Design goals:
/// - Never allow an icon or label to escape its pill.
/// - Keep the bar horizontally scrollable on small phones.
/// - Use the shared glass system instead of opaque oversized pills.
/// - Preserve the existing category values, callbacks and D-pad support.
class CategoryFilterBar extends StatelessWidget {
  final String selectedCategory;
  final ValueChanged<String> onCategorySelected;
  final List<String>? categories;
  final Map<String, int>? counts;

  const CategoryFilterBar({
    super.key,
    required this.selectedCategory,
    required this.onCategorySelected,
    this.categories,
    this.counts,
  });

  IconData _iconFor(String category) {
    final key = category.trim().toLowerCase();
    if (key == 'all' || key == 'all content') return Icons.grid_view_rounded;
    if (key == 'movie' || key == 'movies') return Icons.movie_creation_outlined;
    if (key == 'tv' || key == 'tv show' || key == 'tv shows' || key == 'series') {
      return Icons.tv_rounded;
    }
    if (key == 'anime') return Icons.animation_rounded;
    if (key.contains('live')) return Icons.live_tv_rounded;
    if (key.contains('sport')) return Icons.sports_soccer_rounded;
    if (key.contains('news')) return Icons.newspaper_rounded;
    return Icons.category_outlined;
  }

  @override
  Widget build(BuildContext context) {
    final cats = categories ?? IptvParserService.topCategories;
    final reduceMotion = AppMotion.shouldReduceMotion(context);

    return SizedBox(
      height: 48,
      child: FocusTraversalGroup(
        policy: OrderedTraversalPolicy(),
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          itemCount: cats.length,
          separatorBuilder: (_, _) => const SizedBox(width: 6),
          itemBuilder: (context, index) {
            final cat = cats[index];
            final isSelected = cat == selectedCategory;
            final count = counts?[cat];
            final icon = _iconFor(cat);

            return FocusableScale(
              onTap: () {
                HapticFeedback.selectionClick();
                onCategorySelected(cat);
              },
              borderRadius: BorderRadius.circular(18),
              scale: 1.025,
              child: GlassSurface(
                fill: isSelected ? GlassFill.subtle : GlassFill.bar,
                borderRadius: 18,
                fillColor: isSelected
                    ? AppDesignTokens.gold.withValues(alpha: 0.96)
                    : AppDesignTokens.glassFillSubtle,
                borderColor: isSelected
                    ? AppDesignTokens.gold.withValues(alpha: 0.95)
                    : AppDesignTokens.glassHighlight,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                sheen: !reduceMotion,
                child: AnimatedDefaultTextStyle(
                  duration: reduceMotion
                      ? Duration.zero
                      : AppMotion.standardScaled(context),
                  curve: AppMotion.easeOut,
                  style: TextStyle(
                    fontFamily: AppDesignTokens.fontFamily,
                    color: isSelected
                        ? AppDesignTokens.textOnGold
                        : AppDesignTokens.textCream.withValues(alpha: 0.82),
                    fontSize: 12.5,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    height: 1.0,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        icon,
                        size: 15,
                        color: isSelected
                            ? AppDesignTokens.textOnGold
                            : AppDesignTokens.textCream.withValues(alpha: 0.72),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        cat,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (count != null && count > 0) ...[
                        const SizedBox(width: 5),
                        Text(
                          '$count',
                          style: TextStyle(
                            color: isSelected
                                ? AppDesignTokens.textOnGold.withValues(alpha: 0.58)
                                : AppDesignTokens.textCream.withValues(alpha: 0.38),
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
