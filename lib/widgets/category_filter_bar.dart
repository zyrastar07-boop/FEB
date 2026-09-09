import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/iptv_parser_service.dart';
import '../widgets/focusable_scale.dart';
import '../design/tokens.dart';
import '../design/motion.dart';

/// Horizontal scrollable category pills (Telegram / modern filter style).
/// Fully responsive + Android TV / D-pad ready.
class CategoryFilterBar extends StatelessWidget {
  final String selectedCategory;
  final ValueChanged<String> onCategorySelected;
  final List<String>? categories;

  /// Per-category channel counts shown inside each pill.
  final Map<String, int>? counts;

  const CategoryFilterBar({
    super.key,
    required this.selectedCategory,
    required this.onCategorySelected,
    this.categories,
    this.counts,
  });

  @override
  Widget build(BuildContext context) {
    final cats = categories ?? IptvParserService.topCategories;

    return SizedBox(
      height: 42,
      child: FocusTraversalGroup(
        policy: OrderedTraversalPolicy(),
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: cats.length,
          separatorBuilder: (_, _) => const SizedBox(width: 8),
          itemBuilder: (context, index) {
            final cat = cats[index];
            final isSelected = cat == selectedCategory;
            final count = counts?[cat];

            return FocusableScale(
              onTap: () {
                HapticFeedback.selectionClick();
                onCategorySelected(cat);
              },
              borderRadius: BorderRadius.circular(20),
              scale: 1.04,
              child: AnimatedContainer(
                duration: AppMotion.standardScaled(context),
                curve: AppMotion.easeOut,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppDesignTokens.gold
                      : Colors.white.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isSelected
                        ? Colors.transparent
                        : Colors.white.withValues(alpha: 0.08),
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      cat,
                      style: TextStyle(
                        color: isSelected
                            ? AppDesignTokens.textOnGold
                            : Colors.white.withValues(alpha: 0.75),
                        fontSize: 13.5,
                        fontWeight:
                            isSelected ? FontWeight.w700 : FontWeight.w500,
                        letterSpacing: 0.2,
                      ),
                    ),
                    if (count != null && count > 0) ...[
                      const SizedBox(width: 6),
                      Text(
                        '$count',
                        style: TextStyle(
                          color: isSelected
                              ? AppDesignTokens.textOnGold
                                  .withValues(alpha: 0.55)
                              : Colors.white.withValues(alpha: 0.35),
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}