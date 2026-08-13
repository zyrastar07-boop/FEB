import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Floating glass navigation bar with integrated IPTV Live TV tab (5 items total)
class FloatingNavBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const FloatingNavBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      // Padding reduced to 16 on sides to give enough space for 5 tabs
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Center(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(34),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Container(
              height: 64,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.75),
                borderRadius: BorderRadius.circular(34),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.10),
                  width: 0.8,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.45),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _item(0, Icons.home_rounded, 'Home'),
                  _item(1, Icons.search_rounded, 'Search'),
                  _item(2, Icons.live_tv_rounded, 'Live'),
                  _item(3, Icons.collections_bookmark_rounded, 'Collections'),
                  _item(4, Icons.person_outline_rounded, 'Me'),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _item(int index, IconData icon, String label) {
    final active = currentIndex == index;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        HapticFeedback.selectionClick();
        onTap(index);
      },
      child: SizedBox(
        width: 60, // Sized perfectly to fit 5 tabs inside the floating bar
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              width: active ? 42 : 32,
              height: 28,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                color: active
                    ? const Color(0xFFFFB800).withValues(alpha: 0.20)
                    : Colors.transparent,
              ),
              child: Center(
                child: Icon(
                  icon,
                  size: 20,
                  color: active
                      ? const Color(0xFFFFB800)
                      : Colors.white.withValues(alpha: 0.55),
                ),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: active
                    ? const Color(0xFFFFB800)
                    : Colors.white.withValues(alpha: 0.55),
                fontSize: 10,
                height: 1.1,
                fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                letterSpacing: 0.05,
              ),
            ),
          ],
        ),
      ),
    );
  }
}