import 'package:flutter/material.dart';
import '../design/tokens.dart';

const _gold = AppDesignTokens.gold;

/// Placeholder rows shown while the download sheet resolves TV structure or
/// quality lists. A looping opacity pulse keeps it lightweight (no shader /
/// shimmer cost on low-end devices).
class DownloadSkeletonLoader extends StatefulWidget {
  final int itemCount;
  final EdgeInsets padding;

  const DownloadSkeletonLoader({
    super.key,
    this.itemCount = 4,
    this.padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
  });

  @override
  State<DownloadSkeletonLoader> createState() => _DownloadSkeletonLoaderState();
}

class _DownloadSkeletonLoaderState extends State<DownloadSkeletonLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: widget.padding,
      child: FadeTransition(
        opacity: Tween<double>(begin: 0.35, end: 0.85).animate(
          CurvedAnimation(parent: _pulse, curve: Curves.easeInOut),
        ),
        child: Column(
          children: List.generate(widget.itemCount, (index) {
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.06),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Title bar — slightly narrower each row for a
                        // natural staggered look.
                        FractionallySizedBox(
                          widthFactor: 0.85 - (index % 3) * 0.12,
                          child: Container(
                            height: 11,
                            decoration: BoxDecoration(
                              color: _gold.withValues(alpha: 0.25),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
                        const SizedBox(height: 7),
                        FractionallySizedBox(
                          widthFactor: 0.55,
                          child: Container(
                            height: 8,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.10),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.08),
                    ),
                  ),
                ],
              ),
            );
          }),
        ),
      ),
    );
  }
}
