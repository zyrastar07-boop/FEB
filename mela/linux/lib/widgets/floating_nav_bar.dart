import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Compact floating glass navigation bar — items sit close together
/// like the reference screenshots (not stretched edge-to-edge).
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
      // More side inset so the pill is narrower and centered
      padding: const EdgeInsets.fromLTRB(48, 0, 48, 20),
      child: Center(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Container(
              height: 54,
              // Intrinsic width from children — keeps icons close
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.75),
                borderRadius: BorderRadius.circular(28),
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
                  _item(2, Icons.collections_bookmark_rounded, 'Collections'),
                  _item(3, Icons.person_outline_rounded, 'Me'),
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
        // Narrower slot so icons sit closer
        width: 58,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              width: active ? 28 : 24,
              height: active ? 28 : 24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: active
                    ? const Color(0xFFFFB800).withValues(alpha: 0.18)
                    : Colors.transparent,
              ),
              child: Icon(
                icon,
                size: 17,
                color: active
                    ? const Color(0xFFFFB800)
                    : Colors.white.withValues(alpha: 0.48),
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
                    : Colors.white.withValues(alpha: 0.48),
                fontSize: 9,
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