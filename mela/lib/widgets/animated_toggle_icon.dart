import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Icon that pops / scales when its active state flips.
class AnimatedToggleIcon extends StatefulWidget {
  final bool active;
  final IconData activeIcon;
  final IconData inactiveIcon;
  final Color activeColor;
  final Color inactiveColor;
  final double size;
  final VoidCallback onTap;
  final String label;

  const AnimatedToggleIcon({
    super.key,
    required this.active,
    required this.activeIcon,
    required this.inactiveIcon,
    required this.onTap,
    this.activeColor = const Color(0xFFFFB800),
    this.inactiveColor = Colors.white70,
    this.size = 20,
    this.label = '',
  });

  @override
  State<AnimatedToggleIcon> createState() => _AnimatedToggleIconState();
}

class _AnimatedToggleIconState extends State<AnimatedToggleIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
    _scale = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.35), weight: 40),
      TweenSequenceItem(tween: Tween(begin: 1.35, end: 0.9), weight: 30),
      TweenSequenceItem(tween: Tween(begin: 0.9, end: 1.0), weight: 30),
    ]).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
  }

  @override
  void didUpdateWidget(covariant AnimatedToggleIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active != widget.active) {
      _ctrl.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        HapticFeedback.selectionClick();
        widget.onTap();
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ScaleTransition(
            scale: _scale,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: widget.active
                      ? widget.activeColor.withValues(alpha: 0.45)
                      : Colors.white.withValues(alpha: 0.1),
                ),
              ),
              child: Icon(
                widget.active ? widget.activeIcon : widget.inactiveIcon,
                color: widget.active ? widget.activeColor : widget.inactiveColor,
                size: widget.size,
              ),
            ),
          ),
          if (widget.label.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              widget.label,
              style: TextStyle(
                color: widget.active ? widget.activeColor : Colors.white54,
                fontSize: 10,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
